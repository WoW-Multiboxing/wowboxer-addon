-- One Macro editor for every entry point, and own macros end to end (docs/feedback-2026-10-30-night.md §1): create a
-- single spell and a sequence, edit, rename, delete, drag, Place, level-up update, share string, Advanced targeting on
-- an own macro, Back to WoWBoxer's version – each step also in the diagnose (ownFlow).
local dir = (arg[0]:match("^(.*)/[^/]+$") or ".")
local H = dofile(dir .. "/harness.lua")
local Mock = dofile(dir .. "/wowmock.lua")

local W = Mock.new(H, { name = "Anna", class = "PRIEST", race = "Scourge", level = 20, party = { party1 = "Dorin", party2 = "Bo" },
  partyInfo = { party1 = { class = "PALADIN", race = "Scourge", level = 20 }, party2 = { class = "HUNTER", race = "Orc", level = 20 } } })
local ns = H.loadAddon({ env = W.env })
W.fire("ADDON_LOADED", "WoWBoxer"); W.fire("PLAYER_LOGIN")
for _, s in ipairs(ns.Data.spells.priest) do if s.level <= 20 and s.gate ~= "talent" then W.known[s.name] = true end end
local Core, UI, A, KE, Book = ns.Core, ns.UI, ns.Advanced, ns.KeyEditor, ns.Book
local sq = ns.State.newSquad({ name = "Trio", members = {
  { name = "Dorin", cls = "paladin", race = "undead", role = "tank", leader = true },
  { name = "Anna", cls = "priest", race = "undead", role = "healer", unit = "party1" },
  { name = "Bo", cls = "hunter", race = "orc", role = "ranged", unit = "party1" } } })
Core.db.squads = { sq }; Core.db.active = sq.id
Core.cdb.guide = "done"
UI.Open("custom")
local p = UI.panels.custom
local _, me = Core.me()
local function cellOf(pred) for _, b in ipairs(p.cells) do if b:IsShown() and b.cell and pred(b.cell) then return b end end end
local function desired(name) for _, d in ipairs(Core.compute().desired) do if d.name == name then return d end end end
local function status(name) for _, it in ipairs(Core.compute().macros.items) do if it.name == name then return it.status end end end
local function same(what) H.ok(A.ef:IsShown() and A.ef.title:GetText():find("^Macro editor"), what .. ": the Macro editor") end

