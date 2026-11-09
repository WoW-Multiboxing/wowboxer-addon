-- TBC Anniversary client (interface 20506, plan step 2 "basic TBC"): the addon loads with TBC's own data, macros come
-- from the live spellbook (no future spells), every page opens without errors, selftest works, Place all works,
-- the new races, the TBC talent trees (61 points, level 70) and Wowhead /tbc/ links.
local dir = (arg[0]:match("^(.*)/[^/]+$") or ".")
local H = dofile(dir .. "/harness.lua")
local Mock = dofile(dir .. "/wowmock.lua")

local function boot(opts)
  opts.toc = 20506
  opts.spellbookStyle = opts.spellbookStyle or "classic"
  local W = Mock.new(H, opts)
  local ns = H.loadAddon({ env = W.env })
  W.fire("ADDON_LOADED", "WoWBoxer"); W.fire("PLAYER_LOGIN")
  return W, ns
end
local function errors(ns)
  local n = {}
  for _, e in ipairs(ns.Core.db.log) do if e.l == "error" then n[#n + 1] = e.m end end
  return n
end
local function names(list) local o = {}; for _, d in ipairs(list) do o[#o + 1] = d.name .. "=" .. (d.label or "") end return table.concat(o, ", ") end

-- ------------------------------------------------------------------ the game and its data
do
  local W, ns = boot({ name = "Velen", class = "SHAMAN", race = "Draenei", faction = "Alliance", level = 30 })
  local C, D, E = ns.Compat, ns.Data, ns.Engine
  H.eq(C.game(), "tbc", "TBC client")
  H.eq(D.game.key, "tbc", "TBC data loaded")
  H.eq(E.maxLevel(), 70, "max level 70")
  H.eq(E.maxPoints(), 61, "61 talent points")
  H.eq(E.pointsAt(70, 0), 61, "61 points at 70")
  H.eq(C.playerRace(), "draenei", "Draenei race file")
  local races = {}
  for _, r in ipairs(D.races) do races[r.k] = r end
  H.ok(races.draenei and races.bloodelf and not races["high-order-skyborne"], "TBC races: Draenei and Blood Elf, no Skyborne")
  H.ok(ns.Engine.contains(races.draenei.c, "shaman") and ns.Engine.contains(races.bloodelf.c, "paladin"), "Alliance Shaman, Horde Paladin")
  H.ok(not ns.Engine.contains(races.dwarf.c, "shaman"), "no Dwarf Shaman in TBC")
  for _, cls in ipairs(D.classOrder) do
    local T = ns.Kit.tree(cls)
    local rows = 0
    for _, n in ipairs(T.nodes) do if n.r > rows then rows = n.r end end
    H.ok(#T.trees == 3 and #T.nodes >= 60 and rows == 9, cls .. ": three TBC trees, nine rows (" .. #T.nodes .. " talents)")
    local gs = ns.Kit.dataGuidesOf(cls)
    H.ok(#gs >= 1 and #gs[1].order == 61 and not E.validateOrder(T, gs[1].order), cls .. ": WoWBoxer starter builds with all 61 points, legal")
    for _, role in ipairs(D.classes[cls].roles) do
      local g = ns.Kit.guide(cls, ns.Kit.defaultGuideFor(cls, role))
      H.ok(g ~= nil and #g.order == 61, cls .. "/" .. role .. ": a default guide for the role")
    end
    H.ok(E.seqSupported(cls), cls .. ": built-in sequence macros")
  end
  -- a 41-point talent (row 9) is legal once 40 points are in the tree
  local T = ns.Kit.tree("mage")
  local deep
  for _, n in ipairs(T.nodes) do if n.r == 9 and n.t == 2 then deep = n end end
  H.eq(deep and deep.n, "Summon Water Elemental", "Frost row 9: Summon Water Elemental")
end

-- ------------------------------------------------------------------ live spellbook decides, every page, Place all
for _, sc in ipairs({
  { name = "Velen", class = "SHAMAN", race = "Draenei", faction = "Alliance", level = 30, book = { "Earth Shock", "Lightning Bolt", "Healing Wave", "Gift of the Naaru", "Stormstrike" } },
  { name = "Kael", class = "PALADIN", race = "BloodElf", faction = "Horde", level = 64, book = { "Seal of Righteousness", "Holy Light", "Judgement", "Crusader Strike", "Arcane Torrent", "Flash of Light" } },
  { name = "Rexxar", class = "HUNTER", race = "Orc", faction = "Horde", level = 12, book = { "Auto Shot", "Serpent Sting", "Arcane Shot", "Raptor Strike", "Hunter's Mark" }, spellbookStyle = "modern" },
}) do
  local book0 = sc.book; sc.book = nil
  local W, ns = boot(sc)
  sc.book = book0
  for _, n in ipairs(sc.book) do W.known[n] = true end
  ns.Compat.invalidateSpellbook()
  local UI, Core, M, K = ns.UI, ns.Core, ns.Macros, ns.Kit
  local tag = sc.class .. " " .. sc.race .. ": "
  UI.Toggle()
  H.ok(UI.frame:IsShown(), tag .. "window opens")
  local _, me = Core.me()
  H.ok(me ~= nil and me.cls == sc.class:lower(), tag .. "this character is set up")
  H.eq(me.race, sc.race == "BloodElf" and "bloodelf" or sc.race:lower(), tag .. "race")
  for _, t in ipairs(UI.tabs) do UI.Select(t.key); H.ok(UI.panels[t.key]:IsShown(), tag .. "page " .. t.key .. " opens") end
  local ctx = Core.compute()
  H.ok(ctx ~= nil, tag .. "macros computed")
  -- only spells in the spellbook get a macro (no future spells)
  local book = {}
  for _, n in ipairs(sc.book) do book[n] = true end
  for _, d in ipairs(ctx.desired) do
    if d.spell and d.group == "kit" then H.ok(book[d.spell.name], tag .. d.name .. " " .. d.spell.name .. " is in the spellbook") end
  end
  local kit = 0
  for _, d in ipairs(ctx.desired) do if d.group == "kit" then kit = kit + 1 end end
  H.ok(kit >= 2, tag .. "spell macros from the spellbook (" .. names(ctx.desired) .. ")")
  -- Place all
  Core.sync()
  for _ = 1, 3 do W.flush() end
  H.eq(Core.compute().macros.changes, 0, tag .. "Place all creates every macro")
  local kitMacros = 0 -- plain spells (no target) are the spell itself on the bar, no macro (owner, 9 Nov 2026)
  for _, d in ipairs(ctx.desired) do if d.group == "kit" and not d.plain then kitMacros = kitMacros + 1 end end
  H.ok((W.calls.CreateMacro or 0) >= kitMacros, tag .. "macros created")
  -- selftest + login checks run without errors
  for _ = 1, 4 do W.flush() end
  Core.selftest(true)
  local diag = Core.db.diag[Core.charKey]
  H.ok(diag and diag.probe and diag.probe.game == "tbc", tag .. "selftest written (game tbc)")
  local e = errors(ns)
  H.eq(#e, 0, tag .. "no errors in the log: " .. table.concat(e, " | "))
  -- talents page: the role's starter build, Blizzard credit, no error
  UI.Select("talents")
  local p = UI.panels.talents
  H.ok((p.kind._text or ""):find("Guide's final build", 1, true) ~= nil, tag .. "Talents page shows the starter build: " .. tostring(p.kind._text))
  H.ok((p.source._text or ""):find("Blizzard client tables", 1, true) ~= nil, tag .. "Blizzard credit on the Talents page")
end

-- ------------------------------------------------------------------ Wowhead /tbc/ talent links
do
  local W, ns = boot({ name = "Jaina", class = "MAGE", race = "Human", faction = "Alliance", level = 70 })
  local WH, K, E = ns.Wowhead, ns.Kit, ns.Engine
  -- a full 61-point frost build in Wowhead's TBC format, made by the encoder and read back
  local T = K.tree("mage")
  local order, c = {}, E.newCounts()
  for _ = 1, 200 do
    if #order >= 61 then break end
    for _, n in ipairs(T.nodes) do
      if #order < 61 and (n.t == 2 or (n.t == 0 and n.r <= 2)) and not E.addBlocker(T, c, n.k) then order[#order + 1] = n.k; E.bump(c, n.k) end
    end
  end
  H.eq(#order, 61, "61 points placed")
  local link = WH.encode("mage", order, 0)
  H.ok(link:find("^https://www%.wowhead%.com/tbc/talent%-calc/mage/") ~= nil, "links are /tbc/ links: " .. link)
  local r = WH.import(link)
  H.ok(not r.error, "the link reads back: " .. tostring(r.error))
  H.eq(r.points, 61, "61 points read")
  H.deqMsg(r.order, order, "same order")
  -- a hand-written TBC link: 2 points Arcane Subtlety, 3 Improved Frostbolt … (points only, no order)
  local r2 = WH.import("https://www.wowhead.com/tbc/talent-calc/mage/2--05")
  H.ok(not r2.error and r2.points == 7, "points-only link: " .. tostring(r2.error or r2.points))
  local bad = WH.import("https://www.wowhead.com/forever/talent-calc/mage/v22")
  H.ok(bad.error and bad.error:find("TBC Anniversary", 1, true), "a Forever link is refused on TBC: " .. tostring(bad.error))
end

os.exit(H.report("tbc") and 0 or 1)
