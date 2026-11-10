--[[ WoWBoxer – squad automation through WoW's normal addon API (CLAUDE.md hard rule 1 and 5, docs/automation-policy.md).
  Allowed: accepting invites, quests, resurrections and summons; sharing and turning in quests; repeating the leader's
  dialog, quest or flight choice on a follower that has the SAME window open; selling junk, repairing, restocking.
  Never: casting, targeting, moving, following or opening an NPC – those stay one key press on that character, and
  nothing here works around protected actions. Every automation:
  - is a named option (Setup → Automation), off unless the player ticks it (resurrect/summon: on by default);
  - only reacts to squad members (the WoWBoxer squad, matched by name) who are in the party;
  - is skipped while Shift is held;
  - writes one log line (and, with the option, one chat line).
  Messages between clients (prefix WBXA) are data only: a few fields, never code (hard rule 2). ]]
local _, ns = ...
local AU = {}
ns.Auto = AU

local G = _G
AU.PREFIX = "WBXA"
local function Core() return ns.Core end
local function C() return ns.Compat end
local function now() return (G.GetTime and G.GetTime()) or 0 end

-- ------------------------------------------------------------------ options
--- {key, label, tip, default, display}. Labels ≤ 3 words; the tip is the one line about what it does. display = only
--- shows something (Relay.lua), so it does not count as "automation on" for the nudge and the OFF badge.
AU.OPTIONS = {
  { "invite", "Accept invites", "Accepts a group invite from a squad member." },
  { "autoInvite", "Invite the squad", "Leader: invites squad members who are not in the group (now and then, while you lead)." },
  { "quests", "Accept quests", "Leader: takes every quest a quest giver you open offers. Followers: accept the quests the leader has." },
  { "questAny", "Accept any quest", "Accepts every quest offered, not only the leader's (needs Accept quests)." },
  { "share", "Share quests", "Leader: shares every quest you accept with the party." },
  { "turnin", "Turn in quests", "Completes and turns in finished quests at the quest giver you opened." },
  { "abandon", "Abandon together", "When the leader abandons a quest, followers abandon it too (never a completed quest)." },
  { "dialog", "Follow dialogs", "Picks the leader's dialog, quest or flight choice when you have the same NPC window open." },
  { "res", "Accept resurrection", "Accepts a resurrection from a squad member.", true },
  { "summon", "Accept summons", "Accepts a summon from a squad member.", true },
  { "rolecheck", "Accept role checks", "Accepts the group's role check when the group leader is in your squad." },
  { "sell", "Sell junk", "Sells grey items and your sell list (/wbx sell) at a merchant you open." },
  { "repair", "Repair", "Repairs everything at a merchant that can repair, keeping at least the gold floor." },
  { "restock", "Restock reagents", "Buys your class reagents (candles, symbols, ankhs, powders, ammo you use) up to a set amount." },
  { "shareSell", "Share sell list", "Keeps the sell list the same on every squad window (/wbx sell add [item]); each sells at its own merchant." },
  { "whispers", "Forward whispers", "Followers' whispers show in the leader's chat; GM whispers are tagged, with a sound.", true, true },
  { "followWarn", "Follow warning", "Warning on the leader when a follower stops following (not in combat, zoning, death, flights).", true, true },
  -- [6] = shown as a small Sound button inside that option's card, not as a card of its own
  { "warnSound", "Warning sound", "Plays the raid-warning sound with the follow warning and GM whispers (/wbx sound toggles it).", true, true, "followWarn" },
  { "autoEquip", "Auto-equip", "Equips new items that are clearly better; asks for bind-on-equip items and when unsure. Off by default." },
  { "greed", "Auto greed", "In 5-player dungeons: Greed on grey and white items, and on better items you can't use or that are no upgrade. Never Need; bind on pickup stays yours. Off by default." },
  { "chat", "Chat line", "Writes one chat line for each automatic action." },
}
AU.BY_KEY = {}
for _, o in ipairs(AU.OPTIONS) do AU.BY_KEY[o[1]] = o end
AU.PRESET_LEVELLING = { "invite", "quests", "share", "turnin", "dialog", "res", "summon", "rolecheck", "sell", "repair", "shareSell",
  "whispers", "followWarn", "warnSound" }
AU.REWARD_RULES = { "leader", "value", "ask" }
AU.GOLD_FLOOR = 10000     -- copper kept when repairing (1 gold)
AU.TAXI_LIMIT = 20000     -- a synced flight costs at most 2 gold
AU.INVITE_EVERY = 120     -- seconds between invites of the same name

local function db() return Core().db and Core().db.settings or {} end
local function opts()
  local s = db()
  s.auto = type(s.auto) == "table" and s.auto or {}
  return s.auto
end
--- Is option `key` on? (resurrect/summon default on)
function AU.on(key)
  local v = opts()[key]
  if v == nil then return AU.BY_KEY[key] and AU.BY_KEY[key][4] == true or false end
  return v == true
end
function AU.set(key, v) opts()[key] = v and true or false end
function AU.setAll(v) for _, o in ipairs(AU.OPTIONS) do AU.set(o[1], v) end end
--- WoWBoxer's recommendation (the owner, 30 Oct 2026): everything on except these three.
AU.RECOMMENDED_OFF = { abandon = true, questAny = true, restock = true, autoEquip = true, greed = true }
function AU.defaults() for _, o in ipairs(AU.OPTIONS) do AU.set(o[1], not AU.RECOMMENDED_OFF[o[1]]) end end
function AU.preset() for _, o in ipairs(AU.OPTIONS) do AU.set(o[1], false) end for _, k in ipairs(AU.PRESET_LEVELLING) do AU.set(k, true) end AU.set("chat", true) end
function AU.rewardRule() local r = db().autoReward; for _, x in ipairs(AU.REWARD_RULES) do if x == r then return r end end return "leader" end

