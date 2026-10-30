-- The read-only diagnose runs by itself a few seconds after login, so a /reload is enough to read it from the
-- SavedVariables. It must never write to the game. Run: lua tests/test_diag.lua
local dir = (arg[0]:match("^(.*)/[^/]+$") or ".")
local H = dofile(dir .. "/harness.lua")
local Mock = dofile(dir .. "/wowmock.lua")

for _, toc in ipairs({ 16001, 11509 }) do
  local W = Mock.new(H, { toc = toc, name = "Warlocker", class = "PRIEST", race = "Scourge", level = 12 })
  local ns = H.loadAddon({ env = W.env })
  W.fire("ADDON_LOADED", "WoWBoxer")
  W.fire("PLAYER_LOGIN")
  local Core = ns.Core
  H.eq(next(Core.db.diag), nil, toc .. ": nothing before the timer")
  local timers = W.timers; W.timers = {}
  for _, fn in ipairs(timers) do fn() end
  local d = Core.db.diag["Warlocker-Realm"]
  H.ok(d ~= nil, toc .. ": diagnose written after login")
  H.ok(d and d.probe and d.probe.interface == toc, toc .. ": probe has the interface number")
  H.ok(d and d.error ~= nil, toc .. ": no squad yet is reported, not an error")
  H.eq(W.calls.CreateMacro, nil, toc .. ": no macro written")
  H.eq(W.calls.EditMacro, nil, toc .. ": no macro edited")
  H.ok(not W.chatHas("Selftest done"), toc .. ": quiet (no chat spam at login)")
  for _, e in ipairs(Core.db.log) do H.ok(e.l ~= "error", toc .. ": " .. e.m) end
end

-- bridge for the window app (WS-C contract): who is logged in on this account
do
  local W = Mock.new(H, { name = "Dorin", class = "PALADIN", race = "Scourge", level = 12 })
  local ns = H.loadAddon({ env = W.env })
  W.fire("ADDON_LOADED", "WoWBoxer")
  W.fire("PLAYER_LOGIN")
  local b = W.env.WoWBoxerDB.bridge
  H.ok(b ~= nil, "bridge written at login")
  H.eq(b.version, 1, "bridge version")
  H.eq(b.character, "Dorin", "character")
  H.eq(b.realm, "Realm", "realm")
  H.eq(b.class, "PALADIN", "class file token")
  H.eq(b.level, 12, "level")
  H.ok(b.loggedInAt and b.savedAt and b.savedAt >= b.loggedInAt, "timestamps")
  local first = b.savedAt
  W.player.level = 13
  W.fire("PLAYER_LOGOUT")
  H.eq(b.level, 13, "level updated on logout/reload")
  H.ok(b.savedAt > first, "savedAt moves on logout/reload")
  H.eq(W.calls.CreateMacro, nil, "bridge writes nothing but SavedVariables")
end

-- hard rule: events alone (login, level-ups, spells, bars, bindings, combat, group, team messages) never write to the game
do
  local W = Mock.new(H, { name = "Dorin", class = "WARRIOR", race = "Orc", level = 9, party = { party1 = "Wowtwo" } })
  local ns = H.loadAddon({ env = W.env })
  W.fire("ADDON_LOADED", "WoWBoxer")
  W.fire("PLAYER_LOGIN")
  for _, sp in ipairs(ns.Data.spells.warrior) do if sp.level <= 20 then W.known[sp.name] = true end end
  ns.State.quickStart(ns.Core.db, ns.Core.cdb, ns.Core.playerInfo())
  ns.Core.cdb.lastSync = { level = 9, at = 1 } -- a player who already uses WoWBoxer keys gets offers
  for lvl = 10, 20 do
    W.player.level = lvl
    W.fire("PLAYER_LEVEL_UP", lvl); W.fire("SPELLS_CHANGED"); W.fire("LEARNED_SPELL_IN_TAB")
    W.fire("ACTIONBAR_SLOT_CHANGED", 1); W.fire("UPDATE_BINDINGS")
    W.combat = true; W.fire("PLAYER_REGEN_DISABLED"); W.combat = false; W.fire("PLAYER_REGEN_ENABLED")
    W.fire("GROUP_ROSTER_UPDATE"); W.fire("AUTOFOLLOW_BEGIN", "Wowtwo"); W.fire("AUTOFOLLOW_END")
    W.fire("CHAT_MSG_ADDON", "WBX1", "S|20|50|0|1|Creature-0-1", "PARTY", "Wowtwo-Realm")
    W.flush()
  end
  W.fire("PLAYER_LOGOUT")
  for _, api in ipairs({ "CreateMacro", "EditMacro", "PlaceAction", "SetBindingMacro", "SetBinding" }) do
    H.eq(W.calls[api], nil, "no " .. api .. " without a click")
  end
  H.eq(W.cvars.autoLootDefault, "0", "no CVar changed without a click")
  H.ok(W.chatHas("macros? changed"), "but the level-up offer was shown")
end

