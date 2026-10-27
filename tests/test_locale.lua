-- Non-English clients: spell names in macros are translated token by token. Run: lua tests/test_locale.lua
local dir = (arg[0]:match("^(.*)/[^/]+$") or ".")
local H = dofile(dir .. "/harness.lua")
local Mock = dofile(dir .. "/wowmock.lua")

-- 1. Round trip: every macro the companion engine produces survives the translator unchanged with an identity map.
do
  local ns = H.loadAddon({ env = Mock.new(H, {}).env })
  local M, J = ns.Macros, ns.Json
  local names = {}
  for _, list in pairs(ns.Data.spells) do for _, s in ipairs(list) do names[s.name] = s.name end end
  local bodies, n = {}, 0
  local function walk(v)
    if type(v) == "string" then
      if (v:sub(1, 1) == "#" or v:sub(1, 1) == "/") and v:find("\n") and not bodies[v] then bodies[v] = true; n = n + 1 end
    elseif type(v) == "table" then for _, x in pairs(v) do walk(x) end end
  end
  for _, f in ipairs({ "macros", "sequences", "custom" }) do
    local txt = H.readFile(H.root .. "/tests/vectors/" .. f .. ".json")
    if txt then walk(J.decode(txt)) end
  end
  H.ok(n > 1000, "many engine macros to check (" .. n .. ")")
  local bad = 0
  for b in pairs(bodies) do
    local out = M.localize(b, names)
    if out ~= b then bad = bad + 1; if bad <= 3 then H.eq(out, b, "round trip") end end
  end
  H.eq(bad, 0, "every engine macro round-trips byte for byte")
end

-- 2. Translation of whole tokens only.
do
  local ns = H.loadAddon({ env = Mock.new(H, {}).env })
  local M = ns.Macros
  local de = { ["Smite"] = "Göttliche Pein", ["Heal"] = "Heilen", ["Greater Heal"] = "Große Heilung",
    ["Shadow Word: Pain"] = "Schattenwort: Schmerz", ["Auto Shot"] = "Automatischer Schuss" }
  H.eq(M.localize("#showtooltip Greater Heal\n/cast [@mouseover,help,nodead][@party1,help,nodead][@player] Greater Heal", de),
    "#showtooltip Große Heilung\n/cast [@mouseover,help,nodead][@party1,help,nodead][@player] Große Heilung", "whole name, not 'Heal' inside")
  H.eq(M.localize("#showtooltip\n/castsequence [@mouseover,harm,nodead][harm,nodead] reset=combat Shadow Word: Pain, Smite, Smite", de),
    "#showtooltip\n/castsequence [@mouseover,harm,nodead][harm,nodead] reset=combat Schattenwort: Schmerz, Göttliche Pein, Göttliche Pein", "castsequence entries")
  H.eq(M.localize("#showtooltip Auto Shot\n/petattack [harm,nodead]\n/cast [harm,nodead] !Auto Shot", de),
    "#showtooltip Automatischer Schuss\n/petattack [harm,nodead]\n/cast [harm,nodead] !Automatischer Schuss", "! prefix kept")
  H.eq(M.localize("/cast [combat] Heal\n/startattack [harm,nodead]\n/follow party1", de), "/cast [combat] Heilen\n/startattack [harm,nodead]\n/follow party1", "other lines untouched")
  H.eq(M.localize("#showtooltip Attack\n/startattack [harm,nodead]", de), "#showtooltip Attack\n/startattack [harm,nodead]", "unknown names stay")
end

-- 3. In a simulated German client the planned macros use the client's names; English clients are unchanged.
do
  local W = Mock.new(H, { name = "Pri", class = "PRIEST", race = "Scourge", level = 20 })
  W.env.GetLocale = function() return "deDE" end
  local ns = H.loadAddon({ env = W.env })
  W.fire("ADDON_LOADED", "WoWBoxer"); W.fire("PLAYER_LOGIN")
  local smiteId
  for _, s in ipairs(ns.Data.spells.priest) do
    if s.level <= 20 and s.gate ~= "talent" then W.known[s.name] = true end
    if s.name == "Smite" then smiteId = s.ranks[1].id end
  end
  local cs = W.env.C_Spell or {}
  cs.GetSpellName = function(id) return id == smiteId and "Göttliche Pein" or nil end
  W.env.C_Spell = cs
  ns.UI.Open("keys")
  local body
  for _, d in ipairs(ns.Core.compute().desired) do if d.label == "Smite" then body = d.body end end
  H.ok(body and body:find("Göttliche Pein", 1, true) and not body:find("Smite", 1, true), "deDE: Smite macro uses the German name: " .. tostring(body))

  local W2 = Mock.new(H, { name = "Pri", class = "PRIEST", race = "Scourge", level = 20 })
  local ns2 = H.loadAddon({ env = W2.env })
  W2.fire("ADDON_LOADED", "WoWBoxer"); W2.fire("PLAYER_LOGIN")
  for _, s in ipairs(ns2.Data.spells.priest) do if s.level <= 20 and s.gate ~= "talent" then W2.known[s.name] = true end end
  W2.env.C_Spell = cs
  ns2.UI.Open("keys")
  for _, d in ipairs(ns2.Core.compute().desired) do if d.label == "Smite" then body = d.body end end
  H.ok(body:find("Smite", 1, true) ~= nil, "enUS: unchanged")
end

os.exit(H.report("locale") and 0 or 1)
