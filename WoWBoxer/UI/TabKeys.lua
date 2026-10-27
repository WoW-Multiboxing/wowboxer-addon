--[[ WoWBoxer – Keys tab: this character's WBX keys for its level, what changes, the macro text, which key presses
  it, drag & drop onto any action button, an optional per-character key binding, and "Create & place keys".
  "Spells" lists every learned spell so any of them can be dragged out as an extra WBX key. ]]
local _, ns = ...
local UI, W = ns.UI, ns.Widgets
local tab = { key = "keys", label = "Keys" }

local STATUS = {
  create = { "New", W.BLUE }, update = { "Changed", W.ORANGE }, same = { "OK", W.GREEN }, noslot = { "No slot", W.RED },
  invalid = { "Blocked", W.RED }, skipped = { "Off", W.MUTED },
}
local TIERS = { { "off", "Off" }, { "simple", "Simple" }, { "medium", "Medium" }, { "advanced", "Advanced" } }
local ROW_H = 24
local LIST_W, LIST_H = 356, 214

local function Core() return ns.Core end
local function selectedItem(p, ctx)
  for _, it in ipairs(ctx.macros.items) do if it.name == p.selected then return it end end
  return ctx.macros.items[1]
end
local function pickupResult(ok, why) if not ok and why then Core().print("|cffff8a80" .. why .. "|r") end end

-- ------------------------------------------------------------------ key capture (bind a key to one WBX macro)
local function buildCapture(p, parent)
  local c = W.box(parent, 0.12, 0.09, 0.04, 0.98)
  c:SetAllPoints()
  c:SetFrameLevel((parent:GetFrameLevel() or 1) + 10)
  c:EnableMouse(true)
  c.text = W.text(c, "GameFontHighlight", nil, W.TEXT, "CENTER")
  c.text:SetPoint("TOPLEFT", 8, -10)
  c.text:SetPoint("BOTTOMRIGHT", -8, 30)
  c.cancel = W.button(c, "Cancel", 80, 20, function() c:Stop() end)
  c.cancel:SetPoint("BOTTOM", 0, 6)
  c:Hide()
  function c:Start(name)
    self.name, self.pending = name, nil
    self.text:SetText("Press the key (with Shift / Ctrl / Alt if you like) for\n|cffffd100" .. name .. "|r\n\nEsc cancels.")
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
      self.text:SetText("|cffffd100" .. full .. "|r is used for |cfff0b43c" .. used .. "|r.\nPress it again to give it to " .. self.name ..
        " (this character only),\nor press another key. Esc cancels.")
      return
    end
    self:Stop()
    Core().bindKey(self.name, full)
  end)
  return c
end

