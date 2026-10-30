--[[ WoWBoxer – dropdowns (docs/squad-overhaul.md §2). One API for both clients:
  - The war table look (docs/ui-redesign.md §3): our own list dropdown on every client – a flat pill with a gold ▾
    that opens one shared list frame with check rows; it closes on a choice, Esc or a click outside. Mouse only.
  - Without the themed skins (W.themed): Forever's modern menu system (CreateFrame("DropdownButton", …,
    "WowStyle1DropdownTemplate") + SetupMenu with radios) when it exists, else the same own list.
  Never UIDropDownMenu (deprecated in the modern UI and taint-prone).
  W.dropdown(parent, {width, values=fn -> {{value, label, tip?}}, get=fn, set=fn(value)}) returns a frame with
  Refresh(), select(value), step(±1), open() and isBlizzard. W.seqControl is the "Use sequence macros" box + tier. ]]
local _, ns = ...
local W = ns.Widgets

W.DROPDOWN_H = 24
W.LIST_ROW = 20
W.LIST_MAX = 16

--- True when this client has the modern menu system. Probed once; tests set W.forceOwnDropdown.
function W.hasBlizzardDropdown()
  if W.forceOwnDropdown or W.themed() then return false end
  if W._modernMenu == nil then
    W._modernMenu = false
    if type(_G.MenuUtil) == "table" then
      local ok, f = pcall(CreateFrame, "DropdownButton", nil, UIParent, "WowStyle1DropdownTemplate")
      if ok and f and type(f.SetupMenu) == "function" then W._modernMenu = true; f:Hide() end
    end
  end
  return W._modernMenu
end

local function labelOf(opts)
  local cur = opts.get()
  for _, v in ipairs(opts.values()) do if v[1] == cur then return v[2] end end
  return nil
end

