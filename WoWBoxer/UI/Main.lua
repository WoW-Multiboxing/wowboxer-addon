--[[ WoWBoxer – main window, built like the game's spellbook: a book with two pages, bookmark tabs on the right edge,
  the character line on top. Tabs register themselves in ns.UI.tabs ({key, label, icon, tip, build(panel),
  refresh(panel, ctx), book=true for the spellbook pages}). The window keeps its design size and is scaled down to fit
  small screens / big UI scales; the player's own scale (/wbx scale, Setup) comes on top. ]]
local _, ns = ...
local UI = {}
ns.UI = UI
UI.LOGO = "Interface\\AddOns\\WoWBoxer\\Media\\Logo"           -- the WoWBoxer shield (same as CurseForge)
UI.LOGO_SMALL = "Interface\\AddOns\\WoWBoxer\\Media\\LogoSmall"
local W = ns.Widgets

UI.WIDTH, UI.HEIGHT = 760, 500
UI.TAB_W = 40 -- bookmark column inside the cover, right edge
UI.tabs = {}
UI.current = "keys"

function UI.RegisterTab(tab) UI.tabs[#UI.tabs + 1] = tab end

local function D() return ns.Data end

--- Book colours (dark leather cover, dark parchment pages).
UI.COVER = { 0.16, 0.1, 0.055 }
UI.PAGE = { 0.2, 0.155, 0.1 }
UI.PAGE_EDGE = { 0.29, 0.22, 0.13 }

local function tex(parent, layer, c, a)
  local t = parent:CreateTexture(nil, layer)
  t:SetColorTexture(c[1], c[2], c[3], a or 1)
  return t
end

--- Area of the pages (inside the cover, left of the bookmarks): tabs put their panel here.
local PAGE_L, PAGE_T, PAGE_R, PAGE_B = 16, -40, -(UI.TAB_W + 12), 16

function UI.Build()
  if UI.frame then return UI.frame end
  local f = W.frame("Frame", UIParent, _G.BackdropTemplateMixin and "BackdropTemplate" or nil, "WoWBoxerMainFrame")
  UI.frame = f
  f:SetSize(UI.WIDTH, UI.HEIGHT)
  f:SetFrameStrata("HIGH")
  f:SetToplevel(true)
  f:SetClampedToScreen(true)
  f:EnableMouse(true)
  f:SetMovable(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function(self) self:StartMoving() end)
  f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, rel, x, y = self:GetPoint()
    if point and ns.Core.cdb then ns.Core.cdb.window = { point, rel or point, math.floor((x or 0) + 0.5), math.floor((y or 0) + 0.5) } end
  end)
  if f.SetBackdrop then
    f:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
      tile = true, tileSize = 32, edgeSize = 24, insets = { left = 6, right = 6, top = 6, bottom = 6 } })
    f:SetBackdropColor(UI.COVER[1], UI.COVER[2], UI.COVER[3], 0.98)
  end
  f:Hide()
  table.insert(UISpecialFrames, "WoWBoxerMainFrame")
  f:SetScript("OnShow", function() UI.Refresh() end)

  -- the two pages + spine
  local pages = CreateFrame("Frame", nil, f)
  pages:SetPoint("TOPLEFT", PAGE_L, PAGE_T)
  pages:SetPoint("BOTTOMRIGHT", PAGE_R, PAGE_B)
  UI.pages = pages
  local edge = tex(pages, "BACKGROUND", UI.PAGE_EDGE)
  edge:SetAllPoints()
  local pg = tex(pages, "BORDER", UI.PAGE)
  pg:SetPoint("TOPLEFT", 2, -2)
  pg:SetPoint("BOTTOMRIGHT", -2, 2)
  UI.spine = tex(pages, "ARTWORK", { 0.08, 0.05, 0.03 }, 0.55)
  UI.spine:SetPoint("TOP", 0, -2)
  UI.spine:SetPoint("BOTTOM", 0, 2)
  UI.spine:SetWidth(6)

  local logo = f:CreateTexture(nil, "ARTWORK")
  logo:SetSize(22, 22)
  logo:SetPoint("TOPLEFT", 16, -10)
  logo:SetTexture(UI.LOGO)
  UI.logo = logo
  local title = W.text(f, "GameFontNormalLarge", 16, W.GOLD)
  title:SetPoint("TOPLEFT", 42, -14)
  title:SetText("WoWBoxer")
  local close = W.frame("Button", f, "UIPanelCloseButton")
  close:SetSize(28, 28)
  close:SetPoint("TOPRIGHT", -4, -4)
  close:SetScript("OnClick", function() f:Hide() end)
  -- character line between the title and the help/close buttons: "Name · Warlock 4 · Follower" + a small client tag;
  -- squad, leader and client in the tooltip
  local whoHit = CreateFrame("Frame", nil, f)
  whoHit:SetPoint("TOPLEFT", 292, -14)
  whoHit:SetPoint("TOPRIGHT", -100, -14)
  whoHit:SetHeight(18)
  UI.whoHit = whoHit
  UI.who = W.line(whoHit, "GameFontHighlightSmall", nil, W.TEXT)
  UI.who:SetPoint("LEFT", 0, 0)
  UI.who:SetPoint("RIGHT", 0, 0)
  UI.who.wbxCopy = "data"
  W.tooltip(whoHit, function(GT)
    GT:AddLine(UI.who:GetText() or "", 1, 0.82, 0)
    for _, l in ipairs(UI.whoTip or {}) do GT:AddLine(l, 1, 1, 1, true) end
  end)
  UI.tag = W.text(f, "GameFontNormalSmall", nil, { 0.85, 0.7, 0.42 }, "RIGHT")
  UI.tag:SetPoint("TOPRIGHT", -72, -16)
  UI.tag.wbxCopy = "status"
  local tagHit = CreateFrame("Frame", nil, f)
  tagHit:SetAllPoints(UI.tag)
  W.tip(tagHit, "Classic Era", "This client is Classic Era. WoWBoxer uses WoW: Forever data; spells and talents can differ here.")
  UI.tagHit = tagHit
  UI.errText = W.line(f, "GameFontHighlightSmall", nil, W.RED, "RIGHT")
  UI.errText:SetPoint("BOTTOMRIGHT", -(UI.TAB_W + 14), 3)
  UI.errText:SetWidth(260)

  -- bookmark tabs
  UI.tabButtons, UI.panels = {}, {}
  for i, tab in ipairs(UI.tabs) do
    local b = CreateFrame("Button", nil, f)
    b:SetSize(34, 40)
    b:SetPoint("TOPRIGHT", -8, -44 - (i - 1) * 44)
    b.bg = tex(b, "BACKGROUND", UI.PAGE_EDGE)
    b.bg:SetAllPoints()
    b.icon = W.icon(b, 26, true)
    b.icon:SetPoint("CENTER")
    W.setIcon(b.icon, tab.icon)
    b.sel = b:CreateTexture(nil, "OVERLAY")
    b.sel:SetPoint("TOPLEFT", -3, 3)
    b.sel:SetPoint("BOTTOMRIGHT", 3, -3)
    b.sel:SetTexture("Interface\\Buttons\\CheckButtonHilight")
    if b.sel.SetBlendMode then b.sel:SetBlendMode("ADD") end
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 0.82, 0, 0.15)
    b:SetScript("OnClick", function() UI.Select(tab.key) end)
    W.tip(b, tab.label, tab.tip)
    b.wbxLabel = tab.label
    UI.tabButtons[tab.key] = b
    local p = CreateFrame("Frame", nil, pages)
    p:SetPoint("TOPLEFT", 10, -8)
    p:SetPoint("BOTTOMRIGHT", -10, 8)
    p:Hide()
    UI.panels[tab.key] = p
    tab.build(p)
  end
  if ns.Help then ns.Help.attach(f) end
  if ns.Advanced then ns.Advanced.attachSwitch(f) end
  UI.ApplyWindowSettings()
  UI.Select(UI.current)
  return f
