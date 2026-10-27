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

function W.button(parent, label, width, height, onClick)
  local b = W.frame("Button", parent, "UIPanelButtonTemplate")
  b:SetSize(width or 110, height or 22)
  b:SetText(label)
  if onClick then b:SetScript("OnClick", function(self, button) onClick(self, button) end) end
  return b
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

--- A "‹ value ›" selector that cycles through a list. opts: {values={{value, label}}, get=fn, set=fn, width}
function W.cycle(parent, opts)
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(opts.width or 150, 22)
  local prev = W.button(f, "<", 22, 22)
  local nxt = W.button(f, ">", 22, 22)
  prev:SetPoint("LEFT")
  nxt:SetPoint("RIGHT")
  local label = W.text(f, "GameFontHighlightSmall", nil, nil, "CENTER")
  label:SetPoint("LEFT", prev, "RIGHT", 2, 0)
  label:SetPoint("RIGHT", nxt, "LEFT", -2, 0)
  f.label = label
  local function index()
    local cur = opts.get()
    for i, v in ipairs(opts.values()) do if v[1] == cur then return i end end
    return 1
  end
  function f.Refresh()
    local vals = opts.values()
    local v = vals[index()]
    label:SetText(v and v[2] or "-")
    local many = #vals > 1
    prev:SetEnabled(many); nxt:SetEnabled(many)
  end
  local function step(d)
    local vals = opts.values()
    if #vals == 0 then return end
    local i = ((index() - 1 + d) % #vals) + 1
    opts.set(vals[i][1])
    f.Refresh()
  end
  prev:SetScript("OnClick", function() step(-1) end)
  nxt:SetScript("OnClick", function() step(1) end)
  return f
end

--- Scroll area with a content frame. Returns scroll, content.
function W.scroll(parent, width, height)
  local sf = W.frame("ScrollFrame", parent, "UIPanelScrollFrameTemplate")
  sf:SetSize(width, height)
  local content = CreateFrame("Frame", nil, sf)
  content:SetSize(width, height)
  sf:SetScrollChild(content)
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
