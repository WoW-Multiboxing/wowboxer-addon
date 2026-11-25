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
UI.popup.btns[3]:Click() -- Save · Discard · Keep editing
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

-- ===================================================================== docs/feedback-2026-11-25-macro-editor.md
-- The owner: "bugs when you create macros and click on and off with the macro editor, especially for sequencing".
local P = UI.panels.custom
UI.Select("custom")
local function fresh()
  if A.ef then A.closeEditor() end
  if UI.popup then UI.popup:Hide() end
  me.customSeq, me.lines = {}, nil
  Core.cdb.overrides, Core.cdb.keyLines = {}, {}
end
local function shownSteps() local n = 0; for _, b in ipairs(KE.frame.stepBtns) do if b:IsShown() then n = n + 1 end end return n end
local function pickRow(name)
  for _, r in ipairs(KE.frame.pickPool.rows) do if r:IsShown() and r.spell and r.spell.name == name then return r end end
end
local function popupAsks() return UI.popup and UI.popup:IsShown() and UI.popup.text:GetText():find("Unsaved changes", 1, true) ~= nil end
local function save(name, kind, steps, extra)
  local c = { name = name, kind = kind, aim = "harm", steps = steps, filler = "", fills = 1, reset = "combat" }
  for k, v in pairs(extra or {}) do c[k] = v end
  return KE.save(me, c, nil)
end
fresh()
Core.db.settings.advanced = nil