-- 1. New macro → Single spell (Myself)
cellOf(function(c) return c.kind == "new" end):Click("LeftButton")
same("New macro")
H.ok(KE.frame:IsShown() and KE.frame:GetParent() == A.ef.spellsBox, "its Spells section is the own-macro editor (no window of its own)")
KE.frame.choice.single:Click()
KE.addStep("Lesser Heal")
KE.frame.preset.select("self")
A.ef.save:Click()
H.eq(#me.customSeq, 1, "single spell saved")
H.ok(desired("WBX C1").body:find("[@player,help", 1, true), "Myself")
-- 2. New macro → Sequence
cellOf(function(c) return c.kind == "new" end):Click("LeftButton")
KE.frame.choice.seq:Click()
KE.addStep("Shadow Word: Pain"); KE.addStep("Mind Blast")
KE.frame.name:SetText("Dots"); KE.frame.name._scripts.OnTextChanged(KE.frame.name, true)
A.ef.save:Click()
H.ok(#me.customSeq == 2 and me.customSeq[2].kind == "sequence" and me.customSeq[2].name == "Dots", "sequence saved")
-- 3. every entry point opens the same window
UI.Refresh()
cellOf(function(c) return c.name == "WBX C2" end):Click("LeftButton")
same("click on an own macro"); H.eq(KE.frame.index, 2, "with that macro's spells"); A.ef:Hide()
local items = Book.menuFor(p, cellOf(function(c) return c.name == "WBX C2" end).cell)
local edit
for _, it in ipairs(items) do if it[1] == "Edit macro…" and not it[4] then edit = it end end
H.ok(edit ~= nil, "right-click an own macro: Edit macro… (also in Standard)")
for _, it in ipairs(items) do H.ok(it[1] ~= "Edit", "no old Edit entry") end
edit[2](); same("right-click → Edit macro… on an own macro"); A.ef:Hide()
Core.db.settings.advanced = true
UI.Select("keys")
local kp = UI.panels.keys
local rec
for _, b in ipairs(kp.cells) do if not rec and b:IsShown() and b.cell and b.cell.name and b.cell.name:find("^WBX K") then rec = b.cell end end
for _, it in ipairs(Book.menuFor(kp, rec)) do if it[1] == "Edit macro…" then it[2]() end end
same("Edit macro… on a recommended macro"); H.ok(not A.ef.spellsBox:IsShown() and A.ef.section == "target", "it opens on the targeting"); A.ef:Hide()
UI.Select("spells")
local sp = UI.panels.spells
local spell
for _, b in ipairs(sp.cells) do if not spell and b:IsShown() and b.cell and b.cell.spell and not b.cell.name and not b.cell.pending then spell = b.cell end end
for _, it in ipairs(Book.menuFor(sp, spell)) do if it[1] == "Edit macro…" then it[2]() end end
same("Edit macro… on a spell"); H.eq(#me.customSeq, 3, "the spell became own macro C3"); A.ef:Hide()
-- 4. edit + rename (Spells section) and Advanced targeting on an own macro (Targeting section)
UI.Select("custom")
A.openEditor(p, "WBX C2")
KE.frame.name:SetText("Two dots"); KE.frame.name._scripts.OnTextChanged(KE.frame.name, true)
A.showSection("target")
H.ok(A.ef.tabTarget:IsShown() and A.ef.list:IsShown(), "Advanced: the Targeting section of the same window")
for _, t in ipairs(A.ef.tiles) do if t:IsShown() and t.target.who == "focus" then t:Click() end end
A.ef.save:Click()
H.eq(me.customSeq[2].name, "Two dots", "renamed")
H.ok(Core.cdb.overrides["WBX C2"] and desired("WBX C2").body:find("[@focus", 1, true), "own macro with Advanced targeting")
-- 5. Back to WoWBoxer's version
A.openEditor(p, "WBX C2"); A.showSection("target")
A.ef.back:Click()
H.eq(Core.cdb.overrides["WBX C2"], nil, "Back to WoWBoxer's version")
-- 6. drag and Place
Core.pickup("WBX C2"); W.env.PlaceAction(50); W.env.ClearCursor(); W.fire("ACTIONBAR_SLOT_CHANGED", 50); W.flush()
H.eq(W.slotMacroName(50), "WBX C2", "dragged to a button")
Core.cdb.offBars["WBX C1"] = false
Core.sync({})
H.ok(ns.Macros.findIndex("WBX C1") and status("WBX C1") == "same", "Place: C1 created")
-- 7. level-up update
local before = desired("WBX C2").body
W.player.level = 30
for _, s in ipairs(ns.Data.spells.priest) do if s.level <= 30 and s.gate ~= "talent" then W.known[s.name] = true end end
W.fire("PLAYER_LEVEL_UP", 30); W.flush()
local after = desired("WBX C2").body
H.ok(after ~= nil and (after ~= before and status("WBX C2") == "update" or after == before), "level-up: the own macro follows the new ranks (" .. tostring(status("WBX C2")) .. ")")
Core.sync({})
H.eq(status("WBX C2"), "same", "and Update macros writes it")
-- 8. share string export / import keeps the own macros (data only)
local str = Core.exportString()
local res = ns.Share.import(str)
local rm
for _, m in ipairs(res.squad.members) do if m.name == "Anna" then rm = m end end
H.ok(rm and #rm.customSeq == 3 and rm.customSeq[2].name == "Two dots", "share string carries the own macros")
H.ok(not str:find("castsequence", 1, true), "but no macro text")
-- 9. delete
A.openEditor(p, "WBX C3")
KE.frame.delete:Click(); KE.frame.delete:Click()
H.eq(#me.customSeq, 2, "deleted (two clicks)")
-- the diagnose shows every step
local d = Core.selftest(true)
local flow = table.concat(d.ownFlow or {}, " | ")
for _, step in ipairs({ "own macro: new", "saved as", "open C2", "deleted C3", "made from the spell" }) do H.ok(flow:find(step, 1, true), "diagnose ownFlow: " .. step) end
H.ok(d.ownMacros and d.ownMacros[2] and d.ownMacros[2].name == "Two dots", "diagnose: the own macros")
os.exit(H.report("ownmacros") and 0 or 1)
