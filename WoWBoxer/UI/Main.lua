--[[ WoWBoxer – main window: title, character line, tabs, level-up offer. Tabs register themselves in ns.UI.tabs. ]]
local _, ns = ...
local UI = {}
ns.UI = UI
local W = ns.Widgets

UI.WIDTH, UI.HEIGHT = 660, 480
UI.tabs = {}           -- {key, label, build(panel), refresh(panel, ctx)}
UI.current = "keys"

function UI.RegisterTab(tab) UI.tabs[#UI.tabs + 1] = tab end

local function D() return ns.Data end

function UI.Build()
  if UI.frame then return UI.frame end
  local f = W.frame("Frame", UIParent, _G.BackdropTemplateMixin and "BackdropTemplate" or nil, "WoWBoxerMainFrame")
  UI.frame = f
  f:SetSize(UI.WIDTH, UI.HEIGHT)
  f:SetPoint("CENTER")
  f:SetFrameStrata("HIGH")
  f:SetToplevel(true)
  f:SetClampedToScreen(true)
  f:EnableMouse(true)
  f:SetMovable(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function(self) self:StartMoving() end)
  f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
  if f.SetBackdrop then
    f:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
      tile = true, tileSize = 32, edgeSize = 24, insets = { left = 6, right = 6, top = 6, bottom = 6 } })
    f:SetBackdropColor(0.1, 0.078, 0.055, 0.97)
  end
  f:Hide()
  table.insert(UISpecialFrames, "WoWBoxerMainFrame")
  f:SetScript("OnShow", function() UI.Refresh() end)

  local title = W.text(f, "GameFontNormalLarge", 18, W.GOLD)
  title:SetPoint("TOPLEFT", 18, -16)
  title:SetText("WoWBoxer")
  UI.who = W.text(f, "GameFontHighlightSmall", nil, W.TEXT)
  UI.who:SetPoint("LEFT", title, "RIGHT", 12, -1)
  UI.who:SetPoint("RIGHT", f, "RIGHT", -40, 0)
  local close = W.frame("Button", f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", -6, -6)
  close:SetScript("OnClick", function() f:Hide() end)

  -- tabs
  UI.tabButtons, UI.panels = {}, {}
  local x = 16
  for _, tab in ipairs(UI.tabs) do
    local b = W.button(f, tab.label, 92, 22, function() UI.Select(tab.key) end)
    b:SetPoint("TOPLEFT", x, -42)
    x = x + 96
    UI.tabButtons[tab.key] = b
    local p = CreateFrame("Frame", nil, f)
    p:SetPoint("TOPLEFT", 16, -70)
    p:SetPoint("BOTTOMRIGHT", -16, 14)
    p:Hide()
    UI.panels[tab.key] = p
    tab.build(p)
  end
  UI.Select(UI.current)
  return f
end

function UI.Select(key)
  UI.current = key
  for k, p in pairs(UI.panels or {}) do
    if k == key then p:Show() else p:Hide() end
    local b = UI.tabButtons[k]
    if b then if k == key then b:LockHighlight() else b:UnlockHighlight() end end
  end
  UI.Refresh()
end

--- Re-render the visible tab with fresh data.
function UI.Refresh()
  local f = UI.frame
  if not f or not f:IsShown() then return end
  local Core = ns.Core
  local ctx = Core.compute()
  local _, m = Core.me()
  local info = Core.playerInfo()
  local cls = D().classes[info.cls or ""]
  local line = W.hex(W.classColor(info.cls)) .. (info.name or "?") .. "|r · " .. (cls and cls.n or "?") .. " · Level " .. tostring(info.level)
  if m then
    local s = Core.me()
    line = line .. " · " .. (m.leader and "Leader" or ("follows via " .. m.unit)) .. " · " .. s.name
  else line = line .. " · |cffff8a80not in a squad yet|r" end
  if ns.Compat.game() ~= "forever" then line = line .. " · |cffd9b36c" .. ns.Compat.game() .. " (Forever data)|r" end
  UI.who:SetText(line)
  for _, tab in ipairs(UI.tabs) do
    if tab.key == UI.current and tab.refresh then
      local ok, err = pcall(tab.refresh, UI.panels[tab.key], ctx)
      if not ok then Core.log("error", "UI " .. tab.key .. ": " .. tostring(err)) end
    end
  end
end

function UI.Toggle()
  UI.Build()
  if UI.frame:IsShown() then UI.frame:Hide() else UI.frame:Show() end
end
function UI.Open(tab) UI.Build(); UI.frame:Show(); if tab then UI.Select(tab) end end

-- ------------------------------------------------------------------ level-up offer toast
function UI.ShowOffer(ctx)
  if not UI.offer then
    local o = W.box(UIParent, 0.1, 0.13, 0.06, 0.95)
    o:SetSize(380, 74)
    o:SetPoint("TOP", 0, -120)
    o:SetFrameStrata("DIALOG")
    o.text = W.text(o, "GameFontHighlightSmall", nil, W.TEXT)
    o.text:SetPoint("TOPLEFT", 12, -10)
    o.text:SetPoint("TOPRIGHT", -12, -10)
    o.go = W.button(o, "Update keys", 120, 22, function() o:Hide(); ns.Core.sync({}) end)
    o.go:SetPoint("BOTTOMRIGHT", -10, 8)
    o.show = W.button(o, "Show", 70, 22, function() o:Hide(); UI.Open("keys") end)
    o.show:SetPoint("RIGHT", o.go, "LEFT", -6, 0)
    o.later = W.button(o, "Later", 70, 22, function() o:Hide() end)
    o.later:SetPoint("RIGHT", o.show, "LEFT", -6, 0)
    UI.offer = o
  end
  local names = {}
  for _, it in ipairs(ctx.macros.items) do if it.status == "create" or it.status == "update" then names[#names + 1] = it.label end end
  UI.offer.text:SetText("|cffffd100WoWBoxer – level " .. ctx.level .. ":|r " .. ctx.macros.changes .. " key(s) changed (" .. table.concat(names, ", ", 1, math.min(4, #names)) ..
    (#names > 4 and ", …" or "") .. "). Same buttons, new macros.")
  UI.offer:Show()
  UI.Refresh()
end