end

--- Size of the panel area a tab gets (design units).
function UI.PanelSize()
  return UI.WIDTH - PAGE_L + PAGE_R - 20, UI.HEIGHT + PAGE_T - PAGE_B - 16
end

function UI.Select(key)
  if not (UI.panels and UI.panels[key]) then key = "keys" end
  UI.current = key
  local book = false
  for _, tab in ipairs(UI.tabs) do if tab.key == key then book = tab.book end end
  if UI.spine then UI.spine:SetShown(book and true or false) end
  for k, p in pairs(UI.panels or {}) do
    if k == key then p:Show() else p:Hide() end
    local b = UI.tabButtons[k]
    if b then b.sel:SetShown(k == key) end
  end
  UI.Refresh()
end

--- Re-render the visible tab with fresh data.
function UI.Refresh()
  local f = UI.frame
  if not f or not f:IsShown() then return end
  ns.Core.batch(UI.RefreshNow)
end
function UI.RefreshNow()
  local Core = ns.Core
  if ns.Advanced then ns.Advanced.refreshSwitch() end
  local ctx = Core.compute()
  local _, m = Core.me()
  local info = Core.playerInfo()
  local cls = D().classes[info.cls or ""]
  local line = W.hex(W.classColor(info.cls)) .. (info.name or "?") .. "|r · " .. (cls and cls.n or "?") .. " " .. tostring(info.level)
  local tip = {}
  if m then
    local s = Core.me()
    local L = ns.State.leaderOf(s)
    line = line .. " · " .. (m.leader and "Leader" or "Follower")
    if not m.leader then tip[#tip + 1] = "Follows " .. (L and L.name or "the leader") .. " (" .. m.unit .. ")" end
    tip[#tip + 1] = "Squad: " .. s.name .. " (" .. #s.members .. ")"
  end
  local era = ns.Compat.game() ~= "forever"
  tip[#tip + 1] = era and "Classic Era client, WoW: Forever data" or "WoW: Forever"
  UI.whoTip = tip
  UI.tag:SetText(era and "Era" or "")
  UI.tagHit:SetShown(era)
  UI.who:SetText(line)
  for _, tab in ipairs(UI.tabs) do
    if tab.key == UI.current and tab.refresh then
      local ok, err = pcall(tab.refresh, UI.panels[tab.key], ctx)
      if not ok then
        Core.log("error", "UI " .. tab.key .. ": " .. tostring(err))
        if Core.db.settings.debug then Core.print("|cffff6060UI error:|r " .. tostring(err)) end
      end
      UI.errText:SetText(ok and "" or "Error – type /wbx log")
    end
  end
  if ns.Help then ns.Help.onPage() end
end

--- The player's scale (/wbx scale, Setup; 0.7-1.3), but never bigger than what fits the screen.
function UI.FitScale()
  local sw, sh = UIParent:GetWidth() or UI.WIDTH, UIParent:GetHeight() or UI.HEIGHT
  local fit = math.min((sw * 0.96) / UI.WIDTH, (sh * 0.94) / UI.HEIGHT)
  local st = ns.Core.db and ns.Core.db.settings or {}
  return math.min(tonumber(st.scale) or 1, fit), fit
end

--- Position (per character, saved when the window is dragged) and scale; back to the centre when it would be off screen.
function UI.ApplyWindowSettings()
  local f = UI.frame
  if not f then return end
  local cdb = ns.Core.cdb or {}
  f:SetScale(UI.FitScale())
  f:ClearAllPoints()
  local w = cdb.window or (ns.Core.db and ns.Core.db.settings.window)
  if type(w) == "table" and type(w[1]) == "string" then f:SetPoint(w[1], UIParent, w[2], tonumber(w[3]) or 0, tonumber(w[4]) or 0)
  else f:SetPoint("CENTER") end
  local l, r, b, t = f:GetLeft(), f:GetRight(), f:GetBottom(), f:GetTop()
  if l and r and b and t then
    local s = (f:GetEffectiveScale() or 1) / (UIParent:GetEffectiveScale() or 1)
    if l * s < -1 or b * s < -1 or r * s > UIParent:GetWidth() + 1 or t * s > UIParent:GetHeight() + 1 then
      f:ClearAllPoints(); f:SetPoint("CENTER")
    end
  end
end

function UI.Toggle()
  ns.Core.ensureMe()
  UI.Build()
  if UI.frame:IsShown() then UI.frame:Hide() else UI.ApplyWindowSettings(); UI.frame:Show(); if ns.Audit then ns.Audit.onFirstOpen() end end
end
function UI.Open(tab)
  ns.Core.ensureMe(); UI.Build()
  if not UI.frame:IsShown() then UI.ApplyWindowSettings() end
  UI.frame:Show()
  if tab then UI.Select(tab) end
  if ns.Audit then ns.Audit.onFirstOpen() end
end

-- ------------------------------------------------------------------ level-up toast
-- One sentence + Update keys / Later + "Don't show again" (this pending state, this character; a new change shows
-- again). Width from the text (300–480), height from the wrapped text, under the top centre.
function UI.ShowOffer(ctx, sig)
  if not UI.offer then
    local o = W.box(UIParent, 0.1, 0.13, 0.06, 0.95)
    o:SetFrameStrata("DIALOG")
    o:SetClampedToScreen(true)
    o:SetPoint("TOP", 0, -120)
    o.text = W.text(o, "GameFontHighlightSmall", nil, W.TEXT)
    o.text:SetPoint("TOPLEFT", 12, -10)
    o.text:SetPoint("TOPRIGHT", -12, -10)
    o.go = W.button(o, "Update", 80, 22, function() o:Hide(); ns.Core.sync({ replace = ns.Core.cdb.replace }) end,
      "Updates the changed WoWBoxer macros. They keep their action buttons and keybinds.")
    o.go:SetPoint("BOTTOMRIGHT", -10, 8)
    o.later = W.button(o, "Later", 60, 22, function() o:Hide() end, "Closes this. Open WoWBoxer (/wbx or the minimap button) whenever you like.")
    o.later:SetPoint("RIGHT", o.go, "LEFT", -6, 0)
    o.never = W.check(o, "Don't show again", function(_, v) if v then ns.Core.dontShowAgain(o.sig); o:Hide() end end)
    o.never:SetPoint("BOTTOMLEFT", 8, 8)
    o.never.label.wbxCopy = "label"
    W.tip(o.never, "Don't show again", "This reminder does not come back on this character, also after /reload. A new change (level-up, new spell) shows again. Turn reminders off in Setup.")
    o.text.wbxCopy = "hint"
    local hit = CreateFrame("Frame", nil, o)
    hit:SetAllPoints(o.text)
    W.tooltip(hit, function(GT) GT:AddLine(o.text:GetText() or "", 1, 0.82, 0); GT:AddLine(o.tip or "", 1, 1, 1, true) end)
    UI.offer = o
  end
  local o = UI.offer
  o.sig = sig or ns.Core.pending(ctx)
  o.never:SetChecked(false)
  local names = {}
  for _, it in ipairs(ctx.macros.items) do if it.status == "create" or it.status == "update" then names[#names + 1] = ns.Book.shortLabel(it) end end
  local n = ctx.macros.changes
  local text = "|cffffd100Level " .. ctx.level .. ":|r " .. n .. (n == 1 and " macro changed" or " macros changed")
  o.tip = table.concat(names, ", ") .. ". Same buttons, new spells."
  o.text:SetText(text)
  local maxW = math.min(480, (UIParent:GetWidth() or 800) * 0.9)
  local want = W.measure(text, "GameFontHighlightSmall") + 24
  local btns = o.go:GetWidth() + o.later:GetWidth() + 26 + 22 + W.measure("Don't show again", "GameFontHighlightSmall") + 16
  local w = math.max(300, btns, math.min(maxW, want))
  o:SetWidth(w)
  o.text:SetWidth(w - 24)
  local th = o.text:GetStringHeight() or 14
  o:SetHeight(math.ceil(th) + 10 + 8 + 22 + 10)
  o:Show()
  UI.Refresh()
end
