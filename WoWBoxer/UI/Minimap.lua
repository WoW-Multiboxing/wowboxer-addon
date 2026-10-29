--[[ WoWBoxer – minimap button (no libraries) and Addon Compartment entry.
  Left-click: open/close the window. Right-click: small menu. Drag: move around the minimap edge (angle saved in
  WoWBoxerDB.settings.minimapAngle). "Hide minimap button" in the menu; /wbx minimap brings it back.
  The Addon Compartment (Forever's minimap "addons" menu) is registered through the TOC; on clients without it the
  TOC lines are ignored. ]]
local _, ns = ...
local MM = {}
ns.Minimap = MM
local W = ns.Widgets

MM.DEFAULT_ANGLE = 210
local ICON = "Interface\\AddOns\\WoWBoxer\\Media\\LogoSmall" -- the WoWBoxer shield (same as CurseForge)

local function settings() return ns.Core.db and ns.Core.db.settings or {} end

function MM.Place()
  local b = MM.button
  if not b or not _G.Minimap then return end
  local a = math.rad(tonumber(settings().minimapAngle) or MM.DEFAULT_ANGLE)
  local r = (_G.Minimap:GetWidth() or 140) / 2 + 6
  local x, y = math.cos(a), math.sin(a)
  -- square minimaps (ElvUI and others report it through GetMinimapShape): run along the edge, not a circle
  local shape = _G.GetMinimapShape and _G.GetMinimapShape()
  if shape == "SQUARE" then
    local m = math.max(math.abs(x), math.abs(y))
    if m > 0 then x, y = x / m, y / m end
    r = (_G.Minimap:GetWidth() or 140) / 2 + 2
  end
  b:ClearAllPoints()
  b:SetPoint("CENTER", _G.Minimap, "CENTER", x * r, y * r)
end

--- Angle in degrees from the minimap centre to the cursor.
function MM.cursorAngle()
  local mx, my = _G.Minimap:GetCenter()
  local px, py = GetCursorPosition()
  local scale = _G.Minimap:GetEffectiveScale() or 1
  if not mx or not px then return MM.DEFAULT_ANGLE end
  return math.deg(math.atan2(py / scale - my, px / scale - mx)) % 360
end

local function tooltip(GT)
  GT:AddLine("WoWBoxer", 1, 0.82, 0)
  local ok, ctx = pcall(ns.Core.compute)
  if ok and ctx then
    if ctx.macros.changes > 0 then GT:AddLine(ctx.macros.changes .. (ctx.macros.changes == 1 and " macro" or " macros") .. " to create or update", 0.94, 0.71, 0.24)
    else GT:AddLine("Macros up to date for level " .. ctx.level, 0.56, 0.75, 0.42) end
  end
  GT:AddLine("Left-click: open / close", 0.85, 0.85, 0.85)
  GT:AddLine("Right-click: menu", 0.85, 0.85, 0.85)
  GT:AddLine("Drag: move around the minimap", 0.85, 0.85, 0.85)
end

-- ------------------------------------------------------------------ right-click menu
local ITEMS = { -- (MM.MENU, for tests)
  { "Open WoWBoxer", function() ns.UI.Open("keys") end },
  { "Place all macros", function() ns.Core.sync({ replace = ns.Core.cdb.replace }) end },
  { "First-run guide", function() ns.Book.ShowGuide() end },
  { "Squad guide", function() ns.Help.ShowSquadGuide() end },
  { "Setup", function() ns.UI.Open("setup") end },
  { "Automation", function() ns.UI.Open("automation") end },
  { "Key bindings", function() ns.Core.openKeyBindings() end },
  { "Hide minimap button", function() MM.SetHidden(true) end },
  { "Close", function() end },
}
MM.MENU = ITEMS
function MM.ShowMenu(anchor)
  if not MM.menu then
    local m = W.box(UIParent, 0.07, 0.055, 0.035, 0.97)
    m:SetFrameStrata("DIALOG")
    m:SetClampedToScreen(true)
    m:SetSize(190, 12 + #ITEMS * 22)
    for i, it in ipairs(ITEMS) do
      local b = CreateFrame("Button", nil, m)
      b:SetSize(176, 20)
      b:SetPoint("TOPLEFT", 7, -6 - (i - 1) * 22)
      local hl = b:CreateTexture(nil, "HIGHLIGHT")
      hl:SetAllPoints()
      hl:SetColorTexture(1, 0.82, 0, 0.18)
      local t = W.text(b, "GameFontHighlightSmall", nil, i == #ITEMS and W.MUTED or W.TEXT)
      t:SetPoint("LEFT", 6, 0)
      t:SetText(it[1])
      b:SetScript("OnClick", function() m:Hide(); it[2]() end)
    end
    m:Hide()
    table.insert(UISpecialFrames, "WoWBoxerMinimapMenu")
    _G.WoWBoxerMinimapMenu = m
    MM.menu = m
  end
  local m = MM.menu
  if m:IsShown() then m:Hide(); return end
  m:ClearAllPoints()
  m:SetPoint("TOPRIGHT", anchor or UIParent, "BOTTOMLEFT", 0, 0)
  m:Show()
end

-- ------------------------------------------------------------------ button
function MM.Create()
  if MM.button or not _G.Minimap then return MM.button end
  local b = CreateFrame("Button", "WoWBoxerMinimapButton", _G.Minimap)
  b:SetSize(31, 31)
  b:SetFrameStrata("MEDIUM")
  b:SetFrameLevel((_G.Minimap:GetFrameLevel() or 1) + 8)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:RegisterForDrag("LeftButton")
  local bg = b:CreateTexture(nil, "BACKGROUND")
  bg:SetSize(20, 20)
  bg:SetPoint("TOPLEFT", 7, -5)
  bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
  local icon = b:CreateTexture(nil, "ARTWORK")
  icon:SetSize(19, 19)
  icon:SetPoint("TOPLEFT", 6, -5)
  icon:SetTexture(ICON)
  b.icon = icon
  local border = b:CreateTexture(nil, "OVERLAY")
  border:SetSize(53, 53)
  border:SetPoint("TOPLEFT")
  border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  local dot = b:CreateTexture(nil, "OVERLAY", nil, 7)
  dot:SetSize(10, 10)
  dot:SetPoint("TOPRIGHT", -2, -2)
  dot:SetTexture("Interface\\COMMON\\Indicator-Yellow")
  dot:Hide()
  b.dot = dot
  if b.SetHighlightTexture then b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight") end

  b:SetScript("OnClick", function(self, button)
    if button == "RightButton" then MM.ShowMenu(self) else ns.UI.Toggle() end
  end)
  b:SetScript("OnDragStart", function(self)
    self:SetScript("OnUpdate", function()
      settings().minimapAngle = math.floor(MM.cursorAngle() + 0.5)
      MM.Place()
    end)
  end)
  b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
  W.tooltip(b, function(GT) tooltip(GT) end)
  MM.button = b
  MM.Place()
  return b
end

--- Yellow dot on the button while keys wait for an update after a level-up (set by Core.checkOffer / Core.sync).
function MM.SetAttention(on)
  MM.attention = on and true or false
  if MM.button and MM.button.dot then MM.button.dot:SetShown(MM.attention) end
end

function MM.SetHidden(hidden)
  settings().minimapHidden = hidden and true or nil
  if hidden then
    if MM.button then MM.button:Hide() end
    ns.Core.print("Minimap button hidden. Type /wbx minimap to bring it back.")
  else
    MM.Create()
    if MM.button then MM.button:Show(); MM.Place() end
  end
end

function MM.Init()
  if settings().minimapHidden then return end
  MM.Create()
end

-- ------------------------------------------------------------------ Addon Compartment (TOC: AddonCompartmentFunc...)
function _G.WoWBoxer_OnAddonCompartmentClick(_, button)
  if button == "RightButton" then MM.ShowMenu(_G.AddonCompartmentFrame) else ns.UI.Toggle() end
end
function _G.WoWBoxer_OnAddonCompartmentEnter(_, frame)
  local GT = _G.GameTooltip
  GT:SetOwner(frame or UIParent, "ANCHOR_LEFT")
  tooltip(GT)
  GT:Show()
end
function _G.WoWBoxer_OnAddonCompartmentLeave() _G.GameTooltip:Hide() end

return MM
