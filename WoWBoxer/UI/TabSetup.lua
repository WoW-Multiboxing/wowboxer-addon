--[[ WoWBoxer – Setup tab: where your keys go and how the window behaves (left), the multibox checklist (left, below),
  recommended game settings with apply / restore and recommended addons (right). ]]
local _, ns = ...
local UI, W = ns.UI, ns.Widgets
local tab = { key = "setup", label = "Setup", icon = "INV_Misc_Gear_01", tip = "Where your macros go, window size, animations, the multibox checklist and game settings. WoWBoxer's settings are per WoW account: with one account per character, use Copy settings to use the same on your other characters." }
local LEFT_W = 300

local function Core() return ns.Core end
local SCALES = { { 0.7, "70 %" }, { 0.8, "80 %" }, { 0.9, "90 %" }, { 1, "100 %" }, { 1.1, "110 %" }, { 1.2, "120 %" }, { 1.3, "130 %" } }

function tab.build(p)
  -- your keys + window
  local h0 = W.text(p, "GameFontNormal", nil, W.GOLD)
  h0:SetPoint("TOPLEFT", 0, -4)
  h0:SetText("Macros and window")
  local Bars = ns.Bars
  local function barValues() local v = {}; for _, b in ipairs(Bars.BARS) do v[#v + 1] = { b.first, b.label } end return v end
  local function row(y, label, widget, tip)
    local t = W.text(p, "GameFontHighlightSmall", nil, W.TEXT)
    t:SetPoint("TOPLEFT", 0, y - 6)
    t:SetText(label)
    widget:SetPoint("TOPLEFT", 120, y)
    if tip then W.ddTip(widget, label, tip) end
    return t
  end
  p.bar1 = W.dropdown(p, { width = 170, values = barValues, get = function() return Core().cdb.primaryBar end,
    set = function(v) Core().cdb.primaryBar = v; Core().cdb.slots = {}; Core().changed() end })
  row(-22, "Main macros", p.bar1, "Where Place all puts macros 1–8, the sequences and Follow/Assist. Macros you dragged somewhere yourself stay there.")
  p.bar2 = W.dropdown(p, { width = 170, values = barValues, get = function() return Core().cdb.secondaryBar end,
    set = function(v) Core().cdb.secondaryBar = v; Core().cdb.slots = {}; Core().changed() end })
  row(-50, "Other macros", p.bar2, "Where Place all puts your own macros, Focus and the pet macros.")
  p.scale = W.dropdown(p, { width = 170, values = function() return SCALES end,
    get = function() local v = tonumber(Core().db.settings.scale) or 1; return math.floor(v * 10 + 0.5) / 10 end,
    set = function(v) Core().db.settings.scale = v; UI.ApplyWindowSettings() end })
  row(-78, "Window size", p.scale, "Makes this window bigger or smaller. It always fits the screen. Same as /wbx scale.")
  p.replace = W.check(p, "Ask to replace buttons", function(_, v) Core().cdb.askReplace = v and true or false; Core().changed() end)
  p.replace:SetPoint("TOPLEFT", -4, -104)
  W.tip(p.replace, "Ask to replace buttons", "A macro goes where you put it, else where its spell already is. On: when that button holds something else (a spell, an item or another macro), WoWBoxer asks before replacing it. Off: it never replaces; drag the macro yourself.")
  p.anim = W.check(p, "Animations", function(_, v) Core().db.settings.animations = v; Core().changed() end)
  p.anim:SetPoint("TOPLEFT", -4, -126)
  W.tip(p.anim, "Animations", "When WoWBoxer places or updates macros, their icons fly to the action buttons and the buttons flash. Only a picture: it changes nothing.")
  p.remind = W.check(p, "Level-up reminders", function(_, v) if v then Core().cdb.reminders = nil else Core().cdb.reminders = false end; Core().changed() end)
  p.remind:SetPoint("TOPLEFT", 140, -126)
  W.tip(p.remind, "Level-up reminders", "On: a small window (and one chat line) when a level-up or a new spell changes your macros. Off: no reminders – the book still marks changed macros with an orange dot.")
  p.strip = W.check(p, "Sequence strip", function(_, v) Core().db.settings.seqStrip = v; ns.SeqStrip.markDirty(); ns.SeqStrip.request(); Core().changed() end)
  p.strip:SetPoint("TOPLEFT", -4, -148)
  W.tip(p.strip, "Sequence strip", "Shows the steps of your sequence macros as small icons on the action button and frames the spell that comes next. Only a picture: it changes nothing.")
  p.guideBtn = W.button(p, "Guide", 80, 22, function() ns.Book.ShowGuide() end, "Opens the 3-step guide again on the My macros page.")
  p.guideBtn:SetPoint("TOPLEFT", 0, -174)
  p.macrosOnly = W.button(p, "Macros only", 100, 22, function() Core().sync({ macrosOnly = true }) end,
    "Creates or updates your WoWBoxer macros without touching your action bars (drag them yourself from the book).")
  p.macrosOnly:SetPoint("LEFT", p.guideBtn, "RIGHT", 6, 0)
  p.autoBtn = W.button(p, "Automation…", 96, 22, function() UI.Select("automation") end,
    "Squad automation: accept invites, quests, resurrections and summons, follow the leader's dialogs, sell junk, repair – each one a tick.")
  p.autoBtn:SetPoint("LEFT", p.macrosOnly, "RIGHT", 6, 0)
  p.copySet = W.button(p, "Copy settings", 120, 22, function() if ns.Settings then ns.Settings.send() end end,
    { "Copy settings", "WoWBoxer's settings are per WoW account, so with one account per character each one has its own. This sends this character's settings (Standard/Advanced, Automation, Accept from, quest reward, window size, animations, sequence strip, team panel, minimap button, reminders) to your squad in the party. Each character shows Use them / Ignore." })
  p.copySet:SetPoint("TOPLEFT", 0, -200)
  p.copyHint = W.text(p, "GameFontHighlightSmall", nil, W.MUTED)
  p.copyHint:SetPoint("LEFT", p.copySet, "RIGHT", 8, 0)
  p.copyHint:SetText("to my other characters")
  p.copyHint.wbxCopy = "hint"
  -- Reset to default (docs/advanced-mode.md §5): a red text button at the bottom; opens a two-step window
  p.resetAll = CreateFrame("Button", nil, p)
  p.resetAll:SetSize(110, 18)
  p.resetAll:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", -2, 2)
  p.resetAll.text = W.text(p.resetAll, "GameFontHighlightSmall", nil, { 1, 0.4, 0.35 }, "RIGHT")
  p.resetAll.text:SetPoint("RIGHT", 0, 0)
  p.resetAll.text:SetText("Reset to default…")
  p.resetAll.text.wbxCopy = "label"
  p.resetAll:SetScript("OnClick", function() ns.Advanced.openReset() end)
  W.tip(p.resetAll, "Reset to default", "Choose what to reset: this character, all squads and builds, WBX macros, game settings. Asks twice; nothing happens in combat.")

  -- checklist
  local h1 = W.text(p, "GameFontNormal", nil, W.GOLD)
  h1:SetPoint("TOPLEFT", 0, -230)
  h1:SetText("Multibox checklist")
  local sf, content = W.scroll(p, LEFT_W - 24, 170)
  sf:SetPoint("TOPLEFT", 0, -248)
  p.checkSf, p.checks = sf, content
  p.checkPool = W.pool(content, function(parent)
    local r = CreateFrame("Frame", nil, parent)
    r:SetSize(LEFT_W - 28, 36)
    r.mark = W.text(r, "GameFontNormal")
    r.mark:SetPoint("TOPLEFT", 2, -2)
    r.fix = W.button(r, "Fix", 60, 18, function() if r.fixFn then r.fixFn() end end, "Makes this change in WoWBoxer for you.")
    r.fix:SetPoint("TOPRIGHT", 0, -1)
    r.text = W.text(r, "GameFontHighlightSmall", nil, W.TEXT)
    r.text:SetPoint("TOPLEFT", 20, -2)
    W.tooltip(r, function(GT) GT:AddLine(r.text:GetText() or "", 1, 0.82, 0); if r.tip and r.tip ~= "" then GT:AddLine(r.tip, 1, 1, 1, true) end end)
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
    r:SetPoint("TOPLEFT", X, -40 - (i - 1) * 19)
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
  p.restore = W.button(p, "Restore", 90, 22, function() Core().restoreCVars() end,
    "Puts back the game settings WoWBoxer changed.")
  p.restore:SetPoint("LEFT", p.applyCv, "RIGHT", 6, 0)
  -- a setting the game did not keep: open its options page (Sticky Targeting for "Clear target on click")
  p.openOpt = W.button(p, "Open Options", 100, 22, function() ns.Compat.openOptions(p.stuckName) end, { "Open Options", function()
    return p.stuckName == "deselectOnClick" and "Opens the game's Controls options. Untick Sticky Targeting there." or "Opens the game's options for the setting that did not stick." end })
  p.openOpt:SetPoint("LEFT", p.restore, "RIGHT", 6, 0)
  p.openOpt:Hide()

  -- a line that points at Automation (docs/feedback-2026-10-30-night.md §6)
  p.autoLine = W.text(p, "GameFontHighlightSmall", nil, W.MUTED)
  p.autoLine:SetPoint("TOPLEFT", p.applyCv, "BOTTOMLEFT", 0, -8)
  p.autoLine:SetText("Also: invites, quests, summons →")
  p.autoLine.wbxCopy = "hint"
  p.autoLink = W.button(p, "Automation", 90, 20, function() UI.Select("automation") end, "Opens the Automation bookmark: invites, quests, dialogs, summons and the vendor for your squad.")
  p.autoLink:SetPoint("LEFT", p.autoLine, "RIGHT", 6, 0)
  local h2 = W.text(p, "GameFontNormal", nil, W.GOLD)
  h2:SetPoint("TOPLEFT", p.autoLine, "BOTTOMLEFT", 0, -12)
  h2:SetText("Recommended addons")
  p.addons = W.text(p, "GameFontHighlightSmall", nil, W.TEXT)
  p.addons:SetPoint("TOPLEFT", h2, "BOTTOMLEFT", 0, -4)
  p.addons:SetWidth(330)
  p.addons:SetJustifyV("TOP")
end

local STATE = { loaded = { "Loaded", W.GREEN }, installed = { "Not loaded", W.ORANGE }, missing = { "Missing", W.RED } }

function tab.refresh(p)
  local C, R = ns.Compat, ns.Rules
  local cdb = Core().cdb
  p.bar1.Refresh(); p.bar2.Refresh(); p.scale.Refresh()
  p.replace:SetChecked(cdb.askReplace ~= false)
  p.anim:SetChecked(Core().db.settings.animations ~= false)
  p.strip:SetChecked(Core().db.settings.seqStrip ~= false)
  p.remind:SetChecked(Core().remindersOn())
  p.macrosOnly:SetEnabled(not C.inCombat())
  p.copySet:SetEnabled(C.inParty() and true or false)
  p.resetAll:SetEnabled(not C.inCombat())
  if ns.Advanced then ns.Advanced.refreshReset() end
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
    r.fix.wbxBig = (it.fix and it.fix.big) or nil -- a named preset may be 3 words (the page's big action)
    if it.fix then W.setLabel(r.fix, it.fix.label); r.fix:Show(); tw = tw - r.fix:GetWidth() - 6 else r.fix:Hide() end
    r.text:SetWidth(tw)
    r.text:SetText(it.text)
    r.tip = it.hint
    local h = (r.text:GetStringHeight() or 12) + 6
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
  p.cvTitle:SetText("Game settings")
  p.cvRole = role
  p.cvPool:reset()
  local nChange, nStuck, stuckName = 0, 0, nil
  local rows = 0
  for _, c in ipairs(plan) do
    if c.status ~= "missing" then -- only settings this client has
    rows = rows + 1
    local r = p.cvPool:get()
    r.label:SetText(c.label)
    r.now:SetText(c.current == nil and "–" or tostring(c.current))
    r.rec:SetText(c.want or "–")
    local st = ({ change = { "Change", W.ORANGE }, ok = { "OK", W.GREEN }, missing = { "n/a", W.MUTED }, leave = { "", W.MUTED },
      stuck = { "Didn't stick", W.ORANGE } })[c.status]
    if c.status == "stuck" then nStuck = nStuck + 1; stuckName = c.name end
    r.st:SetText(st[1]); r.st:SetTextColor(st[2][1], st[2][2], st[2][3])
    if c.status == "change" or c.status == "stuck" then nChange = nChange + 1 end
    W.tooltip(r, function(GT) GT:AddLine(c.label .. " (" .. c.name .. ")", 1, 0.82, 0); GT:AddLine(c.why, 1, 1, 1, true) end)
    end
  end
  p.applyCv:ClearAllPoints()
  p.applyCv:SetPoint("TOPLEFT", LEFT_W + 20, -40 - rows * 19 - 6)
  W.setLabel(p.applyCv, nChange > 0 and ("Apply " .. nChange .. " setting" .. (nChange > 1 and "s" or "")) or "Settings OK")
  p.applyCv:SetEnabled(nChange > 0)
  p.stuckName = stuckName
  p.openOpt:SetShown(nStuck > 0)
  p.restore:SetEnabled(next(cdb.cvarBackup) ~= nil)
end

UI.RegisterTab(tab)
