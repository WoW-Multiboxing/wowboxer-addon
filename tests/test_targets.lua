-- The Macro editor's "Available targets" (Advanced → Targeting): every target, in groups (Common · Squad · Party ·
-- Raid folded), scrolling; drag from the bottom of the list into "This macro tries, in order"; raid units go through
-- the same conditional checks and still work in a party; old saved overrides still load; no errors with 0, 1, 4
-- squad members or in a raid. Run: lua tests/test_targets.lua
local dir = (arg[0]:match("^(.*)/[^/]+$") or ".")
local H = dofile(dir .. "/harness.lua")
local Mock = dofile(dir .. "/wowmock.lua")

local function errors(ns)
  local n = {}
  for _, e in ipairs(ns.Core.db.log) do if e.l == "error" then n[#n + 1] = e.m end end
  return table.concat(n, " | ")
end
--- Boot Anna (priest) with `others` squad members besides her; returns W, ns, the editor frame.
local function boot(others, opts)
  opts = opts or {}
  local names = { { "Dorin", "paladin" }, { "Bo", "hunter" }, { "Cid", "warlock" }, { "Dee", "mage" }, { "Eli", "rogue" } }
  local party, members = {}, { { name = "Anna", cls = "priest", race = "undead", role = "healer", unit = "party1" } }
  for i = 1, others do
    local n = names[i]
    if i <= 4 then party["party" .. i] = n[1] end
    members[#members + 1] = { name = n[1], cls = n[2], race = "undead", role = "dps", leader = i == 1, unit = "party1" }
  end
  if others == 0 then members[1].leader = true end
  local W = Mock.new(H, { name = "Anna", class = "PRIEST", race = "Scourge", level = 20, party = party })
  if opts.raid then W.env.IsInRaid = function() return true end end
  local ns = H.loadAddon({ env = W.env })
  if opts.overrides then W.env.WoWBoxerCharDB = nil end
  W.fire("ADDON_LOADED", "WoWBoxer"); W.fire("PLAYER_LOGIN")
  for _, s in ipairs(ns.Data.spells.priest) do if s.level <= 20 and s.gate ~= "talent" then W.known[s.name] = true end end
  local Core, UI, A = ns.Core, ns.UI, ns.Advanced
  local sq = ns.State.newSquad({ name = "Test", members = members })
  Core.db.squads = { sq }; Core.db.active = sq.id
  Core.cdb.guide = "done"
  Core.db.settings.advanced = true
  if opts.overrides then Core.cdb.overrides = opts.overrides end
  UI.Open("keys")
  local p = UI.panels.keys
  local heal
  for _, b in ipairs(p.cells) do if not heal and b:IsShown() and b.cell and b.cell.d and b.cell.d.body:find("help", 1, true) then heal = b.cell end end
  A.openTargeting(p, heal.name, heal.label)
  return W, ns, A.ef, heal
end
local function shownUnits(f)
  local set = {}
  for _, t in ipairs(f.tiles) do if t:IsShown() and t.target and t.target.who == "unit" then set[t.target.unit] = t end end
  return set
end
local function groupKeys(f) local k = {}; for _, g in ipairs(f.groups) do k[#k + 1] = g.key end return table.concat(k, ",") end

-- 0, 1 and 4 other squad members, and a raid: every group draws without errors
for _, case in ipairs({ { 0 }, { 1 }, { 4 }, { 5, raid = true } }) do
  local W, ns, f = boot(case[1], { raid = case.raid })
  local tag = case[1] .. " others" .. (case.raid and ", raid" or "")
  H.eq(errors(ns), "", tag .. ": no errors")
  H.eq(groupKeys(f), case[1] == 0 and "common,party,raid" or "common,squad,party,raid", tag .. ": groups in order")
  local n = 0
  for _, t in ipairs(f.tiles) do if t:IsShown() then n = n + 1 end end
  H.ok(n >= 8 + 8, tag .. ": common + party tiles shown (" .. n .. ")")
  H.eq(W.calls.CreateMacro ~= nil and #W.calls.CreateMacro > 0 and "wrote" or "nothing", "nothing", tag .. ": opening writes nothing")
end

-- the full list: all 8 party units and pets, the headings, Raid folded and unfoldable, scrolling, drag from the bottom
do
  local W, ns, f, heal = boot(4)
  local A, O = ns.Advanced, ns.Override
  local u = shownUnits(f)
  for _, x in ipairs({ "party1", "party2", "party3", "party4", "party1pet", "party2pet", "party3pet", "party4pet" }) do
    H.ok(u[x] ~= nil, "party unit visible: " .. x)
  end
  H.ok(u.raid1 == nil and u.raid40pet == nil, "Raid is folded by default")
  local heads = {}
  for _, h in ipairs(f.heads) do if h:IsShown() then heads[#heads + 1] = h.text:GetText() end end
  H.eq(table.concat(heads, "|"), "COMMON|SQUAD|PARTY|+ RAID (80)", "headings")
  local party
  for _, h in ipairs(f.heads) do if h.key == "party" then party = h end end
  H.ok(party.tip:find("A party is you + party1–4", 1, true) ~= nil, "Party heading tooltip: no party5")
  -- Common: the eight in order, full width
  local common = {}
  for _, t in ipairs(f.tiles) do if t:IsShown() and t.group == "common" then common[#common + 1] = t.target.who end end
  H.eq(table.concat(common, ","), "mouseover,target,leader,leadertarget,focus,targettarget,player,mypet", "Common in order")
  H.ok(f.tiles[1]:GetWidth() > 200, "Common tiles take the full width")
  -- Squad: each member with the unit here, pets for hunters and warlocks
  local squad = {}
  for _, t in ipairs(f.tiles) do if t:IsShown() and t.group == "squad" then squad[#squad + 1] = t.full end end
  H.ok(table.concat(squad, "|"):find("Bo's pet (party2pet)", 1, true) ~= nil, "Squad lists a pet with its unit: " .. table.concat(squad, " | "))
  -- the tooltip carries the whole label and what it is
  W.env.GameTooltip._lines = nil
  local lines = {}
  W.env.GameTooltip.AddLine = function(_, text) lines[#lines + 1] = text end
  f.tiles[1]._scripts.OnEnter(f.tiles[1])
  H.ok(table.concat(lines, "|"):find("Mouseover – whoever your mouse is over", 1, true) ~= nil, "tooltip: " .. table.concat(lines, " | "))
  -- unfold Raid
  local raidHead
  for _, h in ipairs(f.heads) do if h.key == "raid" then raidHead = h end end
  raidHead:Click()
  u = shownUnits(f)
  H.ok(u.raid1 ~= nil and u.raid40 ~= nil and u.raid1pet ~= nil and u.raid40pet ~= nil, "Raid unfolds: raid1–40 and their pets")
  H.eq(raidHead.text:GetText(), "– RAID (80)", "heading shows it is open")
  -- scrolling: the list is taller than its box; the bar shows; the wheel moves it
  H.ok(f.availContent:GetHeight() > f.availSF:GetHeight() * 3, "the list is taller than its box (it scrolls)")
  local bar = f.availSF.ScrollBar
  H.ok(bar ~= nil and bar:IsShown(), "the flat scroll bar shows")
  if f.availSF._scripts.OnScrollRangeChanged then
    f.availSF._scripts.OnScrollRangeChanged(f.availSF, 0, f.availContent:GetHeight() - f.availSF:GetHeight())
    f.availSF._scripts.OnMouseWheel(f.availSF, -1)
    H.ok((bar:GetValue() or 0) > 0, "the mouse wheel scrolls down")
  end
  -- drag the very last tile (raid40pet, the bottom of the scrolled list) into the order list
  local last = u.raid40pet
  local function cursorAt(frame) local x, y = frame:GetCenter(); local k = frame:GetEffectiveScale() or 1; W.cursorPos = { x * k, y * k } end
  local before = #f.targets
  last._scripts.OnDragStart(last)
  cursorAt(f.rows[1])
  last._scripts.OnDragStop(last)
  H.eq(#f.targets, before + 1, "dragged in from the bottom of the list")
  H.eq(f.targets[1].unit, "raid40pet", "dropped at row 1")
  -- the macro: raid units pass the checks (<= 255, conditionals), and the unit is in the macro text
  A.saveEditor()
  local d
  for _, x in ipairs(ns.Core.compute().desired) do if x.name == heal.name then d = x end end
  H.ok(d.body:find("[@raid40pet", 1, true) ~= nil, "the macro aims at raid40pet first")
  H.ok(#d.body <= 255 and ns.Rules.validateMacro(d.name, d.body), "still a valid macro (" .. #d.body .. " chars)")
  H.eq(#O.checkConditionals(d.body), 0, "conditional check passes")
  H.eq(d.ovMissing, nil, "in a party the raid unit is just skipped by the game – nothing is missing here")
  H.eq(errors(ns), "", "no errors")
end

-- old saved overrides (made before the groups and raid units) still load
do
  local _, ns, f, heal = boot(2)
  local name = heal.name
  ns.Core.cdb.overrides[name] = ns.Override.clean({ targets = {
    { who = "mouseover", help = true, nodead = true }, { who = "member", name = "Bo", pet = true, help = true, nodead = true },
    { who = "unit", unit = "party3pet", help = true, nodead = true }, { who = "player" } }, mod = "shift" })
  ns.Advanced.openTargeting(ns.UI.panels.keys, name, heal.label)
  f = ns.Advanced.ef
  H.eq(#f.targets, 4, "old override: all four targets load")
  H.eq(f.targets[3].unit, "party3pet", "old override: party3pet kept")
  local d
  for _, x in ipairs(ns.Core.compute().desired) do if x.name == name then d = x end end
  H.ok(d.body:find("@party3pet", 1, true) and d.body:find("mod:shift", 1, true), "old override still builds the macro: " .. d.body)
end

os.exit(H.report("targets") and 0 or 1)
