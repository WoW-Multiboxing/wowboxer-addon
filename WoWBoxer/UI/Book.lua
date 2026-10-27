--[[ WoWBoxer – the spellbook: My keys, All spells and Custom keys as book pages.
  Each page is a 2 x 6 grid of spell buttons (icon with the action-button border, name in gold, a plain second line).
  Drag a button onto an action bar: the WBX macro is created/updated first (out of combat), then picked up; the player
  drops it. Click selects (details + Bind key / Leave out under the pages), right-click or Shift-click opens a menu.
  On top, one "next step" line with the one button that does it. A 3-step guide on a fresh character. ]]
local _, ns = ...
local UI, W = ns.UI, ns.Widgets
local Book = {}
ns.Book = Book

local PER_PAGE, COLS, ROWS = 12, 2, 6
local CELL_W, CELL_H, PITCH = 158, 40, 46
local STRIP_H, OPT_Y, GRID_Y = 40, -48, -78
local function Core() return ns.Core end

-- ------------------------------------------------------------------ plain words
local KIND = { S1 = "Damage sequence", S2 = "Healing sequence" }
--- "Key 3", "Own key 2", "Damage sequence", "Helper", "Extra key"
function Book.kindName(it)
  local k = it.key or ""
  if k:match("^K%d$") then return "Key " .. k:sub(2) end
  if k:match("^C%d$") then return "Own key " .. k:sub(2) end
  if KIND[k] then return KIND[k] end
  if it.group == "helper" then return "Helper" end
  if it.group == "extra" then return "Extra key" end
  return k
end
Book.STATUS = {
  create = { "New", W.BLUE }, update = { "Changed", W.ORANGE }, noslot = { "No free macro slot", W.RED },
  invalid = { "Blocked", W.RED }, skipped = { "Left out", W.MUTED },
}
--- What a key does, in plain words, from its macro text.
function Book.describe(d, mem)
  if not d then return "" end
  if d.group == "sequence" or (d.group == "custom" and d.seq) then
    return "Each press casts the next spell of the " .. (d.label or "sequence") .. " – one spell per press."
  end
  if d.group == "helper" then return (d.label or "") .. "." end
  local body, spell = d.body or "", d.label or "the spell"
  local lead = body:match("@(%w+)target") -- the leader's unit when this character follows
  if body:find("help", 1, true) then
    return "Casts " .. spell .. " on the friend under your mouse, else " ..
      (body:match("@(party%d)") and ("the leader (" .. body:match("@(party%d)") .. ")") or "your friendly target") .. ", else yourself."
  elseif body:find("harm", 1, true) then
    return "Casts " .. spell .. " on the enemy under your mouse, else " ..
      (lead and ("the leader's target (" .. lead .. "target)") or "your target") .. "."
  end
  return "Casts " .. spell .. "."
end

