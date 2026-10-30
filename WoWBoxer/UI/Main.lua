--[[ WoWBoxer – the main window in the "war table" look (docs/ui-redesign.md §3): a 52-unit header (crest, title,
  character chip, Standard | Advanced, Reset, ?, close; the window is dragged by it), a left navigation rail (icon +
  word + a small state word, the macro-slot meter at the bottom) and the page body. Tabs register themselves in
  ns.UI.tabs ({key, label, icon, tip, build(panel), refresh(panel, ctx), book=true for the spellbook pages,
  badge=fn(ctx) -> text, token}). The window keeps its design size and is scaled down to fit small screens / big UI
  scales; the player's own scale (/wbx scale, Setup) comes on top. A client without the themed skins (W.themed) gets
  the same parts in plain frames. ]]
local _, ns = ...
local UI = {}
ns.UI = UI
UI.LOGO = "Interface\\AddOns\\WoWBoxer\\Media\\Logo"           -- the WoWBoxer shield (same as CurseForge)
UI.LOGO_SMALL = "Interface\\AddOns\\WoWBoxer\\Media\\LogoSmall"
local W = ns.Widgets
local T = ns.Theme

UI.HEADER_H, UI.RAIL_W = 52, 172
-- the body keeps the page size of the old book window (672 x 428), so no page needed new coordinates
UI.WIDTH, UI.HEIGHT = 889, 517
UI.tabs = {}
UI.current = "keys"
--- Order of the rail (§3); a tab without a place goes last.
UI.ORDER = { keys = 1, spells = 2, custom = 3, talents = 4, squad = 5, automation = 6, setup = 7, share = 8 }

