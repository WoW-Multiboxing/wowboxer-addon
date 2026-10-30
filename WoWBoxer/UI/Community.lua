--[[ WoWBoxer – community links and "Report a problem" (LOG.md [WS-C] "community-links", adapted to WoW).
  Addons cannot open a browser or write the clipboard, so a link opens a small copy box: the URL selected, "Press
  Ctrl+C to copy", Esc closes it. Everything here opens only from the player's own click or slash command – no pop-up
  at login, no chat spam, no telemetry, nothing is sent anywhere. In combat a box opens without taking the keyboard
  ("click the box, then Ctrl+C"), so it never steals a key press from a fight. ]]
local _, ns = ...
local CM = {}
ns.Community = CM
local W, TH = ns.Widgets, ns.Theme
local function Core() return ns.Core end
local function inCombat() return ns.Compat.inCombat() end

--- Select all text in an edit box and give it the keyboard – only out of combat (CM.focused for tests).
local function grab(eb)
  if inCombat() then CM.focused = nil; return false end
  eb:SetFocus()
  eb:HighlightText()
  CM.focused = eb
  return true
end

-- ------------------------------------------------------------------ the link box
local function linkBox()
  if CM.box then return CM.box end
  local f = W.window(UIParent)
  f:SetSize(420, 150)
  f:SetFrameStrata("DIALOG")
  f:SetClampedToScreen(true)
  f:SetPoint("CENTER", 0, 120)
  f:EnableMouse(true)
  f.title = W.text(f, "GameFontNormalLarge", 15, W.GOLD)
  f.title:SetPoint("TOPLEFT", 16, -14)
  f.title:SetPoint("TOPRIGHT", -44, -14)
  f.title.wbxCopy = "data"
  f.sub = W.text(f, "GameFontHighlightSmall", 11, W.MUTED)
  f.sub:SetPoint("TOPLEFT", 16, -38)
  f.sub:SetWidth(388)
  f.sub.wbxCopy = "sentence"
  f.x = W.frame("Button", f, "UIPanelCloseButton")
  f.x:SetPoint("TOPRIGHT", -8, -8)
  f.x:SetScript("OnClick", function() f:Hide() end)
  f.url = W.frame("EditBox", f, "InputBoxTemplate")
  f.url:SetSize(388, 26)
  f.url:SetPoint("TOPLEFT", 16, -64)
  f.url:SetAutoFocus(false)
  -- the text cannot be changed: typing puts the link back (and selects it again)
  f.url:SetScript("OnTextChanged", function(self, user) if user and self:GetText() ~= f.link then self:SetText(f.link or ""); self:HighlightText() end end)
  f.url:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
  f.url:SetScript("OnMouseUp", function(self) grab(self) end)
  f.url:SetScript("OnEscapePressed", function() f:Hide() end)
  f.url:SetScript("OnEnterPressed", function() f:Hide() end)
  f.hint = W.text(f, "GameFontHighlightSmall", 11, W.TEXT)
  f.hint:SetPoint("BOTTOMLEFT", 16, 16)
  f.hint.wbxCopy = "hint"
  f.close = W.button(f, "Close", 70, 24, function() f:Hide() end, "Closes this box.")
  f.close:SetPoint("BOTTOMRIGHT", -14, 12)
  f:Hide()
  _G.WoWBoxerLinkBox = f
  table.insert(UISpecialFrames, "WoWBoxerLinkBox")
  CM.box = f
  W.dialog(f, "WoWBoxerLinkBox")
  return f
end

--- Show a link (key of ns.Links, or any text) in the copy box. Returns the box.
function CM.ShowLink(key)
  local L = ns.Links
  local def
  for _, d in ipairs(L.LIST) do if d[1] == key then def = d end end
  local f = linkBox()
  f.link = L[key] or tostring(key)
  f.title:SetText(def and def[3] or "Link")
  f.sub:SetText(def and def[4] or "")
  f.url:SetText(f.link)
  f:Show()
  local got = grab(f.url)
  f.hint:SetText(got and "Press Ctrl+C to copy, then paste it in your browser." or "Click the link, then press Ctrl+C to copy it.")
  Core().log("info", "link box: " .. tostring(key))
  return f
