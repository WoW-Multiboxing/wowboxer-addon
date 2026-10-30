--[[ WoWBoxer – small widget helpers on plain frames (no libraries), in the "war table" look of UI/Theme.lua
  (docs/ui-redesign.md). The Blizzard templates our pages ask for (button, check box, input box, scroll frame, close
  button) are drawn by our own skins; a client without the API for a skin (CreateFont) keeps the template. ]]
local _, ns = ...
local W = {}
ns.Widgets = W
local T = ns.Theme

-- the colour names the pages use, as theme tokens
local function tok(name) local c = T.C[name]; return { c[1], c[2], c[3] } end
W.GOLD = tok("uiGold")
W.TEXT = tok("text")
W.MUTED = tok("muted")
W.GREEN = tok("ok")
W.ORANGE = tok("warn")
W.RED = tok("no")
W.BLUE = tok("goldHi") -- "new" / "drag me" hints: gold-hi in the war table look
W.PARCHMENT = tok("parchment")

--- True when the themed skins can be drawn on this client (fonts for buttons and edit boxes need CreateFont).
function W.themed() return _G.CreateFont ~= nil and not W.forceOldLook end

local SKIN = {} -- template -> skin(frame), filled in below
W.SKIN = SKIN
--- CreateFrame with an optional template. Templates with a skin of ours are drawn by the skin instead; any other
--- template falls back to no template if it does not exist on this client.
function W.frame(kind, parent, template, name)
  if template and SKIN[template] and W.themed() then
    local f = CreateFrame(kind, name, parent)
    SKIN[template](f)
    return f
  end
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
--- A box with a thin border: a card (panel-2) or, for very dark colours, an inset well (night-2). In the themed look
--- the colour arguments only pick which of the two; `a` is the fill alpha.
function W.box(parent, r, g, b, a)
  if W.themed() then
    local f = CreateFrame("Frame", nil, parent)
    local dark = ((r or 0.07) + (g or 0.055) + (b or 0.035)) / 3 < 0.05
    T.box(f, dark and "night2" or "panel2", "lineSoft", 6, a or 1)
    return f
  end
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
--- A window-style box (dialogs, popups, menus): panel fill, gold line border, radius 10.
function W.window(parent)
  if not W.themed() then return W.box(parent, 0.11, 0.085, 0.05, 0.99) end
  local f = CreateFrame("Frame", nil, parent)
  T.box(f, "panel", "line", 10)
  return f
end

-- the colour a Blizzard font template stands for, in the war table look
local function templateColor(font)
  if font:find("Disable", 1, true) then return W.MUTED end
  if font:find("Normal", 1, true) then return W.GOLD end
  return W.TEXT
end
--- A font string. `font` is a Blizzard font template name; in the themed look it picks our role and size
--- (T.TEMPLATE); `size` overrides the size. Names and spell names: W.gameFont(fs) afterwards.
function W.text(parent, font, size, color, justify)
  font = font or "GameFontHighlightSmall"
  local fs = parent:CreateFontString(nil, "OVERLAY", font)
  local map = W.themed() and T.TEMPLATE[font]
  if map then
    T.font(fs, map[1], size or map[2])
    color = color or templateColor(font)
  elseif size and fs.SetFont then
    local file, _, flags = fs:GetFont()
    if file then fs:SetFont(file, size, flags) end
  end
  fs.wbxFont = font
  if color then fs:SetTextColor(color[1], color[2], color[3]) end
  fs:SetJustifyH(justify or "LEFT")
  if fs.SetWordWrap then fs:SetWordWrap(true) end
  return fs
end
--- Keep the game font on a font string (character names, spell names, chat-like text: every locale renders).
function W.gameFont(fs, size)
  if fs and W.themed() then
    local _, cur = fs:GetFont()
    T.font(fs, "game", size or cur)
  end
  return fs
end
--- Put a theme role on a font string: "heading" (Cinzel), "bold", "body" (Inter) or "game".
function W.role(fs, role, size) if W.themed() then T.font(fs, role, size) end return fs end

--- Width a text needs in a font template (real client: measured with a hidden font string in the same font; the
--- simulator uses the same formula as for every text).
local ruler
function W.measure(text, font)
  if not ruler then ruler = UIParent:CreateFontString(nil, "OVERLAY", "GameFontNormal"); ruler:Hide() end
  font = font or "GameFontNormal"
  if ruler.SetFontObject then ruler:SetFontObject(_G[font] or font) end
  local map = W.themed() and T.TEMPLATE[font]
  if map then T.font(ruler, map[1], map[2]) end
  ruler:SetText(text or "")
  return ruler:GetStringWidth() or 0