-- ------------------------------------------------------------------ who may trigger it
local function short(n) return C().baseName(n) end -- realm-free, trimmed, full name kept ("Rip And")
--- The squad member named `name` (not this character), or nil. inParty = also in the party here. Matching is
--- Compat.sameName (full name, or the first name for old squads); an exact match wins.
function AU.member(name, inParty)
  local n = short(name)
  if not n then return nil end
  local s, me = Core().me()
  local others = {}
  for _, m in ipairs(s and s.members or {}) do if m ~= me then others[#others + 1] = m end end
  local m = C().findByName(others, n)
  if not m then return nil end
  if inParty and not ns.Squad.unitOf(n) then return nil end
  return m
end
function AU.isLeader() local _, me = Core().me(); return me ~= nil and me.leader == true end

-- ------------------------------------------------------------------ "Accept from" (docs/feedback-2026-10-30-night.md §5)
-- squad (default): WoWBoxer squad members in your party · friends: also friends, Battle.net friends on this game and
-- your guild · everyone: anyone (the page warns first). Used by every accept: invites, escorts/shares, resurrections,
-- summons and role checks. In Advanced mode a row can have its own choice.
AU.FROM = { { "squad", "Squad only" }, { "friends", "Squad, friends and guild" }, { "everyone", "Everyone" } }
AU.FROM_SHORT = { squad = "Squad", friends = "Squad, friends, guild", everyone = "Everyone" }
AU.ACCEPTS = { invite = true, quests = true, res = true, summon = true, rolecheck = true }
function AU.acceptFrom(key)
  local s = db()
  local o = key and ns.Advanced and ns.Advanced.on() and type(s.acceptOverride) == "table" and s.acceptOverride[key]
  local v = o or s.acceptFrom
  if v ~= "friends" and v ~= "everyone" then v = "squad" end
  return v
end
--- Is `name` on this character's friends list (or a Battle.net friend playing this game)?
function AU.isFriend(name)
  local n = short(name)
  if not n then return false end
  n = n:lower()
  local CF = G.C_FriendList
  if CF and CF.GetNumFriends and CF.GetFriendInfoByIndex then
    for i = 1, (CF.GetNumFriends() or 0) do local f = CF.GetFriendInfoByIndex(i); if f and f.name and C().sameName(f.name, n) then return true end end
  elseif G.GetNumFriends and G.GetFriendInfo then
    for i = 1, (G.GetNumFriends() or 0) do local fn = G.GetFriendInfo(i); if fn and C().sameName(fn, n) then return true end end
  end
  local BN = G.C_BattleNet
  if BN and BN.GetFriendAccountInfo and G.BNGetNumFriends then
    for i = 1, (G.BNGetNumFriends() or 0) do
      local ok, a = pcall(BN.GetFriendAccountInfo, i)
      local gi = ok and a and a.gameAccountInfo
      if gi and gi.characterName and C().sameName(gi.characterName, n) then return true end
    end
  end
  return false
end
--- Is `name` in this character's guild?
function AU.isGuild(name)
  local n = short(name)
  if not (n and G.IsInGuild and G.IsInGuild() and G.GetNumGuildMembers and G.GetGuildRosterInfo) then return false end
  n = n:lower()
  for i = 1, (G.GetNumGuildMembers() or 0) do
    local gn = G.GetGuildRosterInfo(i)
    if gn and C().sameName(gn, n) then return true end
  end
  return false
end
--- May option `key` accept from `name`? inParty: a squad member must also be in the party (invites: not yet).
--- Returns the display name or nil.
function AU.allowed(key, name, inParty)
  local n = short(name)
  if not n then return nil end -- unknown / secret name: never
  local m = AU.member(n, inParty)
  if m then return m.name end
  local from = AU.acceptFrom(key)
  if from == "everyone" then return n end
  if from == "friends" and (AU.isFriend(n) or AU.isGuild(n)) then return n end
  return nil
end
local function shift() return G.IsShiftKeyDown and G.IsShiftKeyDown() and true or false end
--- One log line per automatic action (and a chat line with the Chat line option).
function AU.did(text)
  Core().log("info", "auto: " .. text)
  if AU.on("chat") then Core().print(text) end
  AU.last = text
end
local function skipShift(what) if shift() then Core().log("info", "auto: " .. what .. " skipped (Shift held)"); return true end return false end
local function call(f, ...) if not f then return false end return pcall(f, ...) end

-- ------------------------------------------------------------------ messages (data only)
local function clean(t) return (tostring(t or ""):gsub("[|\n\r]", "")):sub(1, 60) end
function AU.send(...)
  if not C().inParty() then return false end
  local parts = {}
  for i = 1, select("#", ...) do parts[i] = clean(select(i, ...)) end
  return (C().sendAddon(AU.PREFIX, table.concat(parts, "|"), (G.IsInRaid and G.IsInRaid()) and "RAID" or "PARTY", "auto " .. tostring(parts[1])))
end
AU.leaderQuests = {}   -- quest IDs the squad leader has (from "QL" messages)
AU.leaderReward = {}   -- questID -> reward index the leader picked
function AU.receive(prefix, text, _, sender)
  if prefix ~= AU.PREFIX or type(text) ~= "string" then return end
  C().arrived(prefix, sender)
  if C().sameName(sender, C().playerName()) then return end -- our own message, echoed back by the party channel
  local m = AU.member(sender, true)
  if not m then return C().drop(prefix, sender, "not a squad member in your party (name not matched)") end -- only squad members in the party
  local f = {}
  for x in (text .. "|"):gmatch("([^|]*)|") do f[#f + 1] = x end
  local kind = f[1]
  if kind == "QL" and m.leader then
    AU.leaderQuests = {}
    for id in (f[2] or ""):gmatch("(%d+)") do AU.leaderQuests[tonumber(id)] = true end
    -- the quest window is already open here and the leader just took that quest: accept it now
    if AU.detailOpen and AU.leaderQuests[AU.detailOpen] then AU.onQuestDetail() end
  elseif kind == "QQ" and AU.isLeader() then AU.sendQuestList() -- a follower has a quest window open and asks again
  elseif kind == "QR" and m.leader then
    local q, i = tonumber(f[2]), tonumber(f[3])
    if q and i then AU.leaderReward[q] = i; AU.chooseReward() end
  elseif kind == "QA" and m.leader then AU.abandonHere(tonumber(f[2]), f[3])
  elseif kind == "D" and m.leader then AU.applyDialog(f[2], f[3], tonumber(f[4]), f[5], m)
  end
end

-- ------------------------------------------------------------------ 1. invites
function AU.onInvite(name)
  if not AU.on("invite") then return end
  local who = AU.allowed("invite", name, false) -- not in the party yet: matched by name only
  if not who then Core().log("info", "auto: invite not accepted (Accept from: " .. AU.FROM_SHORT[AU.acceptFrom("invite")] .. ")"); return end
  if skipShift("invite") then return end
  if call(G.AcceptGroup) then
    if G.StaticPopup_Hide then pcall(G.StaticPopup_Hide, "PARTY_INVITE") end
    AU.did("Accepted the group invite from " .. who .. ".")
  end
end
AU.invited = {}
--- Leader: invite squad members who are not in the group (at most every INVITE_EVERY seconds per name).
function AU.inviteMissing()
  if not (AU.on("autoInvite") and AU.isLeader()) then return 0 end
  local s, me = Core().me()
  local n = 0
  for _, m in ipairs(s and s.members or {}) do
    if m ~= me and not ns.Squad.unitOf(m.name) and now() - (AU.invited[m.name] or -1e9) >= AU.INVITE_EVERY then
      AU.invited[m.name] = now()
      local who = ns.Macros.inviteName(m)
      local inv = (G.C_PartyInfo and G.C_PartyInfo.InviteUnit) or G.InviteUnit -- [AFKLAR: without a key press on Forever]
      if call(inv, who) then n = n + 1; AU.did("Invited " .. m.name .. ".") end
    end
  end
  return n
end

-- ------------------------------------------------------------------ 2. quests
function AU.questIds()
  local out = {}
  local QL = G.C_QuestLog
  if QL and QL.GetNumQuestLogEntries and QL.GetInfo then
    local ok, n = pcall(QL.GetNumQuestLogEntries)
    for i = 1, (ok and n or 0) do local okI, info = pcall(QL.GetInfo, i); if okI and info and info.questID and not info.isHeader then out[#out + 1] = info.questID end end
  elseif G.GetNumQuestLogEntries and G.GetQuestLogTitle then
    local ok, n = pcall(G.GetNumQuestLogEntries)
    for i = 1, (ok and n or 0) do
      local r = { pcall(G.GetQuestLogTitle, i) }
      if r[1] and not r[5] and r[9] then out[#out + 1] = r[9] end -- title, level, tag, isHeader(5) … questID(9)
    end
  end
  return out
end
--- The leader's quest list as one message: "QL|id,id,…" – every quest that fits in an addon message (255).
--- (Before 1.1.1 each field was cut at 60 characters: ~10 quests, so newer quests never reached the followers.)
AU.QL_MAX = 250
function AU.questListText()
  local out = "QL|"
  local first = true
  for _, id in ipairs(AU.questIds()) do
    local add = (first and "" or ",") .. tostring(math.floor(tonumber(id) or 0))
    if #out + #add > AU.QL_MAX then break end
    out = out .. add
    first = false
  end
  return out
end
--- Leader: tell the followers which quests it has (for "Accept quests"). Several triggers in a row (taking every
--- quest from an NPC, roster updates) become one message a moment later; a throttled send is tried again.
AU.QL_DELAY, AU.QL_RETRY, AU.QL_TRIES = 0.3, 2, 3
function AU.sendQuestList(tries)
  if not AU.isLeader() then return end
  local after = G.C_Timer and G.C_Timer.After
  if tries == nil and after then
    if AU.qlPending then return end
    AU.qlPending = true
    after(AU.QL_DELAY, function() AU.qlPending = nil; AU.sendQuestList(1) end)
    return
  end
  if not C().inParty() then return end
  local ok = C().sendAddon(AU.PREFIX, AU.questListText(), (G.IsInRaid and G.IsInRaid()) and "RAID" or "PARTY", "auto QL")
  if not ok and after and (tries or 1) < AU.QL_TRIES and not AU.qlPending then
    AU.qlPending = true
    after(AU.QL_RETRY, function() AU.qlPending = nil; AU.sendQuestList((tries or 1) + 1) end)
  end
end
--- A quest window shared by a squad member: "questnpc" is then that player. [AFKLAR: Forever + Era – if it is not,
--- the follower asks the leader for its list instead (QQ) and accepts when it arrives.]
function AU.questSharer()
  local isP = G.UnitIsPlayer and C().safe(G.UnitIsPlayer("questnpc"))
  if not isP then return nil end
  local n = G.UnitName and C().safe(G.UnitName("questnpc"))
  if type(n) ~= "string" or n == "" then return nil end
  local m = AU.member(n, true)
  return m and m.name or nil
end
AU.asked = {}
AU.ASK_EVERY = 5
local function questId() return (G.GetQuestID and C().safe(G.GetQuestID())) or nil end
local function questTitle(id)
  local t = G.GetTitleText and C().safe(G.GetTitleText())
  if type(t) ~= "string" or t == "" then
    local QL = G.C_QuestLog
    t = QL and QL.GetTitleForQuestID and C().safe(QL.GetTitleForQuestID(id or 0)) or nil
  end
  return (type(t) == "string" and t ~= "") and t or ("#" .. tostring(id or "?"))
end
function AU.onQuestDetail()
  local id = questId()
  AU.detailOpen = id
  if not AU.on("quests") then return end
  if AU.isLeader() then
    -- the leader (owner, 5 Nov 2026): every quest a quest giver offers is taken; Share quests then shares it
    if skipShift("quest") then return end
    if call(G.AcceptQuest) then AU.detailOpen = nil; AU.did("Accepted quest " .. questTitle(id) .. ".") end
    return
  end
  if not (AU.on("questAny") or (id and AU.leaderQuests[id]) or AU.questSharer()) then
    -- maybe the leader's list was lost on the way: ask once (the answer accepts it while this window is open)
    local t = now()
    if id and t - (AU.asked[id] or -1e9) >= AU.ASK_EVERY then AU.asked[id] = t; AU.send("QQ", id) end
    Core().log("info", "auto: quest " .. questTitle(id) .. " not accepted yet – the leader does not have it (accepted when " ..
      "the leader takes it while this window is open)")
    return
  end
  if skipShift("quest") then return end
  if call(G.AcceptQuest) then AU.detailOpen = nil; AU.did("Accepted quest " .. questTitle(id) .. ".") end
end
function AU.onQuestConfirm(name) -- an escort / shared start from a squad member
  if not AU.on("quests") or not AU.allowed("quests", name, true) or skipShift("quest") then return end
  if call(G.ConfirmAcceptQuest) then AU.did("Accepted the quest " .. (short(name) or "?") .. " started.") end
end
--- Leader: share a quest it just accepted (QUEST_ACCEPTED: retail = questID, Classic = questLogIndex, questID).
function AU.onQuestAccepted(a, b)
  if AU.isLeader() then AU.sendQuestList() end
  if not (AU.on("share") and AU.isLeader() and C().inParty()) or skipShift("share") then return end
  local id = b or a
  local QL = G.C_QuestLog
  local ok
  if QL and QL.SetSelectedQuest and b == nil then ok = pcall(QL.SetSelectedQuest, a) and call(G.QuestLogPushQuest)
  elseif G.SelectQuestLogEntry then ok = pcall(G.SelectQuestLogEntry, a) and call(G.QuestLogPushQuest) end
  if ok then AU.did("Shared quest " .. tostring(id) .. " with the party.") end
end
function AU.onQuestProgress()
  if not AU.on("turnin") or skipShift("turn in") then return end
  if G.IsQuestCompletable and G.IsQuestCompletable() and call(G.CompleteQuest) then AU.did("Handed in " .. tostring(questId()) .. ".") end
end
--- The reward to take: 1 when there is no choice; else by rule (leader's choice / best vendor value / ask = nil).
function AU.rewardIndex()
  local n = (G.GetNumQuestChoices and G.GetNumQuestChoices()) or 0
  if n <= 1 then return 1 end
  local rule = AU.rewardRule()
  if rule == "leader" then return AU.leaderReward[questId() or -1] end
  if rule == "value" then
    local best, bi = -1, nil
    for i = 1, n do
      local link = G.GetQuestItemLink and G.GetQuestItemLink("choice", i)
      local price = link and G.GetItemInfo and select(11, G.GetItemInfo(link)) or 0
      if (price or 0) > best then best, bi = price or 0, i end
    end
    return bi
  end
  return nil
end
AU.completeOpen = false
function AU.chooseReward()
  if not (AU.completeOpen and AU.on("turnin")) then return end
  if skipShift("reward") then return end
  local i = AU.rewardIndex()
  if i and call(G.GetQuestReward, i) then AU.completeOpen = false; AU.did("Took reward " .. i .. " for quest " .. tostring(questId()) .. ".") end
end
function AU.onQuestComplete() AU.completeOpen = true; AU.chooseReward() end
--- Leader: tell the followers which reward it picked (hooked on GetQuestReward).
function AU.leaderPicked(i)
  if AU.isLeader() and i then AU.send("QR", questId() or 0, i) end
end
--- Leader abandoned a quest: followers drop it too (never a completed one).
function AU.leaderAbandoned()
  if not AU.isLeader() then return end
  local QL = G.C_QuestLog
  local id = QL and QL.GetAbandonQuest and C().safe(QL.GetAbandonQuest()) or nil
  local name = G.GetAbandonQuestName and C().safe(G.GetAbandonQuestName()) or ""
  AU.send("QA", id or 0, name)
end
function AU.abandonHere(id, name)
  if not AU.on("abandon") or skipShift("abandon") then return end
  local QL = G.C_QuestLog
  if QL and QL.GetLogIndexForQuestID and id and id > 0 then
    local idx = QL.GetLogIndexForQuestID(id)
    if not idx then return end
    if QL.IsComplete and QL.IsComplete(id) then return end
    if pcall(QL.SetSelectedQuest, id) and call(QL.SetAbandonQuest) and call(QL.AbandonQuest) then AU.did("Abandoned quest " .. id .. " with the leader.") end
  elseif G.GetNumQuestLogEntries and G.GetQuestLogTitle then
    for i = 1, G.GetNumQuestLogEntries() do
      local title, _, _, header, _, complete, _, qid = G.GetQuestLogTitle(i)
      if not header and ((id and id > 0 and qid == id) or (name ~= "" and title == name)) then
        if complete == 1 then return end
        if pcall(G.SelectQuestLogEntry, i) and call(G.SetAbandonQuest) and call(G.AbandonQuest) then AU.did("Abandoned " .. tostring(title) .. " with the leader.") end
        return
      end
    end
  end
end

-- ------------------------------------------------------------------ 3. dialog sync (gossip, quest lists, flights)
AU.NEVER = { "logout", "log out", "quit", "delete", "destroy", "unlearn", "reset my talents", "reset talents", "abandon" }
local function dangerous(text)
  local t = tostring(text or ""):lower()
  for _, w in ipairs(AU.NEVER) do if t:find(w, 1, true) then return true end end
  return false
end
AU.window = {} -- what NPC window is open here: {gossip = npc name, taxi = true, quest = npc name}
local function npcName() return (G.UnitName and C().safe(G.UnitName("npc"))) or nil end
--- Gossip option texts here (Classic: GetGossipOptions pairs; modern: C_GossipInfo.GetOptions).
function AU.gossipOptions()
  local out = {}
  local GI = G.C_GossipInfo
  if GI and GI.GetOptions then
    local ok, list = pcall(GI.GetOptions)
    for _, o in ipairs(ok and list or {}) do out[#out + 1] = { text = o.name, id = o.gossipOptionID } end
  elseif G.GetGossipOptions then
    local r = { G.GetGossipOptions() }
    for i = 1, #r, 2 do out[#out + 1] = { text = r[i], id = (i + 1) / 2 } end
  end
  return out
end
local function choiceCount()
  local GI = G.C_GossipInfo
  local n = #AU.gossipOptions()
  if GI and GI.GetNumAvailableQuests then n = n + (GI.GetNumAvailableQuests() or 0) + (GI.GetNumActiveQuests() or 0)
  elseif G.GetNumGossipAvailableQuests then n = n + (G.GetNumGossipAvailableQuests() or 0) + (G.GetNumGossipActiveQuests() or 0) end
  return n
end
--- Leader picked something in a dialog: send it (kind g = gossip option, a / c = available / active quest, t = flight).
function AU.leaderChose(kind, index, text)
  if not (AU.isLeader() and C().inParty()) then return end
  if kind ~= "t" and choiceCount() <= 1 then return end -- single-option dialogs (vendors, trainers): nothing to sync
  if dangerous(text) then Core().log("info", "auto: dialog choice not synced (never: " .. tostring(text) .. ")"); return end
  AU.send("D", kind == "t" and "taxi" or (npcName() or ""), kind, index or 0, text or "")
end
--- A follower with the same window open picks the same; anything else is ignored.
function AU.applyDialog(npc, kind, index, text, from)
  if not AU.on("dialog") or AU.isLeader() or dangerous(text) or skipShift("dialog") then return false end
  local GI = G.C_GossipInfo
  if kind == "t" then
    if not AU.window.taxi or not G.NumTaxiNodes then return false end
    for i = 1, G.NumTaxiNodes() do
      if G.TaxiNodeName(i) == text then
        local cost = G.TaxiNodeCost and G.TaxiNodeCost(i) or 0
        if cost > AU.TAXI_LIMIT then Core().log("info", "auto: flight not synced (costs " .. cost .. ")"); return false end
        AU.applying = true
        local okT = call(G.TakeTaxiNode, i)
        AU.applying = false
        if okT then AU.did("Took the flight to " .. text .. " like " .. from.name .. "."); return true end
      end
    end
    return false
  end
  if not (AU.window.gossip and AU.window.gossip == npc) then return false end -- not the same NPC window here
  if kind == "g" then
    for _, o in ipairs(AU.gossipOptions()) do
      if o.text == text then
        local ok = GI and GI.SelectOption and pcall(GI.SelectOption, o.id) or call(G.SelectGossipOption, o.id)
        if ok then AU.did("Picked \"" .. text .. "\" like " .. from.name .. "."); return true end
      end
    end
  elseif kind == "a" or kind == "c" then
    local ok
    if GI and GI.SelectAvailableQuest then ok = pcall(kind == "a" and GI.SelectAvailableQuest or GI.SelectActiveQuest, index)
    else ok = call(kind == "a" and G.SelectGossipAvailableQuest or G.SelectGossipActiveQuest, index) end
    if ok then AU.did("Picked the quest " .. tostring(text) .. " like " .. from.name .. "."); return true end
  end
  return false
end

-- ------------------------------------------------------------------ 3b. leader: take every quest a quest giver offers
-- The leader opened the NPC (own key press). WoWBoxer opens the first quest not tried yet in this NPC window;
-- QUEST_DETAIL then accepts it. When the NPC shows its list again, the next one follows. [AFKLAR: whether Forever
-- returns to the list after an accept, or the leader talks to the NPC again for the next quest.]
AU.picked = { npc = nil, at = 0, tried = {} }
AU.PICK_MAX = 12
local function pickSession()
  local npc, t = npcName(), now()
  local P = AU.picked
  if P.npc ~= npc or t - P.at > 120 then P.npc, P.tried, P.n = npc, {}, 0 end
  P.at = t
  return P
end
--- Available quests here: {{key, title, pick = function}} – modern gossip, Classic gossip or a quest greeting.
function AU.availableQuests(greeting)
  local out, GI = {}, G.C_GossipInfo
  if greeting then
    local n = G.GetNumAvailableQuests and C().safe(G.GetNumAvailableQuests()) or 0
    for i = 1, (tonumber(n) or 0) do
      local title = G.GetAvailableTitle and C().safe(G.GetAvailableTitle(i)) or ("#" .. i)
      out[#out + 1] = { key = "g:" .. tostring(title), title = title, pick = function() return call(G.SelectAvailableQuest, i) end }
    end
  elseif GI and GI.GetAvailableQuests and GI.SelectAvailableQuest then
    local ok, list = pcall(GI.GetAvailableQuests)
    for _, q in ipairs(ok and type(list) == "table" and list or {}) do
      local id = C().safe(q.questID)
      if id then out[#out + 1] = { key = "q:" .. tostring(id), title = C().safe(q.title) or ("#" .. id), pick = function() return pcall(GI.SelectAvailableQuest, id) end } end
    end
  elseif G.GetNumGossipAvailableQuests and G.SelectGossipAvailableQuest then
    local n = tonumber(C().safe(G.GetNumGossipAvailableQuests())) or 0
    local raw = G.GetGossipAvailableQuests and { G.GetGossipAvailableQuests() } or {}
    local per = n > 0 and math.floor(#raw / n) or 0
    for i = 1, n do
      local title = type(raw[1]) == "table" and raw[i] and raw[i].title or (per > 0 and raw[(i - 1) * per + 1]) or ("#" .. i)
      out[#out + 1] = { key = "g:" .. tostring(title), title = tostring(title), pick = function() return call(G.SelectGossipAvailableQuest, i) end }
    end
  end
  return out
end
--- GOSSIP_SHOW / QUEST_GREETING on the leader: open the next quest not tried in this NPC window.
function AU.leaderTakeQuests(greeting)
  if not (AU.on("quests") and AU.isLeader()) or shift() then return false end
  local P = pickSession()
  if (P.n or 0) >= AU.PICK_MAX then return false end
  for _, q in ipairs(AU.availableQuests(greeting)) do
    if not P.tried[q.key] then
      P.tried[q.key], P.n = true, (P.n or 0) + 1
      if q.pick() then Core().log("info", "auto: leader opens quest " .. tostring(q.title)); return true end
    end
  end
  return false
end

-- ------------------------------------------------------------------ 4. resurrection, summons, role checks
function AU.onResurrect(name)
  if not AU.on("res") then return end
  local who = AU.allowed("res", name, true)
  if not who or skipShift("resurrection") then return end
  if call(G.AcceptResurrect) then
    if G.StaticPopup_Hide then pcall(G.StaticPopup_Hide, "RESURRECT"); pcall(G.StaticPopup_Hide, "RESURRECT_NO_SICKNESS") end
    AU.did("Accepted the resurrection from " .. who .. ".")
  end
end
function AU.onSummon()
  if not AU.on("summon") then return end
  local SI = G.C_SummonInfo
  local who = (SI and SI.GetSummonConfirmSummoner and SI.GetSummonConfirmSummoner()) or (G.GetSummonConfirmSummoner and G.GetSummonConfirmSummoner())
  local from = AU.allowed("summon", who, true)
  if not from or skipShift("summon") then return end
  local ok = (SI and SI.ConfirmSummon and pcall(SI.ConfirmSummon)) or call(G.ConfirmSummon)
  if ok then
    if G.StaticPopup_Hide then pcall(G.StaticPopup_Hide, "CONFIRM_SUMMON") end
    AU.did("Accepted the summon from " .. from .. ".")
  end
end
function AU.onRoleCheck()
  if not AU.on("rolecheck") then return end
  -- the group leader must be a squad member
  local leaderOk = false
  for _, u in ipairs(ns.Squad.PARTY) do
    if G.UnitIsGroupLeader and C().safe(G.UnitIsGroupLeader(u)) == true and AU.allowed("rolecheck", C().unitName(u), true) then leaderOk = true end
  end
  if AU.isLeader() and G.UnitIsGroupLeader and C().safe(G.UnitIsGroupLeader("player")) == true then leaderOk = true end
  if not leaderOk or skipShift("role check") then return end
  if call(G.CompleteLFGRoleCheck, true) then AU.did("Accepted the role check.") end
end

-- ------------------------------------------------------------------ 5. merchant
AU.RESTOCK = {
  priest = { { "Holy Candle", 20 }, { "Sacred Candle", 20 } }, paladin = { { "Symbol of Divinity", 5 }, { "Symbol of Kings", 40 } },
  shaman = { { "Ankh", 5 } }, mage = { { "Arcane Powder", 20 }, { "Rune of Teleportation", 5 }, { "Rune of Portals", 5 } },
  druid = { { "Wild Berries", 10 }, { "Wild Thornroot", 10 } }, rogue = { { "Flash Powder", 20 } },
  hunter = { { "Rough Arrow", 800 }, { "Sharp Arrow", 800 }, { "Razor Arrow", 800 }, { "Jagged Arrow", 800 },
    { "Light Shot", 800 }, { "Heavy Shot", 800 }, { "Solid Shot", 800 }, { "Accurate Slugs", 800 } },
}
AU.AMMO = { ["Rough Arrow"] = true, ["Sharp Arrow"] = true, ["Razor Arrow"] = true, ["Jagged Arrow"] = true, ["Light Shot"] = true,
  ["Heavy Shot"] = true, ["Solid Shot"] = true, ["Accurate Slugs"] = true }
local function bagApi()
  local CC = G.C_Container
  return {
    slots = (CC and CC.GetContainerNumSlots) or G.GetContainerNumSlots,
    info = function(b, s)
      if CC and CC.GetContainerItemInfo then
        local t = CC.GetContainerItemInfo(b, s)
        return t and { link = t.hyperlink, quality = t.quality, count = t.stackCount, noValue = t.hasNoValue, locked = t.isLocked }
      end
      if G.GetContainerItemInfo then
        local _, count, locked, quality, _, _, link, _, noValue = G.GetContainerItemInfo(b, s)
        return link and { link = link, quality = quality, count = count, noValue = noValue, locked = locked }
      end
    end,
    use = (CC and CC.UseContainerItem) or G.UseContainerItem,
  }
end
--- Sell grey items and the shared sell list (db.settings.sellList: item names). Returns the count sold.
function AU.sellJunk()
  local api = bagApi()
  if not (api.slots and api.use) then return 0 end
  local list = {}
  for _, n in ipairs(db().sellList or {}) do if type(n) == "string" then list[n:lower()] = true end end
  local n = 0
  for bag = 0, 4 do
    for slot = 1, (api.slots(bag) or 0) do
      local it = api.info(bag, slot)
      if it and not it.locked and not it.noValue and it.link then
        local name = it.link:match("%[(.-)%]")
        if (it.quality == 0) or (name and list[name:lower()]) then
          if pcall(api.use, bag, slot) then n = n + 1 end
        end
      end
    end
  end
  return n
end
function AU.repair()
  if not (G.CanMerchantRepair and G.CanMerchantRepair()) then return 0 end
  local cost = G.GetRepairAllCost and G.GetRepairAllCost() or 0
  if cost <= 0 then return 0 end
  local money = G.GetMoney and G.GetMoney() or 0
  local floor = tonumber(db().repairFloor) or AU.GOLD_FLOOR
  if money - cost < floor then Core().log("info", "auto: repair skipped (would go below the gold floor)"); return 0 end
  if call(G.RepairAllItems) then return cost end
  return 0
end
--- Buy class reagents up to their amount (ammo only of a kind you already carry). Returns the number of buys.
function AU.restock()
  local cls = C().playerClass and C().playerClass() or nil
  local list = cls and AU.RESTOCK[cls] or nil
  if not (list and G.GetMerchantNumItems and G.BuyMerchantItem) then return 0 end
  local want = {}
  for _, x in ipairs(list) do want[x[1]] = x[2] end
  local n = 0
  for i = 1, G.GetMerchantNumItems() do
    local name, _, _, quantity = G.GetMerchantItemInfo(i)
    local target = name and want[name]
    local have = name and G.GetItemCount and G.GetItemCount(name) or 0
    if target and (not AU.AMMO[name] or have > 0) and have < target then
      local need = target - have
      local stack = (G.GetMerchantItemMaxStack and G.GetMerchantItemMaxStack(i)) or need
      local buy = math.min(need, stack)
      if (quantity or 1) > 1 then buy = math.max(1, math.floor(buy / quantity)) end
      if pcall(G.BuyMerchantItem, i, buy) then n = n + 1; AU.did("Bought " .. name .. " (" .. need .. " to " .. target .. ").") end
    end
  end
  return n
end
function AU.onMerchant()
  if shift() then Core().log("info", "auto: merchant skipped (Shift held)"); return end
  if AU.on("sell") then local n = AU.sellJunk(); if n > 0 then AU.did("Sold " .. n .. " junk item" .. (n == 1 and "" or "s") .. ".") end end
  if AU.on("repair") then
    local c = AU.repair()
    if c > 0 then AU.did("Repaired for " .. (G.GetCoinText and G.GetCoinText(c) or (c .. " copper")) .. ".") end
  end
  if AU.on("restock") then AU.restock() end
end

-- ------------------------------------------------------------------ the nudge (once per character, §6)
--- Is any automation on (beyond resurrections and summons, which are on by default)?
function AU.anyOn()
  for _, o in ipairs(AU.OPTIONS) do if o[1] ~= "res" and o[1] ~= "summon" and o[1] ~= "chat" and not o[5] and AU.on(o[1]) then return true end end
  return false
end
--- At login, in a squad of two or more with automation off: ask once on this character.
function AU.nudge()
  local cdb = Core().cdb
  local s = Core().me()
  if not cdb or cdb.autoNudged or AU.anyOn() or not (s and #s.members >= 2) or not (ns.UI and ns.UI.Popup) then return false end
  cdb.autoNudged = true
  ns.UI.Popup("Automation is off – turn on Default squad values? Invites, quests, dialogs, resurrections, summons and the vendor, for your squad only.", {
    { "Yes", function() AU.preset(); Core().log("info", "automation: default squad values (nudge)"); Core().changed() end, "Turns on the Default squad values preset." },
    { "Choose…", function() ns.UI.Open("automation") end, "Opens the Automation page: one tick per automation." },
    { "Not now", function() end, "Does not ask again on this character. Automation is in the book." } })
  Core().log("info", "automation nudge shown")
  return true
end
--- The automation choice for the share string (data only): {on = {keys}, from}.
function AU.export()
  local on = {}
  for _, o in ipairs(AU.OPTIONS) do if AU.on(o[1]) then on[#on + 1] = o[1] end end
  return { on = on, from = AU.acceptFrom() }
end
--- Apply an imported automation choice (the Import click is the confirmation). Unknown keys are dropped.
function AU.import(t)
  if type(t) ~= "table" or type(t.on) ~= "table" then return false end
  local want = {}
  for _, k in ipairs(t.on) do if AU.BY_KEY[k] then want[k] = true end end
  for _, o in ipairs(AU.OPTIONS) do AU.set(o[1], want[o[1]] == true) end
  if t.from == "squad" or t.from == "friends" then db().acceptFrom = t.from end -- "everyone" never travels
  return true
end

-- ------------------------------------------------------------------ probes (diagnose) and events
--- Which automation APIs this client has (read-only). [AFKLAR: which ones work without a key press on Forever.]
function AU.probe()
  local r = {}
  local function has(path)
    local t = G
    for part in path:gmatch("[^%.]+") do t = type(t) == "table" and t[part] or nil end
    return type(t) == "function"
  end
  for _, p in ipairs({ "AcceptGroup", "C_PartyInfo.InviteUnit", "InviteUnit", "AcceptQuest", "ConfirmAcceptQuest", "CompleteQuest", "GetQuestReward",
    "QuestLogPushQuest", "C_QuestLog.SetSelectedQuest", "SelectQuestLogEntry", "C_QuestLog.AbandonQuest", "AbandonQuest",
    "C_GossipInfo.SelectOption", "SelectGossipOption", "C_GossipInfo.SelectAvailableQuest", "SelectGossipAvailableQuest", "TakeTaxiNode",
    "AcceptResurrect", "C_SummonInfo.ConfirmSummon", "ConfirmSummon", "CompleteLFGRoleCheck", "RepairAllItems", "C_Container.UseContainerItem",
    "UseContainerItem", "BuyMerchantItem" }) do r[p] = has(p) end
  r.afklar = "InviteUnit / TakeTaxiNode / AcceptQuest without a key press on Forever – check in the launch test"
  return r
end

local f = CreateFrame("Frame")
AU.frame = f
local EVENTS = { "CHAT_MSG_ADDON", "PARTY_INVITE_REQUEST", "QUEST_DETAIL", "QUEST_ACCEPT_CONFIRM", "QUEST_ACCEPTED", "QUEST_PROGRESS",
  "QUEST_COMPLETE", "QUEST_FINISHED", "QUEST_GREETING", "GOSSIP_SHOW", "GOSSIP_CLOSED", "TAXIMAP_OPENED", "TAXIMAP_CLOSED", "RESURRECT_REQUEST",
  "CONFIRM_SUMMON", "LFG_ROLE_CHECK_SHOW", "MERCHANT_SHOW", "GROUP_ROSTER_UPDATE", "QUEST_REMOVED" }
function AU.Init()
  local CI = G.C_ChatInfo
  local regp = (CI and CI.RegisterAddonMessagePrefix) or G.RegisterAddonMessagePrefix
  if regp then pcall(regp, AU.PREFIX) end
  for _, ev in ipairs(EVENTS) do pcall(f.RegisterEvent, f, ev) end
  -- the leader's own choices (hooks only listen; they never change what the leader does)
  local hook = G.hooksecurefunc
  if hook then
    local GI = G.C_GossipInfo
    local function optText(id) for _, o in ipairs(AU.gossipOptions()) do if o.id == id then return o.text end end end
    if GI and GI.SelectOption then pcall(hook, GI, "SelectOption", function(id) AU.leaderChose("g", id, optText(id)) end)
    elseif G.SelectGossipOption then pcall(hook, "SelectGossipOption", function(i) AU.leaderChose("g", i, optText(i)) end) end
    if GI and GI.SelectAvailableQuest then pcall(hook, GI, "SelectAvailableQuest", function(id) AU.leaderChose("a", id, tostring(id)) end)
    elseif G.SelectGossipAvailableQuest then pcall(hook, "SelectGossipAvailableQuest", function(i) AU.leaderChose("a", i, tostring(i)) end) end
    if GI and GI.SelectActiveQuest then pcall(hook, GI, "SelectActiveQuest", function(id) AU.leaderChose("c", id, tostring(id)) end)
    elseif G.SelectGossipActiveQuest then pcall(hook, "SelectGossipActiveQuest", function(i) AU.leaderChose("c", i, tostring(i)) end) end
    if G.TakeTaxiNode then pcall(hook, "TakeTaxiNode", function(i) if not AU.applying then AU.leaderChose("t", i, G.TaxiNodeName and G.TaxiNodeName(i)) end end) end
    if G.GetQuestReward then pcall(hook, "GetQuestReward", function(i) AU.leaderPicked(i) end) end
    if G.AbandonQuest then pcall(hook, "AbandonQuest", function() AU.leaderAbandoned() end) end
  end
  if G.C_Timer and G.C_Timer.NewTicker then G.C_Timer.NewTicker(30, function() pcall(AU.inviteMissing) end) end
end
f:SetScript("OnEvent", function(_, event, a, b, c, d)
  if not Core().db then return end
  local ok, err = pcall(function()
    if event == "CHAT_MSG_ADDON" then AU.receive(a, b, c, d)
    elseif event == "PARTY_INVITE_REQUEST" then AU.onInvite(a)
    elseif event == "QUEST_DETAIL" then AU.onQuestDetail()
    elseif event == "QUEST_ACCEPT_CONFIRM" then AU.onQuestConfirm(a)
    elseif event == "QUEST_ACCEPTED" then AU.onQuestAccepted(a, b)
    elseif event == "QUEST_REMOVED" then if AU.isLeader() then AU.sendQuestList() end
    elseif event == "QUEST_PROGRESS" then AU.onQuestProgress()
    elseif event == "QUEST_COMPLETE" then AU.onQuestComplete()
    elseif event == "QUEST_FINISHED" then AU.completeOpen = false; AU.detailOpen = nil
    elseif event == "GOSSIP_SHOW" then AU.window.gossip = npcName(); AU.leaderTakeQuests(false)
    elseif event == "QUEST_GREETING" then AU.leaderTakeQuests(true)
    elseif event == "GOSSIP_CLOSED" then AU.window.gossip = nil
    elseif event == "TAXIMAP_OPENED" then AU.window.taxi = true
    elseif event == "TAXIMAP_CLOSED" then AU.window.taxi = nil
    elseif event == "RESURRECT_REQUEST" then AU.onResurrect(a)
    elseif event == "CONFIRM_SUMMON" then AU.onSummon()
    elseif event == "LFG_ROLE_CHECK_SHOW" then AU.onRoleCheck()
    elseif event == "MERCHANT_SHOW" then AU.onMerchant()
    elseif event == "GROUP_ROSTER_UPDATE" then AU.inviteMissing(); if AU.isLeader() then AU.sendQuestList() end
    end
  end)
  if not ok then Core().log("error", "auto " .. event .. ": " .. tostring(err)) end
end)

return AU
