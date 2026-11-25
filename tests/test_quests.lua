-- Quest givers + Shared quests (owner, 25 Nov 2026; docs/automation-policy.md): every mode × leader or follower × a
-- quest giver's quest or a share × a squad member or a stranger; QUEST_ACCEPT_CONFIRM; the migration of the old
-- Accept quests tick; chain quests that wait for the squad's turn-ins (QT); escorts and events; never a quest that is
-- already in the log; Shift skips.
local dir = (arg[0]:match("^(.*)/[^/]+$") or ".")
local H = dofile(dir .. "/harness.lua")
local Mock = dofile(dir .. "/wowmock.lua")

local PAL = { class = "PALADIN", race = "Scourge", level = 20 }
local PRI = { class = "PRIEST", race = "Scourge", level = 20 }
local HUN = { class = "HUNTER", race = "Orc", level = 20 }
local function boot(me)
  local lead = me == "Dorin"
  local W = Mock.new(H, { name = me, class = lead and "PALADIN" or "PRIEST", race = "Scourge", level = 20,
    party = lead and { party1 = "Anna", party2 = "Bo" } or { party1 = "Dorin", party2 = "Bo" },
    partyInfo = lead and { party1 = PRI, party2 = HUN } or { party1 = PAL, party2 = HUN } })
  local ns = H.loadAddon({ env = W.env })
  W.fire("ADDON_LOADED", "WoWBoxer"); W.fire("PLAYER_LOGIN")
  local sq = ns.State.newSquad({ name = "Trio", members = {
    { name = "Dorin", cls = "paladin", race = "undead", role = "tank", leader = true },
    { name = "Anna", cls = "priest", race = "undead", role = "healer" },
    { name = "Bo", cls = "hunter", race = "orc", role = "ranged" } } })
  ns.Core.db.squads = { sq }; ns.Core.db.active = sq.id
  W.did = {}
  for _, fn in ipairs({ "AcceptQuest", "ConfirmAcceptQuest", "GetQuestReward", "StaticPopup_Hide", "QuestLogPushQuest", "SelectQuestLogEntry" }) do
    W.env[fn] = function(...) W.did[#W.did + 1] = fn .. "(" .. table.concat((function(...) local t = {}; for i = 1, select("#", ...) do t[i] = tostring(select(i, ...)) end return t end)(...), ",") .. ")"; return true end
  end
  W.env.C_QuestLog = nil
  W.env.C_GossipInfo = nil
  W.now = 1000
  W.onScreen = {}
  W.env.UIErrorsFrame = W.env.CreateFrame("Frame")
  W.env.UIErrorsFrame.AddMessage = function(_, t) W.onScreen[#W.onScreen + 1] = t end
  -- the quest window: an NPC by default; share(W, name) makes "questnpc" that player
  local oldUN = W.env.UnitName
  W.questnpc = nil
  W.env.UnitIsPlayer = function(u) if u == "questnpc" then return W.questnpc ~= nil end return true end
  W.env.UnitName = function(u) if u == "questnpc" then return W.questnpc or "Marshal Dughan" end return oldUN(u) end
  W.env.GetTitleText = function() return "Quest " .. tostring(W.qid) end
  W.env.GetQuestID = function() return W.qid end
  return W, ns
end
local function did(W, name) for _, c in ipairs(W.did) do if c:find("^" .. name .. "%(") then return c end end return nil end
local function msg(W, from, text) W.fire("CHAT_MSG_ADDON", "WBXA", text, "PARTY", from) end
local function sent(W, text) for _, m in ipairs(W.sent) do if m.msg == text then return true end end return false end
--- Open quest id in the quest window (from = nil: a quest giver; a name: that player shares it). True = accepted.
local function detail(W, id, from)
  W.did = {}
  W.qid, W.questnpc = id, from
  W.fire("QUEST_DETAIL")
  return did(W, "AcceptQuest") ~= nil
end
local function close(W) W.fire("QUEST_FINISHED") end
local function fresh(ns)
  local AU = ns.Auto
  AU.leaderQuests, AU.turnIns, AU.lastTurnIn, AU.waiting, AU.asked, AU.lastNotice = {}, {}, nil, nil, {}, nil
end

-- ------------------------------------------------------------------ the options and the migration
do
  local W, ns = boot("Anna")
  local AU = ns.Auto
  local s = ns.Core.db.settings
  s.auto = nil
  H.eq(AU.questGiverMode(), "off", "nothing stored: Quest givers Off (today's default)")
  H.eq(AU.on("questShared"), false, "nothing stored: Shared quests off")
  s.auto = { quests = true }
  H.eq(AU.questGiverMode(), "all", "old Accept quests on reads as Leader and followers")
  H.eq(AU.on("questShared"), true, "… and Shared quests on")
  H.ok(s.auto.quests == true and s.auto.questGivers == nil and s.auto.questShared == nil, "reading it writes nothing")
  s.auto = { quests = false }
  H.ok(AU.questGiverMode() == "off" and not AU.on("questShared"), "old Accept quests off reads as Off + Shared quests off")
  s.auto = { quests = true }
  AU.setQuestGivers("followers")
  H.ok(s.auto.questGivers == "followers" and s.auto.questShared == true and s.auto.quests == nil, "the first set stores both and drops the old key")
  s.auto = { quests = true }
  AU.set("questShared", false)
  H.ok(s.auto.questGivers == "all" and s.auto.questShared == false and s.auto.quests == nil, "setting Shared quests keeps Quest givers from the old key")
  s.auto = { quests = false }
  AU.set("questGivers", true)
  H.ok(s.auto.questGivers == "all" and s.auto.questShared == false, "Quest givers on from Off: Leader and followers; Shared quests stays off")
  AU.setQuestGivers("followers"); AU.set("questGivers", true)
  H.eq(AU.questGiverMode(), "followers", "on keeps Followers only")
  AU.set("questGivers", false)
  H.eq(AU.questGiverMode(), "off", "off = Off")
  H.eq(AU.setQuestGivers("bogus"), false, "an unknown value is refused")
  AU.set("quests", true)
  H.ok(AU.questGiverMode() == "all" and AU.on("questShared"), "set(quests) (old) turns both on")
  AU.setAll(false); H.ok(AU.questGiverMode() == "off" and not AU.on("questShared"), "All off: both off")
  AU.setAll(true); H.ok(AU.questGiverMode() == "all" and AU.on("questShared"), "All on: Leader and followers + Shared")
  AU.setAll(false); AU.preset(); H.ok(AU.questGiverMode() == "all" and AU.on("questShared"), "Levelling preset: Leader and followers + Shared")
  AU.setAll(false); AU.defaults(); H.ok(AU.questGiverMode() == "all" and AU.on("questShared") and not AU.on("questAny"), "Default: Leader and followers + Shared, not Accept any quest")
  -- share strings: old ones carry "quests", new ones the choice
  AU.setAll(false)
  H.ok(AU.import({ on = { "quests", "invite" }, from = "squad" }), "an old share string imports")
  H.ok(AU.questGiverMode() == "all" and AU.on("questShared") and AU.on("invite"), "old string with quests: Leader and followers + Shared")
  AU.import({ on = { "invite" }, from = "squad" })
  H.ok(AU.questGiverMode() == "off" and not AU.on("questShared"), "old string without quests: Off + Shared off")
  AU.setAll(false); AU.setQuestGivers("followers"); AU.set("questShared", true)
  local ex = AU.export()
  H.eq(ex.qg, "followers", "export carries the Quest givers choice")
  local str = ns.Core.exportString()
  local res = ns.Share.import(str)
  H.ok(res and res.auto and res.auto.qg == "followers", "the share string carries it (data only)")
  AU.setAll(false)
  ns.Core.applyImport(res)
  H.ok(AU.questGiverMode() == "followers" and AU.on("questShared"), "importing it: Followers only + Shared quests")
  local bad = ns.Share.validate({ squad = res.squad and { name = "X", members = {} } or nil, auto = { on = { "questGivers" }, qg = "loadstring" } })
  H.ok(not (bad and bad.auto and bad.auto.qg), "a bad qg value is dropped")
  -- the settings list (Copy settings)
  local ST = ns.Settings
  AU.setAll(false); AU.setQuestGivers("followers"); AU.set("questShared", true)
  local text = ST.encode()
  H.ok(text:find("qg=followers", 1, true) and text:find("questShared", 1, true), "settings text: " .. text)
  AU.setAll(false)
  local t = ST.decode(text)
  for _, k in ipairs({ "auto", "qg" }) do ST.BY_KEY[k][4](t[k]) end
  H.ok(AU.questGiverMode() == "followers" and AU.on("questShared"), "settings text applied: Followers only + Shared")
  ST.BY_KEY.auto[4]("invite,quests")
  H.ok(AU.questGiverMode() == "all" and AU.on("questShared"), "an old settings text with quests: Leader and followers + Shared")
  H.eq(ST.BY_KEY.qg[4]("off") and AU.questGiverMode(), "off", "qg=off")
  -- the Automation page: Quest givers is a dropdown card, Shared quests a tick
  AU.setQuestGivers("all")
  ns.UI.Open("automation")
  local p = ns.UI.panels.automation
  local card = p.questGivers
  if H.ok(card and card.dd, "Automation page: Quest givers is a dropdown") then
    H.eq(card.label:GetText(), "Quest givers", "its name")
    local vals = card.dd.opts.values()
    H.eq(vals[1][2] .. "|" .. vals[2][2] .. "|" .. vals[3][2], "Leader and followers|Followers only|Off", "the three choices")
    H.eq(card.line:GetText(), "The leader takes every quest; followers accept the leader's quests.", "the line for Leader and followers")
    card.dd.select("followers")
    H.ok(AU.questGiverMode() == "followers" and card.line:GetText():find("You pick quests on the leader", 1, true), "choosing Followers only")
    card.dd.select("off")
    H.ok(AU.questGiverMode() == "off" and card.line:GetText() == "Nothing is accepted from quest givers.", "choosing Off")
  end
  local shared
  for _, c in ipairs(p.ticks) do if c.key == "questShared" then shared = c end H.ok(c.key ~= "questGivers" and c.key ~= "quests", "no tick for " .. c.key .. " (Quest givers is the dropdown)") end
  if H.ok(shared, "Shared quests is a tick") then
    H.eq(shared.label:GetText(), "Shared quests", "its name")
    H.ok(not shared.own, "no Accept from of its own: squad members in the party only")
    AU.set("questShared", false); ns.UI.Refresh()
    shared:Click()
    H.ok(AU.on("questShared"), "the tick turns it on")
  end
  local d = ns.Core.selftest(true)
  H.ok(d.auto and d.auto.questGivers == "off" and d.auto.on.questShared == true, "diagnose: Quest givers and Shared quests")
end

-- ------------------------------------------------------------------ every mode × leader / follower × NPC / share × squad / stranger
do
  local L, nsL = boot("Dorin")
  local F, nsF = boot("Anna")
  local id = 2000
  local n = 0
  for _, mode in ipairs({ "all", "followers", "off" }) do
    for _, sharedOn in ipairs({ true, false }) do
      for _, role in ipairs({ "leader", "follower" }) do
        local W, ns = L, nsL
        if role == "follower" then W, ns = F, nsF end
        local AU = ns.Auto
        AU.setQuestGivers(mode); AU.set("questShared", sharedOn)
        for _, src in ipairs({ "npc", "share" }) do
          for _, who in ipairs({ "squad", "stranger" }) do
            fresh(ns); id = id + 1
            local from
            if src == "share" then from = who == "squad" and (role == "leader" and "Anna" or "Dorin") or "Stranger"
            else msg(W, who == "squad" and "Dorin" or "Stranger", "QL|" .. id) end -- a follower: the leader's (or a stranger's) quest list
            local want
            if src == "share" then want = sharedOn and who == "squad"
            elseif role == "leader" then want = mode == "all"
            else want = mode ~= "off" and who == "squad" end
            local tag = mode .. " × shared " .. (sharedOn and "on" or "off") .. " × " .. role .. " × " .. src .. " × " .. who
            H.eq(detail(W, id, from), want, tag)
            close(W)
            n = n + 1
          end
        end
        -- QUEST_ACCEPT_CONFIRM (an escort / event a squad member starts): Shared quests, squad members in the party only
        for _, who in ipairs({ "squad", "stranger" }) do
          W.did = {}
          W.fire("QUEST_ACCEPT_CONFIRM", who == "squad" and "Bo" or "Stranger", "Escort " .. id)
          H.eq(did(W, "ConfirmAcceptQuest") ~= nil, sharedOn and who == "squad", mode .. " × " .. role .. " × confirm × " .. who)
        end
      end
    end
  end
  H.eq(n, 48, "48 cases")
  -- a squad member not in the party: no
  local AU = nsF.Auto
  AU.setQuestGivers("all"); AU.set("questShared", true)
  F.party.party2 = nil
  fresh(nsF)
  H.eq(detail(F, 3001, "Bo"), false, "a squad member who is not in the party: share not accepted")
  F.did = {}; F.fire("QUEST_ACCEPT_CONFIRM", "Bo", "Escort"); H.eq(did(F, "ConfirmAcceptQuest"), nil, "… nor their escort start")
  F.party.party2 = "Bo"
  -- Accept from does not widen Shared quests (squad members only)
  nsF.Core.db.settings.acceptFrom = "everyone"
  H.eq(detail(F, 3002, "Stranger"), false, "Accept from Everyone: a stranger's share is still not accepted")
  F.did = {}; F.fire("QUEST_ACCEPT_CONFIRM", "Stranger", "Escort"); H.eq(did(F, "ConfirmAcceptQuest"), nil, "… nor a stranger's escort")
  nsF.Core.db.settings.acceptFrom = nil
  -- Accept any quest keeps working under Quest givers
  AU.set("questAny", true)
  fresh(nsF)
  H.eq(detail(F, 3003), true, "Accept any quest: a follower takes a quest the leader does not have")
  close(F)
  AU.setQuestGivers("off")
  H.eq(detail(F, 3004), false, "Accept any quest with Quest givers Off: nothing")
  close(F)
  AU.set("questAny", false); AU.setQuestGivers("all")
  -- Shift skips: an NPC quest, a share, an escort start
  F.mods.shift = true
  msg(F, "Dorin", "QL|3005")
  H.eq(detail(F, 3005), false, "Shift: the leader's quest is not accepted"); close(F)
  H.eq(detail(F, 3006, "Dorin"), false, "Shift: a share is not accepted"); close(F)
  F.did = {}; F.fire("QUEST_ACCEPT_CONFIRM", "Dorin", "Escort"); H.eq(did(F, "ConfirmAcceptQuest"), nil, "Shift: an escort start is not joined")
  F.mods.shift = false
  L.mods.shift = true
  nsL.Auto.setQuestGivers("all")
  H.eq(detail(L, 3007), false, "Shift: the leader does not take the quest"); close(L)
  L.mods.shift = false
  -- the leader in Followers only never opens quests from the NPC list either
  nsL.Auto.setQuestGivers("followers")
  local picked = {}
  L.env.C_GossipInfo = { GetAvailableQuests = function() return { { questID = 41, title = "Wolves" } } end, SelectAvailableQuest = function(q) picked[#picked + 1] = q end,
    GetOptions = function() return {} end }
  nsL.Auto.picked.npc = nil; L.fire("GOSSIP_SHOW")
  H.eq(#picked, 0, "Followers only: the leader's NPC list is not opened")
  nsL.Auto.setQuestGivers("off"); nsL.Auto.picked.npc = nil; L.fire("GOSSIP_SHOW")
  H.eq(#picked, 0, "Off: not opened")
  nsL.Auto.setQuestGivers("all"); nsL.Auto.picked.npc = nil; L.fire("GOSSIP_SHOW")
  H.eq(table.concat(picked, ","), "41", "Leader and followers: the leader opens the first quest")
  L.env.C_GossipInfo = nil
end

-- ------------------------------------------------------------------ never a quest that is already in the log
do
  local W, ns = boot("Anna")
  local AU = ns.Auto
  AU.setQuestGivers("all"); AU.set("questShared", true); AU.set("questAny", true)
  W.env.GetNumQuestLogEntries = function() return 2 end
  W.env.GetQuestLogTitle = function(i)
    if i == 1 then return "Elwynn", 0, nil, true, false, nil, nil, nil end
    return "Wolves", 10, nil, false, false, nil, nil, 4000
  end
  fresh(ns)
  H.eq(detail(W, 4000), false, "an NPC quest already in the log: not accepted (Era log)")
  close(W)
  H.eq(detail(W, 4000, "Dorin"), false, "a share already in the log: not accepted")
  close(W)
  H.eq(detail(W, 4001), true, "another quest: accepted")
  close(W)
  W.did = {}; W.fire("QUEST_ACCEPT_CONFIRM", "Dorin", "Wolves")
  H.eq(did(W, "ConfirmAcceptQuest"), nil, "an escort start already in the log (by title): not joined")
  W.did = {}; W.fire("QUEST_ACCEPT_CONFIRM", "Dorin", "Bears")
  H.ok(did(W, "ConfirmAcceptQuest"), "another escort start: joined")
  -- modern quest log
  W.env.GetNumQuestLogEntries, W.env.GetQuestLogTitle = nil, nil
  W.env.C_QuestLog = { IsOnQuest = function(q) return q == 4100 end }
  H.eq(detail(W, 4100), false, "C_QuestLog.IsOnQuest: not accepted")
  close(W)
  W.env.C_QuestLog = { GetLogIndexForQuestID = function(q) if q == 4101 then return 3 end return nil end }
  H.eq(detail(W, 4101), false, "C_QuestLog.GetLogIndexForQuestID: not accepted")
  close(W)
  W.env.C_QuestLog = nil
end

-- ------------------------------------------------------------------ escorts and events
do
  local L, nsL = boot("Dorin")
  local F, nsF = boot("Anna")
  for _, ns in ipairs({ nsL, nsF }) do ns.Auto.setQuestGivers("all"); ns.Auto.set("questShared", true); ns.Auto.set("questAny", true) end
  local function tagged(W, id, form)
    W.env.GetQuestTagInfo, W.env.C_QuestLog = nil, nil
    if form == "classic" then W.env.GetQuestTagInfo = function(q) if q == id then return 84, "Escort" end return nil end
    elseif form == "modern" then W.env.C_QuestLog = { GetQuestTagInfo = function(q) if q == id then return { tagID = 84, tagName = "Escort" } end return nil end }
    elseif form == "type" then W.env.C_QuestLog = { GetQuestType = function(q) if q == id then return 84 end return 0 end } end
  end
  for _, form in ipairs({ "classic", "modern", "type" }) do
    tagged(L, 5000, form); fresh(nsL)
    H.eq(detail(L, 5000), false, "leader: an escort (" .. form .. " tag) is never accepted by itself")
    H.ok(L.onScreen[#L.onScreen] and L.onScreen[#L.onScreen]:find("escort or event", 1, true), "leader: a line on screen: " .. tostring(L.onScreen[#L.onScreen]))
    close(L)
    tagged(F, 5000, form); fresh(nsF)
    msg(F, "Dorin", "QL|5000")
    H.eq(detail(F, 5000), false, "follower: an escort from the NPC is never accepted, even when the leader has it (" .. form .. ")")
    close(F)
  end
  tagged(L, 0, "none"); tagged(F, 0, "none")
  fresh(nsL)
  H.eq(detail(L, 1447), false, "The Missing Diplomat (1447, an event) is never accepted on the leader by itself")
  close(L)
  fresh(nsF); msg(F, "Dorin", "QL|1447")
  H.eq(detail(F, 1447), false, "… nor from the NPC on a follower")
  close(F)
  F.did = {}; F.fire("QUEST_ACCEPT_CONFIRM", "Dorin", "The Missing Diplomat")
  H.ok(did(F, "ConfirmAcceptQuest"), "the follower joins when the leader starts it (QUEST_ACCEPT_CONFIRM)")
  H.eq(detail(L, 5001), true, "an untagged quest: the leader accepts it")
  close(L)
  local d = nsL.Core.selftest(true)
  H.ok(d.auto.questTag and d.auto.questTag.id == 5001, "diagnose: the last quest's tag probe [AFKLAR]")
end

-- ------------------------------------------------------------------ chain quests wait for the squad's turn-ins
do
  local L, ns = boot("Dorin")
  local AU = ns.Auto
  AU.setQuestGivers("all"); AU.set("questShared", true); AU.set("turnin", true)
  L.env.GetNumQuestChoices = function() return 0 end
  local function turnIn(id)
    L.qid, L.questnpc = id, nil
    L.did = {}
    L.fire("QUEST_COMPLETE")
    H.ok(did(L, "GetQuestReward"), "leader turns in " .. id)
    close(L)
  end
  -- the leader turns in 1246; the NPC offers the next quest at once
  fresh(ns); L.now = 1000
  turnIn(1246)
  L.now = 1001
  H.eq(detail(L, 1250), false, "the next quest right after a turn-in waits")
  H.eq(AU.lastNotice, "Waiting for Anna, Bo to turn in.", "a short line on screen")
  H.eq(L.onScreen[#L.onScreen], "Waiting for Anna, Bo to turn in.", "shown in the error frame")
  L.did = {}
  msg(L, "Stranger", "QT|1246")
  H.eq(did(L, "AcceptQuest"), nil, "a stranger's turn-in does not count")
  msg(L, "Anna", "QT|999")
  H.eq(did(L, "AcceptQuest"), nil, "a turn-in of another quest does not count")
  msg(L, "Anna", "QT|1246")
  H.eq(did(L, "AcceptQuest"), nil, "one follower turned in: still waiting")
  H.eq(AU.lastNotice, "Waiting for Bo to turn in.", "the line names who is left")
  L.now = 1005
  msg(L, "Bo", "QT|1246")
  H.ok(did(L, "AcceptQuest"), "every squad member in the party turned in: accepted")
  H.eq(AU.waiting, nil, "not waiting any more")
  close(L)
  -- the timeout: about 20 s, then the quest is accepted
  fresh(ns); L.now = 2000
  turnIn(1300)
  L.now = 2002
  H.eq(detail(L, 1301), false, "waits")
  L.did = {}; L.now = 2010; L.flush()
  L.now = 2010
  AU.chainCheck()
  H.eq(did(L, "AcceptQuest"), nil, "after 8 s: still waiting")
  L.now = 2023; L.flush()
  H.ok(did(L, "AcceptQuest"), "after 20 s: accepted")
  close(L)
  -- the leader closed the window while waiting: nothing is accepted later
  fresh(ns); L.now = 3000
  turnIn(1400)
  L.now = 3001
  H.eq(detail(L, 1401), false, "waits")
  close(L)
  L.did = {}; msg(L, "Anna", "QT|1400"); msg(L, "Bo", "QT|1400"); L.now = 3030; L.flush()
  H.eq(did(L, "AcceptQuest"), nil, "window closed: nothing accepted later")
  -- the followers turned in first: accepted at once
  fresh(ns); L.now = 4000
  msg(L, "Anna", "QT|1500"); msg(L, "Bo", "QT|1500")
  turnIn(1500)
  L.now = 4001
  H.eq(detail(L, 1501), true, "the followers turned in before the leader: accepted at once")
  close(L)
  -- not right after a turn-in: accepted at once
  fresh(ns); L.now = 5000
  turnIn(1600)
  L.now = 5030
  H.eq(detail(L, 1601), true, "a quest opened later (not the chain offer): accepted at once")
  close(L)
  -- only squad members in the party are waited for
  fresh(ns); L.now = 6000
  L.party.party2 = nil
  turnIn(1700)
  L.now = 6001
  H.eq(detail(L, 1701), false, "waits")
  H.eq(AU.lastNotice, "Waiting for Anna to turn in.", "Bo is not in the party: not waited for")
  msg(L, "Anna", "QT|1700")
  H.ok(did(L, "AcceptQuest"), "Anna turned in: accepted")
  close(L)
  L.party.party2 = "Bo"
  -- Shift held when the last turn-in arrives: skipped
  fresh(ns); L.now = 7000
  turnIn(1800)
  L.now = 7001
  H.eq(detail(L, 1801), false, "waits")
  msg(L, "Anna", "QT|1800")
  L.mods.shift = true; L.did = {}
  msg(L, "Bo", "QT|1800")
  L.mods.shift = false
  H.eq(did(L, "AcceptQuest"), nil, "Shift held: skipped")
  close(L)
  -- an escort right after a turn-in: never accepted, also after everyone turned in
  fresh(ns); L.now = 8000
  turnIn(1246)
  L.now = 8001
  H.eq(detail(L, 1447), false, "The Missing Diplomat after 1246: not accepted")
  msg(L, "Anna", "QT|1246"); msg(L, "Bo", "QT|1246")
  H.eq(did(L, "AcceptQuest"), nil, "… also not after the followers turned in (the leader starts it)")
  close(L)
  -- Followers only / Off: the leader takes nothing, so there is nothing to wait for
  AU.setQuestGivers("followers")
  fresh(ns); L.now = 9000
  turnIn(1900)
  L.now = 9001
  H.eq(detail(L, 1901), false, "Followers only: the leader does not take the next quest")
  H.eq(AU.waiting, nil, "and does not wait")
  close(L)
end

-- ------------------------------------------------------------------ followers report each turn-in (QT)
do
  local F, ns = boot("Anna")
  local AU = ns.Auto
  AU.setQuestGivers("all"); AU.set("questShared", true); AU.set("turnin", true)
  F.env.GetNumQuestChoices = function() return 0 end
  F.sent = {}
  F.qid, F.questnpc = 1246, nil
  F.fire("QUEST_COMPLETE")
  H.ok(sent(F, "QT|1246"), "follower: the turn-in is sent to the leader (QT|1246)")
  local n = 0
  F.fire("QUEST_TURNED_IN", 1246, 0, 0)
  for _, m in ipairs(F.sent) do if m.msg == "QT|1246" then n = n + 1 end end
  H.eq(n, 1, "QUEST_TURNED_IN right after: not sent twice")
  close(F)
  F.sent = {}
  F.fire("QUEST_TURNED_IN", 1300, 0, 0)
  H.ok(sent(F, "QT|1300"), "a turn-in by hand (QUEST_TURNED_IN): sent too")
  -- the chain on a follower: the next quest waits for the leader's list, then it is accepted
  F.did = {}
  H.eq(detail(F, 1250), false, "follower: the next quest waits until the leader has it")
  msg(F, "Dorin", "QL|1250")
  H.ok(did(F, "AcceptQuest"), "the leader took it (QL): accepted")
  close(F)
  -- the leader never sends QT; a follower ignores QT
  local L, nsL = boot("Dorin")
  nsL.Auto.setQuestGivers("all"); nsL.Auto.set("turnin", true)
  L.env.GetNumQuestChoices = function() return 0 end
  L.sent = {}
  L.qid = 1246; L.fire("QUEST_COMPLETE")
  H.ok(not sent(L, "QT|1246"), "the leader does not send QT")
  msg(F, "Bo", "QT|1246")
  H.eq(next(AU.turnIns), nil, "a follower does not collect turn-ins")
end

os.exit(H.report("quests") and 0 or 1)
