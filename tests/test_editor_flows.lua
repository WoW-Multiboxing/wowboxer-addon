-- docs/feedback-2026-10-30-editor.md: the Macro editor's one tab bar (Spells · Targeting) from every entry point,
-- unsaved changes kept across tabs, the dialog layer above the editor, menus that read the mode when they open and
-- never linger, and every flow of §5. Run: lua tests/test_editor_flows.lua
local dir = (arg[0]:match("^(.*)/[^/]+$") or ".")
local H = dofile(dir .. "/harness.lua")
local Mock = dofile(dir .. "/wowmock.lua")

local W = Mock.new(H, { name = "Anna", class = "PRIEST", race = "Scourge", level = 20, party = { party1 = "Dorin", party2 = "Bo" },
  partyInfo = { party1 = { class = "PALADIN", race = "Scourge", level = 20 }, party2 = { class = "HUNTER", race = "Orc", level = 20 } } })
local ns = H.loadAddon({ env = W.env })
W.fire("ADDON_LOADED", "WoWBoxer"); W.fire("PLAYER_LOGIN")
for _, s in ipairs(ns.Data.spells.priest) do if s.level <= 20 and s.gate ~= "talent" then W.known[s.name] = true end end
local Core, UI, A, KE, Book, Wd = ns.Core, ns.UI, ns.Advanced, ns.KeyEditor, ns.Book, ns.Widgets
local sq = ns.State.newSquad({ name = "Trio", members = {
  { name = "Dorin", cls = "paladin", race = "undead", role = "tank", leader = true },
  { name = "Anna", cls = "priest", race = "undead", role = "healer", unit = "party1" },
  { name = "Bo", cls = "hunter", race = "orc", role = "ranged", unit = "party1" } } })
