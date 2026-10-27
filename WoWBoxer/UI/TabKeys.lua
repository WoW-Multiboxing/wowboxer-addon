--[[ WoWBoxer – Keys tab: the character's WBX keys for its level, what changes, the macro text, bars, apply. ]]
local _, ns = ...
local UI, W = ns.UI, ns.Widgets
local tab = { key = "keys", label = "Keys" }

local STATUS = {
  create = { "New", W.BLUE }, update = { "Changed", W.ORANGE }, same = { "OK", W.GREEN }, noslot = { "No slot", W.RED },
  invalid = { "Blocked", W.RED }, skipped = { "Off", W.MUTED },
}
local TIERS = { { "off", "Off" }, { "simple", "Simple" }, { "medium", "Medium" }, { "advanced", "Advanced" } }
local ROW_H = 26

local function selectedItem(p, ctx)
  for _, it in ipairs(ctx.macros.items) do if it.name == p.selected then return it end end
  return ctx.macros.items[1]
end

function tab.build(p)
  -- banner
  p.banner = W.box(p, 0.17, 0.23, 0.11, 0.95)
  p.banner:SetPoint("TOPLEFT", 0, 0)
  p.banner:SetPoint("TOPRIGHT", 0, 0)
  p.banner:SetHeight(30)
  p.bannerText = W.text(p.banner, "GameFontHighlightSmall", nil, W.TEXT)
  p.bannerText:SetPoint("LEFT", 10, 0)
  p.bannerText:SetPoint("RIGHT", -130, 0)
  p.bannerBtn = W.button(p.banner, "Update keys", 116, 22, function() ns.Core.sync({ replace = ns.Core.cdb.replace }) end)
  p.bannerBtn:SetPoint("RIGHT", -6, 0)

  -- empty state (no squad)
  p.empty = CreateFrame("Frame", nil, p)
  p.empty:SetAllPoints()
  local et = W.text(p.empty, "GameFontHighlight", nil, W.TEXT, "CENTER")
  et:SetPoint("TOP", 0, -60)
  et:SetWidth(520)
  et:SetText("This character is not in a squad yet.\n\nStart a squad with just this character (you can add the others later),\nor import your squad string from the WoWBoxer website or another character.")
  local qs = W.button(p.empty, "Start a squad", 140, 24, function()
    local Core = ns.Core
    ns.State.quickStart(Core.db, Core.cdb, Core.playerInfo())
    Core.log("info", "quick start")
    Core.changed()
  end)
  qs:SetPoint("TOP", et, "BOTTOM", -76, -20)
  local imp = W.button(p.empty, "Import a string", 140, 24, function() UI.Select("share") end)
  imp:SetPoint("LEFT", qs, "RIGHT", 12, 0)

  p.main = CreateFrame("Frame", nil, p)
  p.main:SetAllPoints()
  local m = p.main
  local head = W.text(m, "GameFontNormal", nil, W.GOLD)
  head:SetPoint("TOPLEFT", 0, -38)
  head:SetText("Your keys")
  p.head = head
  -- sequence tier
  p.tierButtons = {}
  local prevBtn
  for i = #TIERS, 1, -1 do
    local t = TIERS[i]
    local b = W.button(m, t[2], 70, 20, function()
      local _, mem = ns.Core.me()
      if mem then mem.seq = t[1]; ns.Core.log("info", "sequence tier " .. t[1]); ns.Core.changed() end
    end)
    if prevBtn then b:SetPoint("RIGHT", prevBtn, "LEFT", -2, 0) else b:SetPoint("TOPRIGHT", m, "TOPRIGHT", -232, -34) end
    prevBtn = b
    p.tierButtons[t[1]] = b
  end
  p.tierLabel = W.text(m, "GameFontHighlightSmall", nil, W.MUTED, "RIGHT")
  p.tierLabel:SetPoint("RIGHT", prevBtn, "LEFT", -6, 0)
  p.tierLabel:SetText("Sequence:")
  p.tierNone = W.text(m, "GameFontHighlightSmall", nil, W.MUTED, "RIGHT")
  p.tierNone:SetPoint("TOPRIGHT", m, "TOPRIGHT", -232, -38)

  -- list
  local sf, content = W.scroll(m, 360, 250)
  sf:SetPoint("TOPLEFT", 0, -58)
  p.list = content
  p.pool = W.pool(content, function(parent)
    local r = CreateFrame("Button", nil, parent)
    r:SetSize(356, ROW_H)
    r.hl = r:CreateTexture(nil, "BACKGROUND")
    r.hl:SetAllPoints()
    r.hl:SetColorTexture(1, 0.82, 0, 0.12)
    r.check = W.frame("CheckButton", r, "UICheckButtonTemplate")
    r.check:SetSize(20, 20)
    r.check:SetPoint("LEFT", 0, 0)
    r.icon = W.icon(r, 20)
    r.icon:SetPoint("LEFT", 22, 0)
    r.key = W.text(r, "GameFontDisableSmall", nil, W.MUTED)
    r.key:SetPoint("LEFT", 48, 0)
    r.key:SetWidth(54)
    r.label = W.text(r, "GameFontHighlightSmall", nil, W.TEXT)
    r.label:SetPoint("LEFT", 104, 0)
    r.label:SetWidth(150)
    if r.label.SetWordWrap then r.label:SetWordWrap(false) end
    r.status = W.text(r, "GameFontHighlightSmall")
    r.status:SetPoint("LEFT", 258, 0)
    r.status:SetWidth(52)
    r.slot = W.text(r, "GameFontDisableSmall", nil, W.MUTED, "RIGHT")
    r.slot:SetPoint("RIGHT", -2, 0)
    r.slot:SetWidth(46)
    r:SetScript("OnClick", function(self) p.selected = self.name; UI.Refresh() end)
    r.check:SetScript("OnClick", function(self)
      local cdb = ns.Core.cdb
      cdb.skip[r.name] = (not self:GetChecked()) or nil
      ns.Core.changed()
    end)
    return r
  end)

  -- preview
  p.prevTitle = W.text(m, "GameFontNormal", nil, W.GOLD)
  p.prevTitle:SetPoint("TOPLEFT", 372, -58)
  p.prevTitle:SetWidth(252)
  local pv = W.box(m, 0.05, 0.04, 0.025, 0.95)
  pv:SetPoint("TOPLEFT", 368, -76)
  pv:SetSize(258, 126)
  p.prevBody = W.text(pv, "GameFontHighlightSmall", 11, { 0.85, 0.94, 0.75 })
  p.prevBody:SetPoint("TOPLEFT", 6, -6)
  p.prevBody:SetPoint("BOTTOMRIGHT", -6, 6)
  p.prevBody:SetJustifyV("TOP")
  p.prevInfo = W.text(m, "GameFontHighlightSmall", nil, W.MUTED)
  p.prevInfo:SetPoint("TOPLEFT", pv, "BOTTOMLEFT", 2, -4)
  p.prevInfo:SetWidth(256)
  p.rules = W.text(m, "GameFontHighlightSmall", nil, W.MUTED)
  p.rules:SetPoint("TOPLEFT", p.prevInfo, "BOTTOMLEFT", 0, -6)
  p.rules:SetWidth(256)

  p.trainer = W.text(m, "GameFontHighlightSmall", nil, { 0.85, 0.7, 0.42 })
  p.trainer:SetPoint("TOPLEFT", sf, "BOTTOMLEFT", 0, -6)
  p.trainer:SetWidth(620)

  -- footer
  local Bars = ns.Bars
  local function barValues() local v = {}; for _, b in ipairs(Bars.BARS) do v[#v + 1] = { b.first, b.label } end return v end
  local lb1 = W.text(m, "GameFontHighlightSmall", nil, W.MUTED)
  lb1:SetPoint("BOTTOMLEFT", 0, 34)
  lb1:SetText("Main keys")
  p.bar1 = W.cycle(m, { width = 150, values = barValues, get = function() return ns.Core.cdb.primaryBar end,
    set = function(v) ns.Core.cdb.primaryBar = v; ns.Core.cdb.slots = {}; ns.Core.changed() end })
  p.bar1:SetPoint("LEFT", lb1, "RIGHT", 6, 0)
  local lb2 = W.text(m, "GameFontHighlightSmall", nil, W.MUTED)
  lb2:SetPoint("LEFT", p.bar1, "RIGHT", 10, 0)
  lb2:SetText("Other keys")
  p.bar2 = W.cycle(m, { width = 150, values = barValues, get = function() return ns.Core.cdb.secondaryBar end,
    set = function(v) ns.Core.cdb.secondaryBar = v; ns.Core.cdb.slots = {}; ns.Core.changed() end })
  p.bar2:SetPoint("LEFT", lb2, "RIGHT", 6, 0)
  p.replace = W.check(m, "Replace occupied buttons", function(_, v) ns.Core.cdb.replace = v; ns.Core.changed() end)
  p.replace:SetPoint("BOTTOMLEFT", -2, 4)
  p.slots = W.text(m, "GameFontHighlightSmall", nil, W.MUTED)
  p.slots:SetPoint("LEFT", p.replace.label, "RIGHT", 14, 0)
  p.apply = W.button(m, "Create & place keys", 150, 24, function() ns.Core.sync({ replace = ns.Core.cdb.replace }) end)
  p.apply:SetPoint("BOTTOMRIGHT", 0, 2)
  p.macrosOnly = W.button(m, "Macros only", 100, 24, function() ns.Core.sync({ macrosOnly = true }) end)
  p.macrosOnly:SetPoint("RIGHT", p.apply, "LEFT", -6, 0)
end

function tab.refresh(p, ctx)
  local Core = ns.Core
  if not ctx then p.main:Hide(); p.banner:Hide(); p.empty:Show(); return end
  p.empty:Hide(); p.main:Show()
  local mem = ctx.member
  -- banner
  if ctx.macros.changes > 0 then
    p.banner:Show()
    p.bannerText:SetText((Core.cdb.lastSync and ("|cffb7f07aLevel " .. ctx.level .. ":|r ") or "") .. ctx.macros.changes .. " key(s) to create or update. Same buttons, new macros.")
  else p.banner:Hide() end
  -- tiers
  local seqOk = ns.Engine.seqSupported(mem.cls)
  for k, b in pairs(p.tierButtons) do
    b:SetShown(seqOk)
    if mem.seq == k then b:LockHighlight() else b:UnlockHighlight() end
  end
  p.tierLabel:SetShown(seqOk)
  p.tierNone:SetShown(not seqOk)
  p.tierNone:SetText(seqOk and "" or "Built-in sequences: Paladin, Priest, Warlock")
  -- rows
  local barOf = {}
  for _, it in ipairs(ctx.bars.items) do barOf[it.name] = it end
  local layout = ns.Bars.layout(ctx.desired, Core.cdb)
  local desiredBy = {}
  for _, d in ipairs(ctx.desired) do desiredBy[d.name] = d end
  p.pool:reset()
  local y = 0
  for _, it in ipairs(ctx.macros.items) do
    local r = p.pool:get()
    r.name = it.name
    r:SetPoint("TOPLEFT", 0, -y)
    y = y + ROW_H
    local d = desiredBy[it.name]
    W.setIcon(r.icon, d and d.spell and d.spell.icon or (it.group == "helper" and "Ability_Hunter_Pet_Wolf") or nil)
    r.key:SetText((it.name:gsub("^WBX ", "")))
    r.label:SetText(it.label)
    local st = STATUS[it.status] or { it.status, W.TEXT }
    local b = barOf[it.name]
    local stText, stColor = st[1], st[2]
    if it.status == "same" and b and b.status ~= "placed" then stText, stColor = "Not on bar", W.ORANGE end
    if b and b.status == "occupied" and it.status ~= "skipped" then stText, stColor = (it.status == "same" and "Occupied" or stText), W.ORANGE end
    r.status:SetText(stText)
    r.status:SetTextColor(stColor[1], stColor[2], stColor[3])
    local slot = layout[it.name]
    r.slot:SetText(slot and ns.Bars.slotLabel(slot) or "-")
    r.check:SetChecked(it.status ~= "skipped")
    if p.selected == it.name then r.hl:Show() else r.hl:Hide() end
    W.tooltip(r, function(GT) GT:AddLine(it.name .. " – " .. it.label, 1, 0.82, 0); for line in (it.body .. "\n"):gmatch("([^\n]*)\n") do GT:AddLine(line, 0.85, 0.94, 0.75) end end)
  end
  p.list:SetHeight(math.max(y, 10))
  -- preview
  local sel = selectedItem(p, ctx)
  if sel then
    p.selected = sel.name
    p.prevTitle:SetText(sel.name .. " · " .. sel.label)
    p.prevBody:SetText(sel.body)
    local info = #sel.body .. " / 255 characters"
    local d = desiredBy[sel.name]
    if d and d.seq then
      local s = d.seq
      info = info .. " · " .. (s.kind == "priority" and "priority list, highest first" or (s.kind == "sequence" and ("loop ~" .. ns.Engine.numstr(s.loopSec) .. " s" .. (s.why ~= "" and (", " .. s.why) or "")) or s.kind))
      if s.compact then info = info .. " · shortened to fit" end
    end
    if sel.status == "update" and sel.old then info = info .. "\n|cfff0b43cChanged from:|r " .. sel.old:gsub("\n", " / ") end
    if sel.why then info = info .. "\n|cffff8a80" .. sel.why .. "|r" end
    p.prevInfo:SetText(info)
  else p.prevTitle:SetText(""); p.prevBody:SetText(""); p.prevInfo:SetText("") end
  p.rules:SetText(mem.leader and "Leader: hostile mouseover, then your own target. Heals: friendly mouseover, friendly target, then yourself."
    or ("Follower via " .. mem.unit .. ": hostile mouseover, then the leader's target (" .. mem.unit .. "target), then your own. Heals: mouseover, the leader, then yourself."))
  -- trainer
  if #ctx.missing > 0 then
    local n = {}
    for i, s in ipairs(ctx.missing) do if i <= 5 then n[#n + 1] = s.name end end
    p.trainer:SetText("Visit your trainer: " .. table.concat(n, ", ") .. (#ctx.missing > 5 and (" +" .. (#ctx.missing - 5)) or "") .. " – not in your spellbook yet, so they are left out of your keys.")
  else p.trainer:SetText("") end
  p.bar1.Refresh(); p.bar2.Refresh()
  p.replace:SetChecked(Core.cdb.replace and true or false)
  local _, charMax = ns.Compat.macroLimits()
  p.slots:SetText((charMax - ctx.macros.free - ctx.macros.counts.create) .. " / " .. charMax .. " character macros used" ..
    (ctx.macros.counts.noslot > 0 and ("  |cffff8a80" .. ctx.macros.counts.noslot .. " without a slot|r") or ""))
  local busy = ns.Compat.inCombat()
  p.apply:SetEnabled(not busy); p.macrosOnly:SetEnabled(not busy)
end

UI.RegisterTab(tab)
