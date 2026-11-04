-- Single-character features in the simulated client: minimap button + compartment, drag & drop of keys and spells,
-- remembered bar positions, key bindings, squad edit. Run: lua tests/test_features.lua
local dir = (arg[0]:match("^(.*)/[^/]+$") or ".")
local H = dofile(dir .. "/harness.lua")
local Mock = dofile(dir .. "/wowmock.lua")

local function boot(opts)
  local W = Mock.new(H, opts)
  local ns = H.loadAddon({ env = W.env })
  W.fire("ADDON_LOADED", "WoWBoxer"); W.fire("PLAYER_LOGIN")
  ns.Core.cdb.guide = "done" -- the first-run guide is tested in test_ui
  for _, s in ipairs(ns.Data.spells[(opts.class or "PALADIN"):lower()]) do if s.level <= (opts.level or 10) and s.gate ~= "talent" then W.known[s.name] = true end end
  return W, ns
end
local function findButton(W, text)
  for _, f in ipairs(W.frames) do if f._kind == "Button" and rawget(f, "_text") == text and f:IsVisible() then return f end end
end
--- A visible spell button of the open book page whose cell matches pred(cell).
local function row(ns, pred)
  local p = ns.UI.panels[ns.UI.current]
  for _, r in ipairs(p.cells or {}) do if r:IsShown() and r.cell and pred(r.cell) then return r end end