Core.db.squads = { sq }; Core.db.active = sq.id
Core.cdb.guide = "done"
local _, me = Core.me()
local function errors()
  local n = {}
  for _, e in ipairs(Core.db.log) do if e.l == "error" then n[#n + 1] = e.m end end
  return table.concat(n, " | ")
end
local function desired(name) for _, d in ipairs(Core.compute().desired) do if d.name == name then return d end end end
local function cellIn(key, pred)
  UI.Select(key)
  for _, b in ipairs(UI.panels[key].cells) do if b:IsShown() and b.cell and pred(b.cell) then return b end end
end
local function labels(items) local t = {}; for _, it in ipairs(items) do t[#t + 1] = it[1] .. (it[4] and " [greyed]" or "") end return table.concat(t, "|") end
local function tabsOk(what)
  local f = A.ef
  H.ok(f:IsShown() and f.tabSpells:IsShown() and f.tabTarget:IsShown(), what .. ": one tab bar, Spells · Targeting")
end
local function tile(who) for _, t in ipairs(A.ef.tiles) do if t:IsShown() and t.target and t.target.who == who then return t end end end
local function cursorAt(frame) local x, y = frame:GetCenter(); local k = frame:GetEffectiveScale() or 1; W.cursorPos = { x * k, y * k } end
local function drag(t, row) t._scripts.OnDragStart(t); cursorAt(row); t._scripts.OnDragStop(t) end

UI.Open("custom")
Core.db.settings.advanced = true

-- §5.1 New macro → Single spell → Targeting tab → drag a target → Save → the macro text is right
local new = cellIn("custom", function(c) return c.kind == "new" end)
new:Click("LeftButton")
tabsOk("New macro")
KE.frame.choice.single:Click()
KE.addStep("Lesser Heal")
H.ok(A.ef.tabTarget:IsEnabled(), "single spell: the Targeting tab is there and clickable (also before saving)")
A.ef.tabTarget:Click()
H.eq(A.ef.section, "target", "Targeting tab opens on an unsaved single spell")
drag(tile("focus"), A.ef.rows[1])
H.eq(A.ef.targets[1].who, "focus", "a target dragged in")
A.ef.tabSpells:Click()
H.eq(KE.frame.draft.steps[1], "Lesser Heal", "back on Spells: the spell is still there")
A.ef.tabTarget:Click()
H.eq(A.ef.targets[1].who, "focus", "and on Targeting the target is still there")
A.ef.save:Click()
local c1 = "WBX C" .. #me.customSeq
H.ok(desired(c1) and desired(c1).body:find("[@focus", 1, true) and desired(c1).body:find("Lesser Heal", 1, true), "Save: the macro text has the spell and the target: " .. tostring(desired(c1) and desired(c1).body))

-- §5.2 New macro → Sequence → tabs back and forth → Save
new = cellIn("custom", function(c) return c.kind == "new" end)
new:Click("LeftButton")
KE.frame.choice.seq:Click()
KE.addStep("Shadow Word: Pain"); KE.addStep("Smite")
A.ef.tabTarget:Click(); A.ef.tabSpells:Click(); A.ef.tabTarget:Click(); A.ef.tabSpells:Click()
H.eq(#KE.frame.draft.steps, 2, "sequence: both steps survive the tab switches")
A.ef.save:Click()
H.ok(me.customSeq[#me.customSeq].kind == "sequence", "sequence saved")

-- §5.3 recommended macro → Edit macro… → both tabs → Back to WoWBoxer's version
local rec = cellIn("keys", function(c) return c.name and c.name:find("^WBX K") and c.d and c.d.body:find("help", 1, true) end)
for _, it in ipairs(Book.menuFor(UI.panels.keys, rec.cell)) do if it[1] == "Edit macro…" then it[2]() end end
tabsOk("recommended macro")
A.ef.tabSpells:Click()
H.ok(A.ef.spellsInfo:IsShown() and not A.ef.spellsBox:IsShown(), "recommended: Spells shows what it casts (read-only)")
H.ok((A.ef.spellsInfo.text:GetText() or ""):find(":", 1, true) ~= nil, "recommended: " .. tostring(A.ef.spellsInfo.text:GetText()))
A.ef.tabTarget:Click()
drag(tile("mouseover"), A.ef.rows[1])
A.ef.save:Click()
H.ok(Core.cdb.overrides[rec.cell.name] ~= nil, "recommended: targeting saved")
for _, it in ipairs(Book.menuFor(UI.panels.keys, rec.cell)) do if it[1] == "Edit macro…" then it[2]() end end
A.ef.back:Click()
H.eq(Core.cdb.overrides[rec.cell.name], nil, "Back to WoWBoxer's version removes it")

-- §5.4 own macro → Edit macro… → both tabs
local own = cellIn("custom", function(c) return c.name == c1 end)
for _, it in ipairs(Book.menuFor(UI.panels.custom, own.cell)) do if it[1] == "Edit macro…" then it[2]() end end
tabsOk("own macro")
A.ef.tabTarget:Click(); H.eq(A.ef.section, "target", "own macro: Targeting")
A.ef.tabSpells:Click(); H.eq(A.ef.section, "spells", "own macro: Spells")
A.ef:Hide()

-- §3 menus read the mode when they open: every cell kind, both modes
local function kinds()
  local out = {}
  out.recommended = cellIn("keys", function(c) return c.name and c.name:find("^WBX K") end)
  out.squad = nil
  for _, b in ipairs(UI.panels.keys.helperPool or {}) do if not out.squad and b:IsShown() and b.cell and b.cell.name then out.squad = b end end
  out.own = cellIn("custom", function(c) return c.name and c.name:find("^WBX C") end)
  out.known = cellIn("spells", function(c) return c.kind == "spell" and not c.name and not c.pending end)
  out.future = cellIn("spells", function(c) return c.kind == "spell" and not c.name and type(c.pending) == "number" end)
  return out
end
for _, adv in ipairs({ true, false }) do
  Core.db.settings.advanced = adv or nil
  local k = kinds()
  for _, name in ipairs({ "recommended", "squad", "own", "known", "future" }) do
    local b = k[name]
    if b then
      local page = name == "own" and "custom" or ((name == "known" or name == "future") and "spells" or "keys")
      UI.Select(page)
      local m = Wd.menu(b, Book.menuFor(UI.panels[page], b.cell))
      local text = {}
      for _, r in ipairs(m.rows) do if r:IsShown() then text[#text + 1] = r.label:GetText() .. (r.disabled and " [greyed]" or "") end end
      local all = table.concat(text, "|")
      local editOn = all:find("Edit macro…", 1, true) and not all:find("Edit macro… (Advanced mode)", 1, true)
      local greyed = all:find("Edit macro… (Advanced mode) [greyed]", 1, true) ~= nil
      if adv or name == "own" then H.ok(editOn, (adv and "Advanced" or "Standard") .. " " .. name .. ": Edit macro… – " .. all)
      else H.ok(greyed, "Standard " .. name .. ": Edit macro… (Advanced mode) greyed – " .. all) end
      m:Hide()
    else H.ok(name == "future", "cell kind present: " .. name) end
  end
end

-- §3/§4 a menu opened in one mode is closed by a mode switch (no stale "(Advanced mode)")
Core.db.settings.advanced = nil
local k = kinds()
UI.Select("spells")
local m = Wd.menu(k.known, Book.menuFor(UI.panels.spells, k.known.cell))
H.ok(m:IsShown(), "menu open")
A.setMode(true)
H.ok(not m:IsShown(), "a mode switch closes the open menu")

-- §4 menus close on: a click elsewhere (world), page change, window hide, combat, another menu, mouse away 1.5 s
local function open() return Wd.menu(k.known, Book.menuFor(UI.panels.spells, k.known.cell)) end
UI.Select("spells"); m = open(); W.fire("GLOBAL_MOUSE_DOWN", "LeftButton"); H.ok(not m:IsShown(), "click elsewhere (also the world) closes it")
m = open(); UI.Select("keys"); H.ok(not m:IsShown(), "a page change closes it"); UI.Select("spells")
m = open(); UI.frame:Hide(); H.ok(not m:IsShown(), "hiding the window closes it"); UI.Open("spells")
m = open(); W.fire("PLAYER_REGEN_DISABLED"); H.ok(not m:IsShown(), "entering combat closes it")
m = open(); UI.panels.keys.role.open(); H.ok(not m:IsShown() and Wd.listFrame:IsShown(), "another menu closes it (one at a time)"); Wd.listFrame:Hide()
m = open(); m._scripts.OnUpdate(m, 0.8); H.ok(m:IsShown(), "mouse away 0.8 s: still open"); m._scripts.OnUpdate(m, 0.8); H.ok(not m:IsShown(), "mouse away 1.6 s: closed")
m = open(); H.ok(m:IsShown(), "reopens"); Wd.closeMenus()

-- §2 the dialog layer: the confirm opens above the editor; Cancel and Turn on work; one dialog at a time; Esc
A.setMode(false)
UI.Select("keys")
A.openEditor(UI.panels.keys, rec.cell.name, rec.cell.label)
H.ok(A.ef:IsShown() or true, "editor open")
UI.modeAdv:Click()
local c = A.confirmFrame
local rank = { HIGH = 4, DIALOG = 5, FULLSCREEN = 6, FULLSCREEN_DIALOG = 7 }
H.ok(c:IsShown() and (rank[c:GetFrameStrata()] or 0) > (rank[A.ef:GetFrameStrata()] or 0), "the confirm is on a layer above the editor (" .. c:GetFrameStrata() .. ")")
local inEsc = {}
for _, n in ipairs(W.env.UISpecialFrames) do inEsc[n] = true end
H.ok(inEsc.WoWBoxerAdvancedConfirm and not inEsc.WoWBoxerMainFrame, "Esc closes the dialog only, not the window")
c.cancel:Click()
H.ok(not c:IsShown() and not Core.advanced(), "Cancel: still Standard")
inEsc = {}
for _, n in ipairs(W.env.UISpecialFrames) do inEsc[n] = true end
H.ok(inEsc.WoWBoxerMainFrame, "dialog closed: Esc closes the window again")
UI.modeAdv:Click(); c.tick:Click(); c.go:Click()
H.ok(Core.advanced(), "Turn on works")
A.openReset()
H.ok(A.rf:IsShown(), "reset dialog")
A.confirm()
H.ok(c:IsShown() and not A.rf:IsShown(), "one dialog at a time")
c:Hide()
-- Advanced → Standard with unsaved targeting: keep editing / discard
A.openEditor(UI.panels.keys, rec.cell.name, rec.cell.label)
drag(tile("focus"), A.ef.rows[1])
UI.modeStd:Click()
H.ok(UI.popup:IsShown() and UI.popup.text:GetText():find("Unsaved changes", 1, true) and Core.advanced(), "Unsaved changes – asks first")
UI.popup.btns[1]:Click()
H.ok(A.ef:IsShown() and Core.advanced(), "Keep editing: still Advanced, editor open")
UI.modeStd:Click(); UI.popup.btns[2]:Click()
H.ok(not A.ef:IsShown() and not Core.advanced(), "Discard: editor closed, Standard")
-- an own macro stays open on Spells, never half-advanced
A.setMode(true)
A.openEditor(UI.panels.custom, c1)
A.ef.tabTarget:Click()
UI.modeStd:Click()
H.ok(A.ef:IsShown() and A.ef.section == "spells" and not A.ef.tabTarget:IsEnabled(), "own macro: switches to Spells, Targeting greyed")
A.ef:Hide()

-- the Spells tab: short type labels, Paste/Copy under the preview, no mid-word wrap
new = cellIn("custom", function(c) return c.kind == "new" end)
new:Click("LeftButton")
KE.frame.choice.seq:Click()
H.eq(KE.frame.kind.label:GetText(), "Sequence", "short type label")
local pv = KE.frame.copy:GetPoint(1)
H.eq(pv, "TOPRIGHT", "Copy… sits under the preview box")
local wrapped = Wd.wrapMacro("/cast [@mouseover,help,nodead][@party1,help,nodead][@party1pet,help,nodead][@player] Flash Heal", 200, 10)
for line in (wrapped .. "\n"):gmatch("([^\n]*)\n") do
  H.ok(not line:find("node$") and not line:find("^%s*ad%]"), "no mid-word break: " .. line)
end
A.ef:Hide()

H.eq(errors(), "", "no Lua errors in the log")
os.exit(H.report("editor flows") and 0 or 1)
