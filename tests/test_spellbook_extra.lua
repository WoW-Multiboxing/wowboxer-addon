-- All spells must contain EVERY spell (owner, 10 Nov 2026: Rup, a Human priest on Forever, knows Divine Grace and All
-- spells never showed it). Two parts: the data now has the Forever spells the pre-launch seed lacked
-- (datasrc/forever/spells-extra.json, docs/forever-new-spells.md), and the live spellbook fills in anything still
-- missing: learned spells in the list, the book's future spells under Future spells; passives, professions and the
-- General tab are skipped. A spellbook spell drags like any other (the spell itself, cast by name).
local dir = (arg[0]:match("^(.*)/[^/]+$") or ".")
local H = dofile(dir .. "/harness.lua")
local Mock = dofile(dir .. "/wowmock.lua")

local function boot(opts)
  local W = Mock.new(H, opts)
  local ns = H.loadAddon({ env = W.env })
  W.fire("ADDON_LOADED", "WoWBoxer"); W.fire("PLAYER_LOGIN")
  ns.Core.cdb.guide = "done"
  ns.State.quickStart(ns.Core.db, ns.Core.cdb, ns.Core.playerInfo())
  for _, s in ipairs(ns.Data.spells[(opts.class or "PALADIN"):lower()]) do
    if s.level <= (opts.level or 10) and s.gate ~= "talent" then W.known[s.name] = true end
  end
  return W, ns
end
local function cells(ns, q)
  local secs = ns.Book.spellSections(ns.Core.compute(), q)
  local learned, future = {}, {}
  for _, c in ipairs(secs[1].cells) do learned[c.label] = c end
  for _, c in ipairs(secs[2].cells) do future[c.label] = c end
  return learned, future, secs
end

