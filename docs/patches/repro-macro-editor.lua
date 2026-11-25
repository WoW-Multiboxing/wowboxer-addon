-- scratch repro (not committed): Macro editor / own-macro bugs, owner 25 Nov 2026
local dir = "tests" -- run from the repo root: python tools/lua.py docs/patches/repro-macro-editor.lua
local H = dofile(dir .. "/harness.lua")
local Mock = dofile(dir .. "/wowmock.lua")
local W = Mock.new(H, { name = "Anna", class = "PRIEST", race = "Scourge", level = 20, party = { party1 = "Dorin" },
  partyInfo = { party1 = { class = "PALADIN", race = "Scourge", level = 20 } } })
local ns = H.loadAddon({ env = W.env })
W.fire("ADDON_LOADED", "WoWBoxer"); W.fire("PLAYER_LOGIN")
for _, s in ipairs(ns.Data.spells.priest) do if s.level <= 20 and s.gate ~= "talent" then W.known[s.name] = true end end
local Core, UI, A, KE = ns.Core, ns.UI, ns.Advanced, ns.KeyEditor
local sq = ns.State.newSquad({ name = "Trio", members = {
  { name = "Dorin", cls = "paladin", race = "undead", role = "tank", leader = true },
  { name = "Anna", cls = "priest", race = "undead", role = "healer", unit = "party1" } } })
Core.db.squads = { sq }; Core.db.active = sq.id
Core.cdb.guide = "done"
UI.Open("custom")
local p = UI.panels.custom
local _, me = Core.me()
local function out(...) print("REPRO", ...) end
local function desired(name) for _, d in ipairs(Core.compute().desired) do if d.name == name then return d end end end

-- 1 Shoot / book spells via Add
A.openNew(p); KE.frame.choice.seq:Click()
local n0 = #KE.frame.draft.steps
KE.addStep("Shoot")
out("1 Add Shoot as a step accepted:", #KE.frame.draft.steps > n0)
local inPicker = false
for _, s in ipairs(KE.spellChoices(me, 20)) do if s.name == "Shoot" then inPicker = true end end
out("1 Shoot offered in the picker:", inPicker)

-- 2 Shoot as filler
KE.frame.draft.steps = { "Shadow Word: Pain" }; KE.frame.draft.filler = "Shoot"; KE.frame.draft.fills = 2
local r, warn = KE.preview(me, KE.frame.draft, 20)
out("2 macro:", (r.macro:gsub("\n", " | ")))
out("2 warnings:", #warn, table.concat(warn, " // "))
A.ef:Hide()

-- 3 delete shifts indices; overrides/keyLines stay on the old names
for i, name in ipairs({ "A one", "B two", "C three" }) do
  me.customSeq = me.customSeq or {}
  KE.save(me, { name = name, kind = "sequence", aim = "harm", steps = { "Mind Blast" }, filler = "", fills = 1, reset = "combat" }, nil)
end
Core.cdb.overrides["WBX C2"] = ns.Override.clean({ targets = { { who = "player", help = true } } })
out("3 before:", me.customSeq[1].name, me.customSeq[2].name, me.customSeq[3].name, "override on C2 =", me.customSeq[2].name)
KE.delete(me, 1)
out("3 after delete C1:", me.customSeq[1].name, me.customSeq[2].name, "override still on WBX C2 =", Core.cdb.overrides["WBX C2"] ~= nil, "-> now belongs to", me.customSeq[2].name)

-- 4 unsaved spell changes dropped silently
A.openEditor(p, "WBX C1", nil)
KE.addStep("Smite")
out("4 dirty after Add:", KE.dirty())
A.ef.cancel:Click()
out("4 after Cancel: saved steps =", table.concat(me.customSeq[1].steps, ","), "(no question asked)")

-- 5 Sequence -> Single drops steps on save
A.openEditor(p, "WBX C1", nil)
KE.frame.draft.steps = { "Mind Blast", "Shadow Word: Pain", "Smite" }
KE.frame.draft.kind = "single"; KE.Refresh()
local shown = 0
for _, b in ipairs(KE.frame.stepBtns) do if b:IsShown() then shown = shown + 1 end end
out("5 Single shows step icons:", shown)
A.saveEditor()
out("5 saved:", me.customSeq[1].kind, table.concat(me.customSeq[1].steps, ","))

-- 6 a 1-step Priority reopens as Single
KE.save(me, { name = "Prio", kind = "priority", aim = "harm", steps = { "Mind Blast" }, filler = "", fills = 1, reset = "combat" }, 1)
A.openEditor(p, "WBX C1", nil)
out("6 reopened kind:", KE.frame.draft.kind)
A.ef:Hide()

-- 7 Advanced on while the editor is open
Core.db.settings.advanced = nil
A.openEditor(p, "WBX C1", nil)
out("7 Standard: Targeting enabled =", A.ef.tabTarget:IsEnabled())
A.setMode(true)
out("7 after turning Advanced on: Targeting enabled =", A.ef.tabTarget:IsEnabled(), "note shown =", A.ef.tabNote:IsShown())
