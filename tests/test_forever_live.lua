-- WoW Forever on the live client's talents (docs/talents-rerun-2026-11-11.md, 11 Nov 2026): the trees come from the
-- client tables (C_Traits), every guide is legal on them, every class and role has a whole default guide, the
-- sequences and recommended macros name spells that exist, talent spells come no earlier than their row, a saved
-- guide that is gone falls back with one chat line, and an own build the live trees no longer hold is kept as saved
-- with a warning (never changed silently).
local dir = (arg[0]:match("^(.*)/[^/]+$") or ".")
local H = dofile(dir .. "/harness.lua")
local Mock = dofile(dir .. "/wowmock.lua")

local function boot(db, opts)
  opts = opts or { name = "Rup", class = "PRIEST", race = "Human", level = 30 }
  local W = Mock.new(H, opts)
  if db then W.env.WoWBoxerDB = db end
  local ns = H.loadAddon({ env = W.env })
  W.fire("ADDON_LOADED", "WoWBoxer"); W.fire("PLAYER_LOGIN")
  return W, ns
end

local W, ns = boot()
local D, E, K = ns.Data, ns.Engine, ns.Kit
H.eq(D.game.key, "forever", "Forever data")
H.ok(D.meta.build == "1.60.1.70888" and D.meta.talentBuild:find("C_Traits", 1, true), "talents from the client tables: " .. tostring(D.meta.talentBuild))