end

--- A clickable link for the addon's own chat lines (|Haddon:WoWBoxer:<key>|h): only in messages the player asked for.
function CM.chatLink(key, label)
  return TH.code("goldHi") .. "|Haddon:WoWBoxer:" .. key .. "|h[" .. label .. "]|h|r"
end
-- a click on such a link opens the copy box (post-hook; other link types are untouched) [AFKLAR: addon links on Era]
if _G.hooksecurefunc and _G.SetItemRef then
  _G.hooksecurefunc("SetItemRef", function(link)
    local key = type(link) == "string" and link:match("^addon:WoWBoxer:(%w+)$")
    if key == "report" then CM.ShowReport() elseif key and ns.Links[key] then CM.ShowLink(key) end
  end)
end

-- ------------------------------------------------------------------ Report a problem
local function reportFrame()
  if CM.rf then return CM.rf end
  local f = W.window(UIParent)
  f:SetSize(560, 470)
  f:SetFrameStrata("DIALOG")
  f:SetClampedToScreen(true)
  f:SetPoint("CENTER", 0, 40)
  f:EnableMouse(true)
  f:SetMovable(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function(self) self:StartMoving() end)
  f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
  f.title = W.text(f, "GameFontNormalLarge", 16, W.GOLD)
  f.title:SetPoint("TOPLEFT", 16, -14)
  f.title:SetText("Report a problem")
  f.title.wbxCopy = "label"
  f.x = W.frame("Button", f, "UIPanelCloseButton")
  f.x:SetPoint("TOPRIGHT", -8, -8)
  f.x:SetScript("OnClick", function() f:Hide() end)
  f.sub = W.text(f, "GameFontHighlightSmall", 11, W.MUTED)
  f.sub:SetPoint("TOPLEFT", 16, -38)
  f.sub:SetWidth(528)
  f.sub:SetText("Nothing is sent: you copy the text and paste it yourself. Character and realm names stay out unless you tick the box.")
  f.sub.wbxCopy = "guide"
  f.whatLabel = W.text(f, "GameFontNormal", 12, W.PARCHMENT)
  f.whatLabel:SetPoint("TOPLEFT", 16, -76)
  f.whatLabel:SetText("What happened?")
  f.whatLabel.wbxCopy = "label"
  f.what = W.frame("EditBox", f, "InputBoxTemplate")
  f.what:SetSize(408, 24)
  f.what:SetPoint("LEFT", f.whatLabel, "RIGHT", 10, 0)
  f.what:SetAutoFocus(false)
  f.what:SetMaxLetters(300)
  f.what:SetScript("OnEnterPressed", function(self) self:ClearFocus(); CM.refreshReport() end)
  f.what:SetScript("OnEditFocusLost", function() CM.refreshReport() end)
  W.tip(f.what, "What happened?", "One or two sentences: what you did, what you expected, what happened instead. Enter puts it into the report.")
  f.names = W.check(f, "Include character and realm names", function() CM.refreshReport() end)
  f.names:SetPoint("TOPLEFT", 12, -104)
  W.tip(f.names, "Include names", "Off: every character, realm and squad name is replaced with <name> / <realm>. Tick it only if the names help.")
  f.eb, f.sf = W.editBox(f, 506, 238)
  f.sf:SetPoint("TOPLEFT", 20, -136)
  f.eb:SetFontObject(_G.GameFontHighlightSmall or _G.ChatFontNormal)
  f.eb:SetScript("OnMouseUp", function(self) if not inCombat() then self:SetFocus() end end)
  f.hint = W.text(f, "GameFontHighlightSmall", 11, W.TEXT)
  f.hint:SetPoint("BOTTOMLEFT", 16, 50)
  f.hint:SetWidth(528)
  f.hint.wbxCopy = "hint"
  f.select = W.button(f, "Select all", 90, 26, function() grab(f.eb); CM.reportHint() end, "Selects the whole report, so Ctrl+C copies it.")
  W.primary(f.select)
  f.select:SetPoint("BOTTOMLEFT", 14, 14)
  f.help = W.button(f, "Discord #setup-help", 150, 26, function() CM.ShowLink("discordHelp") end,
    "Shows the invite link to WoWBoxer's #setup-help on Discord, to copy into your browser.")
  f.help:SetPoint("LEFT", f.select, "RIGHT", 8, 0)
  f.close = W.button(f, "Close", 70, 26, function() f:Hide() end, "Closes this window. Nothing is sent.")
  f.close:SetPoint("BOTTOMRIGHT", -14, 14)
  f:Hide()
  _G.WoWBoxerReportFrame = f
  table.insert(UISpecialFrames, "WoWBoxerReportFrame")
  CM.rf = f
  W.dialog(f, "WoWBoxerReportFrame")
  return f