end

--- A button that is always wide enough for its label (minimum `width`). tip = "text" or {title, text}: the tooltip
--- says what the click will do in the game. Secondary style; W.primary(b) for the page's main action.
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

-- ------------------------------------------------------------------ button styles (§2: one red primary per page)
-- secondary: gold outline · primary: horde red, Cinzel · raised: panel-3 with a gold-lo border · ghost: text only
-- (a link) · segment: one part of a segmented control · nav: a row of the left rail. Hover = a soft wash in the
-- HIGHLIGHT layer (no script is taken from the page); LockHighlight keeps it on.
local STYLE = {
  secondary = { fill = "none", border = "line", role = "bold", size = 12, color = "text", hi = "uiGold" },
  primary = { fill = "horde", border = "goldLo", role = "heading", size = 13, color = "uiGold", hi = "parchment" },
  raised = { fill = "panel3", border = "goldLo", role = "bold", size = 12, color = "uiGold", hi = "parchment" },
  ghost = { fill = "none", border = "none", role = "bold", size = 12, color = "goldHi", hi = "uiGold" },
  segment = { fill = "none", border = "none", role = "bold", size = 12, color = "muted", hi = "text" },
  nav = { fill = "none", border = "none", role = "bold", size = 13, color = "text", hi = "uiGold" },
}
W.STYLE = STYLE
function W.setStyle(b, style)
  local st = STYLE[style] or STYLE.secondary
  b.wbxStyle = style
  if not (W.themed() and b.wbxSkinned) then return b end
  T.box(b, st.fill, st.border, 4)
  if b.SetNormalFontObject then
    b:SetNormalFontObject(T.fontObject(st.role, st.size, st.color))
    b:SetHighlightFontObject(T.fontObject(st.role, st.size, st.hi))
    b:SetDisabledFontObject(T.fontObject(st.role, st.size, "muted"))
  end
  if b.GetText and b:GetText() and b.minWidth then W.setLabel(b, b:GetText()) end
  return b
end
--- The page's one primary action (red, Cinzel).
function W.primary(b) return W.setStyle(b, "primary") end
local function hover(b, token, alpha)
  local hl = T.slice(b, T.TEX .. "Fill4", 4, "HIGHLIGHT")
  for _, t in ipairs(hl) do t:SetVertexColor(T.rgb(token)); t:SetAlpha(alpha or 1) end
  b.wbxHover = hl
end
SKIN.UIPanelButtonTemplate = function(b)
  b.wbxSkinned = true
  hover(b, "goldHi", 0.12)
  if b.SetPushedTextOffset then b:SetPushedTextOffset(0, -1) end
  W.setStyle(b, "secondary")
end
SKIN.UIPanelCloseButton = function(b)
  b.wbxSkinned = true
  b:SetSize(28, 28)
  b.glyph = T.glyph(b, "Close", 16, "muted")
  b.glyph:SetPoint("CENTER")
  hover(b, "panel3")
  W.tip(b, "Close", "Closes this window.")
end
-- check box: a 16-unit dark box with a gold rim inside the 22 x 22 click area; checked = a gold check mark
SKIN.UICheckButtonTemplate = function(c)
  c.wbxSkinned = true
  c:SetSize(22, 22)
  local box = CreateFrame("Frame", nil, c)
  box:SetSize(16, 16)
  box:SetPoint("CENTER")
  T.box(box, "night2", "gold", 3)
  c.wbxBoxFrame = box
  local tick = T.glyph(c, "Check", 16, "uiGold", "OVERLAY")
  tick:SetPoint("CENTER")
  c:SetCheckedTexture(tick)
  local dis = T.glyph(c, "Check", 16, "muted", "OVERLAY")
  dis:SetPoint("CENTER")
  if c.SetDisabledCheckedTexture then c:SetDisabledCheckedTexture(dis) end
  local hl = c:CreateTexture(nil, "HIGHLIGHT")
  hl:SetTexture(T.TEX .. "Ring3")
  hl:SetSize(16, 16)
  hl:SetPoint("CENTER")
  hl:SetVertexColor(T.rgb("goldHi"))
  c:SetHighlightTexture(hl)