-- ------------------------------------------------------------------ trees
local function node(cls, name) for _, n in ipairs(D.talents[cls].nodes) do if n.n == name then return n end end end
local function spell(cls, name) for _, s in ipairs(D.spells[cls]) do if s.name == name then return s end end end
local total = 0
for _, cls in ipairs(D.classOrder) do
  local T = K.tree(cls)
  total = total + #T.nodes
  local rows = 0
  for _, n in ipairs(T.nodes) do if n.r > rows then rows = n.r end end
  H.ok(#T.trees == 3 and rows == 7, cls .. ": three trees, seven rows")
end
H.eq(total, 467, "467 talents (the client's class trees, the same as Wowhead's calculator)")
H.ok(not node("mage", "Arcane Focus") and node("mage", "Accelerant") and node("mage", "Incineration").m == 5 and node("mage", "Critical Mass").m == 3, "Mage: live Arcane/Fire trees (no Arcane Focus, Accelerant, Incineration 5, Critical Mass 3)")
H.ok(node("mage", "Arcane Resilience").m == 3 and node("mage", "Arcane Resilience").r == 1, "Mage: Arcane Resilience 3 ranks in row 1")
H.ok(node("hunter", "Lightning Reflexes").r == 6 and node("priest", "Holy Specialization").r == 1, "parked copies (off the grid in the client) are left out; the live node is used")
H.ok(node("shaman", "Lightning Mastery") and not node("shaman", "Elemental Mastery"), "Shaman: Lightning Mastery (was Elemental Mastery)")

-- ------------------------------------------------------------------ guides
local nGuides = 0
for _, cls in ipairs(D.classOrder) do
  local T = K.tree(cls)
  local defaults = 0
  for _, g in ipairs(D.guides[cls]) do
    nGuides = nGuides + 1
    if g.default then defaults = defaults + 1 end
    if #g.order > 0 then
      local bad = E.validateOrder(T, g.order)
      H.ok(not bad, cls .. " " .. g.id .. ": legal on the live trees" .. (bad and (" – point " .. (bad.index + 1) .. ": " .. bad.reason) or ""))
    end
  end
  H.eq(defaults, 1, cls .. ": one class default")
  for _, role in ipairs(D.classes[cls].roles) do
    local g = K.guide(cls, K.defaultGuideFor(cls, role))
    H.ok(g and #g.order >= 21 and not E.validateOrder(T, g.order), cls .. "/" .. role .. ": a legal default guide (" .. tostring(g and g.id) .. ", " .. tostring(g and #g.order) .. " points)")
  end
end
H.eq(nGuides, 90, "all 90 guide ids kept (saved choices stay valid)")
local function guide(cls, id) for _, g in ipairs(D.guides[cls]) do if g.id == id then return g end end end
local pal = guide("paladin", "pal-prot-holyshield")
H.ok(pal and #pal.order == 51 and pal.source.site == "Icy Veins" and pal.note:find("Rebuilt for WoW Forever's live talents", 1, true), "a rebuilt guide names its new source: " .. tostring(pal and pal.source.site))
local mv = guide("warrior", "war-fury-mobalytics-kargoz")
H.ok(mv and mv.note:find("no updated version of the source was found", 1, true) and mv.note:find("left for you to place", 1, true), "a guide without a current source says so")
H.ok(not guide("hunter", "hun-beast-mastery-mobalytics-kargoz").default and guide("hunter", "hun-beast-mastery-warcraft-tavern-sponge").default, "Hunter: the default moved to a whole current guide")

-- ------------------------------------------------------------------ spells: talents, levels, removed spells
H.eq(spell("shaman", "Lava Burst"), nil, "Lava Burst is gone (no talent, no trainer)")
H.eq(spell("druid", "Berserk"), nil, "Berserk is gone")
H.eq(spell("priest", "Binding Heal"), nil, "Binding Heal is gone")
local lm = spell("shaman", "Lightning Mastery")
H.ok(lm and lm.gate == "talent" and lm.talent == "lightning-mastery" and lm.level == 40, "Lightning Mastery: talent, level 40 (row 7)")
local vt = spell("paladin", "Voice of Truth")
H.ok(vt and vt.gate == "trainer" and vt.level == 20, "Voice of Truth: a trainer spell at 20")
local hs = spell("paladin", "Holy Shield")
H.ok(hs and node("paladin", "Holy Shield").r == 5 and hs.level == 30 and hs.ranks[#hs.ranks].l == 60, "Holy Shield: row 5 now, from level 30 to its rank at 60")
for _, cls in ipairs(D.classOrder) do
  for _, s in ipairs(D.spells[cls]) do
    if s.gate == "talent" and s.talent then
      local n = K.tree(cls).byKey[s.talent]
      H.ok(n ~= nil, cls .. " " .. s.name .. ": its talent " .. s.talent .. " exists")
      if n then H.ok(s.level >= 10 + 5 * (n.r - 1), cls .. " " .. s.name .. ": not before its row (level " .. s.level .. ", row " .. n.r .. ")") end
    end
  end
end

-- ------------------------------------------------------------------ sequences and recommended macros name real spells
local function each(step, f)
  if type(step) == "string" then f(step)
  elseif type(step) == "table" then
    if step.s ~= nil then each(step.s, f) else for _, x in ipairs(step) do each(x, f) end end
  end
end
for cls, byRole in pairs(D.sequences) do
  for role, defs in pairs(byRole) do
    for _, d in ipairs(defs) do
      for tier, t in pairs(d.tiers) do
        for _, st in ipairs(t.steps or {}) do each(st, function(n) H.ok(spell(cls, n) ~= nil, cls .. "/" .. role .. " " .. d.id .. " " .. tier .. ": " .. n .. " is a Forever spell") end) end
        for _, n in ipairs(t.filler or {}) do H.ok(spell(cls, n) ~= nil, cls .. "/" .. role .. " " .. tier .. " filler: " .. n) end
      end
    end
  end
end
for cls, byRole in pairs(D.core) do
  for role, items in pairs(byRole) do
    for _, it in ipairs(items) do each(it, function(n) H.ok(spell(cls, n) ~= nil, cls .. "/" .. role .. " recommended macro: " .. n) end) end
  end
end

-- ------------------------------------------------------------------ a saved guide that is gone; an own build that no longer fits
local db = {
  v = 1,
  squads = { { id = "s1", name = "Trio", members = {
    { id = "m1", name = "Rup", cls = "priest", race = "human", role = "healer", leader = true, level = 30, guide = "pri-holy-gone-id" },
    { id = "m2", name = "Rip", cls = "mage", race = "human", role = "ranged", level = 30, guide = "uOld" } } } },
  active = "s1",
  builds = { mage = { { id = "uOld", label = "Old arcane", kind = "exact-order", saved = "2026-11-01",
    order = { "arcane-focus", "arcane-focus", "wand-specialization", "wand-specialization", "improved-channeling" } } } },
}
local W2, ns2 = boot(db)
local s = ns2.Core.db.squads[1]
H.eq(s.members[1].guide, ns2.Kit.defaultGuideFor("priest", "healer"), "a guide id that is gone falls back to the default")
H.ok(W2.chatHas("Your talent guide was updated for WoW Forever's live talents"), "with one chat line")
local n = 0
for _, m in ipairs(W2.chat) do if m:find("talent guide was updated", 1, true) then n = n + 1 end end
H.eq(n, 1, "only one line")
local b = ns2.Core.db.builds.mage and ns2.Core.db.builds.mage[1]
H.ok(b and b.id == "uOld" and b.label == "Old arcane", "the own build is kept")
H.eq(b and table.concat(b.orig, ","), "arcane-focus,arcane-focus,wand-specialization,wand-specialization,improved-channeling", "as saved (orig)")
H.ok(b and b.stale and b.stale:find("arcane-focus", 1, true), "with a warning: " .. tostring(b and b.stale))
H.eq(b and table.concat(b.order, ","), "wand-specialization,wand-specialization,improved-channeling", "the plan uses the points that still fit")
H.eq(s.members[2].guide, "uOld", "the member still uses it")
-- the warning shows in the Guide list (tooltip) and the list label
local tab
do
  local UI = ns2.UI
  ns2.Core.cdb.guide = "done"
  for _, t in ipairs(UI.tabs) do if t.key == "talents" then tab = t end end
  local tip = tab.guideTip(b)
  H.ok(tip:find("needs an update for the live talents", 1, true), "Guide list tooltip warns: " .. tip)
end
-- a second login: still kept, still warned, nothing new in legacy-less data
local W3, ns3 = boot(ns2.Core.db)
local b3 = ns3.Core.db.builds.mage[1]
H.ok(b3.stale and table.concat(b3.orig, ",") == table.concat(b.orig, ","), "a second login keeps the original and the warning")
H.ok(not W3.chatHas("talent guide was updated"), "no chat line once the guide is fixed")
H.eq(W.calls.LearnTalent, nil, "never touches the game's talents")

os.exit(H.report("forever_live") and 0 or 1)
