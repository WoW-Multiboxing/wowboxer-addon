-- Advanced mode UI + Reset to default (docs/advanced-mode.md §6): Standard hides every advanced control, the confirm
-- needs the tick, overrides stay active after switching back; the Targeting window; Reset: each tick removes exactly
-- its part (DeleteMacro only for WBX names), RESET must be typed, disabled in combat, CVar restore before the backup
-- is forgotten; /wbx reset all opens the window and never resets directly.
local dir = (arg[0]:match("^(.*)/[^/]+$") or ".")
local H = dofile(dir .. "/harness.lua")
local Mock = dofile(dir .. "/wowmock.lua")

local INFO = { class = "PALADIN", race = "Scourge", level = 20 }
local W = Mock.new(H, { name = "Anna", class = "PRIEST", race = "Scourge", level = 20, party = { party1 = "Bo", party2 = "Dorin" },
  partyInfo = { party1 = { class = "HUNTER", race = "Orc", level = 20 }, party2 = INFO } })
local ns = H.loadAddon({ env = W.env })
W.fire("ADDON_LOADED", "WoWBoxer"); W.fire("PLAYER_LOGIN")
for _, s in ipairs(ns.Data.spells.priest) do if s.level <= 20 and s.gate ~= "talent" then W.known[s.name] = true end end
local Core, UI, A, Book = ns.Core, ns.UI, ns.Advanced, ns.Book
local sq = ns.State.newSquad({ name = "Trio", members = {
  { name = "Dorin", cls = "paladin", race = "undead", role = "tank", leader = true },
  { name = "Anna", cls = "priest", race = "undead", role = "healer", unit = "party2" },
  { name = "Bo", cls = "hunter", race = "orc", role = "ranged", unit = "party2" } } })