end
-- input box: a night-2 well with a gold rim that brightens while typing
SKIN.InputBoxTemplate = function(eb)
  eb.wbxSkinned = true
  T.box(eb, "night2", "line", 4)
  eb:SetFontObject(T.fontObject("body", 12, "parchment"))
  if eb.SetTextInsets then eb:SetTextInsets(8, 8, 0, 0) end
  eb:SetAutoFocus(false)
  eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  eb:HookScript("OnEditFocusGained", function(self) T.paint(self, nil, "goldHi") end)
  eb:HookScript("OnEditFocusLost", function(self) T.paint(self, nil, "line") end)
end
-- scroll frame: mouse wheel + a thin gold bar in the 24 units right of the frame (W.SCROLLBAR)
SKIN.UIPanelScrollFrameTemplate = function(sf)
  sf.wbxSkinned = true
  if sf.EnableMouseWheel then sf:EnableMouseWheel(true) end
  local bar = CreateFrame("Slider", nil, sf)
  bar:SetWidth(6)
  bar:SetPoint("TOPLEFT", sf, "TOPRIGHT", 9, 0)
  bar:SetPoint("BOTTOMLEFT", sf, "BOTTOMRIGHT", 9, 0)
  if bar.SetOrientation then bar:SetOrientation("VERTICAL") end
  T.box(bar, "night2", "none", 3)
  local thumb = bar:CreateTexture(nil, "ARTWORK")
  thumb:SetTexture(T.TEX .. "Fill3")
  thumb:SetVertexColor(T.rgb("gold"))
  thumb:SetSize(6, 36)
  bar:SetThumbTexture(thumb)
  bar:SetMinMaxValues(0, 0)
  bar:SetValue(0)
  if bar.SetValueStep then bar:SetValueStep(1) end
  bar:SetScript("OnValueChanged", function(_, v) sf:SetVerticalScroll(v) end)
  sf:SetScript("OnScrollRangeChanged", function(self, _, yr)
    yr = yr or (self.GetVerticalScrollRange and self:GetVerticalScrollRange()) or 0
    bar:SetMinMaxValues(0, yr)
    if (bar:GetValue() or 0) > yr then bar:SetValue(yr) end
    if self.scrollBarHideable then bar:SetShown(yr > 0) end
  end)
  sf:SetScript("OnVerticalScroll", function(_, off) if bar:GetValue() ~= off then bar:SetValue(off) end end)
  sf:SetScript("OnMouseWheel", function(_, delta)
    local lo, hi = bar:GetMinMaxValues()
    bar:SetValue(math.max(lo, math.min(hi, (bar:GetValue() or 0) - delta * 30)))
  end)
  sf.ScrollBar = bar
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

--- On/off switch (a 30 x 16 track with a knob) + label; same API as W.check (GetChecked/SetChecked, onClick(self, on)).
function W.toggle(parent, label, onClick)
  if not W.themed() then return W.check(parent, label, onClick) end
  local c = CreateFrame("CheckButton", nil, parent)
  c:SetSize(30, 16)
  c.wbxSkinned, c.wbxToggle = true, true
  T.box(c, "panel3", "line", 8)
  c.knob = c:CreateTexture(nil, "ARTWORK")
  c.knob:SetTexture(T.TEX .. "Fill6")
  c.knob:SetSize(12, 12)
  local function paint(self)
    local on = self:GetChecked() and true or false
    T.paint(self, on and "gold" or "panel3", on and "gold" or "line")
    self.knob:ClearAllPoints()
    self.knob:SetPoint(on and "RIGHT" or "LEFT", on and -2 or 2, 0)
    self.knob:SetVertexColor(T.rgb(on and "night" or "muted"))
  end
  local set = c.SetChecked
  c.SetChecked = function(self, v) set(self, v); paint(self) end
  local t = W.text(c, "GameFontHighlight")
  t:SetPoint("LEFT", c, "RIGHT", 8, 0)
  t:SetText(label)
  c.label = t
  c:SetScript("OnClick", function(self) paint(self); if onClick then onClick(self, self:GetChecked() and true or false) end end)
  paint(c)
  return c
end

--- A segmented control: items = {{value, label, tip?}}; get() -> value; set(value). Returns the frame (Refresh()).
function W.segmented(parent, items, get, set, size)
  local g = CreateFrame("Frame", nil, parent)
  g:SetHeight((size or 12) + 12)
  if W.themed() then T.box(g, "night2", "lineSoft", 4) end
  g.buttons = {}
  local x = 2
  for i, it in ipairs(items) do
    local b = W.button(g, it[2], 40, (size or 12) + 8, function() set(it[1]); g.Refresh() end, it[3] and { it[2], it[3] } or nil)
    W.setStyle(b, "segment")
    b:SetPoint("LEFT", x, 0)
    x = x + b:GetWidth() + 2
    b.value = it[1]
    g.buttons[i] = b
  end
  g:SetWidth(x)
  function g.Refresh()
    local cur = get()
    for _, b in ipairs(g.buttons) do
      local on = b.value == cur
      if W.themed() then
        T.paint(b, on and "panel3" or "none", "none")
        if b.SetNormalFontObject then b:SetNormalFontObject(T.fontObject("bold", size or 12, on and "uiGold" or "muted")) end
      elseif on then b:LockHighlight() else b:UnlockHighlight() end
    end
  end
  g.Refresh()
  return g
