-- Classic Era client (interface 11509, plan step 3): Era's own data from the client's tables – the vanilla talent trees
-- (7 rows, 51 points), the eight races, vanilla spell names and trainer levels, no Season of Discovery runes, WoWBoxer
-- starter builds per role, built-in sequence macros with Era's spells, Wowhead /classic/ links, future spells.
local dir = (arg[0]:match("^(.*)/[^/]+$") or ".")
local H = dofile(dir .. "/harness.lua")
local Mock = dofile(dir .. "/wowmock.lua")

local W = Mock.new(H, { toc = 11509, spellbookStyle = "classic", name = "Thrall", class = "WARLOCK", race = "Orc", faction = "Horde", level = 40 })
local ns = H.loadAddon({ env = W.env })
W.fire("ADDON_LOADED", "WoWBoxer"); W.fire("PLAYER_LOGIN")
local D, E, K, M = ns.Data, ns.Engine, ns.Kit, ns.Macros

H.eq(D.game.key, "era", "Era data")
H.eq(E.maxLevel(), 60, "max level 60")
H.eq(E.maxPoints(), 51, "51 talent points")
local races = {}
for _, r in ipairs(D.races) do races[r.k] = r end
H.eq(#D.races, 8, "the eight vanilla races")
H.ok(not races.draenei and not races.bloodelf and not races["high-order-skyborne"], "no TBC or Forever races")
H.ok(not E.contains(races.undead.c, "paladin") and not E.contains(races.dwarf.c, "shaman"), "no Forever race/class choices")
local function spell(cls, name) for _, s in ipairs(D.spells[cls]) do if s.name == name then return s end end end
H.ok(spell("warlock", "Curse of Agony") and not spell("warlock", "Bane of Agony"), "vanilla name: Curse of Agony")
H.ok(not spell("mage", "Living Flame") and not spell("rogue", "Mutilate") and not spell("shaman", "Lava Burst"), "no Season of Discovery runes or Forever spells")
H.eq(spell("mage", "Frostbolt").level, 4, "Frostbolt from level 4 (Era trainer)")
H.eq(spell("warlock", "Curse of Agony").action, "petattack", "Curse of Agony takes the macro rules of Bane of Agony")
for _, cls in ipairs(D.classOrder) do
  local T = K.tree(cls)
  local rows = 0
  for _, n in ipairs(T.nodes) do if n.r > rows then rows = n.r end end
  H.ok(#T.trees == 3 and rows == 7, cls .. ": three vanilla trees, seven rows")
  for _, role in ipairs(D.classes[cls].roles) do
    local g = K.guide(cls, K.defaultGuideFor(cls, role))
    H.ok(g ~= nil and #g.order == 51 and not E.validateOrder(T, g.order), cls .. "/" .. role .. ": a legal 51-point starter build")
  end
  H.ok(E.seqSupported(cls), cls .. ": built-in sequence macros")
end
-- future spells: the warlock at 40 gets Curse of Agony now and sees Curse of Doom (60) as a later spell
local m = ns.State.newMember({ name = "Thrall", cls = "warlock", race = "orc", role = "ranged", leader = true, level = 40, seq = "advanced" })
local doom = spell("warlock", "Curse of Doom")
H.eq(M.pendingOf(m, doom, 40, nil), doom.level, "Curse of Doom: a future spell at level " .. tostring(doom.level))
local names = {}
for _, d in ipairs(M.desired(m, 40, { extras = { doom.id } })) do names[d.label] = d end
H.ok(names["Curse of Agony"] ~= nil, "Curse of Agony macro at 40")
H.ok(names["Curse of Doom"] and names["Curse of Doom"].pending == doom.level, "Curse of Doom macro waits for its level")
local s1
for _, d in ipairs(M.desired(m, 40, {})) do if d.key == "S1" then s1 = d end end
H.ok(s1 and s1.body:find("Curse of Agony, Corruption", 1, true), "sequence macro with Era's spells: " .. tostring(s1 and s1.body))
-- Wowhead /classic/ links
local WH = ns.Wowhead
local g = K.guide("warlock", K.defaultGuideFor("warlock", "ranged"))
local link = WH.encode("warlock", g.order, 0)
H.ok(link:find("^https://www%.wowhead%.com/classic/talent%-calc/warlock/") ~= nil, "Era links are /classic/ links")
local r = WH.import(link)
H.ok(not r.error and r.points == 51, "a /classic/ link reads back: " .. tostring(r.error or r.points))
H.deqMsg(r.order, g.order, "same order")
H.ok((WH.import("https://www.wowhead.com/tbc/talent-calc/warlock/05").error or ""):find("Classic Era", 1, true), "a TBC link is refused on Era")
os.exit(H.report("era") and 0 or 1)