--- Dropdown values: the roles of the member's class, and Leader / Follower via a unit.
function Book.roleValues(mem)
  local v = {}
  if mem then for _, r in ipairs(ns.Data.classes[mem.cls].roles) do v[#v + 1] = { r, ns.State.ROLE_NAME[r] } end end
  return v
end
function Book.playsAsValues()
  local v = { { "leader", "Leader", "This character leads: its keys use its own target." } }
  for _, u in ipairs(ns.Engine.UNITS) do
    v[#v + 1] = { u, "Follower (" .. u .. ")", "Its keys use the leader's target through " .. u .. " and heal the leader." }
  end
  return v
end
function Book.setRole(mem, v)
  if not mem then return end
  mem.role = v; mem.guide = ns.Kit.defaultGuideFor(mem.cls, v)
  Core().log("info", "role " .. v); Core().changed()
end

-- ------------------------------------------------------------------ data per page
local function iconFor(d, it)
  if d and d.spell and d.spell.icon then return d.spell.icon end
  if it and it.group == "helper" then return ({ Follow = "Ability_Tracking", Assist = "Ability_Hunter_SniperShot", Focus = "Ability_Hunter_MarkedForDeath",
    Pet = "Ability_Hunter_Pet_Wolf", PetBack = "Ability_Hunter_BeastCall" })[it.key] or "INV_Misc_QuestionMark" end
  if d and d.seq and d.seq.steps and d.seq.steps[1] then return d.seq.steps[1].icon end
  return nil
end
Book.iconFor = iconFor

--- The visible book button of key `name` (where its flight starts), or nil.
function Book.cellFrame(name)
  local p = UI.panels and UI.panels[UI.current]
  if not (p and p.cells and p:IsVisible()) then return nil end
  for _, b in ipairs(p.cells) do if b:IsShown() and b.cell and b.cell.name == name then return b end end
end

--- Cells for a mode: {kind="key"|"spell"|"new", name, label, sub, color, icon, glow, item, d, spell}
function Book.cells(mode, ctx)
  local out = {}
  if not ctx then return out end
  local desiredBy, barOf = {}, {}
  for _, d in ipairs(ctx.desired) do desiredBy[d.name] = d end
  for _, b in ipairs(ctx.bars.items) do barOf[b.name] = b end
  if mode == "spells" then
    local keyOf = {}
    for name, d in pairs(desiredBy) do if d.spell then keyOf[d.spell.id] = name end end
    local lists = ns.Kit.kitLists(ctx.member)
    local all = {}
    for _, s in ipairs(lists.primary) do all[#all + 1] = s end
    for _, s in ipairs(lists.others) do all[#all + 1] = s end
    for _, s in ipairs(all) do
      local key = keyOf[s.id]
      local inBook = not ctx.live or ctx.live(s.name, s)
      local sub, col
      if key then
        local it
        for _, x in ipairs(ctx.macros.items) do if x.name == key then it = x end end
        sub, col = "Your " .. Book.kindName(it or { key = "" }):lower(), W.GREEN
      elseif inBook then sub, col = "Drag to make a key", W.BLUE
      else sub, col = "Learn at your trainer (level " .. s.level .. ")", W.MUTED end
      out[#out + 1] = { kind = "spell", label = s.name, sub = sub, color = col, icon = s.icon, spell = s, name = key or false,
        dim = not inBook and not key }
    end
    return out
  end
  for _, it in ipairs(ctx.macros.items) do
    local custom = it.group == "custom"
    if (mode == "custom") == custom then
      local d = desiredBy[it.name]
      local b = barOf[it.name]
      local st = Book.STATUS[it.status]
      local sub, col
      if st then sub, col = Book.kindName(it) .. " · " .. st[1], st[2]
      elseif b and b.status == "placed" then
        local keys = ns.Binds.keysFor(it.name, b.slot)
        sub = Book.kindName(it) .. " · " .. ns.Bars.slotLabel(b.slot) .. (keys[1] and (" · " .. ns.Binds.short(keys[1].key)) or "")
        col = W.MUTED
      else sub, col = Book.kindName(it) .. " · Not on a bar", W.ORANGE end
      out[#out + 1] = { kind = "key", name = it.name, label = it.label, sub = sub, color = col, icon = iconFor(d, it), item = it, d = d,
        glow = it.status == "create" or it.status == "update" or (it.status == "same" and not (b and b.status == "placed")),
        dim = it.status == "skipped" }
    end
  end
  if mode == "custom" and #(ctx.member.customSeq or {}) < ns.State.CUSTOM_MAX then
    out[#out + 1] = { kind = "new", label = "New own key", sub = "Build a sequence of your spells", color = W.BLUE, icon = "Spell_ChargePositive", name = false }
  end
  return out
end

-- ------------------------------------------------------------------ the next step
--- {text, button={label, tip, fn}?, tip?} – the one thing to do now on this page.
function Book.nextStep(ctx, mode)
  local cdb = Core().cdb
  local C, B = ns.Compat, ns.Bars
  if not ctx then return { text = "This character has no WoWBoxer setup yet.", button = { "Set up", "Sets up this character (only WoWBoxer's own settings change).", function() Core().ensureMe(); Core().changed() end } } end
  if C.inCombat() then return { text = "|cffff8a80In combat.|r WoWBoxer changes nothing until the fight is over." } end
  for _, first in ipairs({ cdb.primaryBar or 1, cdb.secondaryBar or 61 }) do
    if not C.barVisible(first) then
      return { text = "|cfff0b43c" .. B.barLabel(first) .. " is hidden.|r Turn it on in " .. (C.game() == "forever" and "Edit Mode" or "Interface > Action Bars") ..
        ", or choose another bar in Setup.", button = { "Choose bars", "Opens Setup, where you pick the bars WoWBoxer uses.", function() UI.Select("setup") end } }
    end
  end
  if (cdb.primaryBar or 1) == 1 and C.bonusBarOffset() > 0 then
    return { text = "|cfff0b43cBar 1 is showing your stance or form page,|r so keys on Bar 1 are hidden there.",
      button = { "Use Bottom Left", "Moves your main keys to the Bottom Left Bar (they are placed there when you press Place all).", function()
        cdb.primaryBar, cdb.secondaryBar, cdb.slots = 61, 49, {}; Core().changed() end } }
  end
  local m = ctx.macros
  if m.counts.noslot > 0 then
    return { text = "|cffff8a80No free macro slot for " .. m.counts.noslot .. (m.counts.noslot == 1 and " key" or " keys") ..
      ".|r Delete a macro you don't need in the game's macro window (/macro), then come back." }
  end
  local n = m.changes
  if n > 0 then
    if not cdb.lastSync then
      return { text = "|cffffd100Step 2 of 3:|r drag your keys onto your action bar – or press |cffffd100Place all|r and WoWBoxer puts them there.",
        button = { "Place all", "Creates your " .. n .. " WoWBoxer macros and puts them on your action bars. Buttons that hold something else are kept (see Setup).", function() Core().sync({ replace = cdb.replace }) end } }
    end
    local names = {}
    for _, it in ipairs(m.items) do if (it.status == "create" or it.status == "update") and #names < 3 then names[#names + 1] = it.label end end
    local lvl = (cdb.lastSync.level or 0) < ctx.level and ("|cffb7f07aLevel " .. ctx.level .. ":|r ") or ""
    return { text = lvl .. n .. (n == 1 and " key changed" or " keys changed") .. " (" .. table.concat(names, ", ") .. (n > #names and ", …" or "") ..
      "). Same buttons, new spells.", button = { "Update keys", "Updates the changed macros. They stay on the same action buttons and keys.", function() Core().sync({ replace = cdb.replace }) end } }
  end
  if ctx.bars.changes > 0 then
    local k = ctx.bars.changes
    return { text = k .. (k == 1 and " key is" or " keys are") .. " not on your bars yet. Drag them from the book, or press Place all.",
      button = { "Place all", "Puts the keys that are not on a bar onto your action bars. Buttons that hold something else are kept.", function() Core().sync({ replace = cdb.replace }) end } }
  end
  if #ctx.missing > 0 then
    local names = {}
    for i, s in ipairs(ctx.missing) do if i <= 3 then names[#names + 1] = s.name end end
    return { text = "Visit your trainer: " .. table.concat(names, ", ") .. (#ctx.missing > 3 and (" and " .. (#ctx.missing - 3) .. " more") or "") ..
      ". They join your keys when you have learned them." }
  end
  if mode == "spells" then return { text = "Drag any spell onto your action bar to make it a WoWBoxer key for this character." } end
  if mode == "custom" then return { text = "Own keys: build a sequence of your spells. One press is still one spell." } end
  return { text = "|cff8fbf6aAll keys are on your bars.|r Hover a key to see what it does; drag it to move it.",
    button = { "Key bindings", "Opens the game's key bindings, so you can choose which keys press your action buttons.", function() Core().openKeyBindings() end } }
end

-- ------------------------------------------------------------------ key capture (bind a key to one WBX macro)
local function buildCapture(p)
  local c = W.box(p, 0.12, 0.09, 0.04, 0.98)
  c:SetPoint("TOPLEFT", 120, -110)
  c:SetPoint("BOTTOMRIGHT", -120, 110)
  c:SetFrameLevel((p:GetFrameLevel() or 1) + 30)
  c:EnableMouse(true)
  c.wbxModal = true
  c.text = W.text(c, "GameFontHighlight", nil, W.TEXT, "CENTER")
  c.text:SetPoint("TOPLEFT", 12, -14)
  c.text:SetPoint("TOPRIGHT", -12, -14)
  c.cancel = W.button(c, "Cancel", 80, 22, function() c:Stop() end, "Stops waiting for a key. Nothing changes.")
  c.cancel:SetPoint("BOTTOM", 0, 10)
  c:Hide()
  function c:Start(name, label)
    self.name, self.label, self.pending = name, label or name, nil
    self.text:SetText("Press the key for |cffffd100" .. self.label .. "|r\n(with Shift, Ctrl or Alt if you like).\n\nEsc cancels.")
    self:Show()
    if self.EnableKeyboard then self:EnableKeyboard(true) end
    if self.SetPropagateKeyboardInput then self:SetPropagateKeyboardInput(false) end
  end
  function c:Stop()
    if self.EnableKeyboard then self:EnableKeyboard(false) end
    self:Hide()
  end
  c:SetScript("OnKeyDown", function(self, key)
    if key == "ESCAPE" then self:Stop(); return end
    local full = ns.Binds.compose(key, _G.IsAltKeyDown and _G.IsAltKeyDown(), _G.IsControlKeyDown and _G.IsControlKeyDown(),
      _G.IsShiftKeyDown and _G.IsShiftKeyDown())
    if not full then return end -- a modifier on its own: wait for the real key
    local used = ns.Binds.actionOf(full)
    if used and used ~= "MACRO " .. self.name and self.pending ~= full then
      self.pending = full
      self.text:SetText("|cffffd100" .. full .. "|r already does |cfff0b43c" .. used .. "|r.\nPress it again to use it for " .. self.label ..
        " (this character only), or press another key.\nEsc cancels.")
      return
    end
    self:Stop()
    Core().bindKey(self.name, full)
  end)
  return c
end

-- ------------------------------------------------------------------ actions on one key
local function pickupResult(ok, why) if not ok and why then Core().print("|cffff8a80" .. why .. "|r") end end
local function pickupCell(c)
  if not c then return end
  if c.kind == "spell" and not c.name then pickupResult(Core().pickupSpell(c.spell.id))
  elseif c.name then pickupResult(Core().pickup(c.name)) end
end
local function setSkip(name, skip) Core().cdb.skip[name] = skip or nil; Core().changed() end

--- Menu entries for a cell (right-click, Shift-click).
function Book.menuFor(p, c)
  local items = {}
  if ns.Compat.inCombat() then return { { "Not in combat – try again after the fight", function() end } } end
  if c.kind == "new" then return { { "New own key", function() ns.KeyEditor.Open(p, nil) end } } end
  if c.kind == "spell" and not c.name then
    if not c.dim then items[#items + 1] = { "Pick up (make a key)", function() pickupCell(c) end } end
    return items
  end
  items[#items + 1] = { "Pick up", function() pickupCell(c) end }
  items[#items + 1] = { "Bind key…", function() p.capture:Start(c.name, c.label) end }
  if c.item and c.item.status == "skipped" then items[#items + 1] = { "Use again", function() setSkip(c.name, false) end }
  elseif c.item then items[#items + 1] = { "Leave out", function() setSkip(c.name, true) end } end
  local i = c.name and tonumber(c.name:match("^WBX C(%d)$"))
  if i then items[#items + 1] = { "Edit", function() ns.KeyEditor.Open(p, i) end } end
  return items
end

-- ------------------------------------------------------------------ build
local function makeCell(p, parent)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(CELL_W, CELL_H)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:RegisterForDrag("LeftButton")
  b.slotBg = b:CreateTexture(nil, "BACKGROUND")
  b.slotBg:SetSize(36, 36)
  b.slotBg:SetPoint("LEFT", 2, 0)
  b.slotBg:SetColorTexture(0, 0, 0, 0.55)
  b.icon = W.icon(b, 34)
  b.icon:SetPoint("CENTER", b.slotBg, "CENTER", 0, 0)
  b.frame = b:CreateTexture(nil, "OVERLAY")
  b.frame:SetSize(62, 62)
  b.frame:SetPoint("CENTER", b.slotBg, "CENTER", 0, 0)
  b.frame:SetTexture("Interface\\Buttons\\UI-Quickslot2")
  b.glow = b:CreateTexture(nil, "OVERLAY")
  b.glow:SetSize(66, 66)
  b.glow:SetPoint("CENTER", b.slotBg, "CENTER", 0, 0)
  b.glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
  if b.glow.SetBlendMode then b.glow:SetBlendMode("ADD") end
  b.glow:SetVertexColor(0.5, 0.8, 1, 0.9)
  b.sel = b:CreateTexture(nil, "BACKGROUND")
  b.sel:SetAllPoints()
  b.sel:SetColorTexture(1, 0.82, 0, 0.13)
  local hl = b:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints()
  hl:SetColorTexture(1, 1, 1, 0.07)
  b.name = W.line(b, "GameFontNormal", nil, W.GOLD)
  b.name:SetPoint("TOPLEFT", b.slotBg, "TOPRIGHT", 7, -3)
  b.name:SetPoint("TOPRIGHT", b, "TOPRIGHT", -2, -3)
  b.sub = W.line(b, "GameFontHighlightSmall", nil, W.MUTED)
  b.sub:SetPoint("TOPLEFT", b.name, "BOTTOMLEFT", 0, -4)
  b.sub:SetPoint("TOPRIGHT", b.name, "BOTTOMRIGHT", 0, -4)
  b:SetScript("OnClick", function(self, button)
    local c = self.cell
    if not c then return end
    if button == "RightButton" or (_G.IsShiftKeyDown and _G.IsShiftKeyDown()) then W.menu(self, Book.menuFor(p, c)); return end
    if c.kind == "new" then ns.KeyEditor.Open(p, nil); return end
    p.selected = c.name or (c.spell and ("spell:" .. c.spell.id)) or nil
    UI.Refresh()
  end)
  b:SetScript("OnDragStart", function(self) if self.cell and self.cell.kind ~= "new" then pickupCell(self.cell) end end)
  W.tooltip(b, function(GT, self)
    local c = self.cell
    if not c then return end
    GT:AddLine(c.label, 1, 0.82, 0)
    GT:AddLine(c.sub, c.color[1], c.color[2], c.color[3])
    if c.kind == "new" then GT:AddLine("Click to build your own key: a sequence of your spells, one spell per press.", 1, 1, 1, true); return end
    local d = c.d
    if c.kind == "spell" and not d then
      d = { group = "extra", label = c.spell.name, body = ns.Engine.makeMacro(c.spell, ns.Kit.memberCtx(ns.Core.compute().member)) }
    end
    GT:AddLine(Book.describe(d, nil), 1, 1, 1, true)
    if d and d.body then for line in (d.body .. "\n"):gmatch("([^\n]*)\n") do if line ~= "" then GT:AddLine(line, 0.56, 0.85, 0.45) end end end
    if c.item and c.item.why then GT:AddLine(c.item.why, 1, 0.54, 0.5, true) end
    if not c.dim then GT:AddLine("Drag to your action bar · Right-click for more", 0.66, 0.6, 0.49) end
    if c.name then GT:AddLine("Macro: " .. c.name, 0.5, 0.5, 0.5) end
  end)
  return b
end

local function build(p, mode)
  p.mode, p.page = mode, 1
  local body = CreateFrame("Frame", nil, p)
  body:SetAllPoints()
  p.body = body
  -- next step
  p.strip = W.box(body, 0.13, 0.17, 0.08, 0.95)
  p.strip:SetPoint("TOPLEFT", 0, 0)
  p.strip:SetPoint("TOPRIGHT", 0, 0)
  p.strip:SetHeight(STRIP_H)
  p.stepBtn = W.button(p.strip, "Place all", 90, 24, function() if p.stepFn then p.stepFn() end end)
  p.stepBtn:SetPoint("RIGHT", -8, 0)
  W.tip(p.stepBtn, function() return p.stepBtn:GetText() end, function() return p.stepTip end)
  p.stepText = W.text(p.strip, "GameFontHighlight", nil, W.TEXT)
  p.stepText:SetPoint("LEFT", 10, 0)
  p.stepText:SetPoint("RIGHT", p.stepBtn, "LEFT", -10, 0)
  if p.stepText.SetMaxLines then p.stepText:SetMaxLines(2) end

  -- options (My keys only): role, plays as, sequence keys
  if mode == "keys" then
    local function me() local _, mem = Core().me(); return mem end
    p.role = W.dropdown(body, { width = 112, values = function() return Book.roleValues(me()) end,
      get = function() local mem = me(); return mem and mem.role end,
      set = function(v) Book.setRole(me(), v) end })
    local rl = W.labelled(body, "Role", p.role)
    rl:SetPoint("TOPLEFT", 4, OPT_Y - 5)
    W.ddTip(p.role, "Role", "Picks the recommended keys and talent guide for this character. Nothing changes in the game until you place or update keys.")
    p.playsAs = W.dropdown(body, { width = 156, values = function() return Book.playsAsValues(me()) end,
      get = function() local mem = me(); return mem and (mem.leader and "leader" or mem.unit) end,
      set = function(v) Core().setPlaysAs(v) end })
    local pl = W.labelled(body, "Plays as", p.playsAs)
    pl:SetPoint("LEFT", p.role, "RIGHT", 12, 0)
    W.ddTip(p.playsAs, "Plays as", "Leader: your keys use your own target. Follower: your keys use the leader's target (party1–4 or focus). One key press is still one action on this character.")
    p.seq = W.seqControl(body, { member = me, width = 96 })
    p.seq:SetPoint("LEFT", p.playsAs, "RIGHT", 12, 0)
  else
    p.hint = W.text(body, "GameFontHighlightSmall", nil, W.MUTED)
    p.hint:SetPoint("TOPLEFT", 4, OPT_Y - 6)
    p.hint:SetPoint("TOPRIGHT", -4, OPT_Y - 6)
    p.hint:SetText(mode == "spells" and "Every spell you know. Drag one onto your action bar to make it a WoWBoxer key; greyed spells come from your trainer."
      or "Your own keys (up to 8): sequences of your spells with the same rules as the companion.")
  end

  -- two pages of cells
  p.cells = {}
  local pageW = (UI.PanelSize() - 16) / 2
  for i = 1, PER_PAGE * 2 do
    local pageIx = i <= PER_PAGE and 0 or 1
    local j = (i - 1) % PER_PAGE
    local col, row = j % COLS, math.floor(j / COLS)
    local c = makeCell(p, body)
    c:SetPoint("TOPLEFT", pageIx * (pageW + 16) + 2 + col * (CELL_W + 6), GRID_Y - row * PITCH)
    p.cells[i] = c
  end
  p.empty = W.text(body, "GameFontHighlight", nil, W.MUTED, "CENTER")
  p.empty:SetPoint("TOPLEFT", 20, GRID_Y - 40)
  p.empty:SetPoint("TOPRIGHT", -20, GRID_Y - 40)

  -- selected key
  local dy = GRID_Y - ROWS * PITCH - 4
  p.det = CreateFrame("Frame", nil, body)
  p.det:SetPoint("TOPLEFT", 0, dy)
  p.det:SetPoint("TOPRIGHT", 0, dy)
  p.det:SetHeight(28)
  local dbg = p.det:CreateTexture(nil, "BACKGROUND")
  dbg:SetAllPoints()
  dbg:SetColorTexture(0, 0, 0, 0.25)
  p.detIcon = W.icon(p.det, 22, true)
  p.detIcon:SetPoint("LEFT", 4, 0)
  p.edit = W.button(p.det, "Edit", 50, 22, function() local i = p.selected and tonumber(p.selected:match("^WBX C(%d)$")); if i then ns.KeyEditor.Open(p, i) end end,
    "Opens this own key in the editor.")
  p.edit:SetPoint("RIGHT", -2, 0)
  p.leave = W.button(p.det, "Leave out", 80, 22, function() if p.selected then setSkip(p.selected, not Core().cdb.skip[p.selected]) end end,
    { "Leave out / Use again", "Leave out: WoWBoxer stops creating and placing this key (the macro you have stays). Use again brings it back." })
  p.unbind = W.button(p.det, "Unbind", 60, 22, function() if p.selected then Core().unbindKey(p.selected) end end,
    "Removes the key you bound directly to this macro (this character only).")
  p.bind = W.button(p.det, "Bind key", 76, 22, function() if p.selected then p.capture:Start(p.selected, p.selLabel) end end,
    "Press a key to run this macro directly, also when it is not on a bar. Saved for this character only.")
  p.detText = W.line(p.det, "GameFontHighlightSmall", nil, W.TEXT)
  p.detText:SetPoint("LEFT", p.detIcon, "RIGHT", 8, 0)
  p.detText:SetPoint("RIGHT", p.bind, "LEFT", -8, 0)
  local detHit = CreateFrame("Frame", nil, p.det)
  detHit:SetAllPoints(p.detText)
  W.tooltip(detHit, function(GT) GT:AddLine(p.detText:GetText() or "", 1, 1, 1, true) end)

  -- footer: macro slots, page arrows
  p.prev = CreateFrame("Button", nil, body)
  p.prev:SetSize(28, 28)
  p.prev:SetPoint("BOTTOM", -60, 0)
  p.prev:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up")
  p.prev:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Down")
  p.prev:SetDisabledTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Disabled")
  p.prev:SetScript("OnClick", function() p.page = math.max(1, p.page - 1); UI.Refresh() end)
  W.tip(p.prev, "Previous page")
  p.next = CreateFrame("Button", nil, body)
  p.next:SetSize(28, 28)
  p.next:SetPoint("BOTTOM", 60, 0)
  p.next:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up")
  p.next:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Down")
  p.next:SetDisabledTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Disabled")
  p.next:SetScript("OnClick", function() p.page = p.page + 1; UI.Refresh() end)
  W.tip(p.next, "Next page")
  p.pageText = W.text(body, "GameFontNormalSmall", nil, W.GOLD, "CENTER")
  p.pageText:SetPoint("BOTTOM", 0, 9)
  p.slots = W.line(body, "GameFontHighlightSmall", nil, W.MUTED)
  p.slots:SetPoint("BOTTOMLEFT", 4, 9)
  p.slots:SetWidth(200)

  p.capture = buildCapture(p)
  if mode == "keys" then Book.buildGuide(p) end
end

-- ------------------------------------------------------------------ refresh
local function refresh(p, ctx)
  local step = Book.nextStep(ctx, p.mode)
  p.stepText:SetText(step.text)
  if step.button then
    W.setLabel(p.stepBtn, step.button[1]); p.stepTip, p.stepFn = step.button[2], step.button[3]
    p.stepBtn:Show(); p.stepBtn:SetEnabled(not ns.Compat.inCombat())
  else p.stepBtn:Hide(); p.stepFn = nil end
  p.stepText:SetPoint("RIGHT", step.button and p.stepBtn or p.strip, step.button and "LEFT" or "RIGHT", -10, 0)
  if not ctx then for _, c in ipairs(p.cells) do c:Hide() end; p.det:Hide(); return end
  if p.role then p.role.Refresh(); p.playsAs.Refresh(); p.seq.Refresh() end

  local list = Book.cells(p.mode, ctx)
  local pages = math.max(1, math.ceil(#list / (PER_PAGE * 2)))
  p.page = math.min(p.page or 1, pages)
  local first = (p.page - 1) * PER_PAGE * 2
  local selCell
  for i, b in ipairs(p.cells) do
    local c = list[first + i]
    b.cell = c
    if c then
      b:Show()
      W.setIcon(b.icon, c.icon)
      b.name:SetText(c.label)
      b.sub:SetText(c.sub)
      b.sub:SetTextColor(c.color[1], c.color[2], c.color[3])
      if b.icon.SetDesaturated then b.icon:SetDesaturated(c.dim and true or false) end
      b.icon:SetAlpha(c.dim and 0.5 or 1)
      b.glow:SetShown(c.glow and true or false)
      local id = c.name or (c.spell and ("spell:" .. c.spell.id)) or nil
      b.sel:SetShown(id ~= nil and id == p.selected)
      if id ~= nil and id == p.selected then selCell = c end
    else b:Hide() end
  end
  for _, c in ipairs(list) do if not selCell and (c.name or (c.spell and ("spell:" .. c.spell.id))) == p.selected then selCell = c end end
  p.empty:SetText(#list == 0 and (p.mode == "custom" and "No own keys yet." or "No keys for this character yet – learn a spell at your trainer first.") or "")
  p.pageText:SetText(pages > 1 and ("Page " .. p.page .. " / " .. pages) or "")
  p.prev:SetShown(pages > 1); p.next:SetShown(pages > 1)
  p.prev:SetEnabled(p.page > 1); p.next:SetEnabled(p.page < pages)
  local _, charMax = ns.Compat.macroLimits()
  local used = charMax - ctx.macros.free - ctx.macros.counts.create
  p.slots:SetText(used .. " of " .. charMax .. " character macro slots used")

  -- details of the selected key
  if selCell and selCell.name then
    p.det:Show()
    p.selLabel = selCell.label
    W.setIcon(p.detIcon, selCell.icon)
    local b
    for _, x in ipairs(ctx.bars.items) do if x.name == selCell.name then b = x end end
    local keys = ns.Binds.keysFor(selCell.name, b and b.status == "placed" and b.slot or nil)
    local kt, direct = {}, false
    for _, k in ipairs(keys) do kt[#kt + 1] = ns.Binds.short(k.key); if k.via == "macro" then direct = true end end
    p.detText:SetText("|cffffd100" .. selCell.label .. "|r · " .. selCell.sub .. " · Key: " .. (#kt > 0 and ("|cffffd100" .. table.concat(kt, " ") .. "|r") or "none"))
    local busy = ns.Compat.inCombat()
    p.bind:SetEnabled(not busy)
    p.unbind:SetShown(direct)
    p.edit:SetShown(selCell.name:match("^WBX C%d$") ~= nil)
    p.leave:SetShown(selCell.item ~= nil)
    W.setLabel(p.leave, selCell.item and selCell.item.status == "skipped" and "Use again" or "Leave out")
    W.rowRight({ p.edit, p.leave, p.unbind, p.bind }, 4)
    local rightmost = p.edit:IsShown() and p.edit or p.leave:IsShown() and p.leave or p.unbind:IsShown() and p.unbind or p.bind
    rightmost:ClearAllPoints(); rightmost:SetPoint("RIGHT", -2, 0)
    W.rowRight({ p.edit, p.leave, p.unbind, p.bind }, 4)
  else
    p.det:SetShown(selCell ~= nil)
    if selCell then
      W.setIcon(p.detIcon, selCell.icon)
      p.detText:SetText("|cffffd100" .. selCell.label .. "|r · " .. selCell.sub)
      p.bind:Hide(); p.unbind:Hide(); p.edit:Hide(); p.leave:Hide()
      p.detText:SetPoint("RIGHT", p.det, "RIGHT", -8, 0)
    end
  end
  if selCell and selCell.name then p.bind:Show(); p.detText:SetPoint("RIGHT", p.bind, "LEFT", -8, 0) end
  if ns.KeyEditor.IsOpen() then ns.KeyEditor.Refresh() end
  if p.guide then Book.refreshGuide(p, ctx) end
end

-- ------------------------------------------------------------------ first-run guide (3 steps)
local ROLE_TIP = "Picks the recommended keys and talent guide."
function Book.buildGuide(p)
  local g = W.box(p, 0.11, 0.085, 0.05, 0.99)
  g:SetPoint("TOPLEFT", 0, 0)
  g:SetPoint("BOTTOMRIGHT", 0, 0)
  g:SetFrameLevel((p:GetFrameLevel() or 1) + 20)
  g:EnableMouse(true)
  p.guide = g
  g.step = 1
  g.title = W.text(g, "GameFontNormalLarge", 16, W.GOLD)
  g.title:SetPoint("TOPLEFT", 24, -22)
  g.title:SetPoint("TOPRIGHT", -120, -22)
  g.skip = W.button(g, "Skip guide", 90, 22, function() Book.closeGuide(p) end,
    "Closes the guide. Open it again from the minimap button menu or Setup.")
  g.skip:SetPoint("TOPRIGHT", -14, -16)
  g.text = W.text(g, "GameFontHighlight", nil, W.TEXT)
  g.text:SetPoint("TOPLEFT", g.title, "BOTTOMLEFT", 0, -14)
  g.text:SetPoint("TOPRIGHT", g, "TOPRIGHT", -24, -54)
  -- step 1 choices
  g.roleLabel = W.text(g, "GameFontNormal", nil, W.GOLD)
  g.roleLabel:SetPoint("TOPLEFT", 24, -130)
  g.roleLabel:SetText("Role")
  g.roles = {}
  for i = 1, 4 do
    local b = W.button(g, "Role", 100, 28, function(self)
      local _, mem = Core().me()
      if mem and self.value then mem.role = self.value; mem.guide = ns.Kit.defaultGuideFor(mem.cls, self.value); Core().changed() end
    end, { "Role", ROLE_TIP })
    if i == 1 then b:SetPoint("TOPLEFT", 24, -150) else b:SetPoint("LEFT", g.roles[i - 1], "RIGHT", 8, 0) end
    g.roles[i] = b
  end
  g.playLabel = W.text(g, "GameFontNormal", nil, W.GOLD)
  g.playLabel:SetPoint("TOPLEFT", 24, -196)
  g.playLabel:SetText("This character")
  g.lead = W.button(g, "Leads", 100, 28, function() Core().setPlaysAs("leader") end,
    "This character leads: its keys use its own target.")
  g.lead:SetPoint("TOPLEFT", 24, -216)
  g.follow = W.button(g, "Follows the leader (party1)", 200, 28, function()
    local _, mem = Core().me()
    Core().setPlaysAs((mem and not mem.leader and mem.unit) or "party1")
  end, "This character follows: its keys use the leader's target through party1 (change the unit on the My keys page).")
  g.follow:SetPoint("LEFT", g.lead, "RIGHT", 8, 0)
  g.seq = W.seqControl(g, { member = function() local _, mem = Core().me(); return mem end, width = 110 })
  g.seq:SetPoint("TOPLEFT", 20, -262)
  -- step 2 option
  g.replace = W.check(g, "Also replace buttons that hold something else", function(_, v) Core().cdb.replace = v; Core().changed() end)
  g.replace:SetPoint("TOPLEFT", 20, -186)
  W.tip(g.replace, "Replace", "Off: buttons that already hold a spell or item are kept and that key waits for you to drag it. On: WoWBoxer puts its key there.")
  -- navigation
  g.next = W.button(g, "Next", 90, 26, function() g.step = g.step + 1; Core().cdb.guideStep = g.step; UI.Refresh() end, "Goes to the next step.")
  g.next:SetPoint("BOTTOMRIGHT", -16, 16)
  g.place = W.button(g, "Place all", 100, 26, function()
    Core().sync({ replace = Core().cdb.replace })
    g.step = 3; Core().cdb.guideStep = 3; UI.Refresh()
  end, "Creates your WoWBoxer macros and puts them on the action buttons shown above.")
  g.place:SetPoint("BOTTOMRIGHT", -16, 16)
  g.drag = W.button(g, "I'll drag them myself", 150, 26, function() g.step = 3; Core().cdb.guideStep = 3; UI.Refresh() end,
    "Closes this step. Drag each key from the book onto any action button.")
  g.drag:SetPoint("RIGHT", g.place, "LEFT", -8, 0)
  g.back = W.button(g, "Back", 70, 26, function() g.step = math.max(1, g.step - 1); Core().cdb.guideStep = g.step; UI.Refresh() end, "Goes back one step.")
  g.back:SetPoint("BOTTOMLEFT", 16, 16)
  g.done = W.button(g, "Close", 90, 26, function() Book.closeGuide(p) end, "Closes the guide and shows your keys.")
  g.done:SetPoint("BOTTOMRIGHT", -16, 16)
  g:Hide()
end

function Book.closeGuide(p)
  Core().cdb.guide = "done"
  if p.guide then p.guide:Hide() end
  UI.Refresh()
end
--- Show the guide again (minimap menu, Setup).
function Book.ShowGuide()
  Core().cdb.guide, Core().cdb.guideStep = nil, 1
  UI.Open("keys")
end

--- "Bar 1 · 1–10 and Bottom Left Bar · 9–11": where Place all puts the keys.
function Book.whereText(ctx)
  local byBar, order = {}, {}
  for _, it in ipairs(ctx.bars.items) do
    local first = it.slot - (it.slot - 1) % 12
    if not byBar[first] then byBar[first] = {}; order[#order + 1] = first end
    table.insert(byBar[first], (it.slot - 1) % 12 + 1)
  end
  local parts = {}
  for _, first in ipairs(order) do
    local l = byBar[first]
    table.sort(l)
    parts[#parts + 1] = ns.Bars.barLabel(first) .. " (" .. (#l > 1 and (l[1] .. "–" .. l[#l]) or tostring(l[1])) .. ")"
  end
  return table.concat(parts, " and ")
end

function Book.refreshGuide(p, ctx)
  local g, cdb = p.guide, Core().cdb
  local want = ctx and cdb.guide ~= "done" and (not cdb.lastSync or (cdb.guideStep or 1) >= 3) and cdb.guide ~= "skip"
  p.body:SetShown(not want)
  if not want then g:Hide(); return end
  g.step = math.max(1, math.min(3, cdb.guideStep or 1))
  g:Show()
  local mem, info = ctx.member, Core().playerInfo()
  local cls = ns.Data.classes[mem.cls]
  for _, x in ipairs({ g.roleLabel, g.playLabel, g.lead, g.follow, g.seq, g.replace, g.next, g.place, g.drag, g.done }) do x:Hide() end
  for _, b in ipairs(g.roles) do b:Hide() end
  g.back:SetShown(g.step > 1 and g.step < 3)
  if g.step == 1 then
    g.title:SetText("Step 1 of 3 – Who is this character?")
    g.text:SetText("WoWBoxer builds the keys for " .. (info.name or "this character") .. " (" .. (cls and cls.n or mem.cls) ..
      "). Pick the role, whether this character leads or follows, and if you want sequence keys. You can change all of it later on the My keys page.")
    g.roleLabel:Show(); g.playLabel:Show(); g.lead:Show(); g.follow:Show(); g.next:Show()
    g.seq:Show(); g.seq.Refresh()
    for i, r in ipairs(cls and cls.roles or {}) do
      local b = g.roles[i]
      if b then
        b.value = r
        W.setLabel(b, ns.State.ROLE_NAME[r] or r)
        b:Show()
        if mem.role == r then b:LockHighlight() else b:UnlockHighlight() end
      end
    end
    if mem.leader then g.lead:LockHighlight(); g.follow:UnlockHighlight() else g.follow:LockHighlight(); g.lead:UnlockHighlight() end
    local L = ns.State.leaderOf(Core().me())
    W.setLabel(g.follow, "Follows " .. ((L and L ~= mem and L.name) or "the leader") .. " (" .. (mem.leader and "party1" or mem.unit) .. ")")
  elseif g.step == 2 then
    g.title:SetText("Step 2 of 3 – Put your keys on your action bar")
    local occupied = ctx.bars.counts.occupied or 0
    g.text:SetText("Place all puts your " .. #ctx.desired .. " keys on " .. Book.whereText(ctx) .. ". " ..
      (occupied > 0 and (occupied .. (occupied == 1 and " of those buttons holds" or " of those buttons hold") .. " something else; it is kept unless you tick the box below. ")
        or "Those buttons are free. ") .. "Or drag each key from the book onto any action button yourself.")
    g.replace:Show(); g.replace:SetChecked(cdb.replace and true or false)
    g.place:Show(); g.drag:Show()
    g.place:SetEnabled(not ns.Compat.inCombat())
  else
    g.title:SetText("Step 3 of 3 – Done")
    g.text:SetText("Your keys are ready. WoWBoxer tells you when a level-up or a new spell changes a key – then one click updates it, on the same buttons.\n\n" ..
      "Hover a key in the book to see what it does. Drag it to move it. Right-click it to bind a key or leave it out.")
    g.done:Show()
  end
end

-- ------------------------------------------------------------------ register the three book tabs
for _, def in ipairs({
  { key = "keys", label = "My keys", icon = "INV_Misc_Book_09", tip = "Your recommended keys for this level. Drag them onto your action bars." },
  { key = "spells", label = "All spells", icon = "INV_Misc_Book_11", tip = "Every spell you know. Drag one onto a bar to make it a key." },
  { key = "custom", label = "Custom keys", icon = "Spell_ChargePositive", tip = "Your own sequence keys (up to 8)." },
}) do
  UI.RegisterTab({ key = def.key, label = def.label, icon = def.icon, tip = def.tip, book = true,
    build = function(p) build(p, def.key) end, refresh = refresh })
end
