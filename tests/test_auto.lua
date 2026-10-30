-- Squad automation (docs/automation-policy.md, CLAUDE.md hard rules 1 + 5): each automation is mocked with a squad member
-- vs a stranger, the option off, Shift held and secret values. Casting / targeting / moving / NPC interaction never.
local dir = (arg[0]:match("^(.*)/[^/]+$") or ".")
local H = dofile(dir .. "/harness.lua")
local Mock = dofile(dir .. "/wowmock.lua")

local PAL = { class = "PALADIN", race = "Scourge", level = 20 }
local HUN = { class = "HUNTER", race = "Orc", level = 20 }
local function boot(me, leader)
  local W = Mock.new(H, { name = me, class = me == "Dorin" and "PALADIN" or "PRIEST", race = "Scourge", level = 20,
    party = me == "Dorin" and { party1 = "Anna", party2 = "Bo" } or { party1 = "Dorin", party2 = "Bo" },
    partyInfo = me == "Dorin" and { party1 = { class = "PRIEST", race = "Scourge", level = 20 }, party2 = HUN } or { party1 = PAL, party2 = HUN } })
  local ns = H.loadAddon({ env = W.env })
  W.fire("ADDON_LOADED", "WoWBoxer"); W.fire("PLAYER_LOGIN")
  local sq = ns.State.newSquad({ name = "Trio", members = {
    { name = "Dorin", cls = "paladin", race = "undead", role = "tank", leader = true },
    { name = "Anna", cls = "priest", race = "undead", role = "healer", unit = "party1" },
    { name = "Bo", cls = "hunter", race = "orc", role = "ranged", unit = "party1" } } })
  ns.Core.db.squads = { sq }; ns.Core.db.active = sq.id
  -- calls the automation may make
  W.did = {}
  for _, fn in ipairs({ "AcceptGroup", "AcceptQuest", "ConfirmAcceptQuest", "CompleteQuest", "GetQuestReward", "QuestLogPushQuest", "SelectQuestLogEntry",
    "AcceptResurrect", "ConfirmSummon", "CompleteLFGRoleCheck", "RepairAllItems", "BuyMerchantItem", "TakeTaxiNode", "SelectGossipOption",
    "InviteUnit", "StaticPopup_Hide", "UseContainerItem" }) do
    W.env[fn] = function(...) W.did[#W.did + 1] = fn .. "(" .. table.concat((function(...) local t = {}; for i = 1, select("#", ...) do t[i] = tostring(select(i, ...)) end return t end)(...), ",") .. ")"; return true end
  end
  W.env.C_PartyInfo = nil
  W.env.C_GossipInfo = nil
  W.env.C_SummonInfo = nil
  W.env.C_QuestLog = nil
  W.env.C_Container = nil
  return W, ns
end
local function did(W, name) for _, c in ipairs(W.did) do if c:find("^" .. name .. "%(") then return c end end return nil end
local function reset(W) W.did = {} end
local function msg(W, from, text) W.fire("CHAT_MSG_ADDON", "WBXA", text, "PARTY", from) end

-- ------------------------------------------------------------------ follower Anna
do
  local W, ns = boot("Anna")
  local AU = ns.Auto
  H.ok(not AU.on("invite") and AU.on("res") and AU.on("summon"), "defaults: off, except resurrection and summons")
  -- invites
  W.fire("PARTY_INVITE_REQUEST", "Dorin")
  H.eq(did(W, "AcceptGroup"), nil, "option off: the invite is not accepted")
  AU.set("invite", true)
  W.fire("PARTY_INVITE_REQUEST", "Stranger")
  H.eq(did(W, "AcceptGroup"), nil, "a stranger's invite is never accepted")
  W.mods.shift = true; W.fire("PARTY_INVITE_REQUEST", "Dorin"); W.mods.shift = false
  H.eq(did(W, "AcceptGroup"), nil, "Shift held: skipped")
  W.fire("PARTY_INVITE_REQUEST", "Dorin-Silvermoon")
  H.ok(did(W, "AcceptGroup") and did(W, "StaticPopup_Hide"), "a squad member's invite is accepted (Name-Realm too)")
  W.env.issecretvalue = function(v) return v == "SECRET" end
  reset(W); W.fire("PARTY_INVITE_REQUEST", "SECRET")
  H.eq(did(W, "AcceptGroup"), nil, "a secret name is ignored")
  -- quests: only the leader's (from its QL message), or any
  AU.set("quests", true)
  W.env.GetQuestID = function() return 123 end
  W.env.GetTitleText = function() return "Wolves" end
  reset(W); W.fire("QUEST_DETAIL")
  H.eq(did(W, "AcceptQuest"), nil, "a quest the leader does not have: not accepted")
  msg(W, "Stranger", "QL|123")
  W.fire("QUEST_DETAIL")
  H.eq(did(W, "AcceptQuest"), nil, "a stranger's quest list is ignored")
  msg(W, "Bo", "QL|123")
  W.fire("QUEST_DETAIL")
  H.eq(did(W, "AcceptQuest"), nil, "only the squad leader's list counts")
  msg(W, "Dorin", "QL|5,123")
  W.mods.shift = true; W.fire("QUEST_DETAIL"); W.mods.shift = false
  H.eq(did(W, "AcceptQuest"), nil, "Shift held: skipped")
  W.fire("QUEST_DETAIL")
  H.ok(did(W, "AcceptQuest"), "the leader has it: accepted")
  H.ok(ns.Core.db.log[#ns.Core.db.log].m:find("auto: Accepted quest Wolves", 1, true), "one log line")
  W.env.GetQuestID = function() return 999 end
  reset(W); AU.set("questAny", true); W.fire("QUEST_DETAIL")
  H.ok(did(W, "AcceptQuest"), "Accept any quest")
  AU.set("questAny", false)
  -- escort / shared start
  reset(W); W.fire("QUEST_ACCEPT_CONFIRM", "Stranger")
  H.eq(did(W, "ConfirmAcceptQuest"), nil, "a stranger's escort: no")
  W.fire("QUEST_ACCEPT_CONFIRM", "Bo")
  H.ok(did(W, "ConfirmAcceptQuest"), "a squad member's escort: yes")
  -- turn in + rewards
  W.env.IsQuestCompletable = function() return true end
  reset(W); W.fire("QUEST_PROGRESS")
  H.eq(did(W, "CompleteQuest"), nil, "Turn in off: nothing")
  AU.set("turnin", true); W.fire("QUEST_PROGRESS")
  H.ok(did(W, "CompleteQuest"), "Turn in: CompleteQuest")
  W.env.GetNumQuestChoices = function() return 0 end
  W.fire("QUEST_COMPLETE")
  H.eq(did(W, "GetQuestReward"), "GetQuestReward(1)", "no choice: the reward is taken")
  W.fire("QUEST_FINISHED")
  W.env.GetQuestID = function() return 77 end
  W.env.GetNumQuestChoices = function() return 3 end
  reset(W); W.fire("QUEST_COMPLETE")
  H.eq(did(W, "GetQuestReward"), nil, "a choice, rule = the leader's pick: waits")
  msg(W, "Dorin", "QR|77|2")
  H.eq(did(W, "GetQuestReward"), "GetQuestReward(2)", "takes the leader's pick when it arrives")
  W.fire("QUEST_FINISHED")
  ns.Core.db.settings.autoReward = "value"
  W.env.GetQuestItemLink = function(_, i) return "item" .. i end
  W.env.GetItemInfo = function(link) local p = ({ item1 = 10, item2 = 50, item3 = 30 })[link]; return link, nil, nil, nil, nil, nil, nil, nil, nil, nil, p end
  reset(W); W.fire("QUEST_COMPLETE")
  H.eq(did(W, "GetQuestReward"), "GetQuestReward(2)", "rule = best vendor value")
  W.fire("QUEST_FINISHED")
  ns.Core.db.settings.autoReward = "ask"
  reset(W); W.fire("QUEST_COMPLETE")
  H.eq(did(W, "GetQuestReward"), nil, "rule = ask: you pick")
  W.fire("QUEST_FINISHED")
  -- dialog sync: the same NPC window open, the leader's choice
  AU.set("dialog", true)
  W.env.UnitName = (function(orig) return function(u) if u == "npc" then return "Innkeeper Renee" end return orig(u) end end)(W.env.UnitName)
  W.env.GetGossipOptions = function() return "Make this inn your home.", "binder", "What can I do at an inn?", "gossip" end
  reset(W); msg(W, "Dorin", "D|Innkeeper Renee|g|1|Make this inn your home.")
  H.eq(did(W, "SelectGossipOption"), nil, "no NPC window open here: nothing")
  W.fire("GOSSIP_SHOW")
  msg(W, "Bo", "D|Innkeeper Renee|g|1|Make this inn your home.")
  H.eq(did(W, "SelectGossipOption"), nil, "only the leader's choice")
  msg(W, "Dorin", "D|Other NPC|g|1|Make this inn your home.")
  H.eq(did(W, "SelectGossipOption"), nil, "another NPC: nothing")
  msg(W, "Dorin", "D|Innkeeper Renee|g|1|Make this inn your home.")
  H.eq(did(W, "SelectGossipOption"), "SelectGossipOption(1)", "the same NPC window: the same choice")
  reset(W); msg(W, "Dorin", "D|Innkeeper Renee|g|2|Logout now")
  H.eq(#W.did, 0, "never: logout / quit / delete")
  W.fire("GOSSIP_CLOSED")
  -- flights
  W.env.NumTaxiNodes = function() return 2 end
  W.env.TaxiNodeName = function(i) return ({ "Crossroads", "Orgrimmar" })[i] end
  W.env.TaxiNodeCost = function(i) return i == 2 and 50000 or 500 end
  reset(W); msg(W, "Dorin", "D|taxi|t|7|Crossroads")
  H.eq(did(W, "TakeTaxiNode"), nil, "no flight map open: nothing")
  W.fire("TAXIMAP_OPENED")
  msg(W, "Dorin", "D|taxi|t|7|Crossroads")
  H.eq(did(W, "TakeTaxiNode"), "TakeTaxiNode(1)", "the same flight, by name")
  reset(W); msg(W, "Dorin", "D|taxi|t|9|Orgrimmar")
  H.eq(did(W, "TakeTaxiNode"), nil, "a flight above the gold limit: not synced")
  W.fire("TAXIMAP_CLOSED")
  -- resurrection, summons, role check
  reset(W); W.fire("RESURRECT_REQUEST", "Stranger")
  H.eq(did(W, "AcceptResurrect"), nil, "a stranger's resurrection: no")
  W.fire("RESURRECT_REQUEST", "Dorin")
  H.ok(did(W, "AcceptResurrect"), "a squad member's resurrection: yes (on by default)")
  AU.set("res", false); reset(W); W.fire("RESURRECT_REQUEST", "Dorin")
  H.eq(did(W, "AcceptResurrect"), nil, "option off: no")
  W.env.GetSummonConfirmSummoner = function() return "Bo" end
  reset(W); W.fire("CONFIRM_SUMMON")
  H.ok(did(W, "ConfirmSummon"), "a squad member's summon: accepted")
  W.env.GetSummonConfirmSummoner = function() return "Warlockstranger" end
  reset(W); W.fire("CONFIRM_SUMMON")
  H.eq(did(W, "ConfirmSummon"), nil, "a stranger's summon: no")
  AU.set("rolecheck", true)
  W.env.UnitIsGroupLeader = function(u) return u == "party1" end
  reset(W); W.fire("LFG_ROLE_CHECK_SHOW")
  H.eq(did(W, "CompleteLFGRoleCheck"), "CompleteLFGRoleCheck(true)", "role check: the group leader is in the squad")
  -- merchant: junk, repair floor, restock
  AU.set("sell", true); AU.set("repair", true); AU.set("restock", true)
  W.env.GetContainerNumSlots = function(b) return b == 0 and 2 or 0 end
  W.env.GetContainerItemInfo = function(b, s)
    if s == 1 then return nil, 1, false, 0, nil, nil, "|cff9d9d9d|Hitem:1|h[Broken Fang]|h|r", nil, false end
    return nil, 1, false, 2, nil, nil, "|cff1eff00|Hitem:2|h[Good Sword]|h|r", nil, false
  end
  W.env.CanMerchantRepair = function() return true end
  W.env.GetRepairAllCost = function() return 5000 end
  W.env.GetMoney = function() return 12000 end
  W.env.GetMerchantNumItems = function() return 2 end
  W.env.GetMerchantItemInfo = function(i) return ({ "Holy Candle", "Ice Cold Milk" })[i], nil, 50, 1 end
  W.env.GetItemCount = function(n) return n == "Holy Candle" and 5 or 0 end
  W.env.GetMerchantItemMaxStack = function() return 20 end
  reset(W); W.mods.shift = true; W.fire("MERCHANT_SHOW"); W.mods.shift = false
  H.eq(#W.did, 0, "Shift held at the merchant: nothing")
  W.fire("MERCHANT_SHOW")
  H.eq(did(W, "UseContainerItem"), "UseContainerItem(0,1)", "sells the grey item only")
  H.eq(did(W, "RepairAllItems"), nil, "repair would go below the gold floor: skipped")
  H.eq(did(W, "BuyMerchantItem"), "BuyMerchantItem(1,15)", "restocks Holy Candles to 20")
  W.env.GetMoney = function() return 50000 end
  reset(W); W.fire("MERCHANT_SHOW")
  H.ok(did(W, "RepairAllItems"), "repairs above the gold floor")
  -- never: casting, targeting, moving, following, NPC interaction
  for _, api in ipairs({ "CastSpellByName", "TargetUnit", "FollowUnit", "InteractUnit", "MoveForwardStart" }) do H.eq(W.calls[api], nil, "never " .. api) end
end

-- ------------------------------------------------------------------ leader Dorin: share, quest list, invites, dialog sends
do
  local W, ns = boot("Dorin")
  local AU = ns.Auto
  AU.set("share", true); AU.set("autoInvite", true)
  W.sent = {}
  W.fire("QUEST_ACCEPTED", 4, 555) -- Classic: questLogIndex, questID
  H.ok(did(W, "SelectQuestLogEntry") and did(W, "QuestLogPushQuest"), "the leader shares a quest it accepts")
  local ql
  for _, m in ipairs(W.sent) do if m.prefix == "WBXA" and m.msg:find("^QL|") then ql = m.msg end end
  H.ok(ql ~= nil, "and sends its quest list (data only): " .. tostring(ql))
  -- Bo is not in the party: invite him
  W.party = { party1 = "Anna" }
  reset(W)
  H.eq(AU.inviteMissing(), 1, "Invite the squad: one invite")
  H.eq(did(W, "InviteUnit"), "InviteUnit(Bo)", "invites Bo")
  H.eq(AU.inviteMissing(), 0, "not again right away")
  -- the leader's gossip choice is sent; a single-option dialog is not
  W.env.UnitName = (function(orig) return function(u) if u == "npc" then return "Innkeeper Renee" end return orig(u) end end)(W.env.UnitName)
  W.env.GetGossipOptions = function() return "Make this inn your home.", "binder", "What can I do at an inn?", "gossip" end
  W.sent = {}
  AU.leaderChose("g", 1, "Make this inn your home.")
  H.ok(W.sent[1] and W.sent[1].msg == "D|Innkeeper Renee|g|1|Make this inn your home.", "the leader's dialog choice is sent")
  W.env.GetGossipOptions = function() return "Let me browse your goods.", "vendor" end
  W.sent = {}
  AU.leaderChose("g", 1, "Let me browse your goods.")
  H.eq(#W.sent, 0, "a single-option dialog (vendor) is not synced")
  -- the diagnose lists the APIs ([AFKLAR] until the launch test)
  local d = ns.Core.selftest(true)
  H.ok(d.auto and d.auto.api and d.auto.api.AcceptGroup and d.auto.api.afklar, "diagnose: automation API probe")
  H.ok(d.auto.on.share == true and d.auto.on.invite == false, "diagnose: which options are on")
end

-- ------------------------------------------------------------------ Setup → Automation
do
  local W, ns = boot("Anna")
  ns.UI.Open("setup")
  ns.UI.panels.setup.autoBtn:Click()
  local f = ns.AutomationPage.frame
  H.ok(f:IsShown() and #f.ticks == #ns.Auto.OPTIONS and ns.UI.current == "automation", "the Automation bookmark: one tick per option")
  f.preset:Click()
  local on = {}
  for _, c in ipairs(f.ticks) do if c:GetChecked() then on[#on + 1] = c.key end end
  H.eq(table.concat(on, ","), "invite,quests,share,turnin,dialog,res,summon,rolecheck,sell,repair,chat", "Levelling squad preset")
  f.allOff:Click()
  for _, c in ipairs(f.ticks) do H.ok(not c:GetChecked(), "All off: " .. c.key) end
  f.allOn:Click()
  H.ok(ns.Auto.on("restock") and ns.Auto.on("questAny"), "All on")
  f.ticks[1]:Click()
  H.ok(not ns.Auto.on("invite"), "a tick turns one option off")
  H.eq(ns.Core.db.settings.auto.invite, false, "stored account-wide")
end

-- "Accept from" (§5): each level × each accepting automation × stranger, friend, guild member, squad member
do
  local W, ns = boot("Anna")
  local AU = ns.Auto
  W.env.C_FriendList = { GetNumFriends = function() return 1 end, GetFriendInfoByIndex = function() return { name = "Fred" } end }
  W.env.IsInGuild = function() return true end
  W.env.GetNumGuildMembers = function() return 1 end
  W.env.GetGuildRosterInfo = function() return "Gina-Realm" end
  W.party = { party1 = "Dorin", party2 = "Bo", party3 = "Fred", party4 = "Gina" } -- everyone in the party
  W.partyInfo.party3 = PAL; W.partyInfo.party4 = PAL
  for _, k in ipairs({ "invite", "res", "summon" }) do AU.set(k, true) end
  local function fire(kind, who)
    reset(W)
    if kind == "invite" then W.fire("PARTY_INVITE_REQUEST", who); return did(W, "AcceptGroup") ~= nil end
    if kind == "res" then W.fire("RESURRECT_REQUEST", who); return did(W, "AcceptResurrect") ~= nil end
    W.env.GetSummonConfirmSummoner = function() return who end
    W.fire("CONFIRM_SUMMON"); return did(W, "ConfirmSummon") ~= nil
  end
  local want = {
    squad = { Bo = true, Fred = false, Gina = false, Stranger = false },
    friends = { Bo = true, Fred = true, Gina = true, Stranger = false },
    everyone = { Bo = true, Fred = true, Gina = true, Stranger = true },
  }
  W.party.party1, W.party.party2 = "Dorin", "Bo"
  for _, level in ipairs({ "squad", "friends", "everyone" }) do
    ns.Core.db.settings.acceptFrom = level
    for _, kind in ipairs({ "invite", "res", "summon" }) do
      for who, yes in pairs(want[level]) do
        if who == "Stranger" and kind ~= "invite" then W.party.party4 = "Stranger" end
        H.eq(fire(kind, who), yes, level .. " × " .. kind .. " × " .. who)
        W.party.party4 = "Gina"
      end
    end
  end
  -- Everyone warns first
  ns.Core.db.settings.acceptFrom = "squad"
  ns.UI.Open("automation")
  local p = ns.UI.panels.automation
  p.from.select("everyone")
  H.eq(ns.Core.db.settings.acceptFrom, "squad", "Everyone: not before the warning is confirmed")
  H.ok(ns.UI.popup:IsShown() and ns.UI.popup.text:GetText():find("Anyone can then invite you", 1, true), "the warning")
  ns.UI.popup.btns[1]:Click()
  H.eq(ns.Core.db.settings.acceptFrom, "everyone", "confirmed: Everyone")
  ns.UI.Refresh()
  H.ok(p.ticks[1].line:GetText():find("^Accepts from: Everyone"), "each accept row shows the choice: " .. p.ticks[1].line:GetText())
  -- Advanced: one row overrides it
  ns.Core.db.settings.advanced = true
  ns.UI.Refresh()
  H.ok(p.ticks[1].own:IsShown(), "Advanced: a row has its own Accept from")
  p.ticks[1].own.select("squad")
  H.eq(AU.acceptFrom("invite"), "squad", "the row's own choice wins")
  H.eq(AU.acceptFrom("res"), "everyone", "the others keep the top choice")
  ns.Core.db.settings.advanced = nil
  H.eq(AU.acceptFrom("invite"), "everyone", "Standard: the top choice for all")
end

-- the nudge once per character, the share string carries the choice, the line in Setup
do
  local W, ns = boot("Anna")
  local AU = ns.Auto
  H.ok(AU.nudge(), "automation off in a squad: the nudge")
  H.ok(ns.UI.popup.text:GetText():find("Automation is off – turn on Levelling squad?", 1, true), "the question")
  local labels = {}
  for _, b in ipairs(ns.UI.popup.btns) do if b:IsShown() then labels[#labels + 1] = b:GetText() end end
  H.eq(table.concat(labels, ","), "Yes,Choose…,Not now", "Yes / Choose… / Not now")
  ns.UI.popup.btns[1]:Click()
  H.ok(AU.on("quests") and AU.on("dialog"), "Yes: Levelling squad")
  H.ok(not AU.nudge(), "only once per character")
  local str = ns.Core.exportString()
  local res = ns.Share.import(str)
  H.ok(res.auto and #res.auto.on >= 10 and res.auto.from == "squad", "the share string carries the automation choice (data only)")
  AU.setAll(false)
  ns.Core.applyImport(res)
  H.ok(AU.on("quests"), "importing it (a click) applies the choice")
  ns.UI.Open("setup")
  H.ok(ns.UI.panels.setup.autoLink:IsShown() and ns.UI.panels.setup.autoLine:GetText():find("invites", 1, true), "Setup: a line under game settings → Automation")
  ns.UI.panels.setup.autoLink:Click()
  H.eq(ns.UI.current, "automation", "it opens the Automation bookmark")
end


-- Default: WoWBoxer's recommendation – everything on except Accept any quest, Abandon together, Restock reagents
do
  local W = Mock.new(H, { name = "Dorin", class = "PALADIN", race = "Scourge", level = 20 })
  local ns = H.loadAddon({ env = W.env })
  W.fire("ADDON_LOADED", "WoWBoxer"); W.fire("PLAYER_LOGIN")
  ns.UI.Open("automation")
  ns.UI.panels.automation.defaults:Click()
  for _, o in ipairs(ns.Auto.OPTIONS) do
    local want = not (o[1] == "abandon" or o[1] == "questAny" or o[1] == "restock")
    H.eq(ns.Auto.on(o[1]) and true or false, want, "Default: " .. o[1] .. (want and " on" or " off"))
  end
  H.eq(W.calls.CreateMacro, nil, "Default writes nothing to the game")
end

os.exit(H.report("auto") and 0 or 1)