-- ------------------------------------------------------------------ 1. the data: Divine Grace and the other Forever spells
do
  local W, ns = boot({ name = "Rup", class = "PRIEST", race = "Human", level = 18 })
  local learned, future = cells(ns)
  H.ok(learned["Divine Grace"] ~= nil, "Human priest 18: Divine Grace is in All spells")
  H.ok(learned["Feedback"] == nil and future["Feedback"] ~= nil, "Feedback (Human, 20): under Future spells")
  H.ok(learned["Chastise"] == nil and future["Chastise"] == nil, "Chastise is the Dwarf's, not a Human's")
  local dg
  for _, s in ipairs(ns.Data.spells.priest) do if s.name == "Divine Grace" then dg = s end end
  H.eq(dg and #dg.ranks, 7, "Divine Grace: 7 ranks")
  H.eq(dg and dg.ranks[2].id, 1277371, "rank 2 is spell 1277371 (level 18)")
  H.eq(dg and dg.cdSec, 600, "a 10 min cooldown (client table)")
  -- the macro: a friendly heal on a target, never on yourself (it can't be cast on self)
  local body = ns.Engine.makeMacro(dg, ns.Kit.memberCtx(ns.Core.compute().member))
  H.ok(body:find("/cast [@mouseover,help,nodead]", 1, true) ~= nil and not body:find("@player", 1, true), "Divine Grace macro: help target, not @player: " .. body)
  -- drag it: a macro the player can put on a bar
  W.known["Divine Grace"] = true; W.fire("SPELLS_CHANGED"); W.flush()
  local ok, why = ns.Core.pickupSpell(dg.id)
  H.ok(ok, "Divine Grace: drag makes a macro (" .. tostring(why) .. ")")
  local made
  for _, d in ipairs(ns.Core.compute().desired) do if d.spell == dg then made = d end end
  H.ok(made and made.body:find("Divine Grace", 1, true) ~= nil, "the macro casts Divine Grace")

  local W2, ns2 = boot({ name = "Brom", class = "PRIEST", race = "Dwarf", level = 20 })
  local l2 = cells(ns2)
  H.ok(l2["Chastise"] and l2["Desperate Prayer"] and not l2["Divine Grace"], "Dwarf priest 20: Chastise and Desperate Prayer, no Divine Grace")
  local W3, ns3 = boot({ name = "Shanky", class = "ROGUE", race = "Human", level = 24 })
  H.ok(cells(ns3)["Shank"] ~= nil, "rogue 24: Shank (new in Forever)")
  local W4, ns4 = boot({ name = "Totem", class = "SHAMAN", race = "Orc", level = 22 })
  H.ok(cells(ns4)["Totemic Call"] ~= nil, "shaman 22: Totemic Call (new in Forever)")
  -- a talent spell the pre-launch trees don't have: not listed until the spellbook has it
  local W5, ns5 = boot({ name = "Rage", class = "WARRIOR", race = "Orc", level = 30 })
  local l5, f5 = cells(ns5)
  H.ok(not l5["Reckless Swings"] and not f5["Reckless Swings"], "Reckless Swings: not listed while the book doesn't have it")
  W5.known["Reckless Swings"] = true; W5.fire("SPELLS_CHANGED"); W5.flush()
  H.ok(cells(ns5)["Reckless Swings"] ~= nil, "Reckless Swings: listed once the spellbook has it")
end

-- ------------------------------------------------------------------ 2. the live spellbook (a fake book)
-- tab 1 General (a profession, a mount), tab 2 the class: a data spell, an extra known spell (two ranks), a passive,
-- a future spell, a hidden line
local function fakeBook(W, ns, style)
  local G = W.env
  local tabs = {
    { name = "General", items = { { name = "First Aid", id = 3273 }, { name = "Summon Gryphon", id = 32235 } } },
    { name = "Holy", items = {
      { name = "Smite", id = 585 },
      { name = "Holy Bolt", id = 900001, rank = "Rank 1" },
      { name = "Holy Bolt", id = 900003, rank = "Rank 2" },
      { name = "Spirit Tap", id = 900004, passive = true },
      { name = "Future Nova", id = 900002, future = true },
    } },
    { name = "Hidden", hide = true, items = { { name = "Secret Spell", id = 900009 } } },
  }
  local flat, off = {}, {}
  for i, t in ipairs(tabs) do off[i] = #flat; for _, it in ipairs(t.items) do flat[#flat + 1] = it end end
  W.knownIds[900001], W.knownIds[900003] = true, true
  G.GetSpellLevelLearned = function(id) return id == 900002 and 30 or 0 end
  if style == "modern" then
    G.Enum = { SpellBookSpellBank = { Player = 0, Pet = 1 }, SpellBookItemType = { Spell = 1, FutureSpell = 2, PetAction = 3, Flyout = 4 } }
    G.C_SpellBook = {
      GetNumSpellBookSkillLines = function() return #tabs end,
      GetSpellBookSkillLineInfo = function(i) return { name = tabs[i].name, itemIndexOffset = off[i], numSpellBookItems = #tabs[i].items, shouldHide = tabs[i].hide } end,
      GetSpellBookItemName = function(j) return flat[j] and flat[j].name, flat[j] and flat[j].rank end,
      GetSpellBookItemInfo = function(j)
        local it = flat[j]
        if not it then return nil end
        return { name = it.name, spellID = it.id, actionID = it.id, subName = it.rank or "", iconID = 100 + it.id, isPassive = it.passive or false,
          itemType = it.future and 2 or 1 }
      end,
    }
    G.C_Spell.GetSpellLevelLearned = G.GetSpellLevelLearned
  else
    G.C_SpellBook = nil
    G.BOOKTYPE_SPELL = "spell"
    G.GetNumSpellTabs = function() return #tabs - 1 end -- classic: no hidden lines
    G.GetSpellTabInfo = function(i) return tabs[i].name, nil, off[i], #tabs[i].items end
    G.GetSpellBookItemName = function(j) return flat[j] and flat[j].name, flat[j] and flat[j].rank or "" end
    G.GetSpellBookItemInfo = function(j) local it = flat[j]; if not it then return nil end return it.future and "FUTURESPELL" or "SPELL", it.id end
    G.IsPassiveSpell = function(j) return flat[j] and flat[j].passive or false end
    G.GetSpellBookItemTexture = function(j) return flat[j] and 100 + flat[j].id end
  end
  ns.Compat.invalidateSpellbook()
end

for _, style in ipairs({ "modern", "classic" }) do
  local W, ns = boot({ name = "Rup", class = "PRIEST", race = "Human", level = 20, spellbookStyle = style })
  fakeBook(W, ns, style)
  local items = ns.Compat.spellbookItems()
  local names = {}
  for _, it in ipairs(items or {}) do names[#names + 1] = it.name .. (it.future and "(future)" or "") end
  H.eq(table.concat(names, ","), "Smite,Holy Bolt,Holy Bolt,Future Nova(future)", style .. ": book scan skips General, passives and hidden lines: " .. table.concat(names, ","))
  local learned, future = cells(ns)
  local hb = learned["Holy Bolt"]
  H.ok(hb ~= nil and hb.fromBook, style .. ": a known spell the data lacks is in All spells")
  H.eq(hb and #hb.spell.ranks, 2, style .. ": both ranks, one card")
  H.eq(hb and hb.spell.icon, 100 + 900001, style .. ": the game's icon")
  H.ok(future["Future Nova"] ~= nil and future["Future Nova"].pending == 30, style .. ": the book's future spell under Future spells, level 30 (GetSpellLevelLearned)")
  H.ok(not learned["Spirit Tap"] and not future["Spirit Tap"], style .. ": passive skipped")
  H.ok(not learned["First Aid"] and not learned["Summon Gryphon"], style .. ": profession and mount (General tab) skipped")
  H.ok(not learned["Secret Spell"], style .. ": hidden line skipped")
  local nSmite = 0
  for _, c in ipairs(select(3, cells(ns))[1].cells) do if c.label == "Smite" then nSmite = nSmite + 1 end end
  H.eq(nSmite, 1, style .. ": a data spell is not listed twice")
  -- tooltip says where it comes from
  local GT = W.env.GameTooltip
  local lines = {}
  local add = GT.AddLine
  GT.AddLine = function(self, t, ...) lines[#lines + 1] = t; return add(self, t, ...) end
  ns.UI.Open("spells")
  local p = ns.UI.panels.spells
  p.query = "holy bolt"; ns.UI.Refresh()
  local row
  for _, r in ipairs(p.cells or {}) do if r:IsShown() and r.cell and r.cell.label == "Holy Bolt" then row = r end end
  H.ok(row ~= nil, style .. ": the card is on the page (search)")
  if row then row:GetScript("OnEnter")(row) end
  H.ok(table.concat(lines, "\n"):find(ns.Book.FROM_BOOK, 1, true) ~= nil, style .. ": tooltip says From your spellbook")
  GT.AddLine = add
  -- drag: the spell itself goes on the bar (highest known rank)
  local picked
  W.env.PickupSpell = function(id) picked = id end
  if W.env.C_Spell then W.env.C_Spell.PickupSpell = function(id) picked = id end end
  local ok, why = ns.Core.pickupSpell(hb.spell.id)
  H.ok(ok, style .. ": drag works (" .. tostring(why) .. ")")
  H.eq(picked, 900003, style .. ": the highest rank goes on the cursor")
  -- an own macro can use it (Macro editor's spell list)
  local me = ns.Core.compute().member
  local inEditor = false
  for _, s in ipairs(ns.KeyEditor.spellChoices(me, me.level)) do if s.name == "Holy Bolt" then inEditor = true end end
  H.ok(inEditor, style .. ": the Macro editor can use it")
  local mc = ns.Engine.makeMacro(hb.spell, ns.Kit.memberCtx(me))
  H.eq(mc, "#showtooltip Holy Bolt\n/cast Holy Bolt", style .. ": cast by name (the client picks the rank)")
  -- diagnose: diag.extraSpells
  local ex = ns.Core.extraSpellsDiag()
  local txt = {}
  for _, x in ipairs(ex) do txt[#txt + 1] = x.name .. "#" .. x.id .. (x.rank and (" " .. x.rank) or "") .. (x.future and " future" or "") .. (x.level and (" L" .. x.level) or "") end
  H.eq(table.concat(txt, ","), "Holy Bolt#900001 Rank 1,Holy Bolt#900003 Rank 2,Future Nova#900002 future L30", style .. ": diag.extraSpells: " .. table.concat(txt, ","))
  W.fire("PLAYER_ENTERING_WORLD"); W.flush()
  -- another member of the squad (not this window's character): no book spells
  local other = { id = "zz", name = "Other", cls = "priest", race = "human", level = 20 }
  H.eq(#ns.Kit.bookSpells(other), 0, style .. ": only the logged-in character's book counts")
end

-- ------------------------------------------------------------------ 3. no spellbook API, or the mock's General-only book: nothing extra
do
  local W, ns = boot({ name = "Plain", class = "MAGE", race = "Human", level = 20, spellbookStyle = "none" })
  local me = ns.Core.compute().member
  H.eq(#ns.Kit.bookSpells(me), 0, "no spellbook API: no extra spells")
  local W2, ns2 = boot({ name = "Plain", class = "MAGE", race = "Human", level = 20 })
  local me2 = ns2.Core.compute().member
  H.eq(#ns2.Kit.bookSpells(me2), 0, "only a General tab: no extra spells")
end

-- ------------------------------------------------------------------ 4. Era / TBC: the spells the client has that the data lacked
do
  local function names(ns, cls) local t = {}; for _, s in ipairs(ns.Data.spells[cls]) do t[s.name] = s end return t end
  for _, g in ipairs({ { game = "era", spells = { paladin = { "Sense Undead" }, mage = { "Detect Magic" }, rogue = { "Instant Poison II" }, warlock = { "Create Healthstone (Minor)" } } },
                       { game = "tbc", spells = { paladin = { "Sense Undead" }, mage = { "Teleport: Shattrath", "Portal: Exodar" }, rogue = { "Anesthetic Poison" }, shaman = { "Totemic Call" } } } }) do
    local W, ns = boot({ name = "Eric", class = "MAGE", race = "Human", level = 20, toc = g.game == "era" and 11509 or 20506, spellbookStyle = "classic" })
    if ns.dataGame == g.game then
      for cls, list in pairs(g.spells) do
        local have = names(ns, cls)
        for _, n in ipairs(list) do H.ok(have[n] ~= nil and have[n].id ~= "" and have[n].id ~= nil, g.game .. " " .. cls .. ": " .. n .. " is in the data, with its own id") end
      end
      -- every spell has its own id (extras and macros are keyed by it)
      for _, cls in ipairs(ns.Data.classOrder) do
        local seen, dup = {}, nil
        for _, s in ipairs(ns.Data.spells[cls]) do if seen[s.id] then dup = s.name end seen[s.id] = true end
        H.ok(dup == nil, g.game .. " " .. cls .. ": no two spells share an id (" .. tostring(dup) .. ")")
      end
    else H.ok(false, "could not boot " .. g.game .. " (dataGame " .. tostring(ns.dataGame) .. ")") end
  end
end

H.report("spellbook-extra")