-- ------------------------------------------------------------------ our own list (one for all dropdowns)
local function listFrame()
  if W.listFrame then return W.listFrame end
  local catcher = CreateFrame("Button", nil, UIParent) -- a click anywhere outside the list closes it
  catcher:SetAllPoints(UIParent)
  catcher:SetFrameStrata("FULLSCREEN_DIALOG")
  catcher:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  catcher._noHit = true
  catcher:Hide()
  local l = W.box(UIParent, 0.07, 0.055, 0.035, 0.98)
  if W.themed() then ns.Theme.paint(l, "panel", "line") end
  l:SetFrameStrata("TOOLTIP")
  l:SetClampedToScreen(true)
  l:EnableMouse(true)
  l.rows, l.catcher, l.offset, l.values = {}, catcher, 0, {}
  catcher:SetScript("OnClick", function() l:Hide() end)
  l:SetScript("OnHide", function() catcher:Hide(); l.owner = nil end)
  if l.EnableMouseWheel then l:EnableMouseWheel(true) end
  l:SetScript("OnMouseWheel", function(_, delta)
    if not l.owner then return end
    l.offset = math.max(0, math.min(#l.values - W.LIST_MAX, l.offset - delta))
    l.fill()
  end)
  function l.fill()
    local cur = l.owner and l.owner.opts.get()
    local shown = math.min(#l.values, W.LIST_MAX)
    for i = 1, shown do
      local v = l.values[i + l.offset]
      local b = l.rows[i]
      if not b then
        b = CreateFrame("Button", nil, l)
        b:SetHeight(W.LIST_ROW)
        local hl = b:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(ns.Theme.rgb("panel3"))
        b.radio = b:CreateTexture(nil, "ARTWORK")
        b.radio:SetSize(16, 16)
        b.radio:SetPoint("LEFT", 2, 0)
        if W.themed() then b.radio:SetTexture(ns.Theme.TEX .. "Check"); b.radio:SetVertexColor(ns.Theme.rgb("uiGold"))
        else b.radio:SetTexture("Interface\\Buttons\\UI-CheckBox-Check") end
        b.label = W.line(b, "GameFontHighlightSmall", nil, W.TEXT)
        b.label:SetPoint("LEFT", 22, 0)
        b.label:SetPoint("RIGHT", -4, 0)
        b:SetScript("OnClick", function(self) local o = l.owner; l:Hide(); if o then o.select(self.value) end end)
        W.tooltip(b, function(GT, self)
          GT:AddLine(self.text or "", 1, 0.82, 0)
          if self.tipText then GT:AddLine(self.tipText, 1, 1, 1, true) end
        end)
        l.rows[i] = b
      end
      b.value, b.text, b.tipText = v[1], v[2], v[3]
      b:SetWidth(l.rowW)
      b:ClearAllPoints()
      b:SetPoint("TOPLEFT", 6, -6 - (i - 1) * W.LIST_ROW)
      b.label:SetText(v[2])
      b.radio:SetShown(v[1] == cur)
      b:Show()
    end
    for i = shown + 1, #l.rows do l.rows[i]:Hide() end
    l:SetSize(l.rowW + 12, 12 + shown * W.LIST_ROW)
  end
  l:Hide()
  _G.WoWBoxerDropdownList = l
  table.insert(UISpecialFrames, "WoWBoxerDropdownList")
  W.listFrame = l
  return l
end

local function openList(dd)
  local l = listFrame()
  if l:IsShown() and l.owner == dd then l:Hide(); return end
  l:Hide()
  l.owner, l.values, l.offset = dd, dd.opts.values(), 0
  local width = math.max(dd:GetWidth() or 100, 100)
  for _, v in ipairs(l.values) do width = math.max(width, W.measure(v[2], "GameFontHighlightSmall") + 34) end
  l.rowW = math.min(width, (UIParent:GetWidth() or 800) - 40)
  local cur = dd.opts.get() -- start so the chosen row is visible
  for i, v in ipairs(l.values) do if v[1] == cur and i > W.LIST_MAX then l.offset = math.min(i - 1, #l.values - W.LIST_MAX) end end
  l.fill()
  l:SetScale((dd:GetEffectiveScale() or 1) / (UIParent:GetEffectiveScale() or 1))
  l:ClearAllPoints()
  l:SetPoint("TOPLEFT", dd, "BOTTOMLEFT", 0, -2)
  l.catcher:Show()
  l:Show()
end

-- ------------------------------------------------------------------ the dropdown
function W.dropdown(parent, opts)
  local width = opts.width or 150
  local dd
  if W.hasBlizzardDropdown() then
    dd = CreateFrame("DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
    dd.isBlizzard = true
    dd:SetWidth(width)
    dd:SetupMenu(function(_, root)
      local ok, vals = pcall(opts.values) -- the values may depend on state the owner sets later
      for _, v in ipairs(ok and vals or {}) do
        local value = v[1]
        local r = root:CreateRadio(v[2], function() return opts.get() == value end, function() dd.select(value) end, value)
        if v[3] and r and r.SetTooltip then
          r:SetTooltip(function(tt) tt:AddLine(v[2], 1, 0.82, 0); tt:AddLine(v[3], 1, 1, 1, true) end)
        end
      end
    end)
  else
    local themed = W.themed()
    dd = W.frame("Button", parent, (not themed and _G.BackdropTemplateMixin) and "BackdropTemplate" or nil)
    dd:SetSize(width, W.DROPDOWN_H)
    if themed then
      -- the pill: night-2, gold line border, radius 4, a gold ▾ on the right
      ns.Theme.box(dd, "night2", "line", 4)
      dd.arrow = ns.Theme.glyph(dd, "Chevron", 14, "gold")
      dd.arrow:SetPoint("RIGHT", -8, 0)
      local hl = ns.Theme.slice(dd, ns.Theme.TEX .. "Fill4", 4, "HIGHLIGHT")
      for _, t in ipairs(hl) do t:SetVertexColor(ns.Theme.rgb("goldHi")); t:SetAlpha(0.08) end
    else
      if dd.SetBackdrop then
        dd:SetBackdrop(W.BACKDROP)
        dd:SetBackdropColor(0.04, 0.03, 0.02, 0.95)
        dd:SetBackdropBorderColor(0.54, 0.43, 0.2, 1)
      end
      dd.arrow = dd:CreateTexture(nil, "ARTWORK")
      dd.arrow:SetSize(16, 16)
      dd.arrow:SetPoint("RIGHT", -4, 0)
      dd.arrow:SetTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up")
      local hl = dd:CreateTexture(nil, "HIGHLIGHT")
      hl:SetPoint("TOPLEFT", 3, -3)
      hl:SetPoint("BOTTOMRIGHT", -3, 3)
      hl:SetColorTexture(1, 0.82, 0, 0.12)
    end
    dd.label = W.line(dd, "GameFontHighlight", 12, W.TEXT)
    dd.label:SetPoint("LEFT", 8, 0)
    dd.label:SetPoint("RIGHT", dd.arrow, "LEFT", -2, 0)
    dd:SetScript("OnClick", function(self) if self:IsEnabled() then openList(self) end end)
    local enable = dd.SetEnabled
    dd.SetEnabled = function(self, v)
      enable(self, v)
      local c = v and W.TEXT or W.MUTED
      self.label:SetTextColor(c[1], c[2], c[3])
      if self.arrow.SetDesaturated then self.arrow:SetDesaturated(not v) end
    end
  end
  dd.opts = opts
  function dd.Refresh()
    if dd.isBlizzard then
      if dd.GenerateMenu then dd:GenerateMenu() end
      if dd.OverrideText then dd:OverrideText(labelOf(opts) or opts.placeholder or "-") end
    else
      dd.label:SetText(labelOf(opts) or opts.placeholder or "-")
    end
  end
  --- Choose a value: what a click on a row does.
  function dd.select(value)
    opts.set(value)
    dd.Refresh()
  end
  --- Next / previous value (tests).
  function dd.step(d)
    local vals = opts.values()
    if #vals == 0 then return end
    local cur, i = opts.get(), 1
    for k, v in ipairs(vals) do if v[1] == cur then i = k end end
    dd.select(vals[((i - 1 + d) % #vals) + 1][1])
  end
  function dd.open() if dd.isBlizzard then if dd.OpenMenu then dd:OpenMenu() end else openList(dd) end end
  pcall(dd.Refresh) -- the values may depend on state that is set later (the owner refreshes then)
  return dd
end

--- A tooltip on a dropdown that keeps the menu's own scripts.
function W.ddTip(dd, title, text)
  local function show(self)
    local GT = _G.GameTooltip
    GT:SetOwner(self, "ANCHOR_RIGHT")
    GT:AddLine(title, 1, 0.82, 0)
    local t = type(text) == "function" and text() or text
    if t and t ~= "" then GT:AddLine(t, 1, 1, 1, true) end
    GT:Show()
  end
  local function hide() _G.GameTooltip:Hide() end
  if dd.isBlizzard then dd:HookScript("OnEnter", show); dd:HookScript("OnLeave", hide)
  else dd:SetScript("OnEnter", show); dd:SetScript("OnLeave", hide) end
end

--- Label + dropdown in one: returns the label (anchor the dropdown to it with "LEFT", label, "RIGHT").
function W.labelled(parent, text, dd, gap)
  local l = W.text(parent, "GameFontNormalSmall", nil, W.GOLD)
  l:SetText(text)
  dd:SetPoint("LEFT", l, "RIGHT", gap or 6, 0)
  return l
end

-- ------------------------------------------------------------------ sequence keys: [x] Use sequence keys + tier
W.SEQ_TIERS = {
  { "simple", "Simple", "Few spells: your main spell and one more." },
  { "medium", "Medium", "The usual rotation for your level." },
  { "advanced", "Advanced", "More spells and dots – for experienced players." },
}
W.SEQ_CLASSES = "Every class has built-in sequence macros – make your own under My own macros."
--- One sentence each: sequence keys vs priority keys (docs/sequences-all-classes.md §4).
W.SEQ_KINDS = "Sequence macro: each press casts the next spell of a fixed order (DoTs first, then the filler). " ..
  "Priority macro: each press casts the first spell in the list that is ready (Execute, Revenge, Stormstrike …)."
local SEQ_LABEL = "Use sequence macros"
--- opts: {member=fn -> m, set=fn(m, tier)? (default: m.seq = tier + Core.changed()), width (dropdown, default 100)}.
--- A frame (check + tier dropdown, or a note for classes without sequences) with Refresh() and its own width.
function W.seqControl(parent, opts)
  local ddW = opts.width or 100
  local f = CreateFrame("Frame", nil, parent)
  local function set(m, tier)
    if opts.set then opts.set(m, tier) else m.seq = tier; ns.Core.log("info", "sequence macros " .. tier); ns.Core.changed() end
  end
  f.check = W.check(f, SEQ_LABEL, function(_, v)
    local m = opts.member()
    if not m then return end
    if v then set(m, (m.seqTier and m.seqTier ~= "off") and m.seqTier or "simple")
    else
      if m.seq ~= "off" then m.seqTier = m.seq end
      set(m, "off")
    end
  end)
  f.check:SetPoint("LEFT", 0, 0)
  W.tip(f.check, SEQ_LABEL, function()
    local m = opts.member()
    if m and not ns.Engine.seqSupported(m.cls) then return W.SEQ_CLASSES end
    return "Adds a macro that casts your rotation. " .. W.SEQ_KINDS .. " One press is still one spell on one character."
  end)
  f.tier = W.dropdown(f, { width = ddW,
    values = function() return W.SEQ_TIERS end,
    get = function() local m = opts.member(); if not m then return nil end; return m.seq ~= "off" and m.seq or m.seqTier or "simple" end,
    set = function(v) local m = opts.member(); if m then m.seqTier = v; set(m, v) end end })
  f.tier:SetPoint("LEFT", f.check.label, "RIGHT", 6, 0)
  W.ddTip(f.tier, "Sequence macros", "Simple: few spells. Medium: the usual rotation. Advanced: more spells and dots. Untick the box to turn sequence macros off.")
  f.note = W.line(f, "GameFontHighlightSmall", nil, W.MUTED)
  f.note:SetPoint("LEFT", f.check.label, "RIGHT", 6, 0)
  f.note:SetWidth(ddW)
  f.note:SetText("Not for this class")
  f.noteHit = CreateFrame("Frame", nil, f)
  f.noteHit:SetAllPoints(f.note)
  W.tip(f.noteHit, SEQ_LABEL, W.SEQ_CLASSES)
  f:SetSize(22 + 2 + W.measure(SEQ_LABEL, "GameFontHighlightSmall") + 6 + ddW, W.DROPDOWN_H)
  function f.Refresh()
    local m = opts.member()
    local ok = (m and ns.Engine.seqSupported(m.cls)) and true or false
    f.check:SetEnabled(ok)
    f.check:SetChecked(ok and m.seq ~= "off")
    local c = ok and W.TEXT or W.MUTED
    f.check.label:SetTextColor(c[1], c[2], c[3])
    f.tier:SetShown(ok); f.note:SetShown(not ok); f.noteHit:SetShown(not ok)
    if ok then f.tier.Refresh(); f.tier:SetEnabled(m.seq ~= "off") end
  end
  return f
end