-- ------------------------------------------------------------------ build
function tab.build(p)
  p.mode = "keys"
  -- banner (only when keys changed)
  p.banner = W.box(p, 0.17, 0.23, 0.11, 0.95)
  p.banner:SetPoint("TOPLEFT", 0, 0)
  p.banner:SetPoint("TOPRIGHT", 0, 0)
  p.banner:SetHeight(28)
  p.bannerText = W.text(p.banner, "GameFontHighlightSmall", nil, W.TEXT)
  p.bannerText:SetPoint("LEFT", 10, 0)
  p.bannerText:SetPoint("RIGHT", -130, 0)
  if p.bannerText.SetWordWrap then p.bannerText:SetWordWrap(false) end
  p.bannerBtn = W.button(p.banner, "Update keys", 116, 20, function() Core().sync({ replace = Core().cdb.replace }) end)
  p.bannerBtn:SetPoint("RIGHT", -5, 0)

  -- empty state (only if the character could not be set up, e.g. unknown class)
  p.empty = CreateFrame("Frame", nil, p)
  p.empty:SetAllPoints()
  local et = W.text(p.empty, "GameFontHighlight", nil, W.TEXT, "CENTER")
  et:SetPoint("TOP", 0, -60)
  et:SetWidth(520)
  et:SetText("This character has no WoWBoxer setup yet.")
  local qs = W.button(p.empty, "Set up this character", 170, 24, function()
    Core().ensureMe(); Core().changed()
  end)
  qs:SetPoint("TOP", et, "BOTTOM", -90, -20)
  local imp = W.button(p.empty, "Import a string", 140, 24, function() UI.Select("share") end)
  imp:SetPoint("LEFT", qs, "RIGHT", 12, 0)

  p.main = CreateFrame("Frame", nil, p)
  p.main:SetAllPoints()
  local m = p.main

  -- header: role + sequence tier
  local rl = W.text(m, "GameFontNormal", nil, W.GOLD)
  rl:SetPoint("TOPLEFT", 0, -38)
  rl:SetText("Role")
  p.role = W.cycle(m, { width = 130,
    values = function()
      local _, mem = Core().me()
      local v = {}
      if mem then for _, r in ipairs(ns.Data.classes[mem.cls].roles) do v[#v + 1] = { r, ns.State.ROLE_NAME[r] } end end
      return v
    end,
    get = function() local _, mem = Core().me(); return mem and mem.role end,
    set = function(v)
      local _, mem = Core().me()
      if mem then mem.role = v; mem.guide = ns.Kit.defaultGuideFor(mem.cls, v); Core().log("info", "role " .. v); Core().changed() end
    end })
  p.role:SetPoint("LEFT", rl, "RIGHT", 6, 0)
  W.tooltip(p.role, function(GT) GT:AddLine("Role", 1, 0.82, 0); GT:AddLine("Picks the recommended keys and talent guide for this character.", 1, 1, 1, true) end)

  p.tierButtons = {}
  local prevBtn
  for i = #TIERS, 1, -1 do
    local t = TIERS[i]
    local b = W.button(m, t[2], 66, 20, function()
      local _, mem = Core().me()
      if mem then mem.seq = t[1]; Core().log("info", "sequence tier " .. t[1]); Core().changed() end
    end)
    if prevBtn then b:SetPoint("RIGHT", prevBtn, "LEFT", -2, 0) else b:SetPoint("TOPRIGHT", m, "TOPRIGHT", 0, -36) end
    prevBtn = b
    p.tierButtons[t[1]] = b
  end
  p.tierLabel = W.text(m, "GameFontHighlightSmall", nil, W.MUTED, "RIGHT")
  p.tierLabel:SetPoint("RIGHT", prevBtn, "LEFT", -6, 0)
  p.tierLabel:SetText("Sequence keys:")
  p.tierNone = W.text(m, "GameFontHighlightSmall", nil, W.MUTED, "RIGHT")
  p.tierNone:SetPoint("TOPRIGHT", m, "TOPRIGHT", 0, -40)

  -- list mode switch
  p.modeKeys = W.button(m, "My keys", 90, 20, function() p.mode = "keys"; UI.Refresh() end)
  p.modeKeys:SetPoint("TOPLEFT", 0, -62)
  p.modeSpells = W.button(m, "All spells", 90, 20, function() p.mode = "spells"; UI.Refresh() end)
  p.modeSpells:SetPoint("LEFT", p.modeKeys, "RIGHT", 4, 0)
  p.dragHint = W.text(m, "GameFontHighlightSmall", nil, W.MUTED)
  p.dragHint:SetPoint("LEFT", p.modeSpells, "RIGHT", 8, 0)
  p.dragHint:SetText("Drag a row onto any action button")

  -- list
  local sf, content = W.scroll(m, LIST_W, LIST_H)
  sf:SetPoint("TOPLEFT", 0, -86)
  p.list = content
  p.pool = W.pool(content, function(parent)
    local r = CreateFrame("Button", nil, parent)
    r:SetSize(LIST_W - 4, ROW_H)
    r:RegisterForDrag("LeftButton")
    r.hl = r:CreateTexture(nil, "BACKGROUND")
    r.hl:SetAllPoints()
    r.hl:SetColorTexture(1, 0.82, 0, 0.12)
    local hover = r:CreateTexture(nil, "HIGHLIGHT")
    hover:SetAllPoints()
    hover:SetColorTexture(1, 1, 1, 0.06)
    r.check = W.frame("CheckButton", r, "UICheckButtonTemplate")
    r.check:SetSize(20, 20)
    r.check:SetPoint("LEFT", 0, 0)
    r.icon = W.icon(r, 20)
    r.icon:SetPoint("LEFT", 22, 0)
    r.key = W.text(r, "GameFontDisableSmall", nil, W.MUTED)
    r.key:SetPoint("LEFT", 46, 0)
    r.key:SetWidth(48)
    if r.key.SetWordWrap then r.key:SetWordWrap(false) end
    r.label = W.text(r, "GameFontHighlightSmall", nil, W.TEXT)
    r.label:SetPoint("LEFT", 96, 0)
    r.label:SetWidth(130)
    if r.label.SetWordWrap then r.label:SetWordWrap(false) end
    r.status = W.text(r, "GameFontHighlightSmall")
    r.status:SetPoint("LEFT", 230, 0)
    r.status:SetWidth(64)
    if r.status.SetWordWrap then r.status:SetWordWrap(false) end
    r.slot = W.text(r, "GameFontDisableSmall", nil, W.MUTED, "RIGHT")
    r.slot:SetPoint("RIGHT", -2, 0)
    r.slot:SetWidth(54)
    if r.slot.SetWordWrap then r.slot:SetWordWrap(false) end
    r:SetScript("OnClick", function(self) if p.mode == "keys" then p.selected = self.name; UI.Refresh() end end)
    r:SetScript("OnDragStart", function(self)
      if self.spellId then pickupResult(Core().pickupSpell(self.spellId)) elseif self.name then pickupResult(Core().pickup(self.name)) end
    end)
    r.check:SetScript("OnClick", function(self)
      Core().cdb.skip[r.name] = (not self:GetChecked()) or nil
      Core().changed()
    end)
    return r
  end)

  -- preview (right column)
  p.prevTitle = W.text(m, "GameFontNormal", nil, W.GOLD)
  p.prevTitle:SetPoint("TOPLEFT", 370, -64)
  p.prevTitle:SetWidth(258)
  if p.prevTitle.SetWordWrap then p.prevTitle:SetWordWrap(false) end
  local pv = W.box(m, 0.05, 0.04, 0.025, 0.95)
  pv:SetPoint("TOPLEFT", 366, -82)
  pv:SetSize(262, 112)
  p.pv = pv
  p.prevBody = W.text(pv, "GameFontHighlightSmall", 10, { 0.85, 0.94, 0.75 })
  p.prevBody:SetPoint("TOPLEFT", 6, -6)
  p.prevBody:SetPoint("BOTTOMRIGHT", -6, 6)
  p.prevBody:SetJustifyV("TOP")
  W.tooltip(pv, function(GT)
    local _, mem = Core().me()
    GT:AddLine("Targeting", 1, 0.82, 0)
    GT:AddLine(mem and mem.leader and "Leader: hostile mouseover, then your own target. Heals: friendly mouseover, friendly target, then yourself."
      or ("Follower via " .. (mem and mem.unit or "party1") .. ": hostile mouseover, then the leader's target, then your own. Heals: mouseover, the leader, then yourself."), 1, 1, 1, true)
  end)
  p.prevInfo = W.text(m, "GameFontHighlightSmall", nil, W.MUTED)
  p.prevInfo:SetPoint("TOPLEFT", pv, "BOTTOMLEFT", 2, -4)
  p.prevInfo:SetWidth(258)
  p.prevInfo:SetHeight(40)
  p.prevInfo:SetJustifyV("TOP")
  -- keys of the selected macro + bind / unbind
  p.keysLine = W.text(m, "GameFontHighlightSmall", nil, W.TEXT)
  p.keysLine:SetPoint("TOPLEFT", pv, "BOTTOMLEFT", 2, -48)
  p.keysLine:SetWidth(258)
  if p.keysLine.SetWordWrap then p.keysLine:SetWordWrap(false) end
  p.bind = W.button(m, "Bind key", 92, 20, function() if p.selected then p.capture:Start(p.selected) end end)
  p.bind:SetPoint("TOPLEFT", pv, "BOTTOMLEFT", 0, -64)
  W.tooltip(p.bind, function(GT)
    GT:AddLine("Bind key", 1, 0.82, 0)
    GT:AddLine("Press a key to run this WBX macro directly, also when it is not on a bar. Saved for this character only.", 1, 1, 1, true)
  end)
  p.unbind = W.button(m, "Unbind", 70, 20, function() if p.selected then Core().unbindKey(p.selected) end end)
  p.unbind:SetPoint("LEFT", p.bind, "RIGHT", 4, 0)
  p.pickup = W.button(m, "Pick up", 70, 20, function() if p.selected then pickupResult(Core().pickup(p.selected)) end end)
  p.pickup:SetPoint("LEFT", p.unbind, "RIGHT", 4, 0)
  W.tooltip(p.pickup, function(GT) GT:AddLine("Pick up", 1, 0.82, 0); GT:AddLine("Puts this key on your cursor: click an action button to place it.", 1, 1, 1, true) end)
  p.capture = buildCapture(p, pv)

  p.trainer = W.text(m, "GameFontHighlightSmall", nil, { 0.85, 0.7, 0.42 })
  p.trainer:SetPoint("TOPLEFT", sf, "BOTTOMLEFT", 0, -4)
  p.trainer:SetWidth(LIST_W)
  if p.trainer.SetWordWrap then p.trainer:SetWordWrap(false) end

  -- footer
  local Bars = ns.Bars
  local function barValues() local v = {}; for _, b in ipairs(Bars.BARS) do v[#v + 1] = { b.first, b.label } end return v end
  local lb1 = W.text(m, "GameFontHighlightSmall", nil, W.MUTED)
  lb1:SetPoint("BOTTOMLEFT", 0, 36)
  lb1:SetText("Main keys on")
  p.bar1 = W.cycle(m, { width = 150, values = barValues, get = function() return Core().cdb.primaryBar end,
    set = function(v) Core().cdb.primaryBar = v; Core().cdb.slots = {}; Core().changed() end })
  p.bar1:SetPoint("LEFT", lb1, "RIGHT", 6, 0)
  local lb2 = W.text(m, "GameFontHighlightSmall", nil, W.MUTED)
  lb2:SetPoint("LEFT", p.bar1, "RIGHT", 10, 0)
  lb2:SetText("Other keys on")
  p.bar2 = W.cycle(m, { width = 150, values = barValues, get = function() return Core().cdb.secondaryBar end,
    set = function(v) Core().cdb.secondaryBar = v; Core().cdb.slots = {}; Core().changed() end })
  p.bar2:SetPoint("LEFT", lb2, "RIGHT", 6, 0)
  p.replace = W.check(m, "Replace occupied buttons", function(_, v) Core().cdb.replace = v; Core().changed() end)
  p.replace:SetPoint("BOTTOMLEFT", -2, 6)
  p.slots = W.text(m, "GameFontHighlightSmall", nil, W.MUTED)
  p.slots:SetPoint("LEFT", p.replace.label, "RIGHT", 12, 0)
  p.apply = W.button(m, "Create & place keys", 150, 24, function() Core().sync({ replace = Core().cdb.replace }) end)
  p.apply:SetPoint("BOTTOMRIGHT", 0, 4)
  W.tooltip(p.apply, function(GT)
    GT:AddLine("Create & place keys", 1, 0.82, 0)
    GT:AddLine("Creates or updates this character's WBX macros and puts them on your bars. Keys you dragged somewhere else stay there. Only empty or WBX buttons are used unless 'Replace occupied buttons' is ticked.", 1, 1, 1, true)
  end)
  p.macrosOnly = W.button(m, "Macros only", 96, 24, function() Core().sync({ macrosOnly = true }) end)
  p.macrosOnly:SetPoint("RIGHT", p.apply, "LEFT", -6, 0)
end

-- ------------------------------------------------------------------ refresh
local function keysText(name, slot)
  local keys = ns.Binds.keysFor(name, slot)
  if #keys == 0 then return nil, keys end
  local t = {}
  for _, k in ipairs(keys) do t[#t + 1] = ns.Binds.short(k.key) end
  return table.concat(t, " "), keys
end

local function refreshKeys(p, ctx, desiredBy, layout, barOf)
  p.pool:reset()
  local y = 0
  for _, it in ipairs(ctx.macros.items) do
    local r = p.pool:get()
    r.name, r.spellId = it.name, false
    r:SetPoint("TOPLEFT", 0, -y)
    y = y + ROW_H
    local d = desiredBy[it.name]
    W.setIcon(r.icon, d and d.spell and d.spell.icon or (it.group == "helper" and "Ability_Hunter_Pet_Wolf") or nil)
    r.check:Show()
    r.check:SetChecked(it.status ~= "skipped")
    r.key:SetText((it.name:gsub("^WBX ", "")))
    r.label:SetText(it.label)
    local st = STATUS[it.status] or { it.status, W.TEXT }
    local b = barOf[it.name]
    local stText, stColor = st[1], st[2]
    if it.status == "same" and b and b.status ~= "placed" then stText, stColor = "Not on bar", W.ORANGE end
    if b and b.status == "occupied" and it.status ~= "skipped" then stText, stColor = (it.status == "same" and "Occupied" or stText), W.ORANGE end
    r.status:SetText(stText)
    r.status:SetTextColor(stColor[1], stColor[2], stColor[3])
    local slot = layout[it.name]
    local keys = keysText(it.name, b and b.status == "placed" and b.slot or nil)
    r.slot:SetText(keys and ("|cffffd100" .. keys .. "|r") or (slot and ns.Bars.slotLabel(slot) or "-"))
    if p.selected == it.name then r.hl:Show() else r.hl:Hide() end
    W.tooltip(r, function(GT)
      GT:AddLine(it.name .. " – " .. it.label, 1, 0.82, 0)
      for line in (it.body .. "\n"):gmatch("([^\n]*)\n") do GT:AddLine(line, 0.85, 0.94, 0.75) end
      GT:AddLine("Drag onto an action button, or click to select.", 0.66, 0.6, 0.49)
    end)
  end
  return y
end

local function refreshSpells(p, ctx, desiredBy)
  local mem = ctx.member
  local lists = ns.Kit.kitLists(mem)
  local keyOf = {}
  for name, d in pairs(desiredBy) do if d.spell then keyOf[d.spell.id] = name end end
  p.pool:reset()
  local y = 0
  local all = {}
  for _, s in ipairs(lists.primary) do all[#all + 1] = s end
  for _, s in ipairs(lists.others) do all[#all + 1] = s end
  for _, s in ipairs(all) do
    local r = p.pool:get()
    local key = keyOf[s.id]
    r.name, r.spellId = key or false, (not key) and s.id or false
    r:SetPoint("TOPLEFT", 0, -y)
    y = y + ROW_H
    W.setIcon(r.icon, s.icon)
    r.check:Hide()
    r.key:SetText(s.category or "")
    r.label:SetText(s.name)
    local inBook = not ctx.live or ctx.live(s.name, s)
    if key then r.status:SetText("Key " .. key:gsub("^WBX ", "")); r.status:SetTextColor(W.GREEN[1], W.GREEN[2], W.GREEN[3])
    elseif inBook then r.status:SetText("Drag me"); r.status:SetTextColor(W.BLUE[1], W.BLUE[2], W.BLUE[3])
    else r.status:SetText("Train first"); r.status:SetTextColor(W.MUTED[1], W.MUTED[2], W.MUTED[3]) end
    r.slot:SetText("L" .. s.level)
    r.hl:Hide()
    W.tooltip(r, function(GT)
      GT:AddLine(s.name, 1, 0.82, 0)
      local body = ns.Engine.makeMacro(s, ns.Kit.memberCtx(mem))
      for line in (body .. "\n"):gmatch("([^\n]*)\n") do GT:AddLine(line, 0.85, 0.94, 0.75) end
      GT:AddLine(key and ("Already your key " .. key .. ".") or "Drag onto an action button: becomes the key WBX " .. s.name:sub(1, 12) .. ".", 0.66, 0.6, 0.49, true)
    end)
  end
  return y
end

function tab.refresh(p, ctx)
  local cdb = Core().cdb
  if not ctx then p.main:Hide(); p.banner:Hide(); p.empty:Show(); return end
  p.empty:Hide(); p.main:Show()
  local mem = ctx.member
  if ctx.macros.changes > 0 then
    p.banner:Show()
    p.bannerText:SetText((cdb.lastSync and ("|cffb7f07aLevel " .. ctx.level .. ":|r ") or "") .. ctx.macros.changes .. " key(s) to create or update.")
  else p.banner:Hide() end
  p.role.Refresh()
  local seqOk = ns.Engine.seqSupported(mem.cls)
  for k, b in pairs(p.tierButtons) do
    b:SetShown(seqOk)
    if mem.seq == k then b:LockHighlight() else b:UnlockHighlight() end
  end
  p.tierLabel:SetShown(seqOk)
  p.tierNone:SetShown(not seqOk)
  p.tierNone:SetText(seqOk and "" or "Sequence keys: Paladin, Priest, Warlock")
  if p.mode == "keys" then p.modeKeys:LockHighlight(); p.modeSpells:UnlockHighlight() else p.modeSpells:LockHighlight(); p.modeKeys:UnlockHighlight() end

  local barOf, desiredBy = {}, {}
  for _, it in ipairs(ctx.bars.items) do barOf[it.name] = it end
  for _, d in ipairs(ctx.desired) do desiredBy[d.name] = d end
  local layout = ns.Bars.layout(ctx.desired, cdb)
  local y
  if p.mode == "spells" then y = refreshSpells(p, ctx, desiredBy) else y = refreshKeys(p, ctx, desiredBy, layout, barOf) end
  p.list:SetHeight(math.max(y, 10))

  -- preview of the selected key
  local sel = selectedItem(p, ctx)
  if sel then
    p.selected = sel.name
    p.prevTitle:SetText(sel.name .. " · " .. sel.label)
    p.prevBody:SetText(sel.body)
    local info = #sel.body .. " / 255 characters"
    local d = desiredBy[sel.name]
    if d and d.seq then
      local s = d.seq
      info = info .. " · " .. (s.kind == "priority" and "priority list" or (s.kind == "sequence" and ("loop ~" .. ns.Engine.numstr(s.loopSec) .. " s") or s.kind))
      if s.compact then info = info .. " · shortened" end
    end
    if sel.status == "update" and sel.old then info = info .. "\n|cfff0b43cChanged from:|r " .. sel.old:gsub("\n", " / ") end
    if sel.why then info = info .. "\n|cffff8a80" .. sel.why .. "|r" end
    p.prevInfo:SetText(info)
    local b = barOf[sel.name]
    local keys, list = keysText(sel.name, b and b.status == "placed" and b.slot or nil)
    local direct = false
    for _, k in ipairs(list) do if k.via == "macro" then direct = true end end
    p.keysLine:SetText("Key: " .. (keys and ("|cffffd100" .. keys .. "|r") or "|cff9d9d9dnone|r") ..
      (b and b.status == "placed" and ("  ·  on " .. ns.Bars.slotLabel(b.slot)) or ""))
    p.bind:Show(); p.pickup:Show()
    p.unbind:SetShown(direct)
  else
    p.prevTitle:SetText(""); p.prevBody:SetText(""); p.prevInfo:SetText(""); p.keysLine:SetText("")
    p.bind:Hide(); p.unbind:Hide(); p.pickup:Hide()
  end

  if #ctx.missing > 0 then
    local n = {}
    for i, s in ipairs(ctx.missing) do if i <= 3 then n[#n + 1] = s.name end end
    p.trainer:SetText("Visit your trainer: " .. table.concat(n, ", ") .. (#ctx.missing > 3 and (" +" .. (#ctx.missing - 3)) or ""))
    W.tooltip(p.trainer, function(GT)
      GT:AddLine("Not in your spellbook yet", 1, 0.82, 0)
      for _, s in ipairs(ctx.missing) do GT:AddLine(s.name .. " (level " .. s.level .. ")", 1, 1, 1) end
      GT:AddLine("They are left out of your keys until you learn them.", 0.66, 0.6, 0.49, true)
    end)
  else p.trainer:SetText("") end

  p.bar1.Refresh(); p.bar2.Refresh()
  p.replace:SetChecked(cdb.replace and true or false)
  local _, charMax = ns.Compat.macroLimits()
  local used = charMax - ctx.macros.free - ctx.macros.counts.create
  p.slots:SetText(used .. " / " .. charMax .. " character macros" .. (ctx.macros.counts.noslot > 0 and ("  |cffff8a80" .. ctx.macros.counts.noslot .. " without a slot|r") or ""))
  local busy = ns.Compat.inCombat()
  p.apply:SetEnabled(not busy); p.macrosOnly:SetEnabled(not busy); p.bind:SetEnabled(not busy)
end

UI.RegisterTab(tab)
