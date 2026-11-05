-- Spell descriptions in the book (owner, 5 Nov 2026): the selected macro shows what it does (our sentence), how it
-- looks (the macro text) and, under it, what the spell does in the game's own tooltip words. The cell tooltip
-- carries the same words. Read from the client only (GetSpellDescription); not loaded yet = nothing shown + one
-- load request that refreshes the window. Modern (C_Spell) and Classic (global) clients.
local dir = (arg[0]:match("^(.*)/[^/]+$") or ".")
local H = dofile(dir .. "/harness.lua")
local Mock = dofile(dir .. "/wowmock.lua")

local function boot(opts)
  local W = Mock.new(H, opts)
  local ns = H.loadAddon({ env = W.env })
  W.fire("ADDON_LOADED", "WoWBoxer"); W.fire("PLAYER_LOGIN")
  for _, s in ipairs(ns.Data.spells[opts.class:lower()]) do if s.level <= opts.level then W.known[s.name] = true end end
  ns.Core.cdb.guide = "done"
  return W, ns
end
local function rankId(ns, sp, level)
  local r = ns.Kit.rankAt(sp, level)
  return r and r.id or (sp.ranks and sp.ranks[1] and sp.ranks[1].id) or sp.id
end

for _, sc in ipairs({
  { name = "Dorin", class = "PALADIN", race = "Human", level = 20 },
  { name = "Hunty", class = "HUNTER", race = "Orc", level = 30, toc = 11509, spellbookStyle = "classic" },
}) do
  local tag = sc.class .. ": "
  local W, ns = boot(sc)
  local UI, Book, C = ns.UI, ns.Book, ns.Compat
  W.spellDesc = {}
  -- the first spell macro on My keys
  UI.Toggle(); UI.Select("keys")
  local p = UI.panels.keys
  local cell
  for _, b in ipairs(p.cells) do if b:IsShown() and b.cell and b.cell.d and b.cell.d.spell and b.cell.group ~= "helper" then cell = b; break end end
  H.ok(cell ~= nil, tag .. "a spell macro is on the page")
  local sp = cell.cell.d.spell
  local id = rankId(ns, sp, sc.level)
  H.ok(id ~= nil, tag .. "the spell has an ID for its rank")

  -- 1. not loaded yet: nothing shown, no error
  cell:Click("LeftButton")
  H.ok(not p.detSpell:IsShown(), tag .. "no description while the client has none")

  -- 2. the game knows it: shown under the macro text, in the selected panel
  local DESC = "Hurls a holy bolt at the enemy for 30 to 35 Holy damage.\r\nLasts 10 sec."
  W.spellDesc[id] = DESC
  UI.Refresh()
  H.ok(p.detSpell:IsShown(), tag .. "description shown")
  H.eq(p.detSpell:GetText(), "Hurls a holy bolt at the enemy for 30 to 35 Holy damage.\nLasts 10 sec.", tag .. "the game's words, Windows line ends cleaned")
  H.ok(p.detMacro:GetText():find("#showtooltip", 1, true) or p.detMacro:GetText():find("/cast", 1, true), tag .. "the macro text is still there")
  local mr, dr = W.rect(p.detMacro), W.rect(p.detSpell)
  H.ok(mr and dr and dr[2] >= mr[4] - 0.5 or (dr and mr and dr[4] <= mr[2] + 0.5), tag .. "description sits under the macro text")
  H.ok(p.detDesc:GetText() ~= "" and p.detDesc:GetText() ~= p.detSpell:GetText(), tag .. "our one sentence stays on top")

  -- 3. the cell tooltip carries the same words
  local GT, lines = W.env.GameTooltip, {}
  local old = GT.AddLine
  GT.AddLine = function(_, t) lines[#lines + 1] = t end
  cell._scripts.OnEnter(cell)
  GT.AddLine = old
  local all = table.concat(lines, "|")
  H.ok(all:find("Hurls a holy bolt", 1, true) ~= nil, tag .. "tooltip has the spell's words: " .. all:sub(1, 120))

  -- 4. a helper (no spell) shows none
  local helper
  for _, b in ipairs(p.cells) do if b:IsShown() and b.cell and b.cell.group == "helper" then helper = b; break end end
  if helper then
    helper:Click("LeftButton")
    H.ok(not p.detSpell:IsShown(), tag .. "helpers show no spell description")
  end

  -- 5. Compat: rank for the level first, then other ranks; nil and no error without the API
  H.eq(C.spellDescription(sp, sc.level), "Hurls a holy bolt at the enemy for 30 to 35 Holy damage.\nLasts 10 sec.", tag .. "Compat reads the rank's description")
  H.eq(C.spellDescription(nil), nil, tag .. "nil spell")
  local f1, f2 = W.env.GetSpellDescription, W.env.C_Spell and W.env.C_Spell.GetSpellDescription
  W.env.GetSpellDescription = nil
  if W.env.C_Spell then W.env.C_Spell.GetSpellDescription = nil end
  H.eq(C.spellDescription(sp, sc.level), nil, tag .. "no API: nil, no error")
  W.env.GetSpellDescription = f1
  if W.env.C_Spell then W.env.C_Spell.GetSpellDescription = f2 end

  -- 6. "All spells" tooltip (a spell without a macro yet)
  UI.Select("spells")
  local sp2cell
  for _, b in ipairs(UI.panels.spells.cells or {}) do if b:IsShown() and b.cell and b.cell.spell then sp2cell = b; break end end
  if sp2cell then
    local s2 = sp2cell.cell.spell
    W.spellDesc[rankId(ns, s2, sc.level)] = "A test description for All spells."
    lines = {}
    GT.AddLine = function(_, t) lines[#lines + 1] = t end
    sp2cell._scripts.OnEnter(sp2cell)
    GT.AddLine = old
    H.ok(table.concat(lines, "|"):find("A test description for All spells.", 1, true) ~= nil, tag .. "All spells tooltip has the description")
  end

  local errs = {}
  for _, e in ipairs(ns.Core.db.log) do if e.l == "error" then errs[#errs + 1] = e.m end end
  H.eq(#errs, 0, tag .. "no errors: " .. table.concat(errs, " / "))
end

-- 7. not loaded: the client is asked once (Spell mixin) and the window refreshes when it arrives
do
  local W, ns = boot({ name = "Dorin", class = "PALADIN", race = "Human", level = 20 })
  W.spellDesc = {}
  local asked, cb = 0, nil
  W.env.Spell = { CreateFromSpellID = function(_, id)
    return { IsSpellEmpty = function() return false end, ContinueOnSpellLoad = function(_, f) asked = asked + 1; cb = f end }
  end }
  local sp
  for _, s in ipairs(ns.Data.spells.paladin) do if s.ranks and s.ranks[1] and s.ranks[1].id then sp = s; break end end
  H.eq(ns.Compat.spellDescription(sp, 20), nil, "not loaded: nil")
  ns.Compat.spellDescription(sp, 20)
  H.eq(asked, 1, "the client is asked once per spell")
  local refreshed = 0
  local oldR = ns.UI.Refresh
  ns.UI.Refresh = function() refreshed = refreshed + 1 end
  cb()
  ns.UI.Refresh = oldR
  H.eq(refreshed, 1, "the window refreshes when the description arrives")
end

H.report("spelldesc")
