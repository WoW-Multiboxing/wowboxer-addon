--[[ WoWBoxer – small widget helpers on plain Blizzard frames (no libraries).
  Only templates that exist in both Forever (modern UI) and Classic Era are used; every template is optional. ]]
local _, ns = ...
local W = {}
ns.Widgets = W

W.GOLD = { 1, 0.82, 0 }
W.TEXT = { 0.91, 0.86, 0.75 }
W.MUTED = { 0.66, 0.6, 0.49 }
W.GREEN = { 0.56, 0.75, 0.42 }
W.ORANGE = { 0.94, 0.71, 0.24 }
W.RED = { 1, 0.54, 0.5 }
W.BLUE = { 0.49, 0.78, 1 }

--- CreateFrame with an optional template (falls back to no template if it does not exist on this client).
function W.frame(kind, parent, template, name)
  if template then
    local ok, f = pcall(CreateFrame, kind, name, parent, template)
    if ok and f then return f end
  end
  return CreateFrame(kind, name, parent)
end

local BACKDROP = {
  bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
  edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
  tile = true, tileSize = 16, edgeSize = 12,
  insets = { left = 3, right = 3, top = 3, bottom = 3 },
}
W.BACKDROP = BACKDROP
--- A dark box with a thin border.
function W.box(parent, r, g, b, a)
  local f = W.frame("Frame", parent, _G.BackdropTemplateMixin and "BackdropTemplate" or nil)
  if f.SetBackdrop then
    f:SetBackdrop(BACKDROP)
    f:SetBackdropColor(r or 0.07, g or 0.055, b or 0.035, a or 0.92)
    f:SetBackdropBorderColor(0.54, 0.43, 0.2, 1)
  else
    local t = f:CreateTexture(nil, "BACKGROUND")
    t:SetAllPoints()
    t:SetColorTexture(r or 0.07, g or 0.055, b or 0.035, a or 0.92)
  end
  return f
end

function W.text(parent, font, size, color, justify)
  local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
  if size and fs.SetFont then
    local file, _, flags = fs:GetFont()
    if file then fs:SetFont(file, size, flags) end
  end
  if color then fs:SetTextColor(color[1], color[2], color[3]) end
  fs:SetJustifyH(justify or "LEFT")
  if fs.SetWordWrap then fs:SetWordWrap(true) end
  return fs
end

--- Width a text needs in a font size (real client: measured with a hidden font string; same formula in the simulator).
local ruler
function W.measure(text, font)
  if not ruler then ruler = UIParent:CreateFontString(nil, "OVERLAY", "GameFontNormal"); ruler:Hide() end
  if ruler.SetFontObject and font then ruler:SetFontObject(_G[font] or font) end
  ruler:SetText(text or "")
  return ruler:GetStringWidth() or 0
end

--- A Blizzard button that is always wide enough for its label (minimum `width`). tip = "text" or {title, text}:
--- the tooltip says what the click will do in the game.
function W.button(parent, label, width, height, onClick, tip)
  local b = W.frame("Button", parent, "UIPanelButtonTemplate")
  b.minWidth = width or 80
  b:SetHeight(height or 22)
  W.setLabel(b, label)
  if onClick then b:SetScript("OnClick", function(self, button) onClick(self, button) end) end
  if tip then W.tip(b, type(tip) == "table" and tip[1] or label, type(tip) == "table" and tip[2] or tip) end
  return b
end
--- Change a button's label and grow it to fit (text width + 24).
function W.setLabel(b, label)
  b:SetText(label)
  local tw = (b.GetTextWidth and b:GetTextWidth()) or 0
  if not tw or tw <= 0 then tw = W.measure(label, "GameFontNormal") end
  b:SetWidth(math.max(b.minWidth or 0, math.ceil(tw + 24)))
end
--- A simple tooltip: gold title + one wrapped line (+ optional grey hint).
function W.tip(frame, title, text, hint)
  W.tooltip(frame, function(GT)
    GT:AddLine(type(title) == "function" and title() or title, 1, 0.82, 0)
    local t = type(text) == "function" and text() or text
    if t and t ~= "" then GT:AddLine(t, 1, 1, 1, true) end
    if hint then GT:AddLine(hint, 0.66, 0.6, 0.49, true) end
  end)
