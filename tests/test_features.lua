-- Single-character features in the simulated client: minimap button + compartment, drag & drop of keys and spells,
-- remembered bar positions, key bindings, squad edit. Run: lua tests/test_features.lua
local dir = (arg[0]:match("^(.*)/[^/]+$") or ".")
local H = dofile(dir .. "/harness.lua")
local Mock = dofile(dir .. "/wowmock.lua")

local function boot(opts)
  local W = Mock.new(H, opts)
  local ns = H.loadAddon({ env = W.env })
  W.fire("ADDON_LOADED", "WoWBoxer"); W.fire("PLAYER_LOGIN")
  for _, s in ipairs(ns.Data.spells[(opts.class or "PALADIN"):lower()]) do if s.level <= (opts.level or 10) and s.gate ~= "talent" then W.known[s.name] = true end end
  return W, ns
end
local function findButton(W, text)
  for _, f in ipairs(W.frames) do if f._kind == "Button" and rawget(f, "_text") == text and f:IsVisible() then return f end end
end
local function row(ns, pred)
  for _, r in ipairs(ns.UI.panels.keys.pool.rows) do if r:IsShown() and pred(r) then return r end end
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
  findButton(W, "Create & place keys"):Click()
  H.eq(W.slotMacroName(7), "WBX K1", "Create & place keeps K1 where it was dropped")
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
  findButton(W, "All spells"):Click()
  local sr = row(ns, function(x) return rawget(x, "spellId") and W.known[x.label._text] end)
  H.ok(sr ~= nil, "a learned spell without a key is listed")
  if sr then
    local spellName = sr.label._text
    sr._scripts.OnDragStart(sr)
    H.ok(W.cursor and W.cursor.ref.name:sub(1, 4) == "WBX " and spellName:find(W.cursor.ref.name:sub(5), 1, true) == 1, "spell became a WBX key on the cursor: " .. tostring(W.cursor and W.cursor.ref.name))
    H.eq(#Core.cdb.extras, 1, "kept as an extra key for this character")
  end
  W.env.ClearCursor()
  -- not in combat
  W.combat = true
  findButton(W, "My keys"):Click()
  r = row(ns, function(x) return x.name == "WBX K3" end)
  local n = W.calls.CreateMacro
  if r then r._scripts.OnDragStart(r) end
  H.eq(W.calls.CreateMacro, n, "no macro written by a drag in combat")
  H.eq(W.cursor, nil, "nothing picked up in combat")
  W.combat = false
  H.eq(#errors(ns), 0, "no errors (drag): " .. table.concat(errors(ns), " | "))
end

-- ------------------------------------------------------------------ key bindings
do
  local W, ns = boot({ name = "Warlocker", class = "PRIEST", race = "Scourge", level = 20 })
  local Core, UI, KB = ns.Core, ns.UI, ns.Binds
  UI.Open("keys")
  findButton(W, "Create & place keys"):Click()
  -- K1 sits on Action Bar 1 button 1, which is bound to "1"
  local keys = KB.keysFor("WBX K1", 1)
  H.eq(keys[1] and keys[1].key, "1", "K1 is pressed with 1 (its action button)")
  H.eq(KB.commandForSlot(61), "MULTIACTIONBAR1BUTTON1", "bottom-left bar command")
  H.eq(KB.commandForSlot(73), nil, "no fixed button for paged slots")
  H.eq(KB.short("CTRL-SHIFT-F"), "csF", "short labels")
  H.eq(KB.compose("F", true, false, true), "ALT-SHIFT-F", "modifier order")
  H.eq(KB.compose("LSHIFT", false, false, true), nil, "a modifier alone is not a key")
  local r = row(ns, function(x) return x.name == "WBX K2" end)
  r._scripts.OnClick(r)
  H.eq(UI.panels.keys.selected, "WBX K2", "row click selects")
  findButton(W, "Bind key"):Click()
  local cap = UI.panels.keys.capture
  H.ok(cap:IsShown(), "key capture open")
  cap._scripts.OnKeyDown(cap, "F")
  H.eq(W.bindings.F, "ASSISTTARGET", "a used key needs a second press")
  H.ok(cap:IsShown(), "still capturing")
  cap._scripts.OnKeyDown(cap, "F")
  H.eq(W.bindings.F, "MACRO WBX K2", "F bound to WBX K2")
  H.eq(W.bindingSet, 2, "saved as character bindings")
  H.ok(not cap:IsShown(), "capture closed")
  W.mods.shift = true
  findButton(W, "Bind key"):Click()
  cap._scripts.OnKeyDown(cap, "LSHIFT")
  H.ok(cap:IsShown(), "shift alone keeps waiting")
  cap._scripts.OnKeyDown(cap, "G")
  W.mods.shift = false
  H.eq(W.bindings["SHIFT-G"], "MACRO WBX K2", "SHIFT-G bound")
  local list = KB.keysFor("WBX K2", 2)
  H.eq(#list, 3, "K2: F, SHIFT-G and its button key 2")
  UI.Refresh()
  H.ok((UI.panels.keys.keysLine._text or ""):find("sG") ~= nil, "keys shown for the selected macro")
  findButton(W, "Unbind"):Click()
  H.eq(W.bindings.F, nil, "unbind removes F")
  H.eq(W.bindings["SHIFT-G"], nil, "and SHIFT-G")
  H.eq(W.bindings["2"], "ACTIONBUTTON2", "the button key stays")
  -- escape cancels, combat queues
  findButton(W, "Bind key"):Click()
  cap._scripts.OnKeyDown(cap, "ESCAPE")
  H.ok(not cap:IsShown(), "escape cancels")
  W.combat = true
  Core.bindKey("WBX K2", "H")
  H.eq(W.bindings.H, nil, "no binding in combat")
  W.combat = false
  W.fire("PLAYER_REGEN_ENABLED")
  H.eq(W.bindings.H, "MACRO WBX K2", "bound after combat")
  H.ok(not KB.bind("Heal me", "J"), "only WBX macros can be bound")
  H.eq(#errors(ns), 0, "no errors (binds): " .. table.concat(errors(ns), " | "))
end

-- ------------------------------------------------------------------ squad basics: edit
do
  local W, ns = boot({ name = "Dorin", class = "PALADIN", race = "Scourge", level = 10 })
  local Core, UI = ns.Core, ns.UI
  UI.Open("squad")
  local p = UI.panels.squad
  p.newName:SetText("Wowtwo")
  findButton(W, "Add"):Click()
  local s = Core.me()
  local added = s.members[#s.members]
  H.eq(added.name, "Wowtwo", "added")
  H.ok(not added.leader, "the solo character stays leader")
  p.startEdit(added)
  H.eq(findButton(W, "Save") ~= nil, true, "edit mode")
  p.newName:SetText("Wowtwo2")
  p.add.cls, p.add.race, p.add.role = "warlock", "undead", "ranged"
  findButton(W, "Save"):Click()
  local edited = s.members[#s.members]
  H.eq(edited.name, "Wowtwo2", "renamed")
  H.eq(edited.cls, "warlock", "class changed")
  H.eq(edited.id, added.id, "same member id")
  H.ok(findButton(W, "Add") ~= nil, "back to add mode")
  H.eq(#errors(ns), 0, "no errors (squad): " .. table.concat(errors(ns), " | "))
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
  H.ok((UI.panels.keys.warn._text or ""):find("hidden") ~= nil, "hidden bar explained: " .. tostring(UI.panels.keys.warn._text))
  W.env.MultiBarBottomLeft:Show()
  Core.cdb.primaryBar = 1
  W.env.GetBonusBarOffset = function() return 1 end
  UI.Refresh()
  H.ok((UI.panels.keys.warn._text or ""):find("stance") ~= nil, "stance page on bar 1 explained")
  W.env.GetBonusBarOffset = function() return 0 end
  UI.Refresh()
  H.eq(UI.panels.keys.warn._text, "", "no warning when all is fine")
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
  H.eq(Core.db.settings.window[3], 120, "window x saved")
  H.eq(Core.db.settings.window[4], -81, "window y saved")
  W.env.SlashCmdList.WOWBOXER("scale 2")
  H.eq(Core.db.settings.scale, 1.3, "scale clamped")
  W.env.SlashCmdList.WOWBOXER("reset")
  H.eq(Core.db.settings.window, nil, "reset clears the position")
  W.env.SlashCmdList.WOWBOXER("bars")
  H.ok(W.chatHas("WBX K1"), "/wbx bars lists the keys")
  H.eq(#errors(ns), 0, "no errors (warrior): " .. table.concat(errors(ns), " | "))
end

os.exit(H.report("features") and 0 or 1)