end
function CM.reportHint()
  local f = CM.rf
  if not f then return end
  f.hint:SetText(inCombat() and "In combat: click into the report, then Ctrl+A and Ctrl+C. Paste it in #setup-help on Discord."
    or "Ctrl+C, then paste it in #setup-help on Discord.")
end
--- Rebuild the report text (what happened + the names tick); the player may still edit it before copying.
function CM.refreshReport()
  local f = CM.rf
  if not f then return end
  f.text = ns.Report.build({ what = f.what:GetText(), names = f.names:GetChecked() and true or false })
  f.eb:SetText(f.text)
  local lines = select(2, f.text:gsub("\n", "")) + 1
  f.eb:SetHeight(math.max(238, lines * 13 + 8))
  W.tidyScroll(f.sf, lines * 13 + 8)
  CM.reportHint()
end
--- Open "Report a problem" (player's click or /wbx report). Returns the frame.
function CM.ShowReport()
  local f = reportFrame()
  f.names:SetChecked(false)
  f:Show()
  CM.refreshReport()
  grab(f.eb)
  Core().log("info", "report window opened")
  return f
end

-- ------------------------------------------------------------------ the rail: a small Community block above the meter
--- Rows under "COMMUNITY" in the left rail: Discord · YouTube · Website · Report a problem (each a click, nothing more).
function CM.attachRail(rail, meter)
  if not rail or CM.railBlock then return end
  local b = CreateFrame("Frame", nil, rail)
  b:SetPoint("BOTTOMLEFT", meter, "TOPLEFT", 0, 8)
  b:SetPoint("BOTTOMRIGHT", meter, "TOPRIGHT", 0, 8)
  b:SetHeight(4 * 20 + 18)
  b.head = W.text(b, "GameFontNormalSmall", 9, W.MUTED)
  b.head:SetPoint("TOPLEFT", 10, 0)
  b.head:SetText("COMMUNITY")
  b.head.wbxCopy = "label"
  local rows = {
    { "Discord", function() CM.ShowLink("discord") end, "Shows the Discord invite to copy into your browser." },
    { "YouTube", function() CM.ShowLink("youtube") end, "Shows the YouTube channel link to copy." },
    { "Website", function() CM.ShowLink("website") end, "Shows wowboxer.com to copy." },
    { "Problem report", function() CM.ShowReport() end, "Report a problem: builds a report to copy into #setup-help on Discord. Nothing is sent." },
  }
  b.rows = {}
  for i, r in ipairs(rows) do
    local x = W.button(b, r[1], 40, 20, r[2], { r[1], r[3] })
    W.setStyle(x, "ghost")
    x:SetPoint("TOPLEFT", 0, -14 - (i - 1) * 20)
    b.rows[i] = x
  end
  CM.railBlock = b
  return b
end

return CM
