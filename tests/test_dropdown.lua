-- Dropdowns (docs/squad-overhaul.md §2): our own list dropdown (Classic Era, and any client without the menu system),
-- Blizzard's DropdownButton when the client has it, no "< value >" cycle buttons left, the sequence control.
local dir = (arg[0]:match("^(.*)/[^/]+$") or ".")
local H = dofile(dir .. "/harness.lua")
local Mock = dofile(dir .. "/wowmock.lua")
local Layout = dofile(dir .. "/layout.lua")

local function boot(opts)
  local W = Mock.new(H, opts)
  local ns = H.loadAddon({ env = W.env })
  W.fire("ADDON_LOADED", "WoWBoxer"); W.fire("PLAYER_LOGIN")
  ns.Core.cdb.guide = "done"
  for _, s in ipairs(ns.Data.spells[(opts.class or "PALADIN"):lower()]) do if s.level <= (opts.level or 10) then W.known[s.name] = true end end
  return W, ns
end
local function visibleButtons(W, text)
  local n = 0
  for _, f in ipairs(W.frames) do if f._kind == "Button" and rawget(f, "_text") == text and f:IsVisible() then n = n + 1 end end
  return n
end
local function errors(ns)
  local errs = {}
  for _, e in ipairs(ns.Core.db.log) do if e.l == "error" then errs[#errs + 1] = e.m end end
  return table.concat(errs, " | ")
end

-- ------------------------------------------------------------------ our own dropdown (Classic Era)
do
  local W, ns = boot({ class = "PRIEST", level = 20, toc = 11509, spellbookStyle = "classic" })
  local UI = ns.UI
  UI.Open("keys")
  local p = UI.panels.keys
  H.ok(not p.role.isBlizzard, "Era: own dropdown (no menu system)")
  H.eq(p.role.label:GetText(), ns.State.ROLE_NAME[select(2, ns.Core.me()).role], "the dropdown shows the current value")
  p.role:Click()
  local l = W.env.WoWBoxerDropdownList
  H.ok(l and l:IsShown(), "click opens the list")
  local rows = {}
  for _, r in ipairs(l.rows) do if r:IsShown() then rows[#rows + 1] = r end end
  H.eq(#rows, #ns.Data.classes.priest.roles, "one row per role")
  local chosen
  for _, r in ipairs(rows) do if r.radio:IsShown() then chosen = r.value end end
  H.eq(chosen, select(2, ns.Core.me()).role, "the current value has the check mark")
  local esc = false
  for _, n in ipairs(W.env.UISpecialFrames) do if n == "WoWBoxerDropdownList" then esc = true end end
  H.ok(esc, "Esc closes the list")
  H.eq(table.concat(Layout.check(W, { l }), " | "), "", "the list fits the screen, no overlaps")
  local target
  for _, r in ipairs(rows) do if r.value ~= chosen then target = r end end
  target:Click()
  H.ok(not l:IsShown(), "a choice closes the list")
  H.eq(select(2, ns.Core.me()).role, target.value, "the choice is saved")
  H.eq(W.calls.CreateMacro, nil, "choosing writes nothing to the game")
  p.role:Click()
  H.ok(l:IsShown(), "opens again")
  l.catcher:Click()
  H.ok(not l:IsShown(), "a click outside closes the list")
  p.playsAs:Click(); p.playsAs:Click()
  H.ok(not l:IsShown(), "a second click on the dropdown closes it")
  p.playsAs.select("party2")
  local _, m = ns.Core.me()
  H.ok(not m.leader and m.unit == "party2", "plays as Follower (party2)")
  -- no cycle buttons anywhere
  for _, t in ipairs(UI.tabs) do
    UI.Select(t.key)
    H.eq(visibleButtons(W, "<") + visibleButtons(W, ">"), 0, t.key .. ": no < > cycle buttons")
  end
  UI.Select("custom")
  UI.panels.custom.cells[1]:Click("LeftButton")
  H.ok(ns.KeyEditor.IsOpen(), "key editor open")
  H.eq(visibleButtons(W, "<") + visibleButtons(W, ">"), 0, "key editor: no < > cycle buttons")
  local ke = ns.KeyEditor.frame
  ke.kind.select("priority")
  H.eq(ke.draft.kind, "priority", "key editor kind from the dropdown")
  H.ok(ke.kind._scripts.OnEnter ~= nil, "key editor dropdown has a tooltip")
  H.eq(errors(ns), "", "Era: no errors")
end

-- ------------------------------------------------------------------ the sequence control
do
  local _, ns = boot({ class = "WARLOCK", level = 20 })
  ns.UI.Open("keys")
  local sc = ns.UI.panels.keys.seq
  local _, m = ns.Core.me()
  H.ok(sc.check:IsEnabled(), "Warlock: sequence box enabled")
  H.ok(not sc.check:GetChecked(), "off by default")
  H.ok(not sc.tier:IsEnabled(), "tier disabled while off")
  sc.check:Click()
  H.eq(m.seq, "simple", "ticking turns on Simple")
  H.ok(sc.tier:IsEnabled(), "tier enabled when on")
  sc.tier.select("medium")
  H.eq(m.seq, "medium", "tier Medium")
  local seqKey = false
  for _, it in ipairs(ns.Core.compute().macros.items) do if it.group == "sequence" then seqKey = true end end
  H.ok(seqKey, "a sequence key appears in the book")
  sc.check:Click()
  H.eq(m.seq, "off", "unticking turns it off")
  H.eq(m.seqTier, "medium", "the tier is remembered")
  H.ok(ns.Core.importString(ns.Core.exportString()) ~= nil, "the export still imports")
  sc.check:Click()
  H.eq(m.seq, "medium", "ticking again brings back Medium")
  local s2 = ns.State.newSquad({ members = { { name = "X", cls = "warlock", seq = "off", seqTier = "advanced" } } })
  H.eq(s2.members[1].seqTier, "advanced", "seqTier survives the schema clean-up")
end
do
  local _, ns = boot({ class = "HUNTER", race = "Orc", level = 20 })
  ns.UI.Open("keys")
  local sc = ns.UI.panels.keys.seq
  H.ok(sc.check:IsEnabled(), "v8.5: Hunter has sequence keys too")
  sc.check:Click()
  H.ok(sc.tier:IsShown() and not sc.note:IsShown(), "Hunter: Simple / Medium / Advanced")
  local _, m = ns.Core.me()
  H.eq(m.seq, "simple", "ticked: Simple")
  local found
  for _, d in ipairs(ns.Core.compute().desired) do if d.key == "S1" then found = d end end
  H.ok(found and found.body:find("!Auto Shot", 1, true) and found.body:find("/petattack", 1, true), "Hunter Shots key: pet + Auto Shot: " .. tostring(found and found.body))
end

-- ------------------------------------------------------------------ Blizzard's dropdown when the client has it
do
  local W, ns = boot({ class = "PALADIN", level = 20, menu = true })
  local UI = ns.UI
  UI.Open("keys")
  local p = UI.panels.keys
  H.ok(p.role.isBlizzard, "menu system: Blizzard dropdown")
  H.eq(p.role._template, "WowStyle1DropdownTemplate", "WowStyle1DropdownTemplate")
  H.eq(p.role:GetText(), ns.State.ROLE_NAME[select(2, ns.Core.me()).role], "shows the current value")
  H.eq(#p.role._menu, #ns.Data.classes.paladin.roles, "one radio per role")
  H.ok(W.pickMenu(p.role, "Healer"), "radio found")
  H.eq(select(2, ns.Core.me()).role, "healer", "the radio choice is saved")
  H.eq(p.role:GetText(), "Healer", "label follows the choice")
  local sel = 0
  for _, e in ipairs(p.role._menu) do if e.isSel() then sel = sel + 1 end end
  H.eq(sel, 1, "exactly one radio selected")
  p.seq.check:Click()
  W.pickMenu(p.seq.tier, "Advanced")
  H.eq(select(2, ns.Core.me()).seq, "advanced", "sequence tier via the menu")
  for _, t in ipairs(UI.tabs) do UI.Select(t.key) end
  H.eq(errors(ns), "", "every tab renders with Blizzard dropdowns")
end

os.exit(H.report("dropdown") and 0 or 1)