end

--- A card (panel-2, soft gold border, radius 6); raised = panel-3 with a gold border (the chosen one).
function W.card(parent, raised)
  local f = CreateFrame("Frame", nil, parent)
  if W.themed() then T.box(f, raised and "panel3" or "panel2", raised and "gold" or "lineSoft", 6)
  else f.bg = f:CreateTexture(nil, "BACKGROUND"); f.bg:SetAllPoints(); f.bg:SetColorTexture(0.1, 0.08, 0.05, 0.9) end
  return f
end
--- A small rounded chip with a word in capitals (SAVED, LEADER, IN USE); color = a token name. c.set(text, color).
function W.chip(parent, text, color)
  local c = CreateFrame("Frame", nil, parent)
  c.text = W.text(c, "GameFontNormalSmall", 10, nil, "CENTER")
  c.text:SetPoint("CENTER", 0, 0)
  function c.set(t, col)
    col = col or "ok"
    c.text:SetText((t or ""):upper())
    c.text:SetTextColor(T.rgb(col))
    if W.themed() then T.box(c, "none", col, 8); for _, x in ipairs(c.wbxBox.ring) do x:SetAlpha(0.5) end end
    c:SetSize(math.ceil((c.text:GetStringWidth() or 30) + 16), 18)
  end
  c.set(text, color)
  return c
end
--- A 1-unit divider line (soft gold).
function W.divider(parent, vertical)
  local t = T.line(parent, "lineSoft")
  if vertical then t:SetWidth(1) else t:SetHeight(1) end
  return t
end

--- The scroll bar: arrows (template look) get a tooltip; the bar hides when the content fits (contentH given).
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

--- Multi-line edit box in a scroll frame (macro text: the game's chat font, in a tooltip-style well).
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
  if sf.wbxSkinned and _G.ScrollingEdit_OnCursorChanged then
    eb:SetScript("OnCursorChanged", _G.ScrollingEdit_OnCursorChanged)
    eb:SetScript("OnUpdate", function(self, elapsed) if _G.ScrollingEdit_OnUpdate then _G.ScrollingEdit_OnUpdate(self, elapsed, sf) end end)
  end
  sf:SetScrollChild(eb)
  W.tidyScroll(sf)
  local bg = W.box(parent, 0.04, 0.03, 0.02, 0.95)
  if W.themed() then T.paint(bg, "ttBg", "ttEdge") end
  bg:SetPoint("TOPLEFT", sf, "TOPLEFT", -4, 4)
  bg:SetPoint("BOTTOMRIGHT", sf, "BOTTOMRIGHT", 4, -4)
  bg:SetFrameLevel(math.max(0, (sf:GetFrameLevel() or 1) - 1))
  sf:EnableMouse(true)
  sf:SetScript("OnMouseDown", function() eb:SetFocus() end)
  return eb, sf
end

--- Spell-style icon. border=true adds the 1-unit black outline (§2 icons); with it the icon gets rounded corners
--- where the client has mask textures.
function W.icon(parent, size, border)
  local t = parent:CreateTexture(nil, "ARTWORK")
  t:SetSize(size or 20, size or 20)
  if t.SetTexCoord then t:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
  if border then
    local b = parent:CreateTexture(nil, "BORDER")
    b:SetPoint("TOPLEFT", t, "TOPLEFT", -1, 1)
    b:SetPoint("BOTTOMRIGHT", t, "BOTTOMRIGHT", 1, -1)
    if W.themed() then b:SetTexture(T.TEX .. "IconMask"); b:SetVertexColor(T.rgb("black"))
    else b:SetColorTexture(0.54, 0.43, 0.2, 1) end
    t.border = b
    if W.themed() then T.roundIcon(t, parent) end
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

--- Room to keep free right of a scroll frame for its bar (it sits OUTSIDE the scroll frame).
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
  return W.PARCHMENT
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
    if W.themed() then T.paint(m, "panel", "line") end
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
      hl:SetColorTexture(T.rgb("panel3"))
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