function UI.RegisterTab(tab) UI.tabs[#UI.tabs + 1] = tab end

local function D() return ns.Data end

--- Area of the pages (right of the rail, under the header): tabs put their panel here.
local PAGE_L, PAGE_T, PAGE_R, PAGE_B = UI.RAIL_W + 13, -(UI.HEADER_H + 9), -12, 12

local function saveSpot(f)
  f:StopMovingOrSizing()
  local point, _, rel, x, y = f:GetPoint()
  if point and ns.Core.cdb then ns.Core.cdb.window = { point, rel or point, math.floor((x or 0) + 0.5), math.floor((y or 0) + 0.5) } end
end

-- ------------------------------------------------------------------ header
local function buildHeader(f)
  local themed = W.themed()
  local hdr = CreateFrame("Frame", nil, f)
  hdr:SetPoint("TOPLEFT", 1, -1)
  hdr:SetPoint("TOPRIGHT", -1, -1)
  hdr:SetHeight(UI.HEADER_H - 1)
  if themed then
    T.box(hdr, "panel2", "none", 10)
    local sq = T.fill(hdr, "panel2", "BACKGROUND", -6) -- square bottom corners under the rounded top
    sq:SetPoint("TOPLEFT", 0, -12)
    sq:SetPoint("BOTTOMRIGHT", 0, 0)
    local rule = T.line(hdr, "line")
    rule:SetPoint("BOTTOMLEFT", 0, 0)
    rule:SetPoint("BOTTOMRIGHT", 0, 0)
    rule:SetHeight(1)
  end
  -- the window is dragged by its header
  hdr:EnableMouse(true)
  hdr:RegisterForDrag("LeftButton")
  hdr:SetScript("OnDragStart", function() f:StartMoving() end)
  hdr:SetScript("OnDragStop", function() saveSpot(f) end)
  UI.header = hdr

  local logo = hdr:CreateTexture(nil, "ARTWORK")
  logo:SetSize(26, 26)
  logo:SetPoint("LEFT", 15, 0)
  logo:SetTexture(UI.LOGO)
  UI.logo = logo
  local title = W.text(hdr, "GameFontNormalLarge", 18, W.GOLD)
  title:SetPoint("LEFT", logo, "RIGHT", 10, 0)
  title:SetText("WoWBoxer")
  UI.title = title
  local after = title
  -- local test build (tools/install.ps1): an orange label so the owner always knows which build he is testing
  if ns.Core.isTestBuild() then
    local chip = W.chip(hdr, "Test build", "test")
    chip:SetPoint("LEFT", title, "RIGHT", 10, 0)
    UI.testLabel = chip.text
    UI.testLabel:SetText("TEST BUILD")
    W.tip(chip, "Test build", ns.Core.addonVersion() .. " - a local build for testing, not a release.")
    after = chip
  end
  -- character chip: class dot + "Name · Warlock 24 · Follower"; squad, leader and client in the tooltip
  local whoHit = CreateFrame("Frame", nil, hdr)
  whoHit:SetPoint("LEFT", after, "RIGHT", 14, 0)
  whoHit:SetSize(260, 24)
  if themed then T.box(whoHit, "panel", "lineSoft", 10) end
  UI.whoHit = whoHit
  UI.whoDot = whoHit:CreateTexture(nil, "ARTWORK")
  UI.whoDot:SetTexture(T.TEX .. "Circle")
  UI.whoDot:SetSize(8, 8)
  UI.whoDot:SetPoint("LEFT", 10, 0)
  UI.who = W.line(whoHit, "GameFontHighlight", 12, W.MUTED)
  UI.who:SetPoint("LEFT", UI.whoDot, "RIGHT", 8, 0)
  UI.who:SetPoint("RIGHT", -10, 0)
  UI.who.wbxCopy = "data"
  W.tooltip(whoHit, function(GT)
    GT:AddLine(UI.who:GetText() or "", 1, 0.82, 0)
    for _, l in ipairs(UI.whoTip or {}) do GT:AddLine(l, 1, 1, 1, true) end
  end)
  UI.tag = W.text(hdr, "GameFontNormalSmall", 10, W.ORANGE, "LEFT")
  UI.tag:SetPoint("LEFT", whoHit, "RIGHT", 8, 0)
  UI.tag.wbxCopy = "status"
  local tagHit = CreateFrame("Frame", nil, hdr)
  tagHit:SetAllPoints(UI.tag)
  W.tip(tagHit, "Classic Era", "This client is Classic Era. WoWBoxer uses WoW: Forever data; spells and talents can differ here.")
  UI.tagHit = tagHit

  local close = W.frame("Button", hdr, "UIPanelCloseButton")
  close:SetSize(28, 28)
  close:SetPoint("RIGHT", -10, 0)
  close:SetScript("OnClick", function() f:Hide() end)
  UI.closeBtn = close
end

-- ------------------------------------------------------------------ left rail
local function railRow(rail, tab, i)
  local themed = W.themed()
  local b = CreateFrame("Button", nil, rail)
  b:SetSize(UI.RAIL_W - 20, 30)
  b:SetPoint("TOPLEFT", 10, -12 - (i - 1) * 32)
  if themed then
    T.box(b, "none", "none", 4)
    local hl = T.slice(b, T.TEX .. "Fill4", 4, "HIGHLIGHT")
    for _, t in ipairs(hl) do t:SetVertexColor(T.rgb("panel2")) end
  end
  b.iconBox = CreateFrame("Frame", nil, b)
  b.iconBox:SetSize(22, 22)
  b.iconBox:SetPoint("LEFT", 8, 0)
  if themed then T.box(b.iconBox, "panel", "line", 4) end
  b.icon = b.iconBox:CreateTexture(nil, "ARTWORK")
  b.icon:SetPoint("TOPLEFT", 2, -2)
  b.icon:SetPoint("BOTTOMRIGHT", -2, 2)
  if b.icon.SetTexCoord then b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
  W.setIcon(b.icon, tab.icon)
  b.badge = W.text(b, "GameFontNormalSmall", 10, W.ORANGE, "RIGHT")
  b.badge:SetPoint("RIGHT", -8, 0)
  b.badge.wbxCopy = "status"
  b.label = W.line(b, "GameFontNormal", 13, W.TEXT)
  b.label:SetPoint("LEFT", b.iconBox, "RIGHT", 10, 0)
  b.label:SetPoint("RIGHT", b.badge, "LEFT", -4, 0)
  b.label:SetText(tab.label)
  b.label.wbxCopy = "label"
  -- selected: panel-3 fill, gold label and icon rim, a gold accent on the left
  b.sel = T.fill(b, "gold", "ARTWORK")
  b.sel:SetSize(2, 16)
  b.sel:SetPoint("LEFT", 0, 0)
  b:SetScript("OnClick", function() UI.Select(tab.key) end)
  W.tip(b, tab.label, tab.tip)
  b.wbxLabel = tab.label
  return b
end
local function buildRail(f)
  local rail = CreateFrame("Frame", nil, f)
  rail:SetPoint("TOPLEFT", 1, -UI.HEADER_H)
  rail:SetPoint("BOTTOMLEFT", 1, 1)
  rail:SetWidth(UI.RAIL_W)
  if W.themed() then
    T.box(rail, "night2", "none", 10)
    local sq = T.fill(rail, "night2", "BACKGROUND", -6) -- square top and right; only the window's corner is round
    sq:SetPoint("TOPLEFT", 0, 0)
    sq:SetPoint("BOTTOMRIGHT", 0, 12)
    local sq2 = T.fill(rail, "night2", "BACKGROUND", -6)
    sq2:SetPoint("TOPRIGHT", 0, 0)
    sq2:SetPoint("BOTTOMLEFT", rail, "BOTTOMRIGHT", -12, 0)
    local edge = T.line(rail, "lineSoft")
    edge:SetPoint("TOPRIGHT", 0, 0)
    edge:SetPoint("BOTTOMRIGHT", 0, 0)
    edge:SetWidth(1)
  end
  UI.rail = rail
  -- the macro-slot meter at the bottom
  local m = CreateFrame("Frame", nil, rail)
  m:SetPoint("BOTTOMLEFT", 10, 10)
  m:SetPoint("BOTTOMRIGHT", -10, 10)
  m:SetHeight(40)
  local top = T.line(m, "lineSoft")
  top:SetPoint("TOPLEFT", 0, 0)
  top:SetPoint("TOPRIGHT", 0, 0)
  top:SetHeight(1)
  m.text = W.line(m, "GameFontHighlightSmall", 11, W.MUTED)
  m.text:SetPoint("TOPLEFT", 10, -10)
  m.text:SetPoint("TOPRIGHT", -10, -10)
  m.text.wbxCopy = "data"
  m.track = CreateFrame("Frame", nil, m)
  m.track:SetPoint("TOPLEFT", m.text, "BOTTOMLEFT", 0, -6)
  m.track:SetPoint("TOPRIGHT", m.text, "BOTTOMRIGHT", 0, -6)
  m.track:SetHeight(4)
  if W.themed() then T.box(m.track, "panel3", "none", 3) end
  m.bar = m.track:CreateTexture(nil, "ARTWORK")
  m.bar:SetTexture(T.TEX .. "Fill3")
  m.bar:SetVertexColor(T.rgb("gold"))
  m.bar:SetPoint("TOPLEFT", 0, 0)
  m.bar:SetPoint("BOTTOMLEFT", 0, 0)
  m.bar:SetWidth(1)
  W.tip(m, "Macro slots", "Character macros on this character, of the game's limit. WoWBoxer macros start with WBX.")
  UI.meter = m
end
--- The slot meter at the bottom of the rail: "18 of 30 macro slots".
function UI.RefreshMeter()
  local m = UI.meter
  if not m then return end
  local _, used = ns.Compat.numMacros()
  local _, max = ns.Compat.macroLimits()
  m.text:SetText(used .. " of " .. max .. " macro slots")
  local w = m.track:GetWidth() or 0
  m.bar:SetWidth(math.max(1, w * math.min(1, used / math.max(1, max))))
  m.bar:SetVertexColor(T.rgb(used >= max and "warn" or "gold"))
end

function UI.Build()
  if UI.frame then return UI.frame end
  local f = W.frame("Frame", UIParent, (not W.themed() and _G.BackdropTemplateMixin) and "BackdropTemplate" or nil, "WoWBoxerMainFrame")
  UI.frame = f
  f:SetSize(UI.WIDTH, UI.HEIGHT)
  f:SetFrameStrata("HIGH")
  f:SetToplevel(true)
  f:SetClampedToScreen(true)
  f:EnableMouse(true)
  f:SetMovable(true)
  f:SetScript("OnDragStop", saveSpot)
  if W.themed() then T.box(f, "panel", "line", 10)
  elseif f.SetBackdrop then
    f:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
      tile = true, tileSize = 32, edgeSize = 24, insets = { left = 6, right = 6, top = 6, bottom = 6 } })
    f:SetBackdropColor(0.08, 0.09, 0.12, 0.98)
  end
  f:Hide()
  table.insert(UISpecialFrames, "WoWBoxerMainFrame")
  f:SetScript("OnShow", function() UI.Refresh() end)
  buildHeader(f)
  buildRail(f)

  -- the page body; a 1-unit divider stands where the book had its spine (the spellbook pages split here)
  local pages = CreateFrame("Frame", nil, f)
  pages:SetPoint("TOPLEFT", PAGE_L, PAGE_T)
  pages:SetPoint("BOTTOMRIGHT", PAGE_R, PAGE_B)
  UI.pages = pages
  UI.spine = T.line(pages, "lineSoft")
  UI.spine:SetPoint("TOP", 0, -8)
  UI.spine:SetPoint("BOTTOM", 0, 8)
  UI.spine:SetWidth(1)
  UI.errText = W.line(f, "GameFontHighlightSmall", nil, W.RED, "RIGHT")
  UI.errText:SetPoint("BOTTOMRIGHT", -14, 3)
  UI.errText:SetWidth(260)

  -- rail rows in the order of §3, one panel per tab
  local order = {}
  for i, tab in ipairs(UI.tabs) do order[i] = tab end
  table.sort(order, function(x, y) return (UI.ORDER[x.key] or 99) < (UI.ORDER[y.key] or 99) end)
  UI.tabButtons, UI.panels = {}, {}
  for i, tab in ipairs(order) do
    UI.tabButtons[tab.key] = railRow(UI.rail, tab, i)
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
    if b then
      b.sel:SetShown(k == key)
      if b.wbxBox then
        T.paint(b, k == key and "panel3" or "none")
        T.paint(b.iconBox, nil, k == key and "gold" or "line")
      end
      b.label:SetTextColor(T.rgb(k == key and "uiGold" or "text"))
    end
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
  UI.tag:SetText(era and "ERA" or "")
  UI.tagHit:SetShown(era)
  UI.who:SetText(line)
  if UI.whoDot then
    local c = W.classColor(info.cls)
    UI.whoDot:SetVertexColor(c[1], c[2], c[3])
    UI.whoHit:SetWidth(math.min(300, math.ceil((UI.who:GetStringWidth() or 200) + 38)))
  end
  for _, tab in ipairs(UI.tabs) do
    local b = UI.tabButtons and UI.tabButtons[tab.key]
    if b and b.badge then
      local ok, text, token = pcall(tab.badge or function() end, ctx)
      b.badge:SetText(ok and text or "")
      if ok and text then b.badge:SetTextColor(T.rgb(token or "warn")) end
    end
  end
  UI.RefreshMeter()
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

