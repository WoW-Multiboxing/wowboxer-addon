--[[ WoWBoxer – Setup tab: multibox checklist, recommended settings (apply / restore), recommended addons. ]]
local _, ns = ...
local UI, W = ns.UI, ns.Widgets
local tab = { key = "setup", label = "Setup" }

function tab.build(p)
  local h1 = W.text(p, "GameFontNormal", nil, W.GOLD)
  h1:SetPoint("TOPLEFT", 0, -4)
  h1:SetText("Multibox checklist")
  local sf, content = W.scroll(p, 290, 236)
  sf:SetPoint("TOPLEFT", 0, -22)
  p.checks = content
  p.checkPool = W.pool(content, function(parent)
    local r = CreateFrame("Frame", nil, parent)
    r:SetSize(286, 36)
    r.mark = W.text(r, "GameFontNormal")
    r.mark:SetPoint("TOPLEFT", 2, -2)
    r.text = W.text(r, "GameFontHighlightSmall", nil, W.TEXT)
    r.text:SetPoint("TOPLEFT", 20, -2)
    r.text:SetWidth(262)
    r.hint = W.text(r, "GameFontHighlightSmall", nil, W.MUTED)
    r.hint:SetPoint("TOPLEFT", r.text, "BOTTOMLEFT", 0, -1)
    r.hint:SetWidth(262)
    r.fix = W.button(r, "Fix", 80, 18, function() if r.fixFn then r.fixFn() end end)
    r.fix:SetPoint("TOPRIGHT", 0, -1)
    return r
  end)

  local h2 = W.text(p, "GameFontNormal", nil, W.GOLD)
  h2:SetPoint("TOPLEFT", sf, "BOTTOMLEFT", 0, -10)
  h2:SetText("Recommended addons")
  p.addons = W.text(p, "GameFontHighlightSmall", nil, W.TEXT)
  p.addons:SetPoint("TOPLEFT", h2, "BOTTOMLEFT", 0, -4)
  p.addons:SetWidth(290)
  p.addons:SetJustifyV("TOP")

  p.cvTitle = W.text(p, "GameFontNormal", nil, W.GOLD)
  p.cvTitle:SetPoint("TOPLEFT", 312, -4)
  for _, col in ipairs({ { "Setting", 0 }, { "Now", 166 }, { "Tip", 206 } }) do
    local hdr = W.text(p, "GameFontHighlightSmall", nil, W.MUTED)
    hdr:SetPoint("TOPLEFT", 312 + col[2], -24)
    hdr:SetText(col[1])
  end
  p.cvPool = W.pool(p, function(parent, i)
    local r = CreateFrame("Frame", nil, parent)
    r:SetSize(294, 20)
    r:SetPoint("TOPLEFT", 312, -40 - (i - 1) * 21)
    r.label = W.text(r, "GameFontHighlightSmall", nil, W.TEXT)
    r.label:SetPoint("LEFT", 0, 0)
    r.label:SetWidth(160)
    r.now = W.text(r, "GameFontHighlightSmall", nil, W.TEXT)
    r.now:SetPoint("LEFT", 166, 0)
    r.rec = W.text(r, "GameFontHighlightSmall", nil, W.TEXT)
    r.rec:SetPoint("LEFT", 206, 0)
    r.st = W.text(r, "GameFontHighlightSmall")
    r.st:SetPoint("LEFT", 246, 0)
    return r
  end)
  p.restore = W.button(p, "Restore old values", 140, 22, function() ns.Core.restoreCVars() end)
  p.restore:SetPoint("BOTTOMRIGHT", -150, 4)
  p.applyCv = W.button(p, "Apply settings", 140, 22, function() ns.Core.applyCVars(ns.Core.cdb.importCVars) end)
  p.applyCv:SetPoint("BOTTOMRIGHT", 0, 4)
end

local STATE = { loaded = { "Loaded", W.GREEN }, installed = { "Installed, not loaded", W.ORANGE }, missing = { "Missing", W.RED } }

function tab.refresh(p)
  local Core, C, R = ns.Core, ns.Compat, ns.Rules
  -- checklist
  p.checkPool:reset()
  local y = 0
  for _, it in ipairs(ns.Checklist.items()) do
    local r = p.checkPool:get()
    r:SetPoint("TOPLEFT", 0, -y)
    local col = it.ok == true and W.GREEN or (it.ok == false and W.ORANGE or W.BLUE)
    r.mark:SetText(it.ok == true and "+" or (it.ok == false and "!" or "i"))
    r.mark:SetTextColor(col[1], col[2], col[3])
    r.text:SetText(it.text)
    r.hint:SetText(it.hint or "")
    r.fixFn = it.fix and it.fix.fn or false
    if it.fix then r.fix:SetText(it.fix.label); r.fix:Show(); r.text:SetWidth(178) else r.fix:Hide(); r.text:SetWidth(262) end
    y = y + 38
  end
  p.checks:SetHeight(math.max(y, 10))
  -- addons
  local lines = {}
  local list = Core.db.settings.addons or {}
  local seen = {}
  local all = {}
  for _, a in ipairs(R.ADDONS) do all[#all + 1] = a.name; seen[a.name] = true end
  for _, a in ipairs(list) do if not seen[a] then all[#all + 1] = a; seen[a] = true end end
  for _, name in ipairs(all) do
    local st = STATE[C.addonState(name)]
    lines[#lines + 1] = W.hex(st[2]) .. st[1] .. "|r · " .. name
  end
  p.addons:SetText(table.concat(lines, "\n"))
  -- cvars
  local plan, role = Core.cvarPlan(Core.cdb.importCVars)
  p.cvTitle:SetText("Settings for a " .. role)
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
  p.applyCv:SetText(nChange > 0 and ("Apply " .. nChange .. " setting" .. (nChange > 1 and "s" or "")) or "Settings OK")
  p.applyCv:SetEnabled(nChange > 0)
  p.restore:SetEnabled(next(Core.cdb.cvarBackup) ~= nil)
end

UI.RegisterTab(tab)
