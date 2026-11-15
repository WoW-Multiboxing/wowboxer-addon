-- Spell identity must survive localized names, missing seed ranks and alternative client spell IDs.
local dir = (arg[0]:match("^(.*)/[^/]+$") or ".")
local H = dofile(dir .. "/harness.lua")
local Mock = dofile(dir .. "/wowmock.lua")

local function boot()
  local W = Mock.new(H, { class = "PALADIN", race = "Scourge", level = 60 })
  W.env.GetLocale = function() return "deDE" end
  local ns = H.loadAddon({ env = W.env })
  return W, ns
end
local function dataSpell(ns, name)
  for _, s in ipairs(ns.Data.spells.paladin) do if s.name == name then return s end end
end
local de = {
  [20154] = "Siegel der Rechtschaffenheit", [21084] = "Siegel der Rechtschaffenheit",
  [20287] = "Siegel der Rechtschaffenheit", [635] = "Heiliges Licht", [639] = "Heiliges Licht",
  [465] = "Aura der Hingabe",
}

-- The actual report: German book, learned ID 20154, not 21084. The ordinary spells still work.
do
  local W, ns = boot()
  W.env.C_Spell.GetSpellName = function(id) return de[id] end
  for _, id in ipairs({ 20154, 635, 465 }) do W.knownIds[id], W.known[de[id]] = true, true end
  for _, name in ipairs({ "Seal of Righteousness", "Holy Light", "Devotion Aura" }) do
    H.ok(ns.Compat.knowsSpell(dataSpell(ns, name)), "German learned spell: " .. name)
  end
  H.ok(ns.Compat.spellMatches(dataSpell(ns, "Seal of Righteousness"), de[20154], 20154), "same stored ID")
  H.ok(not ns.Compat.spellMatches(dataSpell(ns, "Seal of Righteousness"), de[635], 635), "different localized spell stays different")
  W.knownIds[20154], W.knownIds[21084] = nil, true
  H.ok(ns.Compat.knowsSpell(dataSpell(ns, "Seal of Righteousness")), "alternative ID is recognized through its localized book name")
  H.ok(ns.Compat.spellMatches(dataSpell(ns, "Seal of Righteousness"), de[21084], 21084), "alternative ID matches the same client name")
  -- Old data could omit rank 1 while later ranks still identify the localized spell.
  local old = { name = "Seal of Righteousness", ranks = { { r = 1, l = 1 }, { r = 2, l = 10, id = 20287 } } }
  H.ok(ns.Compat.knowsSpell(old), "missing first-rank ID does not prevent matching via a later rank's client name")
  H.eq(ns.Compat.localSpellName(old), de[20154], "translate from a later rank")
end

-- A client can expose both knowledge APIs; false/error in the first must not hide a positive second.
do
  local W, ns = boot()
  local seal = dataSpell(ns, "Seal of Righteousness")
  W.env.IsSpellKnown = function(id) return id == 20154 end
  H.ok(ns.Compat.knowsAnyRank(seal), "IsSpellKnown fallback when IsPlayerSpell returns false")
  H.eq(ns.Compat.bestRankId(seal), 20154, "fallback API also selects the learned rank")
  W.env.IsPlayerSpell = function() error("unsupported query") end
  H.ok(ns.Compat.knowsAnyRank(seal), "IsSpellKnown fallback when IsPlayerSpell raises")
end

-- Do not permanently cache a missing first-rank name: a later rank or a subsequent lookup can resolve it.
do
  local W, ns = boot()
  local names = { [639] = de[639] }
  W.env.C_Spell.GetSpellName = function(id) return names[id] end
  local light = dataSpell(ns, "Holy Light")
  H.eq(ns.Compat.localSpellName(light), de[639], "uncached first rank falls back to another rank")
  names[639] = nil
  H.eq(ns.Compat.localSpellName(light), nil, "no translated data yet")
  names[635] = de[635]
  H.eq(ns.Compat.localSpellName(light), de[635], "translation becomes available without a reload")
end

local function book(W, ns, style, entries)
  local G = W.env
  G.IsPlayerSpell, G.IsSpellKnown = function() return false end, nil
  G.C_Spell.GetSpellName = function(id) return de[id] end
  if style == "modern" then
    G.Enum.SpellBookItemType = { Spell = 1, FutureSpell = 2 }
    G.C_SpellBook = {
      GetNumSpellBookSkillLines = function() return 2 end,
      GetSpellBookSkillLineInfo = function(i) return { itemIndexOffset = 0, numSpellBookItems = i == 2 and #entries or 0 } end,
      GetSpellBookItemName = function(i) return entries[i].name end,
      GetSpellBookItemInfo = function(i)
        local e = entries[i]
        return { name = e.name, spellID = e.id, subName = e.rank, itemType = e.future and 2 or 1, isPassive = false }
      end,
    }
  else
    G.C_SpellBook = nil
    G.GetNumSpellTabs = function() return 2 end
    G.GetSpellTabInfo = function(i) return i == 2 and "Heilig" or "Allgemein", nil, 0, i == 2 and #entries or 0 end
    G.GetSpellBookItemName = function(i) return entries[i].name, entries[i].rank end
    G.GetSpellBookItemInfo = function(i) return entries[i].future and "FUTURESPELL" or "SPELL", entries[i].id end
    G.IsPassiveSpell = function() return false end
  end
  ns.Compat.invalidateSpellbook()
end

for _, style in ipairs({ "modern", "classic" }) do
  local W, ns = boot()
  local C = ns.Compat
  local light, seal = dataSpell(ns, "Holy Light"), dataSpell(ns, "Seal of Righteousness")
  local entries = {
    { name = de[635], id = 635, rank = "Rang 1" },
    { name = de[639], id = 639, rank = "Rang 2", future = true },
    { name = de[21084], id = 21084, rank = "Rang 1" },
  }
  book(W, ns, style, entries)
  H.ok(C.knowsSpell(light), style .. ": learned German name recognized without knowledge APIs")
  H.eq(C.bestRankId(light), 635, style .. ": level 60 still selects the actual learned rank 1, not an untrained higher rank")
  H.eq(C.bestRankId(seal), 21084, style .. ": use the learned book ID even when the data only lists another ID")
  H.ok(ns.Bars.holdsSpell({ kind = "spell", id = 21084, name = de[21084] }, seal), style .. ": a localized alias already on a bar is recognized")
  H.ok(not ns.Bars.holdsSpell({ kind = "spell", id = 635, name = de[635] }, seal), style .. ": another German spell is not the Seal")
  local desired = { { name = "WBX K2", key = "K2", label = seal.name, plain = true, spell = seal } }
  W.actions[5] = { kind = "spell", id = 21084 }
  local layout = ns.Bars.layout(desired, { slots = {} }, C.actionInfo)
  H.eq(layout["WBX K2"], 5, style .. ": the localized alias keeps its actual button without saved bar memory")
  H.eq(ns.Bars.plan(desired, { slots = {} }).items[1].status, "placed", style .. ": the existing alias is already placed")
  entries[1].future, entries[3].future = true, true
  C.invalidateSpellbook()
  H.ok(not C.knowsSpell(light), style .. ": future spell names do not count as learned")
  H.eq(C.bestRankId(light), nil, style .. ": never put a future spell on the bar")
  entries[1].future, entries[2].future = false, false
  entries[1], entries[2] = entries[2], entries[1] -- rank ordering need not match the data/book order
  C.invalidateSpellbook()
  H.eq(C.bestRankId(light), 639, style .. ": choose the highest learned book rank even in reverse order")
end

os.exit(H.report("spell_identity") and 0 or 1)