-- ------------------------------------------------------------------ a small question (login fixes, nudges)
--- UI.Popup(text, {{label, fn, tip}, …}): one sentence and up to three buttons, under the top centre. A click on any
--- button closes it; nothing happens without a click.
function UI.Popup(text, buttons)
  local o = UI.popup
  if not o then
    o = W.window(UIParent)
    o:SetFrameStrata("DIALOG")
    o:SetClampedToScreen(true)
    o:SetPoint("TOP", 0, -170)
    o:SetWidth(420)
    o.text = W.text(o, "GameFontHighlight", nil, W.TEXT, "CENTER")
    o.text:SetPoint("TOPLEFT", 14, -14)
    o.text:SetPoint("TOPRIGHT", -14, -14)
    o.text.wbxCopy = "guide"
    o.btns = {}
    for i = 1, 3 do
      local b = W.button(o, "OK", 90, 24, function(self) o:Hide(); if self.fn then self.fn() end end)
      W.tip(b, function() return b:GetText() end, function() return b.tipText end)
      o.btns[i] = b
    end
    W.primary(o.btns[1])
    UI.popup = o
  end
  o.text:SetText(text)
  local prev
  for i, b in ipairs(o.btns) do
    local d = buttons[i]
    b:SetShown(d ~= nil)
    if d then
      W.setLabel(b, d[1]); b.fn, b.tipText = d[2], d[3]
      b:ClearAllPoints()
      if prev then b:SetPoint("LEFT", prev, "RIGHT", 8, 0) else b:SetPoint("BOTTOMLEFT", 14, 12) end
      prev = b
    end
  end
  local th = o.text:GetStringHeight() or 14
  o:SetHeight(math.ceil(th) + 14 + 12 + 24 + 14)
  o:Show()
  return o
end

-- ------------------------------------------------------------------ level-up toast
-- One sentence + Update keys / Later + "Don't show again" (this pending state, this character; a new change shows
-- again). Width from the text (300–480), height from the wrapped text, under the top centre.
function UI.ShowOffer(ctx, sig)
  if not UI.offer then
    local o = W.window(UIParent)
    o:SetFrameStrata("DIALOG")
    o:SetClampedToScreen(true)
    o:SetPoint("TOP", 0, -120)
    o.text = W.text(o, "GameFontHighlightSmall", nil, W.TEXT)
    o.text:SetPoint("TOPLEFT", 12, -10)
    o.text:SetPoint("TOPRIGHT", -12, -10)
    o.go = W.button(o, "Update", 80, 22, function() o:Hide(); ns.Core.sync({ replace = ns.Core.cdb.replace }) end,
      "Updates the changed WoWBoxer macros. They keep their action buttons and keybinds.")
    W.primary(o.go)
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
  local text = T.code("uiGold") .. "Level " .. ctx.level .. ":|r " .. n .. (n == 1 and " macro changed" or " macros changed")
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
