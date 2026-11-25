-- Checked accepts (owner, 25 Nov 2026): a resurrection that WoWBoxer "accepted" did not take and Blizzard's box was
-- hidden. Fakes for the corpse recovery delay, a ghost, combat, a blocked call, the check that works and the one that
-- does not – for resurrections, summons, party invites, started quests and role checks. Blizzard's box is never hidden.
local dir = (arg[0]:match("^(.*)/[^/]+$") or ".")
local H = dofile(dir .. "/harness.lua")
local Mock = dofile(dir .. "/wowmock.lua")

local PAL = { class = "PALADIN", race = "Scourge", level = 20 }
local HUN = { class = "HUNTER", race = "Orc", level = 20 }
local function boot()
  local W = Mock.new(H, { name = "Anna", class = "PRIEST", race = "Scourge", level = 20,
    party = { party1 = "Dorin", party2 = "Bo" }, partyInfo = { party1 = PAL, party2 = HUN } })
  local ns = H.loadAddon({ env = W.env })
  W.fire("ADDON_LOADED", "WoWBoxer"); W.fire("PLAYER_LOGIN")
  local sq = ns.State.newSquad({ name = "Trio", members = {
    { name = "Dorin", cls = "paladin", race = "undead", role = "tank", leader = true },
    { name = "Anna", cls = "priest", race = "undead", role = "healer" },
    { name = "Bo", cls = "hunter", race = "orc", role = "ranged" } } })
  ns.Core.db.squads = { sq }; ns.Core.db.active = sq.id
  W.did, W.hidden, W.shown = {}, {}, {}
  W.ghost, W.delay, W.timeLeft, W.pos = false, 0, 120, { 100, 200 }
  W.works = true -- does the game take the accept?
  W.env.UnitIsDeadOrGhost = function(u) return u == "player" and W.ghost end
  W.env.GetCorpseRecoveryDelay = function() return W.delay end
  W.env.C_SummonInfo = nil
  W.env.GetSummonConfirmSummoner = function() return "Bo" end
  W.env.GetSummonConfirmTimeLeft = function() return W.timeLeft end
  W.env.UnitPosition = function() return W.pos[1], W.pos[2], 0, 0 end
  W.env.StaticPopup_Hide = function(n) W.hidden[#W.hidden + 1] = n end
  W.env.StaticPopup_Visible = function(n) return W.visible == n end
  W.env.StaticPopup_Show = function(n) W.shown[#W.shown + 1] = n; W.visible = n end
  local function rec(name, effect)
    W.env[name] = function(...)
      W.did[#W.did + 1] = name
      if W.blockNext then W.fire("ADDON_ACTION_BLOCKED", "WoWBoxer", name .. "()"); return end
      if W.works and effect then effect(...) end
    end
  end
  rec("AcceptResurrect", function() W.ghost = false end)
  rec("ConfirmSummon", function() W.timeLeft = 0; W.pos = { 900, 900 } end)
  rec("AcceptGroup", function() W.grouped = true end)
  rec("ConfirmAcceptQuest", function() W.questOk = true end)
  rec("CompleteLFGRoleCheck", function() W.roleOk = true end)
  W.env.IsInGroup = function() return W.grouped == true end
  W.env.GetNumQuestLogEntries = function() return W.questOk and 1 or 0 end
  W.env.GetQuestLogTitle = function() return "The Missing Diplomat", 20, nil, false, false, nil, nil, 1447 end
  W.env.C_QuestLog = nil
  W.env.UnitIsGroupLeader = function(u) return u == "party1" end
  W.now = 1000
  return W, ns
end
local function called(W, n) for _, x in ipairs(W.did) do if x == n then return true end end return false end
local function chat(W, pat) for _, m in ipairs(W.chat) do if m:find(pat, 1, true) then return m end end return nil end
local function logged(ns, pat) for _, l in ipairs(ns.Core.db.log) do if l.m:find(pat, 1, true) then return l.m end end return nil end
local function clear(W) W.did, W.chat, W.shown = {}, {}, {} end

-- ------------------------------------------------------------------ resurrection
do
  local W, ns = boot()
  local AU = ns.Auto
  AU.set("chat", true)
  -- alive (or no delay): accepted at once, "Accepted" only after the check
  W.ghost = true; W.visible = "RESURRECT"
  W.fire("RESURRECT_REQUEST", "Dorin")
  H.ok(called(W, "AcceptResurrect"), "no delay: AcceptResurrect at once")
  H.eq(chat(W, "Accepted the resurrection"), nil, "not 'Accepted' before the check")
  H.eq(#W.hidden, 0, "Blizzard's box is never hidden")
  W.fire("PLAYER_UNGHOST")
  H.ok(chat(W, "Accepted the resurrection from Dorin."), "alive again (PLAYER_UNGHOST): Accepted")
  H.eq(AU.pending.res, nil, "nothing pending")
  -- a ghost before the corpse recovery delay: waits, then accepts
  clear(W); W.ghost = true; W.delay = 12
  W.fire("RESURRECT_REQUEST", "Dorin")
  H.ok(not called(W, "AcceptResurrect"), "ghost with a 12 s delay: not yet")
  H.ok(logged(ns, "waits (delay 12 s)"), "logged: waits (delay)")
  W.now = 1006; W.flush() -- a timer too early (the delay is still running)
  W.delay = 6
  H.ok(not called(W, "AcceptResurrect"), "still in the delay: not yet")
  W.now = 1013; W.delay = 0; W.flush()
  H.ok(called(W, "AcceptResurrect"), "after the delay: accepted")
  W.flush() -- the check ~1 s later
  H.ok(chat(W, "Accepted the resurrection from Dorin."), "the check: alive -> Accepted")
  -- the game ignores it: one line, the box stays / comes back, reason in the log
  clear(W); W.now = 1100; W.ghost = true; W.delay = 0; W.works = false; W.visible = nil
  W.fire("RESURRECT_REQUEST", "Dorin")
  H.ok(called(W, "AcceptResurrect"), "accept tried")
  W.flush()
  H.eq(chat(W, "Accepted the resurrection"), nil, "verify failed: never 'Accepted'")
  H.ok(chat(W, "Click Accept yourself: WoWBoxer could not accept the resurrection from Dorin (unknown)."), "one line: click Accept yourself")
  H.eq(W.shown[1], "RESURRECT_NO_TIMER", "Blizzard's box shown again when it was gone")
  H.ok(logged(ns, "the resurrection from Dorin not accepted (unknown)"), "logged why")
  local a = AU.accepts[#AU.accepts]
  H.ok(a and a.kind == "res" and a.ok == false and a.why == "unknown", "diagnose list: res, failed, unknown")
  -- the box still shown: not shown twice
  clear(W); W.visible = "RESURRECT"
  W.fire("RESURRECT_REQUEST", "Dorin"); W.flush()
  H.eq(#W.shown, 0, "the box is still there: not shown again")
  -- blocked (ADDON_ACTION_BLOCKED)
  clear(W); W.works = true; W.blockNext = true
  W.fire("RESURRECT_REQUEST", "Dorin"); W.flush()
  W.blockNext = false
  H.ok(chat(W, "(blocked: AcceptResurrect())"), "blocked: the reason says so")
  -- the offer runs out while waiting for the delay: give up with the reason
  clear(W); W.ghost = true; W.delay = 30
  W.fire("RESURRECT_REQUEST", "Dorin")
  W.now = W.now + 100; W.flush()
  H.ok(not called(W, "AcceptResurrect"), "the offer ran out in the delay: not tried")
  H.ok(chat(W, "(delay)"), "delay: click Accept yourself (delay)")
  W.delay = 0
  -- Shift and a stranger: nothing
  clear(W); W.mods.shift = true; W.fire("RESURRECT_REQUEST", "Dorin"); W.mods.shift = false
  H.ok(not called(W, "AcceptResurrect"), "Shift: skipped")
  W.fire("RESURRECT_REQUEST", "Stranger")
  H.ok(not called(W, "AcceptResurrect"), "a stranger: no")
  H.eq(#W.hidden, 0, "no box hidden at all")
end

-- ------------------------------------------------------------------ summons
do
  local W, ns = boot()
  local AU = ns.Auto
  AU.set("chat", true)
  W.combat = true
  W.fire("CONFIRM_SUMMON")
  H.ok(not called(W, "ConfirmSummon"), "in combat: not yet")
  H.ok(logged(ns, "the summon from Bo waits (combat)"), "logged: waits (combat)")
  W.flush()
  H.ok(not called(W, "ConfirmSummon"), "still in combat")
  W.combat = false
  W.fire("PLAYER_REGEN_ENABLED")
  H.ok(called(W, "ConfirmSummon"), "the fight ended: accepted")
  W.flush()
  H.ok(chat(W, "Accepted the summon from Bo."), "the check: summon gone -> Accepted")
  -- moved counts too (time left unknown)
  clear(W); W.timeLeft = 120; W.pos = { 100, 200 }
  W.env.GetSummonConfirmTimeLeft = nil
  W.fire("CONFIRM_SUMMON"); W.flush()
  H.ok(chat(W, "Accepted the summon from Bo."), "moved: Accepted")
  W.env.GetSummonConfirmTimeLeft = function() return W.timeLeft end
  -- ignored by the game
  clear(W); W.timeLeft = 100; W.works = false; W.visible = nil
  W.fire("CONFIRM_SUMMON"); W.flush()
  H.ok(chat(W, "Click Accept yourself: WoWBoxer could not accept the summon from Bo (unknown)."), "verify failed: click Accept yourself")
  H.eq(W.shown[1], "CONFIRM_SUMMON", "the summon box shown again")
  -- the fight lasts longer than the summon
  clear(W); W.works = true; W.timeLeft = 30; W.combat = true
  W.fire("CONFIRM_SUMMON")
  W.now = W.now + 31; W.flush()
  H.ok(not called(W, "ConfirmSummon"), "never accepted in combat")
  H.ok(chat(W, "(combat)"), "the summon ran out in the fight: click Accept yourself (combat)")
  W.combat = false
  -- cancelled before the fight ended: nothing
  clear(W); W.combat = true; W.timeLeft = 100
  W.fire("CONFIRM_SUMMON"); W.fire("CANCEL_SUMMON"); W.combat = false; W.fire("PLAYER_REGEN_ENABLED")
  H.ok(not called(W, "ConfirmSummon"), "cancelled: nothing")
  H.eq(#W.hidden, 0, "no box hidden")
end

-- ------------------------------------------------------------------ party invite, started quest, role check
do
  local W, ns = boot()
  local AU = ns.Auto
  AU.set("chat", true); AU.set("invite", true); AU.set("questShared", true); AU.set("rolecheck", true)
  W.grouped = false
  W.fire("PARTY_INVITE_REQUEST", "Dorin")
  H.ok(called(W, "AcceptGroup"), "invite: AcceptGroup")
  W.fire("GROUP_ROSTER_UPDATE")
  H.ok(chat(W, "Accepted the group invite from Dorin."), "in a group: Accepted")
  clear(W); W.grouped = false; W.works = false; W.visible = "PARTY_INVITE"
  W.fire("PARTY_INVITE_REQUEST", "Dorin"); W.flush()
  H.ok(chat(W, "could not accept the group invite from Dorin"), "invite ignored: click Accept yourself")
  H.eq(#W.shown, 0, "its box is still there")
  W.works = true
  -- a quest a squad member starts
  clear(W)
  W.fire("QUEST_ACCEPT_CONFIRM", "Dorin", "The Missing Diplomat")
  H.ok(called(W, "ConfirmAcceptQuest"), "quest: ConfirmAcceptQuest")
  W.flush()
  H.ok(chat(W, "Accepted the quest from Dorin."), "in the quest log: Accepted")
  clear(W); W.questOk = false; W.works = false; W.visible = nil
  W.fire("QUEST_ACCEPT_CONFIRM", "Dorin", "The Missing Diplomat"); W.flush()
  H.ok(chat(W, "could not accept the quest from Dorin"), "quest not in the log: click Accept yourself")
  H.eq(W.shown[1], "QUEST_ACCEPT", "the quest box shown again")
  W.works = true
  -- role check
  clear(W)
  W.fire("LFG_ROLE_CHECK_SHOW")
  H.ok(called(W, "CompleteLFGRoleCheck"), "role check: CompleteLFGRoleCheck")
  W.fire("LFG_ROLE_CHECK_ROLE_CHOSEN", "Anna", true, false, false)
  H.ok(chat(W, "Accepted the role check"), "role chosen: Accepted")
  clear(W)
  W.fire("LFG_ROLE_CHECK_SHOW"); W.flush()
  H.ok(chat(W, "could not accept the role check"), "no role chosen: click Accept yourself")
  H.eq(#W.hidden, 0, "no box hidden")
  -- diagnose
  local d = ns.Core.selftest(true)
  H.ok(d.auto.accepts and #d.auto.accepts > 0 and d.auto.api.accept and d.auto.api.accept.GetCorpseRecoveryDelay == true, "diagnose: accept outcomes and the probe")
end

os.exit(H.report("accepts") and 0 or 1)
