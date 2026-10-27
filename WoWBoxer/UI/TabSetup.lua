--[[ WoWBoxer – Setup tab: where your keys go and how the window behaves (left), the multibox checklist (left, below),
  recommended game settings with apply / restore and recommended addons (right). ]]
local _, ns = ...
local UI, W = ns.UI, ns.Widgets
local tab = { key = "setup", label = "Setup", icon = "INV_Misc_Gear_01", tip = "Where your keys go, window size, animations, the multibox checklist and game settings." }
local LEFT_W = 300

local function Core() return ns.Core end
local SCALES = { { 0.7, "70 %" }, { 0.8, "80 %" }, { 0.9, "90 %" }, { 1, "100 %" }, { 1.1, "110 %" }, { 1.2, "120 %" }, { 1.3, "130 %" } }

function tab.build(p)
  -- your keys + window
  local h0 = W.text(p, "GameFontNormal", nil, W.GOLD)
  h0:SetPoint("TOPLEFT", 0, -4)
  h0:SetText("Your keys and this window")
  local Bars = ns.Bars
  local function barValues() local v = {}; for _, b in ipairs(Bars.BARS) do v[#v + 1] = { b.first, b.label } end return v end
  local function row(y, label, widget, tip)
    local t = W.text(p, "GameFontHighlightSmall", nil, W.TEXT)
    t:SetPoint("TOPLEFT", 0, y - 5)
    t:SetText(label)
    widget:SetPoint("TOPLEFT", 120, y)
    if tip then W.tip(widget, label, tip) end
    return t
  end
  p.bar1 = W.cycle(p, { width = 170, values = barValues, get = function() return Core().cdb.primaryBar end,
    set = function(v) Core().cdb.primaryBar = v; Core().cdb.slots = {}; Core().changed() end })
  row(-24, "Main keys on", p.bar1, "Where Place all puts keys 1–8, the sequences and Follow/Assist. Keys you dragged somewhere yourself stay there.")
  p.bar2 = W.cycle(p, { width = 170, values = barValues, get = function() return Core().cdb.secondaryBar end,
    set = function(v) Core().cdb.secondaryBar = v; Core().cdb.slots = {}; Core().changed() end })
  row(-50, "Other keys on", p.bar2, "Where Place all puts your own keys, Focus and the pet keys.")
  p.scale = W.cycle(p, { width = 170, values = function() return SCALES end,
    get = function() local v = tonumber(Core().db.settings.scale) or 1; return math.floor(v * 10 + 0.5) / 10 end,
    set = function(v) Core().db.settings.scale = v; UI.ApplyWindowSettings() end })
  row(-76, "Window size", p.scale, "Makes this window bigger or smaller. It always fits the screen. Same as /wbx scale.")
  p.replace = W.check(p, "Place all may replace other buttons", function(_, v) Core().cdb.replace = v; Core().changed() end)
  p.replace:SetPoint("TOPLEFT", -4, -100)
  W.tip(p.replace, "Replace buttons", "Off: a button that holds a spell or item is kept, and that key waits for you to drag it. On: Place all puts the key there.")
  p.anim = W.check(p, "Animations (keys fly to your bar)", function(_, v) Core().db.settings.animations = v; Core().changed() end)
  p.anim:SetPoint("TOPLEFT", -4, -122)
  W.tip(p.anim, "Animations", "When WoWBoxer places or updates keys, their icons fly to the action buttons and the buttons flash. Only a picture: it changes nothing.")
  p.guideBtn = W.button(p, "Show the guide", 120, 22, function() ns.Book.ShowGuide() end, "Opens the 3-step guide again on the My keys page.")
  p.guideBtn:SetPoint("TOPLEFT", 0, -148)
  p.macrosOnly = W.button(p, "Macros only", 100, 22, function() Core().sync({ macrosOnly = true }) end,
    "Creates or updates your WoWBoxer macros without touching your action bars (drag them yourself from the book).")
  p.macrosOnly:SetPoint("LEFT", p.guideBtn, "RIGHT", 6, 0)

  -- checklist
  local h1 = W.text(p, "GameFontNormal", nil, W.GOLD)
  h1:SetPoint("TOPLEFT", 0, -182)
  h1:SetText("Multibox checklist")
  local sf, content = W.scroll(p, LEFT_W - 24, 220)
  sf:SetPoint("TOPLEFT", 0, -200)
  p.checks = content
  p.checkPool = W.pool(content, function(parent)
    local r = CreateFrame("Frame", nil, parent)
    r:SetSize(LEFT_W - 28, 36)
    r.mark = W.text(r, "GameFontNormal")
    r.mark:SetPoint("TOPLEFT", 2, -2)
    r.fix = W.button(r, "Fix", 60, 18, function() if r.fixFn then r.fixFn() end end, "Makes this change in WoWBoxer for you.")
    r.fix:SetPoint("TOPRIGHT", 0, -1)
    r.text = W.text(r, "GameFontHighlightSmall", nil, W.TEXT)
    r.text:SetPoint("TOPLEFT", 20, -2)
    r.hint = W.text(r, "GameFontHighlightSmall", nil, W.MUTED)
    r.hint:SetPoint("TOPLEFT", r.text, "BOTTOMLEFT", 0, -1)
    return r
  end)

  -- game settings
  local X = LEFT_W + 20
  p.cvTitle = W.text(p, "GameFontNormal", nil, W.GOLD)
  p.cvTitle:SetPoint("TOPLEFT", X, -4)
  for _, col in ipairs({ { "Setting", 0 }, { "Now", 176 }, { "Tip", 216 } }) do
    local hdr = W.text(p, "GameFontHighlightSmall", nil, W.MUTED)
    hdr:SetPoint("TOPLEFT", X + col[2], -24)
    hdr:SetText(col[1])
  end
  p.cvPool = W.pool(p, function(parent, i)
    local r = CreateFrame("Frame", nil, parent)
    r:SetSize(330, 20)
    r:SetPoint("TOPLEFT", X, -40 - (i - 1) * 21)
    r.label = W.line(r, "GameFontHighlightSmall", nil, W.TEXT)
    r.label:SetPoint("LEFT", 0, 0)
    r.label:SetWidth(170)
    r.now = W.line(r, "GameFontHighlightSmall", nil, W.TEXT)
    r.now:SetPoint("LEFT", 176, 0)
    r.now:SetWidth(36)
    r.rec = W.line(r, "GameFontHighlightSmall", nil, W.TEXT)
    r.rec:SetPoint("LEFT", 216, 0)
    r.rec:SetWidth(36)
    r.st = W.line(r, "GameFontHighlightSmall")
    r.st:SetPoint("LEFT", 256, 0)
    r.st:SetWidth(72)
    return r
  end)
  p.applyCv = W.button(p, "Apply settings", 130, 22, function() Core().applyCVars(Core().cdb.importCVars) end,
    "Changes the game settings marked Change (they apply to this game installation). The old values are kept so you can restore them.")
  p.applyCv:SetPoint("TOPLEFT", X, -262)
  p.restore = W.button(p, "Restore old values", 130, 22, function() Core().restoreCVars() end,
    "Puts back the game settings WoWBoxer changed.")
  p.restore:SetPoint("LEFT", p.applyCv, "RIGHT", 6, 0)

  local h2 = W.text(p, "GameFontNormal", nil, W.GOLD)
  h2:SetPoint("TOPLEFT", X, -298)
  h2:SetText("Recommended addons")
  p.addons = W.text(p, "GameFontHighlightSmall", nil, W.TEXT)
  p.addons:SetPoint("TOPLEFT", h2, "BOTTOMLEFT", 0, -4)
  p.addons:SetWidth(330)
  p.addons:SetJustifyV("TOP")
end

local STATE = { loaded = { "Loaded", W.GREEN }, installed = { "Installed, not loaded", W.ORANGE }, missing = { "Missing", W.RED } }

function tab.refresh(p)
  local C, R = ns.Compat, ns.Rules
  local cdb = Core().cdb
  p.bar1.Refresh(); p.bar2.Refresh(); p.scale.Refresh()
  p.replace:SetChecked(cdb.replace and true or false)
  p.anim:SetChecked(Core().db.settings.animations ~= false)
  p.macrosOnly:SetEnabled(not C.inCombat())
  -- checklist
  p.checkPool:reset()
  local y = 0
  for _, it in ipairs(ns.Checklist.items()) do
    local r = p.checkPool:get()
    r:SetPoint("TOPLEFT", 0, -y)
    local col = it.ok == true and W.GREEN or (it.ok == false and W.ORANGE or W.BLUE)
    r.mark:SetText(it.ok == true and "+" or (it.ok == false and "!" or "i"))
    r.mark:SetTextColor(col[1], col[2], col[3])
    r.fixFn = it.fix and it.fix.fn or false
    local tw = LEFT_W - 28 - 20
    if it.fix then W.setLabel(r.fix, it.fix.label); r.fix:Show(); tw = tw - r.fix:GetWidth() - 6 else r.fix:Hide() end
    r.text:SetWidth(tw); r.hint:SetWidth(tw)
    r.text:SetText(it.text)
    r.hint:SetText(it.hint or "")
    local h = (r.text:GetStringHeight() or 12) + ((it.hint and it.hint ~= "") and ((r.hint:GetStringHeight() or 12) + 1) or 0) + 6
    r:SetHeight(math.max(22, math.ceil(h)))
    y = y + math.max(22, math.ceil(h)) + 2
  end
  p.checks:SetHeight(math.max(y, 10))
  -- addons
  local lines = {}
  local list = Core().db.settings.addons or {}
  local seen, all = {}, {}
  for _, a in ipairs(R.ADDONS) do all[#all + 1] = a.name; seen[a.name] = true end
  for _, a in ipairs(list) do if not seen[a] then all[#all + 1] = a; seen[a] = true end end
  for _, name in ipairs(all) do
    local st = STATE[C.addonState(name)]
    lines[#lines + 1] = W.hex(st[2]) .. st[1] .. "|r · " .. name
  end
  p.addons:SetText(table.concat(lines, "\n"))
  -- cvars
  local plan, role = Core().cvarPlan(cdb.importCVars)
  p.cvTitle:SetText("Game settings for a " .. role)
  p.cvPool:reset()
  local nChange = 0
  for _, c in ipairs(plan) do
    local r = p.cvPool:get()
    r.label:SetText(c.label)
    r.now:SetText(c.current == nil and "–" or tostring(c.current))
    r.rec:SetText(c.want or "–")
    local st = ({ change = { "Change", W.ORANGE }, ok = { "OK", W.GREEN }, missing = { "n/a", W.MUTED }, leave = { "", W.MUTED } })[c.status]
    r.st:SetText(st[1]); r.st:SetTextColor(st[2][1], st[2][2], st[2][3])
    if c.status == "change" then nChange = nChange + 1 end
    W.tooltip(r, function(GT) GT:AddLine(c.label .. " (" .. c.name .. ")", 1, 0.82, 0); GT:AddLine(c.why, 1, 1, 1, true) end)
  end
  W.setLabel(p.applyCv, nChange > 0 and ("Apply " .. nChange .. " setting" .. (nChange > 1 and "s" or "")) or "Settings OK")
  p.applyCv:SetEnabled(nChange > 0)
  p.restore:SetEnabled(next(cdb.cvarBackup) ~= nil)
end

UI.RegisterTab(tab)