end
--- A one-line text that is cut with "…" when too long; the full text goes into the owner's tooltip (fs.wbxTrunc).
function W.line(parent, font, size, color, justify)
  local fs = W.text(parent, font, size, color, justify)
  if fs.SetWordWrap then fs:SetWordWrap(false) end
  if fs.SetMaxLines then fs:SetMaxLines(1) end
  fs.wbxTrunc = true
  return fs
end
--- Lay out buttons in a row from right to left (anchor = first button's RIGHT point), `gap` apart.
function W.rowRight(buttons, gap)
  local prev
  for _, b in ipairs(buttons) do
    if b:IsShown() then
      if prev then b:ClearAllPoints(); b:SetPoint("RIGHT", prev, "LEFT", -(gap or 6), 0) end
      prev = b
    end
  end
end

function W.check(parent, label, onClick)
  local c = W.frame("CheckButton", parent, "UICheckButtonTemplate")
  c:SetSize(22, 22)
  local t = W.text(c, "GameFontHighlightSmall")
  t:SetPoint("LEFT", c, "RIGHT", 2, 0)
  t:SetText(label)
  c.label = t
  if onClick then c:SetScript("OnClick", function(self) onClick(self, self:GetChecked() and true or false) end) end
  return c
end

--- The template's scroll bar: arrows get a tooltip; the bar hides when the content fits (contentH given).
--- No unlabeled buttons (docs/ui-spec-v3-book.md, key editor).
function W.tidyScroll(sf, contentH)
  local bar = rawget(sf, "ScrollBar")
  if type(bar) ~= "table" then return end
  if not rawget(bar, "wbxTips") then
    bar.wbxTips = true
    for _, k in ipairs({ { "ScrollUpButton", "Scroll up" }, { "ScrollDownButton", "Scroll down" } }) do
      local b = rawget(bar, k[1])
      if type(b) == "table" and b.HookScript then
        b:HookScript("OnEnter", function(self) local GT = _G.GameTooltip; GT:SetOwner(self, "ANCHOR_RIGHT"); GT:AddLine(k[2], 1, 0.82, 0); GT:Show() end)
        b:HookScript("OnLeave", function() _G.GameTooltip:Hide() end)
      end
    end
  end
  if contentH then
    local fits = contentH <= (sf:GetHeight() or 0) + 1
    if fits and bar.Hide then bar:Hide() elseif bar.Show then bar:Show() end
  end
end

--- Scroll area with a content frame. Returns scroll, content.
function W.scroll(parent, width, height)
  local sf = W.frame("ScrollFrame", parent, "UIPanelScrollFrameTemplate")
  sf.scrollBarHideable = true
  sf:SetSize(width, height)
  local content = CreateFrame("Frame", nil, sf)
  content:SetSize(width, height)
  sf:SetScrollChild(content)
  W.tidyScroll(sf)
  return sf, content
end

--- Multi-line edit box in a scroll frame.
function W.editBox(parent, width, height)
  local sf = W.frame("ScrollFrame", parent, "UIPanelScrollFrameTemplate")
  sf:SetSize(width, height)
  local eb = CreateFrame("EditBox", nil, sf)
  eb:SetMultiLine(true)
  eb:SetAutoFocus(false)
  eb:SetFontObject(_G.ChatFontNormal or _G.GameFontHighlightSmall)
  eb:SetWidth(width)
  eb:SetHeight(height)
  eb:SetMaxLetters(20000)
  eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  sf:SetScrollChild(eb)
  W.tidyScroll(sf)
  local bg = W.box(parent, 0.04, 0.03, 0.02, 0.95)
  bg:SetPoint("TOPLEFT", sf, "TOPLEFT", -4, 4)
  bg:SetPoint("BOTTOMRIGHT", sf, "BOTTOMRIGHT", 4, -4)
  bg:SetFrameLevel(math.max(0, (sf:GetFrameLevel() or 1) - 1))
  sf:EnableMouse(true)
  sf:SetScript("OnMouseDown", function() eb:SetFocus() end)
  return eb, sf
end

--- Spell-style icon. border=true adds the spec's thin gold frame (a 1 px darker-gold square behind the icon).
function W.icon(parent, size, border)
  local t = parent:CreateTexture(nil, "ARTWORK")
  t:SetSize(size or 20, size or 20)
  if t.SetTexCoord then t:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
  if border then
    local b = parent:CreateTexture(nil, "BORDER")
    b:SetPoint("TOPLEFT", t, "TOPLEFT", -1, 1)
    b:SetPoint("BOTTOMRIGHT", t, "BOTTOMRIGHT", 1, -1)
    b:SetColorTexture(0.54, 0.43, 0.2, 1)
    t.border = b
  end
  return t
end
--- A composite icon of up to 4 spells over `box` (docs/squad-overhaul.md §1.3): 1 = whole icon, 2 = side by side,
--- 3 = the main spell on the left half + two quarters, 4 = 2 x 2. The first icon in the list (the main spell) gets the
--- biggest part. Returns {set(list), Hide(), Show(), parts}.
function W.composite(parent, box, layer)
  local c = { parts = {} }
  for i = 1, 4 do
    local t = parent:CreateTexture(nil, layer or "ARTWORK")
    t:Hide()
    c.parts[i] = t
  end
  local function place(t, x0, y0, x1, y1, crop)
    t:ClearAllPoints()
    t:SetPoint("TOPLEFT", box, "TOPLEFT", x0, -y0)
    t:SetPoint("BOTTOMRIGHT", box, "TOPLEFT", x1, -y1)
    if t.SetTexCoord then t:SetTexCoord(crop[1], crop[2], crop[3], crop[4]) end
    t:Show()
  end
  local HALF, SQUARE = { 0.29, 0.71, 0.08, 0.92 }, { 0.2, 0.8, 0.2, 0.8 }
  function c.set(list, size)
    local n = math.min(#list, 4)
    local S, g = size or 34, 1
    for i = 1, 4 do c.parts[i]:Hide() end
    for i = 1, n do W.setIcon(c.parts[i], list[i]) end
    local h = S / 2
    if n == 1 then place(c.parts[1], 0, 0, S, S, { 0.08, 0.92, 0.08, 0.92 })
    elseif n == 2 then place(c.parts[1], 0, 0, h - g, S, HALF); place(c.parts[2], h, 0, S, S, HALF)
    elseif n == 3 then
      place(c.parts[1], 0, 0, h - g, S, HALF); place(c.parts[2], h, 0, S, h - g, SQUARE); place(c.parts[3], h, h, S, S, SQUARE)
    elseif n == 4 then
      place(c.parts[1], 0, 0, h - g, h - g, SQUARE); place(c.parts[2], h, 0, S, h - g, SQUARE)
      place(c.parts[3], 0, h, h - g, S, SQUARE); place(c.parts[4], h, h, S, S, SQUARE)
    end
  end
  function c.Hide() for i = 1, 4 do c.parts[i]:Hide() end end
  function c.SetDesaturated(_, v) for i = 1, 4 do if c.parts[i].SetDesaturated then c.parts[i]:SetDesaturated(v) end end end
  function c.SetAlpha(_, a) for i = 1, 4 do c.parts[i]:SetAlpha(a) end end
  return c
end
--- "|T…|t Immolate → |T…|t Shadow Bolt ×4": the steps of a sequence in cast order with small icons.
function W.stepsText(steps, size)
  local out, i = {}, 1
  while i <= #steps do
    local s, n = steps[i], 1
    while steps[i + n] == s do n = n + 1 end
    local icon = type(s.icon) == "number" and s.icon or ("Interface\\Icons\\" .. (s.icon or "INV_Misc_QuestionMark"))
    out[#out + 1] = "|T" .. icon .. ":" .. (size or 14) .. "|t " .. s.name .. (n > 1 and (" ×" .. n) or "")
    i = i + n
  end
  return table.concat(out, " → ")
end

--- Scrollbar width of UIPanelScrollFrameTemplate: it sits to the right, OUTSIDE the scroll frame. Keep this much free.
W.SCROLLBAR = 24
function W.setIcon(tex, slugOrId)
  if type(slugOrId) == "number" then tex:SetTexture(slugOrId)
  elseif type(slugOrId) == "string" and slugOrId ~= "" then tex:SetTexture("Interface\\Icons\\" .. slugOrId)
  else tex:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark") end
end

--- Tooltip helper.
function W.tooltip(frame, fn)
  if frame.EnableMouse then frame:EnableMouse(true) end
  frame:SetScript("OnEnter", function(self)
    local GT = _G.GameTooltip
    GT:SetOwner(self, "ANCHOR_RIGHT")
    fn(GT, self)
    GT:Show()
  end)
  frame:SetScript("OnLeave", function() _G.GameTooltip:Hide() end)
end

function W.classColor(cls)
  local c = _G.RAID_CLASS_COLORS and _G.RAID_CLASS_COLORS[(cls or ""):upper()]
  if c then return { c.r, c.g, c.b } end
  return W.TEXT
end
function W.hex(c) return string.format("|cff%02x%02x%02x", math.floor(c[1] * 255), math.floor(c[2] * 255), math.floor(c[3] * 255)) end

--- Row pool for lists: rows are created on demand and reused.
function W.pool(content, make)
  local p = { rows = {}, used = 0 }
  function p:reset() for _, r in ipairs(self.rows) do r:Hide() end self.used = 0 end
  function p:get()
    self.used = self.used + 1
    local r = self.rows[self.used]
    if not r then r = make(content, self.used); self.rows[self.used] = r end
    r:Show()
    return r
  end
  return p
end

--- A small click menu at `anchor`: items = {{label, fn, tip?, disabled?}}. One menu at a time; Esc closes it.
function W.menu(anchor, items)
  local m = W.menuFrame
  if not m then
    m = W.box(UIParent, 0.07, 0.055, 0.035, 0.97)
    m:SetFrameStrata("TOOLTIP")
    m:SetClampedToScreen(true)
    m.rows = {}
    m:Hide()
    _G.WoWBoxerMenu = m
    table.insert(UISpecialFrames, "WoWBoxerMenu")
    W.menuFrame = m
  end
  if m:IsShown() and m.anchor == anchor then m:Hide(); return m end
  local width = 120
  for _, it in ipairs(items) do width = math.max(width, W.measure(it[1], "GameFontHighlightSmall") + 24) end
  for i, it in ipairs(items) do
    local b = m.rows[i]
    if not b then
      b = CreateFrame("Button", nil, m)
      b:SetHeight(20)
      local hl = b:CreateTexture(nil, "HIGHLIGHT")
      hl:SetAllPoints()
      hl:SetColorTexture(1, 0.82, 0, 0.18)
      b.label = W.text(b, "GameFontHighlightSmall", nil, W.TEXT)
      b.label:SetPoint("LEFT", 8, 0)
      b.label:SetPoint("RIGHT", -4, 0)
      m.rows[i] = b
    end
    b:SetWidth(width)
    b:SetPoint("TOPLEFT", 6, -6 - (i - 1) * 21)
    b.label:SetText(it[1])
    local c = it[4] and W.MUTED or W.TEXT -- it[4] = disabled: greyed, a click does nothing (the tip says why)
    b.label:SetTextColor(c[1], c[2], c[3])
    b.disabled = it[4] and true or nil
    b:SetScript("OnClick", function() if it[4] then return end m:Hide(); it[2]() end)
    if it[3] then W.tip(b, it[1], it[3]) end
    b:Show()
  end
  for i = #items + 1, #m.rows do m.rows[i]:Hide() end
  m:SetSize(width + 12, 12 + #items * 21)
  m.anchor = anchor
  m:ClearAllPoints()
  m:SetPoint("TOPLEFT", anchor, "BOTTOMRIGHT", -8, 8)
  m:Show()
  return m
end
