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

os.exit(H.report("diag") and 0 or 1)
