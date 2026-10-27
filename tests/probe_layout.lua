-- Dev helper (not part of run_all): print layout problems per tab. Run: python tools/lua.py tests/probe_layout.lua
local dir = (arg[0]:match("^(.*)/[^/]+$") or ".")
local H = dofile(dir .. "/harness.lua")
local Mock = dofile(dir .. "/wowmock.lua")
local Layout = dofile(dir .. "/layout.lua")
local W = Mock.new(H, { name = "Dorin", class = "PALADIN", race = "Scourge", level = 20, screen = { w = 1024, h = 768 } })
local ns = H.loadAddon({ env = W.env })
W.fire("ADDON_LOADED", "WoWBoxer"); W.fire("PLAYER_LOGIN")
for _, s in ipairs(ns.Data.spells.paladin) do if s.level <= 20 then W.known[s.name] = true end end
ns.UI.Open("keys")
for _, t in ipairs(ns.UI.tabs) do
  ns.UI.Select(t.key)
  local p = Layout.check(W, { ns.UI.frame })
  print("== " .. t.key .. " " .. #p)
  for i, m in ipairs(p) do if i <= 15 then print("  " .. m) end end
end
