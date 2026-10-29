-- Sequence keys: a real icon instead of "?", composite icons in the book, the step strip on the action bars
-- (docs/squad-overhaul.md §1). The strip is purely visual: it must never call a protected function.
local dir = (arg[0]:match("^(.*)/[^/]+$") or ".")
local H = dofile(dir .. "/harness.lua")
local Mock = dofile(dir .. "/wowmock.lua")

local function boot(opts)
  local W = Mock.new(H, opts)
  local ns = H.loadAddon({ env = W.env })
  W.fire("ADDON_LOADED", "WoWBoxer"); W.fire("PLAYER_LOGIN")
  ns.Core.cdb.guide = "done"
  for _, s in ipairs(ns.Data.spells[(opts.class or "PALADIN"):lower()]) do if s.level <= (opts.level or 10) and s.gate ~= "talent" then W.known[s.name] = true end end
  return W, ns
end
local function errors(ns)
  local n = {}
  for _, e in ipairs(ns.Core.db.log) do if e.l == "error" then n[#n + 1] = e.m end end
  return table.concat(n, " | ")
end
local function byKey(ctx, key) for _, d in ipairs(ctx.desired) do if d.key == key then return d end end end
local function macro(W, name) for _, m in ipairs(W.char) do if m.name == name then return m end end end
--- Blizzard's action buttons for bar 1 (slots 1–12), each knowing its slot like the real ones.
local function actionButtons(W)
  for i = 1, 12 do
    local b = W.newFrame("Button", "ActionButton" .. i, W.env.UIParent)
    b:SetSize(36, 36); b:SetPoint("BOTTOMLEFT", W.env.UIParent, "BOTTOMLEFT", 300 + i * 40, 20)
    b.action = i
  end
end

-- ------------------------------------------------------------------ the "?" fix: real icons for sequence keys
do
  local W, ns = boot({ name = "Lockie", class = "WARLOCK", race = "Scourge", level = 24 })
  local Core = ns.Core
  ns.UI.Open("keys")
  local _, m = Core.me()
  m.seq = "medium"
  local ctx = Core.computeFresh()
  local s1 = byKey(ctx, "S1")
  H.ok(s1 ~= nil, "Warlock has a damage sequence at 24")
  H.ok(s1.icon ~= ns.Macros.ICON, "sequence key gets a real icon, not the ? (134400)")
  H.ok(s1.main ~= nil and s1.seq.filler == s1.main.name, "the main spell of a castsequence is its filler")
  H.eq(s1.icon, 200000 + s1.main.ranks[1].id, "icon file ID from the client for the main spell")
  H.ok(#s1.steps > 2, "the steps in cast order")
  H.eq(s1.steps[#s1.steps], s1.main, "the filler comes last")
  local k1 = byKey(ctx, "K1")
  H.eq(k1.icon, ns.Macros.ICON, "single-spell keys keep #showtooltip with the ? icon")
  -- an old WBX S1 with the ? icon and the same text: Update macros changes only the icon
  W.addMacro("WBX S1", s1.body, true)
  local it
  for _, x in ipairs(Core.computeFresh().macros.items) do if x.name == "WBX S1" then it = x end end
  H.eq(it.status, "update", "an old ? icon counts as a change")
  Core.sync({})
  H.eq(macro(W, "WBX S1").icon, s1.icon, "after Update macros the macro has the real icon")
  for _, x in ipairs(Core.computeFresh().macros.items) do if x.name == "WBX S1" then it = x end end
  H.eq(it.status, "same", "and then nothing more to change")
  H.ok(not ns.Macros.iconChanged("Interface\\Icons\\INV_Misc_QuestionMark", nil), "no wanted icon = no change")
  H.ok(ns.Macros.iconChanged("Interface\\Icons\\INV_Misc_QuestionMark", 123), "a ? as a texture path counts as a change")
  H.ok(not ns.Macros.iconChanged("Interface\\Icons\\Spell_Shadow_ShadowBolt", 123), "an unknown path is left alone (no endless updates)")
  -- the book: composite icon, badge, steps in the tooltip
  ns.UI.Select("keys")
  local cell
  for _, b in ipairs(ns.UI.panels.keys.cells) do if b:IsShown() and b.cell and b.cell.name == "WBX S1" then cell = b end end
  H.ok(cell ~= nil, "the sequence key is in the book")
  local parts = 0
  for _, t in ipairs(cell.multi.parts) do if t:IsShown() then parts = parts + 1 end end
  H.ok(parts >= 2 and parts <= 4, "composite icon of 2–4 spells (" .. parts .. ")")
  H.eq(cell.badge:GetText(), "SEQ", "SEQ badge on the button")
  local lines = {}
  local GT = W.env.GameTooltip
  GT.AddLine = function(_, t) lines[#lines + 1] = t end
  cell._scripts.OnEnter(cell)
  local steps
  for _, l in ipairs(lines) do if l:find("→") then steps = l end end
  H.ok(steps ~= nil and steps:find(s1.main.name .. " ×", 1, true) ~= nil, "tooltip shows the steps with icons and the filler count")
  H.ok(table.concat(lines, "\n"):find("next spell", 1, true) ~= nil, "tooltip says each press casts the next spell")
  -- a plain key has no composite and no badge
  local plain
  for _, b in ipairs(ns.UI.panels.keys.cells) do if b:IsShown() and b.cell and b.cell.name == "WBX K1" then plain = b end end
  H.ok(not plain.multi.parts[1]:IsShown() and not plain.badge:IsShown(), "single-spell key: one icon, no badge")
  H.eq(errors(ns), "", "no errors (warlock)")
end

-- priority keys (Paladin): the first line's spell
do
  local _, ns = boot({ name = "Dorin", class = "PALADIN", race = "Human", level = 30 })
  ns.UI.Open("keys")
  local _, m = ns.Core.me()
  m.seq = "medium"
  local found = false
  for _, d in ipairs(ns.Core.computeFresh().desired) do
    if d.seq and d.seq.base == "priority" and #d.steps > 1 then
      found = true
      H.eq(d.main, d.steps[1], "priority key: main spell = first line")
      H.ok(d.icon ~= ns.Macros.ICON, "priority key gets a real icon")
      H.eq(ns.Book.badge(d), "PRI", "PRI badge")
    end
  end
  H.ok(found, "Paladin has a priority key")
end

-- ------------------------------------------------------------------ the strip on the action bars
do
  local W, ns = boot({ name = "Lockie", class = "WARLOCK", race = "Scourge", level = 24 })
  local Core, SS = ns.Core, ns.SeqStrip
  actionButtons(W)
  Core.ensureMe()
  local _, m = Core.me()
  m.seq = "medium"
  Core.cdb.primaryBar = 1
  Core.sync({ replace = true })
  W.flush()
  local slot = Core.cdb.slots["WBX S1"]
  H.ok(slot ~= nil and slot <= 12, "the sequence key is on bar 1")
  local btn = W.env["ActionButton" .. slot]
  local o = SS.strips[btn]
  H.ok(o ~= nil and o:IsShown(), "a strip on the button that holds the sequence key")
  H.eq(SS.shown, 1, "only sequence keys get a strip")
  H.eq(o.badge:GetText(), "SEQ", "SEQ badge on the action button")
  local icons = 0
  for _, t in ipairs(o.icons) do if t:IsShown() then icons = icons + 1 end end
  H.eq(icons, math.min(4, #o.d.steps), "mini icons of the steps")
  H.eq(o.next, 1, "QueryCastSequence: step 1 is next")
  H.ok(o.mark[1]:IsShown(), "the next step is framed")
  -- after a cast the sequence moves on (event-driven, coalesced)
  local text = SS.sequenceText(o.d.body)
  H.ok(text and text:find("^reset=") ~= nil, "the castsequence list without conditions")
  W.castSeq[text] = 3
  local calls0 = {}
  for k, v in pairs(W.calls) do calls0[k] = v end
  W.fire("UNIT_SPELLCAST_SUCCEEDED", "party1"); W.flush()
  H.eq(o.next, 1, "casts of other units are ignored")
  local u0 = SS.updates or 0
  W.fire("UNIT_SPELLCAST_SUCCEEDED", "player"); W.fire("UNIT_SPELLCAST_SUCCEEDED", "player"); W.fire("PLAYER_TARGET_CHANGED")
  W.flush()
  H.eq((SS.updates or 0) - u0, 1, "a burst of events = one update")
  H.eq(o.next, 3, "after casts: step 3 is next")
  -- combat: only the frame moves; nothing protected is called
  W.combat = true
  W.fire("PLAYER_REGEN_DISABLED"); W.castSeq[text] = 4
  W.fire("UNIT_SPELLCAST_SUCCEEDED", "player"); W.flush()
  H.eq(o.next, 4, "in combat the next step still updates")
  local same = true
  for k, v in pairs(W.calls) do if calls0[k] ~= v then same = false end end
  H.ok(same, "the strip never calls a protected function")
  btn.action = 99 -- the button now shows another page
  W.fire("ACTIONBAR_PAGE_CHANGED"); W.flush()
  H.ok(not o:IsShown(), "in combat a strip whose button changed page hides")
  btn.action = slot
  W.combat = false
  W.fire("PLAYER_REGEN_ENABLED"); W.flush()
  H.ok(o:IsShown(), "after combat it comes back")
  -- setting off
  ns.UI.Open("setup")
  ns.UI.panels.setup.strip:Click()
  W.flush()
  H.ok(not o:IsShown(), "Setup: strip off hides it")
  H.eq(Core.db.settings.seqStrip, false, "setting saved")
  ns.UI.panels.setup.strip:Click(); W.flush()
  H.ok(o:IsShown(), "and on again")
  -- no visible Blizzard button (bar addon): no strip
  for i = 1, 12 do W.env["ActionButton" .. i]:Hide() end
  W.fire("ACTIONBAR_SLOT_CHANGED", slot); W.flush()
  H.ok(not o:IsShown(), "hidden bar: no strip")
  local d = Core.selftest(true)
  H.ok(d.strip and d.strip.query == true, "diagnose records the strip probes")
  H.eq(errors(ns), "", "no errors (strip)")
end

os.exit(H.report("seqicons") and 0 or 1)