Core.db.squads = { sq }; Core.db.active = sq.id
Core.cdb.guide = "done"
UI.Open("keys")
Core.sync({})
local p = UI.panels.keys
local function cellOf(pred) for _, b in ipairs(p.cells) do if b:IsShown() and b.cell and pred(b.cell) then return b.cell end end end
local healCell = cellOf(function(c) return c.d and c.d.group == "kit" and c.d.body:find("help", 1, true) end)
local function labels(items) local t = {}; for _, it in ipairs(items) do t[#t + 1] = it[1] end return table.concat(t, "|") end

-- Standard: nothing advanced
H.ok(not Core.advanced(), "Standard by default")
H.ok(not labels(Book.menuFor(p, healCell)):find("Targeting", 1, true), "Standard: no Targeting… in the menu")
local greyed
for _, it in ipairs(Book.menuFor(p, healCell)) do if it[1] == "Edit macro… (Advanced mode)" then greyed = it end end
H.ok(greyed and greyed[4] == true and greyed[3]:find("Turn on Advanced in the window header", 1, true), "Standard: Edit macro… (Advanced mode) greyed with a tip")
H.ok(not labels(Book.menuFor(p, healCell)):find("Also heal", 1, true), "Standard: no Also heal (Standard stays clean)")
UI.Select("custom")
p = UI.panels.custom
H.ok(true, "custom page")
UI.Select("keys"); p = UI.panels.keys
-- the confirm window needs the tick
UI.modeAdv:Click()
local c = A.confirmFrame
H.ok(c:IsShown() and not c.go:IsEnabled(), "Advanced asks first; Turn on is disabled until ticked")
c.go:Click()
H.ok(not Core.advanced(), "not on without the tick")
c.tick:Click()
H.ok(c.go:IsEnabled(), "ticked: Turn on enabled")
c.go:Click()
H.ok(Core.advanced() and not c:IsShown(), "Advanced on")
H.eq(Core.db.settings.advanced, true, "account-wide setting")
-- the menu: Edit macro… and Also heal Bo's pet (no separate Targeting… any more)
local items = Book.menuFor(p, healCell)
H.ok(labels(items):find("Edit macro…", 1, true) and labels(items):find("Also heal Bo's pet", 1, true) and not labels(items):find("Targeting", 1, true),
  "Advanced menu: " .. labels(items))
for _, it in ipairs(items) do if it[1] == "Also heal Bo's pet" then it[2]() end end
H.ok(Core.cdb.overrides[healCell.name], "Also heal Bo's pet stored")
UI.Refresh()
local hc
for _, b in ipairs(p.cells) do if b:IsShown() and b.cell and b.cell.name == healCell.name then hc = b end end
H.ok(hc.edited:IsShown(), "the key shows the edited mark")
-- the Macro editor: 1 Spells · 2 Targeting (drag and drop) · 3 Options · 4 Preview
for _, it in ipairs(Book.menuFor(p, healCell)) do if it[1] == "Edit macro…" then it[2]() end end
local tf = A.ef
H.ok(tf:IsShown(), "Edit macro… opens the Macro editor")
H.ok(tf.spells:GetText():find(healCell.label, 1, true), "1 Spells: " .. tf.spells:GetText())
local names = {}
for _, r in ipairs(tf.rows) do if r:IsShown() then names[#names + 1] = r.name:GetText() end end
H.ok(table.concat(names, "|"):find("Bo's pet – the pet of party1 (party1pet)", 1, true), "each row says what it targets: " .. table.concat(names, " | "))
H.ok(tf.info:GetText():find("/255", 1, true), "preview with its length: " .. tf.info:GetText())
-- drag a tile (Mouseover) from Available into the list at row 1
local function cursorAt(frame) local x, y = frame:GetCenter(); local k = frame:GetEffectiveScale() or 1; W.cursorPos = { x * k, y * k } end
local nBefore = #tf.targets
local moTile
for _, t in ipairs(tf.tiles) do if t:IsShown() and t.target.who == "focus" then moTile = t end end
moTile._scripts.OnDragStart(moTile)
cursorAt(tf.rows[1])
moTile._scripts.OnDragStop(moTile)
H.eq(#tf.targets, nBefore + 1, "drag in from Available")
H.eq(tf.targets[1].who, "focus", "dropped where the cursor is (row 1)")
-- reorder by drag: row 1 → the last row
local r1 = tf.rows[1]
r1._scripts.OnDragStart(r1)
cursorAt(tf.rows[#tf.targets])
r1._scripts.OnDragStop(r1)
H.eq(tf.targets[#tf.targets].who, "focus", "drag inside the list reorders")
-- drag out removes; × removes
local rl = tf.rows[#tf.targets]
rl._scripts.OnDragStart(rl)
W.cursorPos = { 1, 1 }
rl._scripts.OnDragStop(rl)
H.eq(#tf.targets, nBefore, "drag out of the list removes")
moTile:Click()
H.eq(#tf.targets, nBefore + 1, "a click on a tile adds it last")
tf.rows[#tf.targets].remove:Click()
H.eq(#tf.targets, nBefore, "× removes")
-- a missing unit is greyed "skipped"
table.insert(tf.targets, { who = "member", name = "Cid", help = true, nodead = true })
A.refreshEditor()
H.ok(tf.rows[#tf.targets].name:GetText() == "Cid is not in your party – skipped", "missing: " .. tf.rows[#tf.targets].name:GetText())
table.remove(tf.targets)
tf.mod.select("shift")
H.ok(tf.preview:GetText():find("[mod:shift,@player]", 1, true), "modifier in the preview")
local shown = tf.preview:GetText()
tf.save:Click()
for _, d in ipairs(Core.compute().desired) do if d.name == healCell.name then H.eq(d.body, shown, "the preview is the macro that is built") end end
H.eq(Core.cdb.overrides[healCell.name].mod, "shift", "Save stores it")
-- switch back to Standard: overrides stay active, one line says so
UI.modeStd:Click()
H.ok(not Core.advanced(), "Standard again")
H.ok(Core.cdb.overrides[healCell.name] ~= nil, "your changes stay active")
Core.sync({}) -- the changed key first; then the line stays as a reminder
local step = Book.nextStep(Core.compute(), "keys")
H.ok(step.text:find("your own targeting", 1, true) and step.button[1] == "Show", "My keys: N keys use your own targeting · Show: " .. step.text)
H.ok(labels(Book.menuFor(p, healCell)):find("Back to WoWBoxer's version", 1, true), "Back to WoWBoxer's version also in Standard")
H.ok(not labels(Book.menuFor(p, healCell)):find("Edit macro…\"", 1, true), "but Edit macro… only greyed in Standard")
-- text editor: live checks
UI.modeAdv:Click(); A.confirmFrame.tick:Click(); A.confirmFrame.go:Click()
A.openText(p, healCell.name, healCell.label)
local xf = A.xf
xf.edit:SetText("/run print(1)"); xf.edit._scripts.OnTextChanged(xf.edit)
H.ok(not xf.save:IsEnabled() and xf.info:GetText():find("/run", 1, true), "text: /run refused live")
xf.edit:SetText("#showtooltip\n/cast [@party1pet,help,nodead][@player] Heal"); xf.edit._scripts.OnTextChanged(xf.edit)
H.ok(xf.save:IsEnabled(), "text: a plain macro can be saved")
xf.save:Click()
H.ok(Core.cdb.overrides[healCell.name].text, "text override saved (frozen)")
xf:Hide()
-- KeyEditor shows Targeting… / Macro text… only in Advanced
UI.Select("custom")
UI.panels.custom.cells[1]:Click("LeftButton")
H.ok(ns.Advanced.ef:IsShown() and (not ns.Advanced.ef.tabSpells:IsShown() or ns.Advanced.ef.tabTarget:IsShown()), "own macros: the Macro editor, Targeting in Advanced")
ns.KeyEditor.Close()
UI.modeStd:Click()
UI.panels.custom.cells[1]:Click("LeftButton")
H.ok(ns.Advanced.ef:IsShown() and not (ns.Advanced.ef.tabSpells:IsShown() and ns.Advanced.ef.tabTarget:IsShown()), "Standard: an own macro has no Targeting tab")
ns.KeyEditor.Close()

-- Reset to default
UI.Select("setup")
Core.applyCVars()
H.eq(W.cvars.autoLootDefault, "1", "a setting changed (backup kept)")
W.addMacro("MyOwnMacro", "/say hi", true)
local function wbxCount() local n = 0; for _, x in ipairs(ns.Compat.characterMacros()) do if ns.Rules.isOurs(x.name) then n = n + 1 end end return n end
local wbx = wbxCount()
H.ok(wbx > 3, "WBX macros exist (" .. wbx .. ")")
W.env.SlashCmdList.WOWBOXER("reset all")
local rf = A.rf
H.ok(rf:IsShown() and rf.step == 1, "/wbx reset all opens step 1 (never resets directly)")
H.ok(Core.cdb.overrides[healCell.name] ~= nil, "nothing removed yet")
local function tick(key) for _, c in ipairs(rf.ticks) do if c.key == key then return c end end end
H.ok(tick("char"):GetChecked() and tick("bars"):GetChecked() and tick("macros"):GetChecked() and tick("cvars"):GetChecked() and not tick("account"):GetChecked(),
  "default: this character, bars, WBX macros, settings – not the squads")
for _, c in ipairs(rf.ticks) do if c:GetChecked() then c:Click() end end -- untick all: nothing chosen
H.ok(not rf.next:IsEnabled(), "nothing ticked: Next disabled")
tick("char"):Click(); tick("macros"):Click(); tick("cvars"):Click(); tick("bars"):Click()
rf.next:Click()
H.ok(rf.step == 2 and rf.summary:GetText():find("macro override", 1, true) and rf.summary:GetText():find("WBX macro", 1, true), "step 2 summary: " .. rf.summary:GetText())
H.ok(not rf.go:IsEnabled(), "Reset disabled until RESET is typed")
rf.typed:SetText("reset"); rf.typed._scripts.OnTextChanged(rf.typed)
H.ok(not rf.go:IsEnabled(), "lower case does not count")
rf.typed:SetText("RESET"); rf.typed._scripts.OnTextChanged(rf.typed)
H.ok(rf.go:IsEnabled(), "RESET typed: enabled")
W.combat = true; A.refreshReset()
H.ok(not rf.go:IsEnabled() and rf.go:GetText() == "Not in combat", "disabled in combat")
W.combat = false; A.refreshReset()
-- record the order: CVars restored before the backup is forgotten
local order = {}
local origSet = W.env.C_CVar.SetCVar
W.env.C_CVar.SetCVar = function(n, v) order[#order + 1] = "set:" .. n .. "=" .. tostring(v) .. (next(Core.cdb.cvarBackup) and ":backup" or ":nobackup"); return origSet(n, v) end
rf.go:Click()
W.env.C_CVar.SetCVar = origSet
H.eq(W.cvars.autoLootDefault, "0", "game settings put back")
H.ok(#order > 0 and order[1]:find(":backup$"), "restore ran while the backup still existed: " .. tostring(order[1]))
H.eq(next(Core.cdb.cvarBackup), nil, "then the backup is forgotten")
H.eq(wbxCount(), 0, "all WBX macros deleted")
local own = false
for _, x in ipairs(ns.Compat.characterMacros()) do if x.name == "MyOwnMacro" then own = true end end
H.ok(own, "other macros are never touched")
H.eq(next(Core.cdb.overrides), nil, "this character's overrides gone")
H.ok(#Core.db.squads >= 1, "squads kept (not ticked)")
local kept
for _, s in ipairs(Core.db.squads) do if s.name == "Trio" then kept = true end end
H.ok(kept, "the Trio squad is still there")
H.ok(not Core.advanced(), "back to Standard after a full reset")
H.ok(rf.step == 3 and rf.reload:IsShown(), "offers Reload UI now")
rf.reload:Click()
H.ok(W.reloaded, "Reload UI on a click")
H.ok(W.chatHas("Reset to default: "), "one chat line says what was reset")
-- the account tick removes squads and builds
A.openReset()
for _, c in ipairs(rf.ticks) do if c:GetChecked() then c:Click() end end
tick("account"):Click() -- only account
rf.next:Click(); rf.typed:SetText("RESET"); rf.typed._scripts.OnTextChanged(rf.typed); rf.go:Click()
local trio = false
for _, s in ipairs(Core.db.squads) do if s.name == "Trio" then trio = true end end
H.ok(not trio and next(Core.db.builds) == nil, "account: squads and builds gone (a fresh solo squad for this character)")
os.exit(H.report("advanced") and 0 or 1)