end
local function errors(ns)
  local n = {}
  for _, e in ipairs(ns.Core.db.log) do if e.l == "error" then n[#n + 1] = e.m end end
  return n
end

-- ------------------------------------------------------------------ minimap button + compartment
do
  local W, ns = boot({ name = "Warlocker", class = "PRIEST", race = "Scourge", level = 20 })
  local MM = ns.Minimap
  local b = W.env.WoWBoxerMinimapButton
  H.ok(b ~= nil and b:IsShown(), "minimap button created at login")
  b._scripts.OnClick(b, "LeftButton")
  H.ok(ns.UI.frame and ns.UI.frame:IsShown(), "left-click opens the window")
  b._scripts.OnClick(b, "LeftButton")
  H.ok(not ns.UI.frame:IsShown(), "left-click again closes it")
  b._scripts.OnClick(b, "RightButton")
  H.ok(MM.menu and MM.menu:IsShown(), "right-click opens the menu")
  findButton(W, "Close")
  -- drag: cursor straight above the minimap centre -> 90 degrees
  W.cursorPos = { 500, 600 }
  b._scripts.OnDragStart(b)
  b._scripts.OnUpdate(b)
  b._scripts.OnDragStop(b)
  H.eq(ns.Core.db.settings.minimapAngle, 90, "drag saves the angle")
  H.eq(rawget(b, "_scripts").OnUpdate, nil, "drag stops updating")
  -- hide from the menu, bring back with /wbx minimap
  MM.SetHidden(true)
  H.ok(not b:IsShown() and ns.Core.db.settings.minimapHidden, "hidden")
  W.env.SlashCmdList.WOWBOXER("minimap")
  H.ok(b:IsShown() and not ns.Core.db.settings.minimapHidden, "/wbx minimap shows it again")
  -- addon compartment
  H.ok(type(W.env.WoWBoxer_OnAddonCompartmentClick) == "function", "compartment click handler")
  W.env.WoWBoxer_OnAddonCompartmentClick("WoWBoxer", "LeftButton")
  H.ok(ns.UI.frame:IsShown(), "compartment opens the window")
  W.env.WoWBoxer_OnAddonCompartmentEnter("WoWBoxer", b)
  W.env.WoWBoxer_OnAddonCompartmentLeave("WoWBoxer", b)
  H.eq(W.calls.CreateMacro, nil, "minimap and compartment write nothing")
  local toc = H.readFile(H.root .. "/WoWBoxer/WoWBoxer.toc")
  H.ok(toc:find("## AddonCompartmentFunc: WoWBoxer_OnAddonCompartmentClick", 1, true) ~= nil, "TOC registers the compartment")
  ns.State.quickStart(ns.Core.db, ns.Core.cdb, ns.Core.playerInfo())
  ns.Core.sync({})
  W.player.level = 40
  for _, sp in ipairs(ns.Data.spells.priest) do if sp.level <= 40 and sp.gate ~= "talent" then W.known[sp.name] = true end end
  W.fire("PLAYER_LEVEL_UP", 40)
  W.flush()
  H.ok(ns.Core.compute().macros.changes > 0, "keys changed at level 40")
  H.ok(b.dot:IsShown(), "level-up marks the minimap button")
  ns.Core.sync({})
  H.ok(not b.dot:IsShown(), "update clears the mark")
  H.eq(#errors(ns), 0, "no errors (minimap): " .. table.concat(errors(ns), " | "))
end

-- ------------------------------------------------------------------ drag & drop, remembered positions
do
  local W, ns = boot({ name = "Warlocker", class = "PRIEST", race = "Scourge", level = 20 })
  local Core, UI = ns.Core, ns.UI
  UI.Open("keys")
  local r = row(ns, function(x) return x.name == "WBX K1" end)
  H.ok(r ~= nil, "row for WBX K1")
  r._scripts.OnDragStart(r)
  H.eq(W.calls.CreateMacro, 1, "dragging creates just that macro")
  H.ok(W.cursor and W.cursor.kind == "macro" and W.cursor.ref.name == "WBX K1", "WBX K1 is on the cursor")
  W.env.PlaceAction(7)      -- the player drops it on button 7
  W.fire("ACTIONBAR_SLOT_CHANGED", 7)
  W.flush()
  H.eq(Core.cdb.slots["WBX K1"], 7, "the drop position is remembered")
  findButton(W, "Place all"):Click()
  H.eq(W.slotMacroName(7), "WBX K1", "Place all keeps K1 where it was dropped")
  local k1 = 0
  for slot = 1, 120 do if W.slotMacroName(slot) == "WBX K1" then k1 = k1 + 1 end end
  H.eq(k1, 1, "K1 is placed once")
  H.eq(Core.compute().macros.changes, 0, "everything created")
  -- dragging an existing, unchanged macro writes nothing new
  local before = (W.calls.CreateMacro or 0) + (W.calls.EditMacro or 0)
  r = row(ns, function(x) return x.name == "WBX K2" end)
  r._scripts.OnDragStart(r)
  H.eq((W.calls.CreateMacro or 0) + (W.calls.EditMacro or 0), before, "no write for an up-to-date key")
  H.ok(W.cursor and W.cursor.ref.name == "WBX K2", "K2 on the cursor")
  W.env.ClearCursor()
  -- a spell from the spell list becomes an extra key
  UI.tabButtons.spells:Click()
  local sr = row(ns, function(x) return x.kind == "spell" and not x.name and W.known[x.label] end)
  H.ok(sr ~= nil, "a learned spell without a key is listed")
  if sr then
    local spellName = sr.cell.label
    sr._scripts.OnDragStart(sr)
    H.ok(W.cursor and W.cursor.ref.name:sub(1, 4) == "WBX " and spellName:find(W.cursor.ref.name:sub(5), 1, true) == 1, "spell became a WBX key on the cursor: " .. tostring(W.cursor and W.cursor.ref.name))
    H.eq(#Core.cdb.extras, 1, "kept as an extra key for this character")
  end
  W.env.ClearCursor()
  -- not in combat
  W.combat = true
  UI.tabButtons.keys:Click()
  r = row(ns, function(x) return x.name == "WBX K3" end)
  local n = W.calls.CreateMacro
  if r then r._scripts.OnDragStart(r) end
  H.eq(W.calls.CreateMacro, n, "no macro written by a drag in combat")
  H.eq(W.cursor, nil, "nothing picked up in combat")
  local menu = ns.Book.menuFor(UI.panels.keys, { kind = "key", name = "WBX K3", label = "x" })
  H.eq(#menu, 1, "the right-click menu offers nothing in combat")
  W.combat = false
  -- right-click menu: Pick up, Bind key, Leave out / Use again
  local cell = row(ns, function(x) return x.name == "WBX K3" end)
  cell:Click("RightButton")
  local m = ns.Widgets.menuFrame
  H.ok(m and m:IsShown(), "right-click opens the menu")
  local labels = {}
  for _, b in ipairs(m.rows) do if b:IsShown() then labels[#labels + 1] = b.label._text end end
  H.eq(table.concat(labels, ", "), "Pick up, Set keybind…, Leave out, Edit macro… (Advanced mode), Copy…", "menu entries (Edit macro greyed in Standard)")
  m.rows[3]:Click()
  H.ok(Core.cdb.skip["WBX K3"], "Leave out from the menu")
  H.ok(row(ns, function(x) return x.name == "WBX K3" end).cell.st.off, "shown as left out (greyed)")
  ns.Book.menuFor(UI.panels.keys, row(ns, function(x) return x.name == "WBX K3" end).cell)[3][2]()
  H.eq(Core.cdb.skip["WBX K3"], nil, "Use again")
  H.eq(#errors(ns), 0, "no errors (drag): " .. table.concat(errors(ns), " | "))
end

-- ------------------------------------------------------------------ key bindings
do
  local W, ns = boot({ name = "Warlocker", class = "PRIEST", race = "Scourge", level = 20 })
  local Core, UI, KB = ns.Core, ns.UI, ns.Binds
  UI.Open("keys")
  findButton(W, "Place all"):Click()
  -- K1 sits on Action Bar 1 button 1, which is bound to "1"
  local keys = KB.keysFor("WBX K1", 1)
  H.eq(keys[1] and keys[1].key, "1", "K1 is pressed with 1 (its action button)")
  H.eq(KB.commandForSlot(61), "MULTIACTIONBAR1BUTTON1", "bottom-left bar command")
  H.eq(KB.commandForSlot(73), nil, "no fixed button for paged slots")
  H.eq(KB.short("CTRL-SHIFT-F"), "csF", "short labels")
  H.eq(KB.compose("F", true, false, true), "ALT-SHIFT-F", "modifier order")
  H.eq(KB.compose("LSHIFT", false, false, true), nil, "a modifier alone is not a key")
  local r = row(ns, function(x) return x.name == "WBX K2" end)
  r:Click("LeftButton")
  H.eq(UI.panels.keys.selected, "WBX K2", "click selects")
  findButton(W, "Set keybind"):Click()
  local cap = UI.panels.keys.capture
  H.ok(cap:IsShown(), "key capture open")
  cap._scripts.OnKeyDown(cap, "F")
  H.eq(W.bindings.F, "ASSISTTARGET", "a used key needs a second press")
  H.ok(cap:IsShown(), "still capturing")
  cap._scripts.OnKeyDown(cap, "F")
  H.eq(W.bindings.F, "MACRO WBX K2", "F bound to WBX K2")
  H.eq(W.bindingSet, 1, "the account-wide binding set is kept (SaveBindings(1), not switched to 2)")
  H.ok(W.chatHas("account%-wide"), "and the player is told once")
  H.ok(not cap:IsShown(), "capture closed")
  W.mods.shift = true
  findButton(W, "Set keybind"):Click()
  cap._scripts.OnKeyDown(cap, "LSHIFT")
  H.ok(cap:IsShown(), "shift alone keeps waiting")
  cap._scripts.OnKeyDown(cap, "G")
  W.mods.shift = false
  H.eq(W.bindings["SHIFT-G"], "MACRO WBX K2", "SHIFT-G bound")
  local list = KB.keysFor("WBX K2", 2)
  H.eq(#list, 3, "K2: F, SHIFT-G and its button key 2")
  UI.Refresh()
  H.ok((UI.panels.keys.detSub._text or ""):find("sG") ~= nil, "keys shown for the selected macro")
  local un
  for _, it in ipairs(ns.Book.menuFor(UI.panels.keys, row(ns, function(x) return x.name == "WBX K2" end).cell)) do if it[1] == "Remove keybind" then un = it[2] end end
  H.ok(un ~= nil, "Unbind in the right-click menu")
  un()
  H.eq(W.bindings.F, "ASSISTTARGET", "Remove keybind puts back what F did before (Assist Target)")
  H.eq(W.bindings["SHIFT-G"], nil, "and SHIFT-G")
  H.eq(W.bindings["2"], "ACTIONBUTTON2", "the button key stays")
  -- escape cancels, combat queues
  findButton(W, "Set keybind"):Click()
  cap._scripts.OnKeyDown(cap, "ESCAPE")
  H.ok(not cap:IsShown(), "escape cancels")
  W.combat = true
  Core.bindKey("WBX K2", "H")
  H.eq(W.bindings.H, nil, "no binding in combat")
  W.combat = false
  W.fire("PLAYER_REGEN_ENABLED")
  H.eq(W.bindings.H, "MACRO WBX K2", "bound after combat")
  H.ok(not KB.bind("Heal me", "J"), "only WBX macros can be bound")
  W.env.QuickKeybindFrame = W.newFrame("Frame", "QuickKeybindFrame", W.env.UIParent); W.env.QuickKeybindFrame:Hide()
  W.env.ShowUIPanel = function(f) f:Show() end
  W.env.SlashCmdList.WOWBOXER("keys")
  H.ok(W.env.QuickKeybindFrame:IsShown(), "/wbx keys opens Quick Keybind mode")
  H.ok(not UI.frame:IsShown(), "and closes the WoWBoxer window")
  H.eq(#errors(ns), 0, "no errors (binds): " .. table.concat(errors(ns), " | "))
end

-- ------------------------------------------------------------------ the one-screen Squad page (docs/squad-v2-simple.md §2)
do
  local W, ns = boot({ name = "Dorin", class = "PALADIN", race = "Scourge", level = 10 })
  local Core, UI, SP = ns.Core, ns.UI, ns.SquadPages
  UI.Open("squad")
  local p = UI.panels.squad
  local f = p.frames.main
  local active = Core.db.active
  H.ok(f:IsShown() and f.empty:IsShown(), "solo: the empty state")
  H.ok(not f.empty.party:IsShown() and f.empty.byName:IsShown(), "solo, no party: only Add by name")
  H.ok(not p.more:IsShown() and not p.rename:IsShown(), "nothing else in the empty state")
  findButton(W, "Add by name"):Click()
  H.ok(f.list:IsShown() and f.add:IsShown(), "Add by name shows the list with the add line")
  -- add by name: needs a class; then saves at once and says so
  f.add.name:SetText("Wowtwo"); f.add.go:Click()
  local s = Core.me()
  H.eq(#s.members, 1, "no class picked: nothing added")
  H.ok((f.add.note:GetText() or ""):find("class") ~= nil, "and it says why: " .. tostring(f.add.note:GetText()))
  f.add.cls.select("priest"); f.add.go:Click()
  H.eq(#s.members, 2, "added by name")
  local added = s.members[2]
  H.ok(added.name == "Wowtwo" and added.cls == "priest" and not added.leader, "a priest follower")
  local raceOk = false
  for _, x in ipairs(ns.State.racesFor("priest")) do if x.k == added.race then raceOk = true end end
  H.ok(raceOk, "race: the first valid race")
  H.ok(p.saved:IsShown() and p.saved:GetText():find("Saved", 1, true) ~= nil, "Saved flashes")
  H.eq(f.pool.rows[2].follows:GetText(), "1st in line · follows Dorin", "the row says its place in the line and whom it follows")
  H.ok(f.pool.rows[1].me:IsShown() and not f.pool.rows[1].remove:IsShown(), "own row: This character, no remove")
  f.add.name:SetText("wowtwo"); f.add.go:Click()
  H.eq(#s.members, 2, "the same name twice is refused")
  f.add.name:SetText("Kirra-Silvermoon"); f.add.cls.select("warlock"); f.add.go:Click()
  local x = s.members[3]
  H.ok(x.name == "Kirra" and x.realm == "Silvermoon", "Name-Realm: the realm is kept for invites")
  -- role dropdown in the row, crown makes a leader
  local r2 = f.pool.rows[2]
  r2.role.select("healer")
  H.eq(added.role, "healer", "role from the row")
  r2.crown:Click()
  H.ok(added.leader and not select(2, Core.me()).leader, "the crown makes Wowtwo the leader")
  H.eq(f.pool.rows[1].follows:GetText(), "1st in line · follows Wowtwo", "and Dorin follows Wowtwo")
  f.pool.rows[1].crown:Click()
  H.ok(select(2, Core.me()).leader, "crown back to Dorin")
  -- inline editor
  r2:Click()
  H.ok(f.editor:IsShown(), "a click on a row opens the inline editor")
  f.editor.name:SetText("Wowtwoo"); f.editor.name._scripts.OnEnterPressed(f.editor.name)
  H.eq(added.name, "Wowtwoo", "renamed in the editor")
  f.editor.cls.select("warlock")
  H.ok(added.cls == "warlock" and added.role == "ranged", "class change keeps the role valid")
  f.editor.plays.select("party2")
  H.eq(added.unit, "party2", "follower unit from the editor")
  f.editor.seq.check:Click()
  H.eq(added.seq, "simple", "sequence keys in the editor")
  f.pool.rows[2]:Click()
  H.ok(not f.editor:IsShown(), "a second click closes it")
  -- remove + undo
  f.pool.rows[3].remove:Click()
  H.eq(#s.members, 2, "removed with one click")
  H.ok(p.undo:IsShown() and p.saved:GetText():find("Removed Kirra", 1, true), "Removed … Undo")
  p.undo:Click()
  H.eq(#s.members, 3, "Undo puts it back")
  H.eq(s.members[3].name, "Kirra", "in the same place")
  -- rename the squad
  p.rename:Click()
  H.ok(p.nameBox:IsShown(), "Rename shows a name box")
  p.nameBox:SetText("Undead trio"); p.nameBox._scripts.OnEnterPressed(p.nameBox)
  H.eq(s.name, "Undead trio", "renamed")
  -- More: presets page, everyone's sequence keys
  p.more.select("presets")
  H.ok(p.frames.presets:IsShown() and p.back:IsShown(), "More → Leader presets, with Back")
  p.frames.presets.allSeq.select("medium")
  local on = 0
  for _, m in ipairs(s.members) do if m.seq == "medium" then on = on + 1 end end
  H.eq(on, 3, "everyone's sequence keys (paladin + two warlocks)")
  p.back:Click()
  H.ok(p.frames.main:IsShown(), "Back to the squad")
  H.eq(Core.db.active, active, "no squad switch as a side effect")
  H.eq(ns.State.TEMPLATES, nil, "templates are gone")
  -- only the squad dropdown switches: New squad… / Delete squad…
  p.squadPick.select("new")
  local s2 = ns.State.activeSquad(Core.db)
  H.ok(s2 ~= s and #s2.members == 1 and s2.members[1].name == "Dorin" and s2.members[1].leader, "New squad starts with this character")
  H.eq(select(1, Core.me()), s2, "and this character uses it")
  p.squadPick.select("del")
  H.ok(p.confirm:IsShown(), "Delete asks first")
  p.confirm.no:Click()
  H.eq(#Core.db.squads, 2, "Cancel keeps it")
  p.squadPick.select("del"); p.confirm.yes:Click()
  H.eq(#Core.db.squads, 1, "deleted")
  H.eq(ns.State.activeSquad(Core.db), s, "the other squad is active again")
  H.eq(W.calls.CreateMacro, nil, "squad edits write nothing to the game")
  H.eq(#errors(ns), 0, "no errors (squad): " .. table.concat(errors(ns), " | "))
end

-- ------------------------------------------------------------------ Use my party, the party suggestion, race/level from the party
do
  local W, ns = boot({ name = "Dorin", class = "PALADIN", race = "Scourge", level = 10, party = { party1 = "Wowtwo", party2 = "Kirra" },
    partyInfo = { party1 = { class = "PRIEST", race = "Scourge", level = 11 }, party2 = { class = "WARLOCK", race = "Scourge", level = 9, realm = "Silvermoon" } } })
  local Core, UI, SP = ns.Core, ns.UI, ns.SquadPages
  UI.Open("squad")
  local p = UI.panels.squad
  local f = p.frames.main
  local active = Core.db.active
  H.ok(f.empty.party:IsShown() and f.empty.party:GetText() == "Use my party (2)", "empty state: Use my party (2)")
  -- add one by name first (race unknown), then the party fills it in
  findButton(W, "Add by name"):Click()
  f.add.name:SetText("Wowtwo"); f.add.cls.select("priest"); f.add.go:Click()
  local s = Core.me()
  H.eq(s.members[2].race, "undead", "a party member added by name gets its race from the game")
  H.ok(f.party:IsShown() and f.party:GetText() == "Add my party (1)", "Add my party (1)")
  -- Kirra runs WoWBoxer (team status) but is not in the squad: the suggestion
  ns.Team.peers["kirra"] = { level = 9, at = 0 }
  local origPeer = ns.Team.peer
  ns.Team.peer = function(n) return n:lower() == "kirra" and { level = 9 } or nil end
  UI.Refresh()
  H.ok(f.sugg:IsShown() and f.sugg:GetText():find("Kirra (Warlock) is in your party", 1, true), "suggestion: " .. tostring(f.sugg:GetText()))
  f.suggAdd:Click()
  H.eq(#s.members, 3, "the suggestion adds Kirra")
  H.eq(s.members[3].realm, "Silvermoon", "with the realm from the game")
  H.ok(not f.party:IsShown() and not f.sugg:IsShown(), "everyone is in: no party button, no suggestion")
  ns.Team.peer = origPeer
  H.ok(f.send:IsEnabled(), "Send to my other characters enabled in a party")
  H.eq(Core.db.active, active, "no squad switch")
  H.eq(#errors(ns), 0, "no errors (party page): " .. table.concat(errors(ns), " | "))
end

-- ------------------------------------------------------------------ bars for stance classes, warnings, plays as
do
  local W, ns = boot({ name = "Warry", class = "WARRIOR", race = "Orc", level = 12 })
  local Core, UI = ns.Core, ns.UI
  H.eq(Core.cdb.primaryBar, 61, "warrior keys start on Bottom Left (bar 1 is the stance page)")
  H.eq(Core.cdb.secondaryBar, 49, "other keys on Bottom Right")
  W.env.MultiBarBottomLeft = W.newFrame("Frame", "MultiBarBottomLeft", W.env.UIParent)
  W.env.MultiBarBottomLeft:Hide()
  UI.Open("keys")
  local step = function() return UI.panels.keys.stepText._text or "" end
  H.ok(step():find("hidden") ~= nil, "hidden bar explained: " .. step())
  H.ok(findButton(W, "Choose bars") ~= nil, "with a button that leads to the fix")
  W.env.MultiBarBottomLeft:Show()
  Core.cdb.primaryBar = 1
  W.env.GetBonusBarOffset = function() return 1 end
  UI.Refresh()
  H.ok(step():find("stance") ~= nil, "stance page on bar 1 explained")
  findButton(W, "Move macros"):Click()
  H.eq(Core.cdb.primaryBar, 61, "one click moves the keys to Bottom Left")
  W.env.GetBonusBarOffset = function() return 0 end
  UI.Refresh()
  H.ok(findButton(W, "Place all") ~= nil, "no warning when all is fine: the next step is placing the keys")
  -- plays as: a solo character becomes a follower via party2
  Core.setPlaysAs("party2")
  local s, m = Core.me()
  H.ok(not m.leader and m.unit == "party2", "follower via party2")
  H.eq(#s.members, 2, "a placeholder leader was added")
  H.ok(s.members[1].leader and s.members[1].name == "Leader", "placeholder leads")
  local ctx = Core.compute()
  local uses = false
  for _, d in ipairs(ctx.desired) do if d.body:find("party2target", 1, true) then uses = true end end
  H.ok(uses, "keys now assist party2's target")
  Core.setPlaysAs("leader")
  H.ok(select(2, Core.me()).leader, "back to leader")
  H.eq(#s.members, 2, "no second placeholder")
  -- checklist fix: leader is party3 here
  Core.setPlaysAs("party1")
  s.members[1].name = "Dorin"
  W.party = { party3 = "Dorin" }
  UI.Select("setup")
  local fix = findButton(W, "Use party3")
  H.ok(fix ~= nil, "checklist offers Use party3")
  if fix then fix:Click() end
  H.eq(select(2, Core.me()).unit, "party3", "fix switched the unit")
  -- window position + scale + slash commands
  UI.frame.GetPoint = function() return "TOPLEFT", nil, "TOPLEFT", 120.4, -80.6 end
  UI.frame._scripts.OnDragStop(UI.frame)
  H.eq(Core.cdb.window[3], 120, "window x saved (per character)")
  H.eq(Core.cdb.window[4], -81, "window y saved")
  W.env.SlashCmdList.WOWBOXER("scale 2")
  H.eq(Core.db.settings.scale, 1.3, "scale clamped")
  W.env.SlashCmdList.WOWBOXER("reset")
  H.eq(Core.cdb.window, nil, "reset clears the position")
  W.env.SlashCmdList.WOWBOXER("bars")
  H.ok(W.chatHas("WBX K1"), "/wbx bars lists the keys")
  H.eq(#errors(ns), 0, "no errors (warrior): " .. table.concat(errors(ns), " | "))
end

-- ------------------------------------------------------------------ performance: scans and computes are reused
do
  local W, ns = boot({ name = "Warlocker", class = "PRIEST", race = "Scourge", level = 20 })
  local C, Core, UI = ns.Compat, ns.Core, ns.UI
  local scans, computes = 0, 0
  local scan, fresh = C.scanSpellbook, Core.computeFresh
  C.scanSpellbook = function(...) scans = scans + 1; return scan(...) end
  Core.computeFresh = function(...) computes = computes + 1; return fresh(...) end
  UI.Open("keys")
  local s0, c0 = scans, computes
  for _ = 1, 5 do UI.Refresh() end
  H.eq(computes - c0, 5, "one plan per window refresh")
  UI.Select("setup")
  H.eq(computes - c0, 6, "setup tab + checklist share one plan")
  H.eq(scans, s0, "no spellbook rescan while nothing changed")
  W.fire("SPELLS_CHANGED")
  UI.Refresh()
  H.eq(scans, s0 + 1, "rescan after SPELLS_CHANGED")
  W.flush() -- login timers (offer check, diagnose) first
  W.fire("ACTIONBAR_SLOT_CHANGED", 1); W.fire("ACTIONBAR_SLOT_CHANGED", 2); W.fire("ACTIONBAR_SLOT_CHANGED", 3)
  local c1 = computes
  W.flush()
  H.ok(computes - c1 <= 1, "a burst of bar events refreshes once")
end

-- ------------------------------------------------------------------ talent read-back (Forever C_Traits, read-only)
do
  local W, ns = boot({ name = "Warlocker", class = "PRIEST", race = "Scourge", level = 20 })
  local Core, UI, K, C = ns.Core, ns.UI, ns.Kit, ns.Compat
  UI.Open("talents")
  local _, m = Core.me()
  local plan = K.plan(m)
  local T = K.tree("priest")
  local first = T.byKey[plan[1]]
  -- the client: first plan talent at 2 ranks, one talent the plan does not take yet, one name not in the data
  local offNode
  for _, n in ipairs(T.nodes) do
    local inPlan = false
    for i = 1, 11 do if plan[i] == n.k then inPlan = true end end
    if not inPlan and n.r == 1 then offNode = n; break end
  end
  local defs = { { name = first.n, rank = 2 }, { name = offNode.n, rank = 1 }, { name = "Brand New Talent", rank = 1 } }
  local calls = {}
  W.env.C_ClassTalents = { GetActiveConfigID = function() return 77 end }
  W.env.C_Traits = {
    GetConfigInfo = function(id) return id == 77 and { treeIDs = { 5 } } or nil end,
    GetTreeNodes = function() return { 1, 2, 3, 4 } end,
    GetNodeInfo = function(_, nodeID)
      local d = defs[nodeID]
      return { ranksPurchased = d and d.rank or 0, entryIDs = { nodeID * 10 } }
    end,
    GetEntryInfo = function(_, entryID) return { definitionID = entryID } end,
    GetDefinitionInfo = function(defID) return { overrideName = defs[defID / 10] and defs[defID / 10].name } end,
    PurchaseRank = function() calls.purchase = true end, CommitConfig = function() calls.commit = true end,
  }
  local ranks, src = C.talentRanks()
  H.eq(src, "C_Traits", "Forever talents read through C_Traits")
  H.eq(ranks[first.n], 2, "rank read")
  local st = K.talentStatus(m, ranks, 20)
  H.eq(st.spent, 3, "3 points matched to the data")
  H.eq(st.available, 11, "11 points at level 20")
  H.eq(#st.off, 1, "one talent off the plan")
  H.eq(st.off[1] and st.off[1].name, offNode.n, "the right one")
  H.eq(st.unknown[1], "Brand New Talent", "unknown names reported, not matched")
  H.ok(st.next ~= nil, "next point from the plan")
  UI.Refresh()
  local txt = UI.panels.talents.readback._text or ""
  H.ok(txt:find("3/11") and txt:find("Off plan"), "talents tab shows the read-back: " .. txt)
  H.ok(not calls.purchase and not calls.commit, "read-back never changes talents")
  W.flush()
  local d = Core.db.diag["Warlocker-Realm"]
  H.ok(d and d.talents and d.talents.source == "C_Traits" and d.talents.spent == 3, "diagnose records the read-back")
  H.eq(#errors(ns), 0, "no errors (talents): " .. table.concat(errors(ns), " | "))
end
do
  local W, ns = boot({ name = "Era", class = "PRIEST", race = "Scourge", level = 20, toc = 11509, spellbookStyle = "classic" })
  -- Classic Era has its own talent trees since 0.15: the read-back compares through GetTalentInfo
  W.env.GetNumTalentTabs = function() return 3 end
  W.env.GetNumTalents = function(t) return t == 2 and 1 or 0 end
  W.env.GetTalentInfo = function(t, i) return "Improved Renew", 136081, 1, 2, 2, 3 end
  ns.UI.Open("talents")
  local rb = ns.UI.panels.talents.readback._text or ""
  H.ok(rb:find("In game: 2/11", 1, true) ~= nil and not rb:find("Forever only", 1, true), "Era: read-back with Era's own trees: " .. rb)
end

-- ------------------------------------------------------------------ custom key editor
do
  local W, ns = boot({ name = "Kirra", class = "WARLOCK", race = "Scourge", level = 40 })
  local Core, UI, KE = ns.Core, ns.UI, ns.KeyEditor
  UI.Open("custom")
  H.ok(row(ns, function(c) return c.kind == "new" end) ~= nil, "a New own key button in the book")
  row(ns, function(c) return c.kind == "new" end):Click("LeftButton")
  local f = KE.frame
  H.ok(f and f:IsShown(), "editor opens")
  local function pick(name, btn)
    for _, r in ipairs(f.pickPool.rows) do if r:IsShown() and r.spell.name == name then (btn == "fill" and r.fill or r.add):Click(); return true end end
    return false
  end
  H.ok(pick("Corruption"), "Corruption in the picker")
  H.ok(pick("Immolate"), "Immolate in the picker")
  H.ok(pick("Shadow Bolt", "fill"), "Shadow Bolt as filler")
  -- drop a spell from the spellbook onto the strip (cursor info is data only)
  W.env.GetCursorInfo = function() return "spell", 12, "spell", 172 end
  local cs = W.env.C_Spell or {}
  cs.GetSpellName = function(id) return id == 172 and "Corruption" or nil end
  W.env.C_Spell = cs
  f.strip._scripts.OnReceiveDrag(f.strip)
  W.env.GetCursorInfo = function() return W.cursor and W.cursor.kind or nil end
  H.eq(#f.draft.steps, 3, "dropped spell added")
  f.stepBtns[3]:Click()
  H.eq(#f.draft.steps, 2, "click removes a step")
  H.ok((f.body._text or ""):find("/castsequence", 1, true) ~= nil, "preview shows the castsequence")
  H.ok((f.body._text or ""):find("/petattack", 1, true) ~= nil, "warlock key sends the pet")
  H.ok(#(f.body._text or "") <= 255, "within 255 characters")
  pick("Conflagrate")
  if f.draft.steps[3] == "Conflagrate" then H.ok((f.warnFull or ""):find("Immolate") ~= nil, "Conflagrate warning shown") ; f.stepBtns[3]:Click() end
  f.name:SetText("Dots"); f.name._scripts.OnTextChanged(f.name, true)
  ns.Advanced.ef.save:Click()
  local _, m = Core.me()
  H.eq(#m.customSeq, 1, "saved: " .. table.concat(W.chat, " / "):sub(-200))
  H.eq(m.customSeq[1].name, "Dots", "named")
  H.ok(not f:IsShown(), "editor closed")
  H.eq(W.calls.CreateMacro, nil, "saving writes nothing to the game")
  local ctx = Core.compute()
  local c1
  for _, d in ipairs(ctx.desired) do if d.name == "WBX C1" then c1 = d end end
  H.ok(c1 and c1.body:find("Corruption, Immolate, Shadow Bolt", 1, true), "WBX C1 planned: " .. tostring(c1 and c1.body))
  -- edit it from the details line
  H.eq(UI.panels.custom.selected, "WBX C1", "the saved key is selected")
  UI.Refresh()
  local c1cell = row(ns, function(c) return c.name == "WBX C1" end)
  H.ok(c1cell ~= nil, "own key in the book")
  c1cell:Click("LeftButton")
  H.eq(f.index, 1, "editing C1")
  f.draft.kind = "priority"; KE.Refresh()
  H.ok(not f.reset:IsShown(), "no reset option for a priority list")
  H.ok(ns.Advanced.ef:IsShown() and ns.Advanced.ef.section == "spells", "own macros open the Macro editor on its Spells section")
  ns.Advanced.ef.save:Click()
  H.eq(m.customSeq[1].kind, "priority", "kind changed")
  -- limits and delete
  for i = 2, 8 do KE.save(m, { name = "K" .. i, kind = "sequence", aim = "harm", steps = { "Immolate" }, filler = "Shadow Bolt", fills = 1, reset = "combat" }) end
  UI.Refresh()
  H.ok(row(ns, function(c) return c.kind == "new" end) == nil, "no New own key button at 8 keys")
  H.eq(select(1, KE.save(m, { name = "x", kind = "sequence", aim = "harm", steps = { "Immolate" }, filler = "", fills = 1, reset = "combat" })), nil, "9th key refused")
  row(ns, function(c) return c.name == "WBX C1" end):Click("LeftButton")
  findButton(W, "Delete macro"):Click()
  findButton(W, "Sure?"):Click()
  H.eq(#m.customSeq, 7, "deleted with two clicks")
  H.eq(#errors(ns), 0, "no errors (editor): " .. table.concat(errors(ns), " | "))
end

-- ------------------------------------------------------------------ team status between two clients (display only)
do
  local A, nsA = boot({ name = "Dorin", class = "PALADIN", race = "Scourge", level = 20, party = { party1 = "Wowtwo" } })
  local B, nsB = boot({ name = "Wowtwo", class = "PRIEST", race = "Scourge", level = 20, party = { party1 = "Dorin" } })
  -- same squad on both: Dorin leads, Wowtwo follows via party1
  local str
  do
    nsA.UI.Open("squad")
    local s = nsA.Core.me()
    table.insert(s.members, nsA.State.newMember({ name = "Wowtwo", cls = "priest", race = "undead", role = "healer", unit = "party1" }))
    str = nsA.Core.exportString()
    local res = nsB.Core.importString(str)
    nsB.Core.applyImport(res)
  end
  H.ok(A.prefixes.WBX1 and B.prefixes.WBX1, "prefix registered on both clients")
  local function deliver(from, to, fromName)
    for _, m in ipairs(from.sent) do to.fire("CHAT_MSG_ADDON", m.prefix, m.msg, m.chan, fromName .. "-Realm") end
    from.sent = {}
  end
  A.now, B.now = 100, 100
  local TA, TB = nsA.Team, nsB.Team
  H.ok(TA.active() and TB.active(), "active: grouped squad of two")
  -- leader targets a mob and fights; follower follows and has another target
  A.targetGUID, A.inCombatUnit = "Creature-0-1-2-3-111-AAAA", true
  B.targetGUID, B.inCombatUnit = "Creature-0-1-2-3-222-BBBB", true
  B.fire("AUTOFOLLOW_BEGIN", "Dorin")
  TA.send(true); TB.send(true)
  H.eq(#A.sent, 1, "one message from the leader")
  H.ok(A.sent[1].msg:match("^S|20|%d+|0|1|Creature"), "message format: " .. A.sent[1].msg)
  deliver(A, B, "Dorin"); deliver(B, A, "Wowtwo")
  local function flagsOf(ns, name)
    for _, r in ipairs(ns.Team.rows()) do if r.name == name then local t = {}; for _, f in ipairs(r.flags) do t[#t + 1] = f[1] end; return table.concat(t, ",") end end
  end
  H.eq(flagsOf(nsA, "Wowtwo"), "other target", "leader sees the follower on another target")
  B.targetGUID = A.targetGUID
  B.now = 102; TB.send()
  deliver(B, A, "Wowtwo")
  H.eq(flagsOf(nsA, "Wowtwo"), "", "same target: no problem")
  -- out of combat the follower stops following, mana drops
  B.inCombatUnit, A.inCombatUnit = false, false
  B.fire("AUTOFOLLOW_END")
  B.mana = 150
  B.now = 104; TB.send()
  deliver(B, A, "Wowtwo")
  H.eq(flagsOf(nsA, "Wowtwo"), "not following,low mana", "lost follow and low mana shown")
  -- throttle: a burst of changes sends at most one message per MIN_GAP
  B.now = 104.5
  B.targetGUID = "Creature-0-1-2-3-333-CCCC"; TB.send()
  H.eq(#B.sent, 0, "throttled within MIN_GAP")
  B.flush()
  local team = 0
  for _, m in ipairs(B.sent) do if m.prefix == "WBX1" and m.msg:sub(1, 2) == "S|" then team = team + 1 end end
  H.ok(team <= 1, "one coalesced message later")   -- status (S) only: the heartbeat's R/X and the relay's follow report are their own messages
  B.sent = {}
  -- unchanged state: nothing until the heartbeat
  B.now = 110; TB.send(); B.sent = {}
  B.now = 112; TB.send()
  H.eq(#B.sent, 0, "no resend of an unchanged state")
  B.now = 126; TB.send()
  H.eq(#B.sent, 1, "heartbeat resends after 15 s")
  -- stale: no signal after 40 s
  A.now = 200
  H.eq(flagsOf(nsA, "Wowtwo"), "no signal", "no signal when a client goes quiet")
  -- hostile/garbage messages are ignored
  A.fire("CHAT_MSG_ADDON", "WBX1", "S|20|50|0|0|/run x", "PARTY", "Wowtwo-Realm")
  A.fire("CHAT_MSG_ADDON", "WBX1", string.rep("x", 300), "PARTY", "Wowtwo-Realm")
  A.fire("CHAT_MSG_ADDON", "OTHER", "S|20|50|1|0|-", "PARTY", "Wowtwo-Realm")
  H.eq(flagsOf(nsA, "Wowtwo"), "no signal", "bad messages ignored")
  -- display only: receiving never writes macros, bindings, targets or CVars
  H.eq(A.calls.CreateMacro, nil, "no macro written by team status")
  H.eq(A.calls.SetBindingMacro, nil, "no binding")
  -- panel shows while grouped; /wbx team off silences it
  nsA.TeamFrame.Refresh()
  H.ok(nsA.TeamFrame.frame and nsA.TeamFrame.frame:IsShown(), "team panel shown")
  A.env.SlashCmdList.WOWBOXER("team off")
  H.ok(not nsA.TeamFrame.frame:IsShown(), "team off hides it")
  A.sent = {}
  A.now = 300; TA.send(true)
  H.eq(#A.sent, 0, "team off sends nothing")
  -- solo: nothing sent
  local S, nsS = boot({ name = "Solo", class = "MAGE", race = "Human", level = 20, faction = "Alliance" })
  nsS.UI.Open("keys")
  nsS.Team.send(true)
  H.eq(#S.sent, 0, "solo character sends nothing")
  H.eq(#errors(nsA) + #errors(nsB), 0, "no errors (team)")
end

-- ------------------------------------------------------------------ extra keys: unique, stable names
do
  local W, ns = boot({ name = "Pri", class = "PRIEST", race = "Scourge", level = 60 })
  for _, s in ipairs(ns.Data.spells.priest) do W.known[s.name] = true end
  W.fire("SPELLS_CHANGED")
  ns.UI.Open("keys")
  local pain, death
  for _, s in ipairs(ns.Data.spells.priest) do
    if s.name == "Shadow Word: Pain" then pain = s.id elseif s.name == "Shadow Word: Death" then death = s.id end
  end
  ns.Core.cdb.extras = { death, pain }
  local names, labels = {}, {}
  for _, d in ipairs(ns.Core.compute().desired) do
    H.ok(not names[d.name], "unique macro name " .. d.name); names[d.name] = d.label; labels[d.label] = d.name
    H.ok(#d.name <= 16, "name within 16 characters: " .. d.name)
  end
  H.eq(labels["Shadow Word: Death"], "WBX Shadow Word:", "first extra keeps the plain name")
  H.eq(labels["Shadow Word: Pain"], "WBX Shadow Word2", "second gets a digit")
  -- the names do not swap when the first spell is not learned yet (low level)
  local _, m = ns.Core.me()
  local low = ns.Macros.desired(m, 10, { extras = ns.Core.cdb.extras })
  for _, d in ipairs(low) do if d.label == "Shadow Word: Pain" then H.eq(d.name, "WBX Shadow Word2", "stable name at a lower level") end end
end

-- ------------------------------------------------------------------ layout audit (read-only measurements)
do
  local W, ns = boot({ name = "Warlocker", class = "PRIEST", race = "Scourge", level = 20 })
  ns.UI.Toggle()
  local keep = ns.UI.current
  -- a one-line label that is far too long for its width
  local p = ns.UI.panels.keys
  local long = "Visit your trainer: " .. string.rep("Greater Heal, ", 40)
  local orig = p.stepText.SetText
  p.stepText.SetText = function(self) orig(self, long) end
  W.flush()
  local d = ns.Core.db.diag["Warlocker-Realm"]
  H.ok(d and d.layout, "audit ran after the first open")
  local found = false
  for _, it in ipairs(d and d.layout and d.layout.items or {}) do if it.kind == "cut" and it.text:find("Visit your trainer") then found = true end end
  H.ok(found, "cut-off label reported")
  H.eq(ns.UI.current, keep, "the player's tab is restored")
  H.eq(W.calls.CreateMacro, nil, "audit changes nothing")
  W.env.SlashCmdList.WOWBOXER("audit")
  H.ok(W.chatHas("Layout audit"), "/wbx audit reports")
end

-- ------------------------------------------------------------------ square minimap, welcome line once
do
  local W, ns = boot({ name = "Sq", class = "MAGE", race = "Human", level = 10, faction = "Alliance" })
  H.ok(W.chatHas("Type .*/wbx"), "welcome line on first login")
  local n = #W.chat
  W.fire("PLAYER_LOGIN")
  local again = 0
  for i = n + 1, #W.chat do if W.chat[i]:find("Type") then again = again + 1 end end
  H.eq(again, 0, "welcome only once per character")
  W.env.GetMinimapShape = function() return "SQUARE" end
  local placed
  ns.Minimap.button.SetPoint = function(_, _, _, _, x, y) placed = { x, y } end
  ns.Core.db.settings.minimapAngle = 45
  ns.Minimap.Place()
  H.ok(placed and math.abs(placed[1] - placed[2]) < 0.01 and placed[1] > 70, "square minimap: corner at 45 degrees")
  ns.Core.db.settings.minimapAngle = 0
  ns.Minimap.Place()
  H.ok(math.abs(placed[2]) < 0.01 and math.abs(placed[1] - 72) < 0.01, "square minimap: right edge at 0 degrees")
end


-- ------------------------------------------------------------------ fly to the bar (purely visual)
do
  local W, ns = boot({ name = "Warlocker", class = "PRIEST", race = "Scourge", level = 20 })
  local Core, UI, Fly = ns.Core, ns.UI, ns.Fly
  -- Blizzard's action buttons along the bottom of the screen
  for i = 1, 12 do
    local b = W.newFrame("Button", "ActionButton" .. i, W.env.UIParent)
    b:SetSize(36, 36); b:SetPoint("BOTTOMLEFT", W.env.UIParent, "BOTTOMLEFT", 300 + i * 40, 20)
    local m = W.newFrame("Button", "MultiBarBottomLeftButton" .. i, W.env.UIParent)
    m:SetSize(36, 36); m:SetPoint("BOTTOMLEFT", W.env.UIParent, "BOTTOMLEFT", 300 + i * 40, 60)
  end
  H.eq(Fly.buttonForSlot(3), W.env.ActionButton3, "slot 3 -> ActionButton3")
  H.eq(Fly.buttonForSlot(63), W.env.MultiBarBottomLeftButton3, "slot 63 -> Bottom Left button 3")
  H.eq(Fly.buttonForSlot(27), nil, "no button for a bar that does not exist")
  W.env.GetBonusBarOffset = function() return 1 end
  H.eq(Fly.buttonForSlot(3), nil, "bar 1 on a stance page does not show slot 3")
  H.eq(Fly.buttonForSlot(75), W.env.ActionButton3, "stance page 1: slot 75 -> ActionButton3")
  W.env.GetBonusBarOffset = function() return 0 end
  UI.Open("keys")
  local writes = W.calls.PlaceAction or 0
  findButton(W, "Place all"):Click()
  local placed = (W.calls.PlaceAction or 0) - writes
  W.flush() -- staggered starts
  H.ok(placed > 0, "keys placed")
  H.eq(Fly.flights, placed, "every placed key flies to its button")
  local move
  for _, ag in ipairs(W.playing) do
    for _, a in ipairs(ag._children or {}) do if a._animKind == "Translation" and not move then move = a end end
  end
  H.ok(move and move._offset and move._offset[2] < 0, "the icon flies down to the bar")
  local before = W.calls.PlaceAction
  W.finishAnims()
  H.eq(Fly.flashes, placed, "each button flashes when its icon arrives")
  W.finishAnims()
  H.eq(W.calls.PlaceAction, before, "the animation writes nothing")
  -- level-up: updated keys fly to the buttons they are already on
  W.player.level = 40
  for _, sp in ipairs(ns.Data.spells.priest) do if sp.level <= 40 and sp.gate ~= "talent" then W.known[sp.name] = true end end
  W.fire("PLAYER_LEVEL_UP", 40); W.fire("SPELLS_CHANGED"); W.flush()
  local n0, changes = Fly.flights, Core.compute().macros.changes
  H.ok(changes > 0, "keys changed at 40")
  Core.sync({}); W.flush()
  H.ok(Fly.flights > n0, "updated keys fly too")
  -- bar addon: Blizzard's buttons hidden -> no flight, still placed
  for i = 1, 12 do W.env["ActionButton" .. i]:Hide() end
  Core.cdb.slots = {}
  for slot = 1, 12 do W.actions[slot] = nil end
  local n1 = Fly.flights
  Core.sync({}); W.flush()
  H.eq(Fly.flights, n1, "no visible button, no flight")
  H.ok(W.slotMacroName(1) ~= nil, "keys are placed anyway")
  -- off in the settings
  for i = 1, 12 do W.env["ActionButton" .. i]:Show() end
  Core.db.settings.animations = false
  H.eq(Fly.play({ { slot = 1, icon = "Spell_Holy_Heal" } }), 0, "animations off")
  H.eq(#errors(ns), 0, "no errors (fly): " .. table.concat(errors(ns), " | "))
end

-- ------------------------------------------------------------------ future spells: listed after the known ones, locked, placeable
do
  local W, ns = boot({ name = "Futuretester", class = "PRIEST", race = "Scourge", level = 20 })
  local Core, UI = ns.Core, ns.UI
  UI.Open("spells")
  local p = UI.panels.spells
  local secs = ns.Book.spellSections(Core.compute())
  H.ok(#secs[2].cells > 0, "future spells listed")
  for _, c in ipairs(secs[2].cells) do
    H.ok(type(c.pending) == "number" and c.pending > 20, "future spell unlocks above 20: " .. c.label)
    H.ok(c.st.locked, "future spell is locked: " .. c.label)
  end
  for i = 2, #secs[2].cells do H.ok(secs[2].cells[i].pending >= secs[2].cells[i - 1].pending, "sorted by unlock level") end
  -- a spell of level <= 20 not in the spellbook: at your trainer, greyed but not locked
  local trainer
  for _, s in ipairs(ns.Data.spells.priest) do if s.level <= 20 and s.gate == "trainer" and s.action ~= "passive" then trainer = s end end
  W.known[trainer.name] = nil; W.fire("SPELLS_CHANGED"); W.flush()
  secs = ns.Book.spellSections(Core.compute())
  local tc
  for _, c in ipairs(secs[1].cells) do if c.spell == trainer then tc = c end end
  H.ok(tc and tc.pending == "trainer" and tc.st.off and not tc.st.locked, "a trainer spell is grey, without a lock")
  H.eq(tc and tc.sub, "At your trainer", "trainer note")
  -- no switch: the future spells follow under a "Future spells" rule; paging on reaches them
  local function ruleShown()
    for _, rr in ipairs(p.rules) do if rr:IsShown() and rr.text:GetText() == "Future spells" then return true end end
  end
  local r, sawRule
  for _ = 1, 20 do
    sawRule = sawRule or ruleShown()
    r = row(ns, function(x) return x.future and not x.name end)
    if r then break end
    p.next:Click()
  end
  H.ok(sawRule, "a Future spells rule divides the known spells from the later ones")
  H.ok(r ~= nil and r.lock:IsShown(), "a locked future spell is on the page")
  H.ok(r ~= nil and r.lock:IsShown(), "a locked future spell is on the page")
  -- drag it: the key is made now, with the spell's picture instead of "?"
  local fs = r.cell.spell
  r._scripts.OnDragStart(r)
  H.ok(W.cursor and W.cursor.kind == "macro", "future spell picked up as a WBX macro")
  local d
  for _, x in ipairs(Core.compute().desired) do if x.spell == fs then d = x end end
  H.ok(d and d.pending == r.cell.pending, "the extra key is pending")
  H.ok(d and d.icon ~= ns.Macros.ICON, "pending key has the spell's picture")
  H.ok(d and d.body:find(fs.name, 1, true), "the macro casts the spell")
  W.env.PlaceAction(30); W.fire("ACTIONBAR_SLOT_CHANGED", 30); W.flush()
  -- it shows on My keys as locked too
  UI.Open("keys")
  local kr
  for _, c in ipairs(ns.Book.cells("keys", Core.compute())) do if c.name == d.name then kr = c end end
  H.ok(kr and kr.st.locked and kr.sub:find("Unlocks at", 1, true), "locked on My keys: " .. tostring(kr and kr.sub))
  -- level up and learn it: same macro, nothing to update
  W.player.level = 60
  W.known[fs.name] = true
  W.fire("PLAYER_LEVEL_UP", 60); W.fire("SPELLS_CHANGED"); W.flush()
  local it
  for _, x in ipairs(Core.compute().macros.items) do if x.name == d.name then it = x end end
  H.eq(it and it.status, "same", "learned: the placed key needs no update")
  H.eq(W.slotMacroName(30), d.name, "still on the button it was dropped on")
  H.eq(#errors(ns), 0, "no errors (future spells): " .. table.concat(errors(ns), " | "))
end

-- All spells: search, "New at <level>", ranks in the tooltip
do
  local W, ns = boot({ name = "Dorin", class = "PALADIN", race = "Scourge", level = 10 })
  local UI, Book = ns.UI, ns.Book
  ns.Core.cdb.guide = "done"
  UI.Open("spells")
  local p = UI.panels.spells
  local all = #p.cells
  p.search:SetText("holy"); p.search._scripts.OnTextChanged(p.search)
  local names = {}
  for _, b in ipairs(p.cells) do if b:IsShown() and b.cell then names[#names + 1] = b.cell.label end end
  H.ok(#names > 0 and #names < all, "search narrows the list (" .. #names .. " of " .. all .. ")")
  for _, n in ipairs(names) do H.ok(n:lower():find("holy", 1, true) ~= nil, "match: " .. n) end
  p.search:SetText("zzzz"); p.search._scripts.OnTextChanged(p.search)
  H.eq(p.empty:GetText(), "No spell matches", "nothing found: says so")
  p.search:SetText(""); p.search._scripts.OnTextChanged(p.search)
  local devo
  for _, s in ipairs(ns.Data.spells.paladin) do if s.name == "Devotion Aura" then devo = s end end
  H.ok(Book.newAt(devo, 10), "Devotion Aura rank 2 is new at 10")
  H.eq(Book.rankLine(devo, 10), "Rank 2 of 7 · next rank at 20", "ranks in the tooltip")
  local newCell
  for _, sec in ipairs(Book.spellSections(ns.Core.compute())) do for _, c in ipairs(sec.cells) do if c.label == "Devotion Aura" then newCell = c end end end
  H.ok(newCell and newCell.sub:find("New at 10", 1, true), "All spells marks it: " .. tostring(newCell and newCell.sub))
  H.eq(#errors(ns), 0, "no errors (spell search)")
end

-- Place spells (left page) and Place squad keys (right page): each only its own page's keys
do
  local W, ns = boot({ name = "Lock", class = "WARLOCK", race = "Scourge", level = 20, party = { party1 = "Dorin" } })
  local Core, UI = ns.Core, ns.UI
  Core.cdb.guide = "done"
  UI.Open("keys")
  local s = Core.me()
  table.insert(s.members, 1, ns.State.newMember({ name = "Dorin", cls = "paladin", race = "undead", role = "tank", leader = true }))
  for _, m in ipairs(s.members) do m.leader = m.name == "Dorin" end
  Core.changed()
  local p = UI.panels.keys
  H.ok(p.placeLeft:IsVisible() and p.placeLeft:IsEnabled(), "Place spells on the left page")
  H.ok(p.placeRight:IsVisible() and p.placeRight:IsEnabled(), "Place squad keys on the right page")
  local M = ns.Macros
  W.combat = true
  p.placeLeft:Click()
  H.eq(M.findIndex("WBX K1"), nil, "never in combat")
  W.combat = false; W.fire("PLAYER_REGEN_ENABLED")
  H.ok(M.findIndex("WBX K1") ~= nil and W.slotMacroName(1) == "WBX K1", "after combat: spells placed")
  H.eq(M.findIndex("WBX Follow"), nil, "squad keys untouched by Place spells")
  H.ok(not p.placeLeft:IsEnabled(), "nothing left to place on the left page")
  W.env.PickupAction(73) -- an empty slot: harmless
  Core.cdb.offBars["WBX Pet"] = true
  p.placeRight:Click()
  H.ok(M.findIndex("WBX Follow") ~= nil and W.slotMacroName(11) == "WBX Follow", "Place squad keys: Follow on its button")
  local onBar = false
  for slot = 1, 120 do if W.slotMacroName(slot) == "WBX Pet" then onBar = true end end
  H.ok(not onBar, "a key kept off the bars is skipped")
  H.eq(#errors(ns), 0, "no errors (place per page)")
end

-- Bind key (docs/feedback-2026-10-29-evening.md §3): a key of an action button is not a conflict; plain words only
do
  local W, ns = boot({ name = "Lock", class = "WARLOCK", race = "Scourge", level = 20,
    bindings = { ["1"] = "ACTIONBUTTON1", ["2"] = "ACTIONBUTTON2", ["4"] = "ACTIONBUTTON4", ["5"] = "ACTIONBUTTON5", ["B"] = "OPENALLBAGS", ["Q"] = "ACTIONBUTTON9" } })
  local Core, UI, KB = ns.Core, ns.UI, ns.Binds
  W.env.GetBindingText = function(cmd) return ({ OPENALLBAGS = "Open All Bags" })[cmd] or cmd end
  Core.cdb.guide = "done"
  UI.Open("keys")
  local cap = UI.panels.keys.capture
  local function texts() return (cap.text:GetText() or "") .. " " .. (cap.yes:IsShown() and cap.yes:GetText() or "") .. " " .. (cap.no:IsShown() and cap.no:GetText() or "") end
  local function noRaw(what) H.ok(not texts():find("ACTIONBUTTON", 1, true) and not texts():find("OPENALLBAGS", 1, true), what .. ": no command names: " .. texts()) end
  -- regression: key 4 belongs to the empty action button 4 -> the key goes onto that button, no warning
  H.eq(W.slotMacroName(4), nil, "button 4 is empty")
  cap:Start("WBX K2", "Key 2")
  cap._scripts.OnKeyDown(cap, "4")
  H.ok(not cap:IsShown(), "empty action button: no question")
  H.eq(W.slotMacroName(4), "WBX K2", "regression: key 4 of an empty button puts the key on button 4")
  H.eq(W.bindings["4"], "ACTIONBUTTON4", "the game binding is not touched")
  -- the same key already there
  cap:Start("WBX K2", "Key 2")
  cap._scripts.OnKeyDown(cap, "4")
  H.ok(cap:IsShown() and cap.text:GetText():find("Already on", 1, true), "same key there: Already on 4")
  noRaw("already on")
  cap:Stop()
  -- the button holds something else: a plain question with what it holds
  W.actions[5] = { kind = "spell", id = 686 }
  W.env.C_Spell = W.env.C_Spell or {}
  local origName = W.env.C_Spell.GetSpellName
  W.env.C_Spell.GetSpellName = function(id) if id == 686 then return "Shadow Bolt" end return origName and origName(id) end
  cap:Start("WBX K2", "Key 2")
  cap._scripts.OnKeyDown(cap, "5")
  H.ok(cap:IsShown() and cap.text:GetText():find("is action button 5 (Shadow Bolt)", 1, true), "holds something else: " .. texts())
  H.eq(cap.yes:GetText(), "Put it there", "button: Put it there")
  H.eq(cap.no:GetText(), "Another keybind", "or Another keybind")
  noRaw("button question")
  cap.no:Click()
  H.ok(cap:IsShown() and not cap.yes:IsShown(), "Another key: waits again")
  H.eq(W.actions[5].kind, "spell", "nothing changed")
  cap._scripts.OnKeyDown(cap, "5"); cap.yes:Click()
  H.eq(W.slotMacroName(5), "WBX K2", "Put it there: on button 5")
  -- another game binding: the game's own name, Yes/No, then the binding
  cap:Start("WBX K3", "Key 3")
  cap._scripts.OnKeyDown(cap, "B")
  H.ok(cap.text:GetText():find("\"Open All Bags\"", 1, true) and cap.yes:GetText() == "Yes" and cap.no:GetText() == "No", "other binding: " .. texts())
  noRaw("other binding")
  H.eq(W.bindings.B, "OPENALLBAGS", "not bound before Yes")
  cap.yes:Click()
  H.eq(W.bindings.B, "MACRO WBX K3", "Yes binds it")
  -- an unbound key: bound at once
  cap:Start("WBX K3", "Key 3")
  cap._scripts.OnKeyDown(cap, "J")
  H.ok(not cap:IsShown() and W.bindings.J == "MACRO WBX K3", "unbound key: bound directly")
  H.eq(KB.bindingText("ACTIONBUTTON4"), "another game function", "a raw command never shows")
  H.eq(KB.slotForCommand("MULTIACTIONBAR1BUTTON2"), 62, "bottom left button 2 = slot 62")
  -- in combat: nothing is placed
  W.combat = true
  cap:Start("WBX K1", "Key 1")
  W.actions[6] = nil; W.bindings["6"] = "ACTIONBUTTON6"
  cap._scripts.OnKeyDown(cap, "6")
  H.eq(W.slotMacroName(6), nil, "never in combat")
  W.combat = false; W.fire("PLAYER_REGEN_ENABLED")
  H.eq(W.slotMacroName(6), "WBX K1", "placed after combat")
  H.eq(#errors(ns), 0, "no errors (bind key)")
end

-- keybinds (docs/feedback-2026-10-29-late.md §1): bindPrev, Remove keybind restores, the 0.9.4 "3 → MACRO WBX K2" repair
do
  local W, ns = boot({ name = "Boxtester", class = "WARLOCK", race = "Scourge", level = 20,
    bindings = { ["1"] = "ACTIONBUTTON1", ["2"] = "ACTIONBUTTON2", ["3"] = "MACRO WBX K2", ["4"] = "ACTIONBUTTON4", ["J"] = "TOGGLEBAG1" } })
  local Core, UI, KB = ns.Core, ns.UI, ns.Binds
  Core.cdb.guide = "done"
  UI.Open("keys")
  Core.sync({})
  -- The owner's Classic Era character: bindings-cache.wtf has "bind 3 MACRO WBX K2" (bound with 0.9.4)
  local lost = KB.lostButtons()
  H.ok(#lost == 1 and lost[1].key == "3" and lost[1].slot == 3 and lost[1].macro == "WBX K2", "detected: 3 presses WBX K2 directly")
  local step = ns.Book.nextStep(Core.compute(), "keys")
  H.ok(step.text:find("Your 3 presses WBX K2 directly", 1, true) and step.button[1] == "Give 3 back", "top line: " .. step.text)
  local fix
  for _, it in ipairs(ns.Checklist.items()) do if it.fix and it.fix.label == "Give back" then fix = it end end
  H.ok(fix and fix.hint:find("action button 3 has no keybind", 1, true), "checklist line + Give back")
  local d = Core.selftest(true)
  H.ok(d.binds and d.binds.direct[1] and d.binds.direct[1].key == "3" and d.binds.direct[1].macro == "WBX K2", "diagnose lists the direct WBX keybind")
  H.ok(d.buttons and d.buttons[3] and d.buttons[3].keys == "" and d.buttons[1].keys == "1", "diagnose snapshot: button 3 has no keybind, button 1 has 1")
  -- regression (the owner's Paladin, 30 Oct): binding another macro on 3 while 3 is the broken direct keybind = its button
  local k = KB.classify("WBX K3", "3")
  H.ok(k.kind == "button" and k.slot == 3 and k.broken, "a broken 1–= key counts as its action button, never other")
  -- the login popup: Fix now
  W.flush()
  local pop = UI.popup
  H.ok(pop and pop:IsShown() and pop.text:GetText():find("Key 3 presses a WoWBoxer macro directly, so action button 3 has no keybind.", 1, true), "login popup")
  H.eq(pop.btns[1]:GetText(), "Fix now", "Fix now")
  H.eq(W.bindings["3"], "MACRO WBX K2", "nothing before the click")
  pop.btns[1]:Click()
  H.eq(W.bindings["3"], "ACTIONBUTTON3", "Fix now: 3 presses button 3 again")
  W.bindings["3"] = "MACRO WBX K2"
  Core.cdb.bindPrev["3"] = "MACRO WBX K1" -- a second bind on the broken key remembered a WBX macro as "before"
  H.eq(#KB.lostButtons(), 1, "still counts as lost")
  KB.restoreKey("3")
  H.eq(W.bindings["3"], "ACTIONBUTTON3", "restore gives it to button 3, never to a WBX macro")
  W.bindings["3"] = "MACRO WBX K2"
  W.combat = true
  step.button[3]()
  H.eq(W.bindings["3"], "MACRO WBX K2", "never in combat")
  W.combat = false; W.fire("PLAYER_REGEN_ENABLED")
  H.eq(W.bindings["3"], "ACTIONBUTTON3", "Give 3 back to button 3")
  H.eq(W.bindingSet, 1, "saved in the set the character uses")
  H.eq(#KB.lostButtons(), 0, "nothing lost any more")
  -- bindPrev is stored on every bind, and Remove keybind puts it back
  Core.bindKey("WBX K1", "J")
  H.eq(W.bindings.J, "MACRO WBX K1", "J bound")
  H.eq(Core.cdb.bindPrev.J, "TOGGLEBAG1", "bindPrev remembers what J did")
  Core.unbindKey("WBX K1")
  H.eq(W.bindings.J, "TOGGLEBAG1", "Remove keybind: J opens the bag again")
  H.eq(Core.cdb.bindPrev.J, nil, "and forgets it")
  Core.bindKey("WBX K1", "K")
  H.eq(Core.cdb.bindPrev.K, "", "an unbound key remembers nothing")
  -- regression: a key of an action button is never rebound with SetBindingMacro
  local ok, why = KB.bind("WBX K1", "4")
  H.ok(not ok and why:find("action button 4", 1, true), "bind refuses a key of an action button: " .. tostring(why))
  H.eq(W.bindings["4"], "ACTIONBUTTON4", "4 still presses button 4")
  local cap = UI.panels.keys.capture
  W.actions[4] = { kind = "spell", id = 686 }
  local calls = W.calls.SetBindingMacro or 0
  cap:Start("WBX K1", "Key 1")
  cap._scripts.OnKeyDown(cap, "4")
  H.ok(cap.yes:IsShown(), "pressing 4 on an occupied button asks")
  cap.yes:Click()
  H.eq(W.slotMacroName(4), "WBX K1", "Yes puts the macro on button 4 (placeOn)")
  H.eq(W.bindings["4"], "ACTIONBUTTON4", "and the keybind stays ACTIONBUTTON4")
  H.eq(W.calls.SetBindingMacro or 0, calls, "no SetBindingMacro for an action-button key")
  -- Reset to default puts every WoWBoxer keybind back
  Core.resetToDefault({ char = true })
  H.eq(W.bindings.K, nil, "Reset to default: K back to nothing")
  H.eq(#errors(ns), 0, "no errors (keybinds)")
end

-- the first-run guide restarts at step 1: minimap/compartment menu, right-click on "?", /wbx guide (§4)
do
  local W, ns = boot({ name = "Dorin", class = "PALADIN", race = "Scourge", level = 10 })
  local Core, UI = ns.Core, ns.UI
  UI.Open("keys"); Core.sync({})
  Core.cdb.guide = "done"
  UI.Refresh()
  local g = UI.panels.keys.guide
  H.ok(not g:IsShown(), "guide done and keys placed: hidden")
  local function restart(how, fn)
    Core.cdb.guide, Core.cdb.guideStep = "done", 3; UI.Select("setup"); UI.Refresh()
    fn()
    H.ok(UI.current == "keys" and g:IsShown() and g.title:GetText():find("^Step 1 of 4"), how .. ": the guide starts again at step 1")
  end
  restart("/wbx guide", function() W.env.SlashCmdList.WOWBOXER("guide") end)
  restart("? right-click", function() UI.helpBtn._scripts.OnClick(UI.helpBtn, "RightButton") end)
  local entry
  for _, it in ipairs(ns.Minimap.MENU or {}) do if it[1] == "First-run guide" then entry = it end end
  if entry then restart("minimap menu", function() entry[2]() end) end
  local lines = {}
  local GT = W.env.GameTooltip
  local old = GT.AddLine
  GT.AddLine = function(_, t) lines[#lines + 1] = t end
  UI.helpBtn._scripts.OnEnter(UI.helpBtn)
  GT.AddLine = old
  H.ok(table.concat(lines, "|"):find("Help for this page", 1, true) and table.concat(lines, "|"):find("Right-click: start the first-run guide again.", 1, true), "? tooltip says so")
end

-- Reset to default puts the bars back (cdb.barOriginal, §7) and lists what it could not restore
do
  local W, ns = boot({ name = "Dorin", class = "PALADIN", race = "Scourge", level = 10 })
  local Core, UI = ns.Core, ns.UI
  W.env.PickupSpell = function(id) W.cursor = { kind = "spell", id = id } end
  W.env.GetMacroIndexByName = function() return 0 end
  W.actions[1] = { kind = "spell", id = 635 } -- Holy Light was on button 1 before WoWBoxer
  W.actions[40] = { kind = "spell", id = 19740 }
  Core.cdb.guide = "done"
  UI.Open("keys")
  Core.scanBars()
  Core.cdb.replace = true
  Core.sync({ replace = true })
  H.ok((W.slotMacroName(1) or ""):find("^WBX"), "Place all (Replace) put a macro on button 1")
  H.eq(Core.cdb.barOriginal[1].kind, "spell", "button 1's spell was kept before the first change")
  H.eq(Core.cdb.barOriginal[2].kind, "empty", "an empty button is kept as empty")
  local first = Core.cdb.barOriginal[1].id
  Core.sync({ replace = true })
  H.eq(Core.cdb.barOriginal[1].id, first, "never overwritten")
  -- the player drags a macro onto button 40 (it held a spell): the watch keeps the spell
  Core.pickup("WBX K1"); W.env.PlaceAction(40); W.env.ClearCursor(); Core.scanBars()
  H.ok(Core.cdb.barOriginal[40] and Core.cdb.barOriginal[40].id == 19740, "drag-place: the spell on 40 is kept")
  -- a slot changed before this version (no copy)
  W.actions[30] = W.actions[1]
  Core.cdb.barOriginal[30] = nil
  local msg, report = Core.resetToDefault({ char = true, bars = true, macros = true, cvars = true })
  H.ok(W.actions[1] and W.actions[1].kind == "spell" and W.actions[1].id == 635, "Reset: button 1 has Holy Light again")
  H.eq(W.actions[2], nil, "Reset: button 2 is empty again")
  H.ok(W.actions[40] and W.actions[40].id == 19740, "Reset: button 40 has its spell again")
  H.ok(msg:find("Bottom", 1, true) == nil and msg:find("Right Bar button 6", 1, true) or msg:find("changed before WoWBoxer kept a copy", 1, true), "lists what it could not restore: " .. msg)
  H.ok(#report.failed >= 1, "the report has the failures")
  H.ok(Core.db.lastReset and Core.db.lastReset.failed[1], "the diagnose keeps what was and was not restored")
  local wbx = 0
  for _, x in ipairs(ns.Compat.characterMacros()) do if x.name:find("^WBX") then wbx = wbx + 1 end end
  H.eq(wbx, 0, "WBX macros deleted")
  H.ok(not ns.Auto.anyOn() and not Core.advanced(), "Automation and Advanced off")
  H.ok(UI.resetBtn and UI.resetBtn:IsShown(), "Reset is in the header on every page")
  UI.Select("talents"); UI.resetBtn:Click()
  H.ok(ns.Advanced.rf:IsShown() and ns.Advanced.rf.step == 1, "the header Reset opens the two-step window")
end

os.exit(H.report("features") and 0 or 1)