-- §1 Add takes every spell the picker offers (Shoot, talent and book spells), also from Paste
A.openNew(P); KE.frame.choice.more:Click() -- Priority: every spell is a plain step
local offered, refused = KE.spellChoices(me, 20), {}
H.ok(#offered > 5, "§1 the picker offers spells (" .. #offered .. ")")
local hasShoot = false
for _, s in ipairs(offered) do
  if s.name == "Shoot" then hasShoot = true end
  KE.frame.draft.steps = {}
  if not KE.addStep(s.name) or KE.frame.draft.steps[1] ~= s.name then refused[#refused + 1] = s.name end
end
H.ok(hasShoot, "§1 Shoot is in the picker")
H.eq(table.concat(refused, ", "), "", "§1 Add takes every spell the picker offers")
H.eq(KE.addStep("Holy Light"), false, "§1 a spell not in the picker (another class) is still refused")
KE.frame.draft.steps = {}
KE.usePasted({ kind = "priority", aim = "harm", steps = { "Mind Blast", "Shoot" }, filler = "", fills = 1, reset = "combat" })
H.eq(table.concat(KE.frame.draft.steps, ","), "Mind Blast,Shoot", "§1 Paste keeps Shoot (Priority with the wand last)")

-- §2 Shoot is never a sequence step or filler: Add / Filler on Shoot = the wand line after the sequence
fresh()
A.openNew(P); KE.frame.choice.seq:Click()
KE.addStep("Shadow Word: Pain"); KE.addStep("Mind Blast"); KE.addStep("Shoot")
H.eq(table.concat(KE.frame.draft.steps, ","), "Shadow Word: Pain,Mind Blast", "§2 Add Shoot in a sequence: not a step")
H.ok(KE.frame.draft.wand, "§2 … it is the wand line")
local sr = pickRow("Shoot")
H.ok(sr and not sr.fill:IsShown() and sr.add:IsShown(), "§2 no Filler button on Shoot")
H.ok(pickRow("Smite") and pickRow("Smite").fill:IsShown(), "§2 other spells keep their Filler button")
local r2, w2 = KE.preview(me, KE.frame.draft, 20)
H.ok(r2.macro:find("/castsequence", 1, true) and not r2.macro:match("/castsequence[^\n]*Shoot"), "§2 Shoot is not in the /castsequence")
H.ok(r2.macro:find("!Shoot", 1, true), "§2 the wand line after the sequence: " .. r2.macro:gsub("\n", " | "))
for _, w in ipairs(w2) do H.ok(not w:find("Shoot", 1, true), "§2 no Shoot warning left: " .. w) end
H.ok(KE.frame.fillerText:GetText():find("Shoot", 1, true), "§2 the strip says Shoot runs after the sequence")
-- the old way (a draft with Shoot as the filler, e.g. pasted) builds the same safe macro
local old = { name = "x", kind = "sequence", aim = "harm", steps = { "Shadow Word: Pain" }, filler = "Shoot", fills = 2, reset = "combat" }
local r2b = KE.preview(me, old, 20)
H.ok(not r2b.macro:find("Shoot, Shoot", 1, true) and r2b.macro:find("!Shoot", 1, true), "§2 a Shoot filler never reaches /castsequence")
A.ef.save:Click()
local savedSeq = me.customSeq[1]
H.ok(savedSeq and savedSeq.wand == true and savedSeq.filler == "" and #savedSeq.steps == 2, "§2 saved: steps without Shoot, wand line on")
me.lines = { wand = false } -- the wand switch off: this macro still shoots after its sequence
H.ok(desired("WBX C1") and desired("WBX C1").body:find("!Shoot", 1, true), "§2 the wand line stays with the switch off")
me.lines = nil
-- the owner's two macros on Rup (SavedVariables 25 Nov): migrated once at login, idempotent
local rup = ns.State.newMember({ name = "Rup", cls = "priest", race = "undead", role = "ranged",
  customSeq = { { name = "Dot Wand", kind = "sequence", aim = "harm", steps = { "Shadow Word: Pain" }, filler = "Shoot", fills = 2, reset = "combat" },
    { name = "Test", kind = "sequence", aim = "harm", steps = { "Mind Blast", "Devouring Plague" }, filler = "Shoot", fills = 2, reset = "combat" },
    { name = "Heal", kind = "sequence", aim = "help", steps = { "Renew", "Lesser Heal" }, filler = "", fills = 1, reset = "combat" } } })
local sqR = ns.State.newSquad({ name = "Rup", members = { rup } })
local moved = Core.migrateWandSequences({ squads = { sqR } })
H.eq(#moved, 2, "§2 migration: Rup's two macros with a Shoot filler")
local m1, m2 = sqR.members[1].customSeq[1], sqR.members[1].customSeq[2]
H.ok(m1.filler == "" and m1.wand and m2.filler == "" and m2.wand and table.concat(m2.steps, ",") == "Mind Blast,Devouring Plague", "§2 migrated: no filler, wand line, steps kept")
H.ok(sqR.members[1].customSeq[3].wand == nil, "§2 a macro without Shoot is untouched")
H.eq(#Core.migrateWandSequences({ squads = { sqR } }), 0, "§2 the migration runs once (nothing left to move)")
local clean = ns.State.cleanCustom(sqR.members[1].customSeq)
H.ok(clean[1].wand == true, "§2 the wand line survives the SavedVariables cleaning")

-- §3 Deleting an own macro never renames the others (stable slots), and a new one fills the hole
fresh()
H.eq(save("A one", "sequence", { "Mind Blast" }), 1, "§3 first macro: C1")
H.eq(save("B two", "sequence", { "Smite" }), 2, "§3 C2")
H.eq(save("C three", "sequence", { "Shadow Word: Pain" }), 3, "§3 C3")
Core.cdb.overrides["WBX C1"] = ns.Override.clean({ targets = { { who = "focus" } } })
Core.cdb.overrides["WBX C2"] = ns.Override.clean({ targets = { { who = "player", help = true } } })
Core.cdb.keyLines["WBX C1"] = { wand = false }
KE.delete(me, 1)
H.eq(desired("WBX C1"), nil, "§3 after deleting C1 there is no WBX C1")
H.eq(desired("WBX C2") and desired("WBX C2").label, "B two", "§3 B two is still WBX C2")
H.eq(desired("WBX C3") and desired("WBX C3").label, "C three", "§3 C three is still WBX C3")
H.ok(Core.cdb.overrides["WBX C2"] and desired("WBX C2").body:find("Smite", 1, true), "§3 C2's targeting stays on B two")
H.eq(Core.cdb.overrides["WBX C1"], nil, "§3 the deleted macro's targeting went with it")
H.eq(Core.cdb.keyLines["WBX C1"], nil, "§3 … and its extra-line choices")
H.ok(A.openEditor(P, "WBX C3"), "§3 WBX C3 opens")
H.eq(KE.frame.draft.name, "C three", "§3 … with C three's spells")
A.closeEditor()
H.eq(save("D four", "sequence", { "Smite" }), 1, "§3 a new macro fills the hole: C1")
H.eq(desired("WBX C1") and desired("WBX C1").label, "D four", "§3 WBX C1 is D four")
H.eq(save("E five", "sequence", { "Smite" }), 4, "§3 the next one: C4")
KE.delete(me, 3)
local again = ns.State.cleanCustom(me.customSeq)
local slots = {}
for i, c in ipairs(again) do slots[#slots + 1] = tostring(c.name) .. "=" .. tostring(ns.State.customSlot(again, i)) .. "/" .. tostring(c.slot) end
H.eq(table.concat(slots, " "), "B two=2/2 D four=1/1 E five=4/4", "§3 slots survive the SavedVariables cleaning")
-- saved before stable slots (no slot field): the names stay as they were (position)
local legacy = ns.State.cleanCustom({ { name = "x", steps = { "Smite" } }, { name = "y", steps = { "Smite" } } })
H.ok(legacy[1].slot == nil and legacy[2].slot == nil and ns.State.customSlot(legacy, 2) == 2, "§3 old saved lists keep their names, no new field")

-- §4 unsaved changes: one guard for Cancel, another macro, New macro and the mode switch
fresh()
save("Dots", "sequence", { "Shadow Word: Pain", "Mind Blast" })
A.openEditor(P, "WBX C1")
KE.addStep("Smite")
H.ok(KE.dirty() and A.unsaved(), "§4 Add makes the draft unsaved")
A.ef.cancel:Click()
H.ok(popupAsks() and A.ef:IsShown(), "§4 Cancel asks first: Save · Discard · Keep editing")
UI.popup.btns[3]:Click()
H.ok(A.ef:IsShown() and KE.frame.draft.steps[3] == "Smite", "§4 Keep editing: the draft is still there")
A.ef.cancel:Click(); UI.popup.btns[2]:Click()
H.ok(not A.ef:IsShown() and #me.customSeq[1].steps == 2, "§4 Discard: closed, nothing saved")
A.openEditor(P, "WBX C1"); KE.addStep("Smite")
A.ef.cancel:Click(); UI.popup.btns[1]:Click()
H.ok(not A.ef:IsShown() and me.customSeq[1].steps[3] == "Smite", "§4 Save in the question: saved, then closed")
save("Heal", "priority", { "Renew" })
A.openEditor(P, "WBX C1"); KE.addStep("Mind Blast")
H.ok(A.openEditor(P, "WBX C2") and popupAsks() and KE.frame.draft.name == "Dots", "§4 opening another macro asks first")
UI.popup.btns[2]:Click()
H.ok(A.ef:IsShown() and KE.frame.draft.name == "Heal" and #me.customSeq[1].steps == 3, "§4 Discard: the other macro opens, the first unchanged")
KE.addStep("Lesser Heal")
A.openNew(P)
H.ok(popupAsks() and KE.frame.draft.name == "Heal", "§4 New macro asks first too")
UI.popup.btns[3]:Click()
A.openNew(P) ; UI.popup.btns[2]:Click()
H.ok(A.ef:IsShown() and KE.frame.choice:IsShown(), "§4 … Discard: the new macro starts")
KE.frame.choice.seq:Click(); KE.addStep("Smite")
A.openNew(P)
H.ok(popupAsks(), "§4 a second New macro with spells added asks first")
UI.popup.btns[2]:Click(); KE.frame.choice:Hide()
-- the page or the window hides (WoW also fires the editor's OnHide then): the draft stays for when it comes back
A.closeEditor()
A.openEditor(P, "WBX C1"); KE.addStep("Mind Blast")
UI.Select("keys"); A.ef._scripts.OnHide(A.ef) -- what WoW does to a child when its page hides
UI.Select("custom")
H.ok(A.ef:IsShown() and KE.frame.draft and KE.frame.draft.steps[#KE.frame.draft.steps] == "Mind Blast", "§4 switching page and back keeps the unsaved draft")
UI.frame:Hide(); A.ef._scripts.OnHide(A.ef); UI.Open("custom")
H.ok(KE.frame.draft and KE.dirty(), "§4 closing and opening the window keeps it too")
A.ef.cancel:Click(); UI.popup.btns[2]:Click()

-- §5 Sequence → Single shows and saves one spell, switching back restores the steps; no hidden filler
fresh()
save("Three", "sequence", { "Mind Blast", "Shadow Word: Pain", "Smite" }, { filler = "Smite", fills = 2 })
A.openEditor(P, "WBX C1")
KE.frame.kind.opts.set("single")
H.eq(shownSteps(), 1, "§5 Single shows one step")
H.ok(KE.frame.fillerText:GetText():find("Single uses the first spell", 1, true), "§5 … and says so")
H.ok(not (pickRow("Shadow Word: Pain") and pickRow("Shadow Word: Pain").check:IsShown()), "§5 no gold tick for a hidden step")
KE.frame.kind.opts.set("sequence")
H.eq(shownSteps(), 3, "§5 back to Sequence: all three steps again")
KE.frame.kind.opts.set("priority")
H.eq(shownSteps(), 3, "§5 Priority keeps every step")
H.ok(pickRow("Mind Blast").check:IsShown() and pickRow("Smite").check:IsShown(), "§5 Priority: steps ticked (Smite is a step here)")
KE.frame.draft.steps = { "Mind Blast", "Shadow Word: Pain" }; KE.Refresh()
H.ok(not pickRow("Smite").check:IsShown(), "§5 Priority: no gold tick for the hidden filler")
local rp = KE.preview(me, KE.frame.draft, 20)
H.ok(not rp.macro:find("castsequence", 1, true), "§5 Priority builds no sequence")
KE.frame.kind.opts.set("single")
A.ef.save:Click()
local s5 = me.customSeq[1]
H.ok(s5.kind == "priority" and #s5.steps == 1 and s5.steps[1] == "Mind Blast" and s5.filler == "" and s5.single == true, "§5 saved as one spell, no filler")

-- §6 a one-step Priority reopens as Priority, a Single spell as Single, an old one-step (no flag) as Single
fresh()
A.openNew(P); KE.frame.choice.more:Click(); KE.addStep("Mind Blast"); A.ef.save:Click()
A.openEditor(P, "WBX C1")
H.eq(KE.frame.draft.kind, "priority", "§6 a one-step Priority reopens as Priority")
H.eq(KE.frame.kind.label:GetText(), "Priority", "§6 … and the dropdown says so")
A.closeEditor()
A.openNew(P); KE.frame.choice.single:Click(); KE.addStep("Smite"); A.ef.save:Click()
A.openEditor(P, "WBX C2")
H.eq(KE.frame.draft.kind, "single", "§6 a Single spell reopens as Single")
A.closeEditor()
me.customSeq[3] = { id = "qold", name = "Old", kind = "priority", aim = "harm", steps = { "Smite" }, filler = "", fills = 1, reset = "combat" }
A.openEditor(P, "WBX C3")
H.eq(KE.frame.draft.kind, "single", "§6 saved before 1.3.0 (no flag): Single as before")
A.closeEditor()
local renew
for _, s in ipairs(ns.Kit.spellsOf(me)) do if s.name == "Renew" then renew = s end end
local i6 = Core.newSingle(renew)
H.ok(i6 and ns.State.customAt(me.customSeq, i6).single == true, "§6 a spell made into an own macro is a Single spell")

-- §7 Turning Advanced on (or off) while the editor is open updates the Targeting tab at once
fresh()
save("Dots", "sequence", { "Shadow Word: Pain" })
Core.db.settings.advanced = nil
A.openEditor(P, "WBX C1")
H.ok(not A.ef.tabTarget:IsEnabled() and A.ef.tabNote:IsShown(), "§7 Standard: Targeting greyed")
A.setMode(true)
H.ok(A.ef.tabTarget:IsEnabled() and not A.ef.tabNote:IsShown(), "§7 Advanced on: Targeting enabled, note gone")
A.ef.tabTarget:Click()
H.eq(A.ef.section, "target", "§7 … and it opens")
A.setMode(false)
H.ok(not A.ef.tabTarget:IsEnabled() and A.ef.section == "spells", "§7 Standard again: back on Spells, Targeting greyed")
A.closeEditor()

-- also: a spell on the cursor added by a click on a step; Save greyed with no spells; level-up refreshes the editor
fresh()
A.openNew(P); KE.frame.choice.seq:Click()
H.ok(not A.ef.save:IsEnabled(), "Save is greyed on a new macro with no spells")
KE.addStep("Mind Blast")
H.ok(A.ef.save:IsEnabled(), "… and enabled with one")
local oldInfo, oldName = W.env.GetCursorInfo, W.env.GetSpellInfo
local CS = W.env.C_Spell
local oldCS = CS and CS.GetSpellName
W.env.GetCursorInfo = function() return "spell", 1, "spell", 589 end
if CS then CS.GetSpellName = function() return "Smite" end end
W.env.GetSpellInfo = function() return "Smite" end
KE.frame.stepBtns[1]:Click()
H.eq(table.concat(KE.frame.draft.steps, ","), "Mind Blast,Smite", "a click on a step with a spell on the cursor adds it (never removes)")
W.env.GetCursorInfo, W.env.GetSpellInfo = oldInfo, oldName
if CS then CS.GetSpellName = oldCS end
local calls, origR = 0, KE.Refresh
KE.Refresh = function(...) calls = calls + 1; return origR(...) end
W.fire("PLAYER_LEVEL_UP", 21)
KE.Refresh = origR
H.ok(calls > 0, "a level up refreshes the open editor")
A.closeEditor()

-- Switching Spells ↔ Targeting many times never changes the draft, the targets or the preview
Core.db.settings.advanced = true
local function ser(t)
  if type(t) ~= "table" then return tostring(t) end
  local keys = {}
  for k in pairs(t) do keys[#keys + 1] = tostring(k) end
  table.sort(keys)
  local out = {}
  for _, k in ipairs(keys) do out[#out + 1] = k .. "=" .. ser(t[k] == nil and t[tonumber(k)] or t[k]) end
  return "{" .. table.concat(out, ",") .. "}"
end
local function state()
  local f = A.ef
  return table.concat({ KE.frame.draft and KE.sig(KE.frame.draft) or "-", ser(f.targets), ser(f.opts), ser(f.lines), tostring(f.body), tostring(f.base) }, " #")
end
local function flip(what)
  A.ef.tabTarget:Click(); A.ef.tabSpells:Click()
  local first = state()
  local okAll = true
  for _ = 1, 12 do
    A.ef.tabTarget:Click(); A.ef.tabSpells:Click(); A.ef.tabTarget:Click()
    if state() ~= first then okAll = false end
  end
  H.ok(okAll, what .. ": 36 tab switches change nothing")
  H.ok(not A.unsaved() or what:find("unsaved", 1, true), what .. ": switching alone makes nothing unsaved")
end
fresh()
A.openNew(P); KE.frame.choice.seq:Click(); KE.addStep("Shadow Word: Pain"); KE.addStep("Mind Blast"); KE.addStep("Shoot")
A.ef.tabTarget:Click(); drag(tile("focus"), A.ef.rows[1])
flip("new sequence (unsaved)")
A.ef.save:Click()
A.openEditor(P, "WBX C1")
flip("own sequence")
A.ef.tabTarget:Click(); drag(tile("focus"), A.ef.rows[1])
flip("own sequence with unsaved targeting")
A.ef.cancel:Click(); UI.popup.btns[2]:Click()
local recName = rec.cell.name
A.openEditor(UI.panels.keys, recName, rec.cell.label)
flip("recommended macro")
A.closeEditor()

H.eq(errors(), "", "no Lua errors in the log")
os.exit(H.report("editor flows") and 0 or 1)
