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
  H.ok(W.chatHas("keys? changed"), "but the level-up offer was shown")
end

os.exit(H.report("diag") and 0 or 1)