-- v8.5 sequences: the diagnose holds the [AFKLAR] spell-name check; a Rogue follower gets a combo key + the Assist tip
do
  local W = Mock.new(H, { name = "Stabby", class = "ROGUE", race = "Scourge", level = 30, party = { party1 = "Dorin" } })
  local ns = H.loadAddon({ env = W.env })
  W.fire("ADDON_LOADED", "WoWBoxer"); W.fire("PLAYER_LOGIN")
  for _, sp in ipairs(ns.Data.spells.rogue) do if sp.level <= 30 and sp.gate ~= "talent" then W.known[sp.name] = true end end
  local Core = ns.Core
  Core.ensureMe()
  Core.setPlaysAs("party1")
  local _, m = Core.me()
  m.seq = "medium"
  local key
  for _, d in ipairs(Core.compute().desired) do if d.key == "S1" then key = d end end
  H.ok(key and key.body:find("[@party1target,harm,nodead] reset=combat Sinister Strike, Sinister Strike, Slice and Dice", 1, true),
    "Rogue follower: combo sequence on the leader's target: " .. tostring(key and key.body))
  H.ok(key.body:find("/startattack", 1, true) and #key.body <= 255, "starts auto attack, at most 255 characters")
  local r = Core.selftest(true)
  H.ok(r.seqCheck and r.seqCheck.names["Hemorrhage"] and r.seqCheck.names["Hemorrhage"].id, "diagnose: v8.5 spell names checked by spell ID")
  H.eq(#r.seqCheck.open, 3, "diagnose: the three in-game checks are listed")
  H.eq(r.seqCheck.mine.seq, "medium", "diagnose: this character's sequence tier")
  H.ok(ns.Widgets.SEQ_KINDS:find("Sequence macro", 1, true) and ns.Widgets.SEQ_KINDS:find("Priority macro", 1, true), "help: one sentence each on sequence vs priority keys")
  H.eq(W.calls.CreateMacro, nil, "nothing written")
end

-- test builds (tools/install.ps1): the stamped version reaches the diagnose and the team message, the window shows an
-- orange TEST BUILD label; a tagged release and an unstamped checkout never show it
for _, case in ipairs({ { "0.13.0-test.1 (abc1234)", true, "0.13.0-test.1" }, { "0.12.0", false, "0.12.0" },
                        { "@project-version@", false, nil } }) do
  local ver, isTest, short = case[1], case[2], case[3]
  local W = Mock.new(H, { name = "Dorin", class = "PALADIN", race = "Scourge", level = 12 })
  W.env.GetAddOnMetadata = function(addon, field) if field == "Version" then return ver end end
  local ns = H.loadAddon({ env = W.env })
  W.fire("ADDON_LOADED", "WoWBoxer")
  W.fire("PLAYER_LOGIN")
  H.eq(ns.Core.isTestBuild(), isTest, ver .. ": isTestBuild")
  H.eq(ns.Core.addonVersion(), short and ver or nil, ver .. ": addonVersion")
  H.eq(ns.Team.version(), short or ns.Core.VERSION, ver .. ": team version has no sha")
  local timers = W.timers; W.timers = {}
  for _, fn in ipairs(timers) do fn() end
  H.eq(ns.Core.db.diag["Dorin-Realm"].build, short and ver or nil, ver .. ": diagnose has the build")
  ns.UI.Open("keys")
  H.eq(ns.UI.testLabel and ns.UI.testLabel:GetText() or nil, isTest and "TEST BUILD" or nil, ver .. ": TEST BUILD label")
end

-- /wbx shots: every page and dialog once, one Screenshot() each, the window box saved; nothing written to the game
do
  local W = Mock.new(H, { name = "Dorin", class = "PALADIN", race = "Scourge", level = 12 })
  local n = 0
  W.env.Screenshot = function() n = n + 1 end
  W.env.GetPhysicalScreenSize = function() return 2560, 1440 end
  local ns = H.loadAddon({ env = W.env })
  W.fire("ADDON_LOADED", "WoWBoxer"); W.fire("PLAYER_LOGIN")
  W.flush()
  W.env.SlashCmdList.WOWBOXER("shots")
  for _ = 1, 60 do if #W.timers == 0 then break end W.flush() end
  local shots = ns.Core.db.shots
  H.ok(shots and #shots.list == n and n >= 11, "shots: one record per screenshot (" .. n .. ")")
  local first = shots and shots.list[1]
  H.ok(first and first.name == "page-keys" and first.w == 2560 and first.r > first.l and first.bottom > first.top, "shots: window box in screen pixels")
  H.eq(W.calls.CreateMacro, nil, "shots: no macro written")
  H.eq(W.calls.PlaceAction, nil, "shots: nothing placed")
  H.ok(not (ns.Advanced.confirmFrame and ns.Advanced.confirmFrame:IsShown()) and not (ns.Advanced.rf and ns.Advanced.rf:IsShown()), "shots: dialogs closed again")
end

os.exit(H.report("diag") and 0 or 1)
