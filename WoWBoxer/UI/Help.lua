--[[ WoWBoxer – help on every page (docs/ui-spec-v3-book.md, "Help on every tab + a squad guide").
  One round "?" in the window's title bar belongs to the page you are on: hover = 2–4 short lines on how to use the
  page; click = a help overlay that dims the page and puts 3–5 numbered gold callouts on the real controls (Blizzard's
  HelpPlate when the client has it, else our own overlay with the same idea). Click anywhere or Esc closes it. The
  first time a page is opened, the "?" pulses once (no auto-popup).
  The squad guide (3 steps) opens from the Squad help, the minimap menu, and is offered once when a second
  character joins the party. Display and navigation only: nothing here writes to the game by itself – the step
  buttons are the same buttons as on the pages (a click each). ]]
local _, ns = ...
local UI, W = ns.UI, ns.Widgets
local Help = {}
ns.Help = Help

local function Core() return ns.Core end
local function settings() return Core().db and Core().db.settings or {} end

-- ------------------------------------------------------------------ what each page says
local function vis(f) return f and f.IsVisible and f:IsVisible() and f or nil end
local function firstShown(list) for _, b in ipairs(list or {}) do if b:IsShown() and b.cell then return b end end end
local function firstRow(pool) return pool and pool.rows and pool.rows[1] and pool.rows[1]:IsShown() and pool.rows[1] or nil end
local function sq(key) return UI.panels.squad.frames[key] end

--- page key -> {title, tip = {lines}, callouts = fn() -> {{frame, text}}}
Help.PAGES = {
  keys = { tip = { "Drag a macro onto your action bar.", "Glow = new, orange dot = changed, dim = not on a bar.", "The banner shows the one thing to do now." },
    callouts = function() local p = UI.panels.keys
      local helper
      for _, b in ipairs(p.helperPool or {}) do if b:IsShown() then helper = helper or b end end
      return { { p.strip, "Next step: one click" }, { firstShown(p.cells), "Drag a macro to your bar" }, { p.role, "Role and leader or follower" },
        { helper, "Follow, assist and pet macros" }, { p.det, "The selected macro" } } end },
  spells = { tip = { "Every spell you know, then later ones.", "Drag one onto your bar to make it a macro.", "Grey: trainer. Lock: a later level." },
    callouts = function() local p = UI.panels.spells
      return { { p.strip, "Next step" }, { firstShown(p.cells), "Drag a spell to your bar" }, { p.hint, "Grey: trainer · Lock: later levels" } } end },
  custom = { tip = { "Your own sequence macros, up to 8.", "Click a macro to edit it.", "Right-click for copy and more." },
    callouts = function() local p = UI.panels.custom
      local new, own
      for _, b in ipairs(p.cells) do if b:IsShown() and b.cell then if b.cell.kind == "new" then new = b else own = own or b end end end
      return { { p.strip, "Next step" }, { own, "Click a macro to edit it" }, { new, "Build a new macro" }, { p.hint, "Up to 8 own macros" } } end },
  editor = { tip = { "Build a macro from your spells.", "Add spells as steps; pick a filler.", "Save, then place it like any macro." },
    callouts = function() local f = ns.KeyEditor.frame
      return { { f.kind, "Sequence or priority list" }, { f.strip, "Steps: click one to remove" }, { f.pickSf, "Add spells or pick a filler" },
        { f.macroSf, "The macro WoW will run" }, { ns.Advanced.ef and ns.Advanced.ef.save, "Save the macro" } } end },
  talents = { tip = { "The talent order of your guide.", "Take the point shown under Next." },
    callouts = function() local p = UI.panels.talents
      return { { p.guide, "Pick a talent guide" }, { p.nb, "Your next talent" }, { p.sf, "The whole point order" }, { p.readback, "Points spent in game" } } end },
  setup = { tip = { "Where your macros go and game settings.", "Fix buttons change WoWBoxer only.", "Automation…: invites, quests, dialogs, vendor – for your squad." },
    callouts = function() local p = UI.panels.setup
      return { { p.bar1, "Where your macros go" }, { p.replace, "May replace other buttons" }, { p.checkSf, "Multibox checklist" },
        { p.applyCv, "Apply recommended settings" }, { p.restore, "Undo game settings" } } end },
  ["squad:main"] = { tip = { "Who plays together, who leads; changes save at once.", "Follow (line): each follows the one before – easier on narrow paths.",
    "Follow leader: everyone stays close to the leader." },
    callouts = function() local f, p = sq("main"), UI.panels.squad
      local r = firstRow(f.pool)
      if not f.list:IsShown() then
        return { { f.empty.text, "Start your squad here" }, { vis(f.empty.party), "Everyone in your party" }, { f.empty.byName, "Characters not in your party" } }
      end
      return { { r and r.crown, "Click a crown: the leader" }, { r and r.role, "Role per character" }, { f.add, "Add someone not in your party" },
        { f.send, "Send to your other clients" }, { p.more, "Readiness, key map, plan, presets" } } end },
  ["squad:presets"] = { tip = { "Who leads, saved to switch back.", "Notes and everyone's sequence macros." },
    callouts = function() local f = sq("presets")
      return { { f.preset, "Switch who leads" }, { f.savePreset, "Save who leads now" }, { f.allSeq, "Everyone's sequence macros" } } end },
  ["squad:ready"] = { tip = { "Is everyone set up?", "Fix your own line here; the others on their clients." },
    callouts = function() local f = sq("ready")
      local r = firstRow(f.pool)
      return { { f.sf, "Green check = ready" }, { r and r.name, "Hover a line for details" }, { (r and vis(r.fix)) or f.note, "Fix your own line" } } end },
  ["squad:keymap"] = { tip = { "Same key, same job on every character." },
    callouts = function() local f = sq("keymap")
      return { { f.sf, "Same key, same job" }, { f.heads[1], "Your key per column" }, { f.copy, "Copy as a cheat sheet" } } end },
  ["squad:plan"] = { tip = { "Levelling together: trainer and talents." },
    callouts = function() local f = sq("plan")
      return { { f.heads and f.heads[3], "Next trainer visit" }, { f.heads and f.heads[4], "Next talent" }, { f.link, "Plan at the leader's level" } } end },
  automation = { tip = { "Squad automation: one tick each.", "Accept from: who it reacts to.", "Hold Shift to skip once." },
    callouts = function() local p = UI.panels.automation
      return { { p.from, "Who it accepts from" }, { p.ticks[1], "One tick per automation" }, { p.preset, "One click for levelling" } } end },
  share = { tip = { "Move your squad between clients.", "A string holds no macro text or code." },
    callouts = function() local p = UI.panels.share
      return { { p.importSf, "Paste a string here" }, { p.importBtn, "Import after the preview" }, { p.exportSf, "Your squad as a string" },
        { p.selectAll, "Select, then Ctrl+C" } } end },
}

--- The help key of what the player looks at now: a tab, a squad sub-page or the key editor.
function Help.pageKey()
  local key = UI.current
  if ns.KeyEditor.IsOpen() and (key == "custom" or key == "keys") then return "editor" end
  if key == "squad" and UI.panels.squad then return "squad:" .. (UI.panels.squad.page or "main") end
  return key
end
--- The visible callouts of a page: {{frame, text}} (3–5).
function Help.callouts(key)
  local def = Help.PAGES[key or Help.pageKey()]
  if not def then return {} end
  local ok, list = pcall(def.callouts)
  local out = {}
  for _, c in ipairs(ok and list or {}) do if vis(c[1]) and #out < 5 then out[#out + 1] = c end end
  return out
end

-- ------------------------------------------------------------------ the "?" button
-- A quest-giver "?" in a small round slot (dark disc + thin gold rim), like a quest you can turn in: everything stays
-- inside its 24 x 24 box, so nothing runs over the window border; the first-visit pulse is the icon itself brightening.
-- The war table look (docs/ui-redesign.md §3): a round 28-unit button, 1-unit gold ring, a Cinzel "?" in ui-gold.
local TH = ns.Theme
Help.ICON = TH.TEX .. "Question"
local DISC = TH.TEX .. "Circle"
function Help.attach(f)
  local b = CreateFrame("Button", nil, ns.UI.header or f)
  b:SetSize(28, 28)
  if ns.UI.closeBtn then b:SetPoint("RIGHT", ns.UI.closeBtn, "LEFT", -6, 0) else b:SetPoint("TOPRIGHT", -38, -9) end
  b.rim = b:CreateTexture(nil, "BACKGROUND")
  b.rim:SetAllPoints()
  b.rim:SetTexture(TH.TEX .. "CircleRing")
  b.rim:SetVertexColor(TH.rgb("gold"))
  b.bg = b:CreateTexture(nil, "BORDER")
  b.bg:SetPoint("TOPLEFT", 1, -1)
  b.bg:SetPoint("BOTTOMRIGHT", -1, 1)
  b.bg:SetTexture(DISC)
  b.bg:SetVertexColor(TH.rgb("panel2"))
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetSize(16, 16)
  b.icon:SetPoint("CENTER", 0, 0)
  b.icon:SetTexture(Help.ICON)
  b.icon:SetVertexColor(TH.rgb("uiGold"))
  b.glow = b:CreateTexture(nil, "OVERLAY")
  b.glow:SetAllPoints(b.icon)
  b.glow:SetTexture(Help.ICON)
  if b.glow.SetBlendMode then b.glow:SetBlendMode("ADD") end
  b.glow:Hide()
  local hl = b:CreateTexture(nil, "HIGHLIGHT")
  hl:SetPoint("TOPLEFT", 1, -1)
  hl:SetPoint("BOTTOMRIGHT", -1, 1)
  hl:SetTexture(DISC)
  hl:SetVertexColor(TH.rgb("panel3"))
  b:SetScript("OnMouseDown", function() b.icon:SetPoint("CENTER", 1, -1) end)
  b:SetScript("OnMouseUp", function() b.icon:SetPoint("CENTER", 0, 0) end)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:SetScript("OnClick", function(_, button) if button == "RightButton" then Help.Hide(); ns.Book.ShowGuide() else Help.Toggle() end end)
  W.tooltip(b, function(GT)
    GT:AddLine("Help for this page", 1, 0.82, 0)
    local def = Help.PAGES[Help.pageKey()]
    for _, l in ipairs(def and def.tip or {}) do GT:AddLine(l, 1, 1, 1, true) end
    GT:AddLine("Right-click: start the first-run guide again.", 0.66, 0.6, 0.49)
  end)
  -- one pulse: the glow fades in and out once
  if b.CreateAnimationGroup then
    local ag = b:CreateAnimationGroup()
    local a1 = ag:CreateAnimation("Alpha")
    if a1.SetFromAlpha then a1:SetFromAlpha(0); a1:SetToAlpha(1) end
    if a1.SetDuration then a1:SetDuration(0.5) end
    if a1.SetOrder then a1:SetOrder(1) end
    local a2 = ag:CreateAnimation("Alpha")
    if a2.SetFromAlpha then a2:SetFromAlpha(1); a2:SetToAlpha(0) end
    if a2.SetDuration then a2:SetDuration(0.7) end
    if a2.SetOrder then a2:SetOrder(2) end
    ag:SetScript("OnFinished", function() b.glow:Hide() end)
    b.pulse = ag
  end
  b.wbxLabel = "Help"
  UI.helpBtn = b
  return b
end

--- After a page is shown: pulse the "?" the first time (per page, account-wide).
function Help.onPage()
  local b = UI.helpBtn
  if not b then return end
  local key = Help.pageKey()
  local st = settings()
  st.helpSeen = type(st.helpSeen) == "table" and st.helpSeen or {}
  if Help.overlay and Help.overlay:IsShown() and Help.overlay.key ~= key then Help.Hide() end
  if st.helpSeen[key] then return end
  st.helpSeen[key] = true
  b.glow:Show()
  if b.pulse then b.pulse:Play() else b.glow:Hide() end
end

-- ------------------------------------------------------------------ the overlay
--- Blizzard's HelpPlate when the client has it (probe; tests force our own).
function Help.blizzard()
  if Help.forceOwn then return nil end
  if type(_G.HelpPlate_Show) == "function" and type(_G.HelpPlate_Hide) == "function" then return _G.HelpPlate_Show, _G.HelpPlate_Hide end
  return nil
end

local function overlayFrame()
  if Help.overlay then return Help.overlay end
  local o = CreateFrame("Button", nil, UI.pages)
  o:SetAllPoints(UI.pages)
  o:SetFrameLevel((UI.pages:GetFrameLevel() or 1) + 60)
  o:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  o:SetScript("OnClick", function() Help.Hide() end)
  o._noHit = true
  o.wbxModal = true
  o.dim = o:CreateTexture(nil, "BACKGROUND")
  o.dim:SetAllPoints()
  o.dim:SetColorTexture(0, 0, 0, 0.6)
  o.boxes, o.badges = {}, {}
  o.legend = W.box(o, 0.1, 0.08, 0.05, 0.97)
  o.legend:SetWidth(250)
  o.legend.title = W.text(o.legend, "GameFontNormal", nil, W.GOLD)
  o.legend.title:SetPoint("TOPLEFT", 10, -8)
  o.legend.title:SetText("Help")
  o.legend.title.wbxCopy = "label"
  o.legend.close = W.text(o.legend, "GameFontHighlightSmall", nil, W.MUTED, "RIGHT")
  o.legend.close:SetPoint("TOPRIGHT", -10, -9)
  o.legend.close:SetText("Click to close")
  o.legend.close.wbxCopy = "hint"
  o.legend.lines = {}
  o.guideBtn = W.button(o.legend, "Squad guide", 100, 22, function() Help.Hide(); Help.ShowSquadGuide() end,
    "Three steps to set up a squad on all your clients.")
  o.guideBtn:SetPoint("BOTTOMRIGHT", -8, 8)
  if o.EnableKeyboard then
    o:SetScript("OnKeyDown", function(self, key)
      if key == "ESCAPE" then
        if self.SetPropagateKeyboardInput then self:SetPropagateKeyboardInput(false) end
        Help.Hide()
      elseif self.SetPropagateKeyboardInput then self:SetPropagateKeyboardInput(true) end
    end)
  end
  o:Hide()
  Help.overlay = o
  return o
end

local function rectIn(o, f)
  local l, t, r, b = f:GetLeft(), f:GetTop(), f:GetRight(), f:GetBottom()
  local ol, ot = o:GetLeft(), o:GetTop()
  if not (l and t and r and b and ol and ot) then return nil end
  return { l - ol, ot - t, r - ol, ot - b } -- x0, y0 (down), x1, y1
end
local function hit(a, b) return a[1] < b[3] and b[1] < a[3] and a[2] < b[4] and b[2] < a[4] end

function Help.Show(key)
  key = key or Help.pageKey()
  local list = Help.callouts(key)
  if #list == 0 then return end
  local show = Help.blizzard()
  if show then
    -- HelpPlate: one plate per callout, coordinates from the page's top-left
    local o0 = UI.pages
    local info = { FramePos = { x = 0, y = 0 }, FrameSize = { width = o0:GetWidth(), height = o0:GetHeight() } }
    for i, c in ipairs(list) do
      local r = rectIn(o0, c[1])
      if r then
        info[#info + 1] = { ButtonPos = { x = r[1], y = -r[2] }, HighLightBox = { x = r[1], y = -r[2], width = r[3] - r[1], height = r[4] - r[2] },
          ToolTipDir = "RIGHT", ToolTipText = i .. ". " .. c[2] }
      end
    end
    if pcall(show, info, o0, UI.helpBtn) then Help.plate = info; Help.diag = "blizzard"; return end
  end
  Help.diag = "own"
  local o = overlayFrame()
  o.key = key
  local W0, H0 = o:GetWidth() or 680, o:GetHeight() or 440
  local taken = {}
  for i, c in ipairs(list) do
    local r = rectIn(o, c[1]) or { 0, 0, 0, 0 }
    -- gold frame around the control
    local bx = o.boxes[i]
    if not bx then
      bx = CreateFrame("Frame", nil, o)
      bx.edges = {}
      for e = 1, 4 do bx.edges[e] = bx:CreateTexture(nil, "OVERLAY"); bx.edges[e]:SetColorTexture(1, 0.82, 0, 0.9) end
      bx.edges[1]:SetPoint("TOPLEFT"); bx.edges[1]:SetPoint("TOPRIGHT"); bx.edges[1]:SetHeight(2)
      bx.edges[2]:SetPoint("BOTTOMLEFT"); bx.edges[2]:SetPoint("BOTTOMRIGHT"); bx.edges[2]:SetHeight(2)
      bx.edges[3]:SetPoint("TOPLEFT"); bx.edges[3]:SetPoint("BOTTOMLEFT"); bx.edges[3]:SetWidth(2)
      bx.edges[4]:SetPoint("TOPRIGHT"); bx.edges[4]:SetPoint("BOTTOMRIGHT"); bx.edges[4]:SetWidth(2)
      o.boxes[i] = bx
    end
    bx:ClearAllPoints()
    bx:SetPoint("TOPLEFT", o, "TOPLEFT", r[1] - 2, -(r[2] - 2))
    bx:SetSize(math.max(4, r[3] - r[1] + 4), math.max(4, r[4] - r[2] + 4))
    bx:Show()
    -- numbered badge on the control's top-left corner, moved right until it is free and inside the page
    local bd = o.badges[i]
    if not bd then
      bd = CreateFrame("Frame", nil, o)
      bd:SetSize(20, 20)
      bd.bg = bd:CreateTexture(nil, "ARTWORK")
      bd.bg:SetAllPoints()
      bd.bg:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
      bd.bg:SetVertexColor(1, 0.82, 0, 1)
      bd.n = W.text(bd, "GameFontNormal", 12, { 0.1, 0.06, 0 }, "CENTER")
      bd.n:SetPoint("CENTER", 0, 0)
      bd.n.wbxCopy = "data"
      o.badges[i] = bd
    end
    local x, y = math.max(0, math.min(W0 - 20, r[1] - 8)), math.max(0, math.min(H0 - 20, r[2] - 8))
    local me = { x, y, x + 20, y + 20 }
    local tries = 0
    while tries < 40 do
      local clash = false
      for _, t in ipairs(taken) do if hit(me, t) then clash = true end end
      if not clash then break end
      x = x + 22
      if x > W0 - 20 then x, y = 0, y + 22 end
      me = { x, y, x + 20, y + 20 }
      tries = tries + 1
    end
    taken[#taken + 1] = me
    bd:ClearAllPoints()
    bd:SetPoint("TOPLEFT", o, "TOPLEFT", x, -y)
    bd.n:SetText(tostring(i))
    bd:Show()
  end
  for i = #list + 1, #o.boxes do o.boxes[i]:Hide(); o.badges[i]:Hide() end
  -- the numbered list, in the corner that covers the fewest callouts
  local lg = o.legend
  for i, c in ipairs(list) do
    local l = lg.lines[i]
    if not l then
      l = W.text(lg, "GameFontHighlightSmall", nil, W.TEXT)
      l:SetPoint("TOPLEFT", 10, -28 - (i - 1) * 16)
      l:SetWidth(230)
      if l.SetMaxLines then l:SetMaxLines(1) end
      l.wbxCopy = "hint"
      lg.lines[i] = l
    end
    l:SetText("|cffffd100" .. i .. "|r  " .. c[2])
    l:Show()
  end
  for i = #list + 1, #lg.lines do lg.lines[i]:Hide() end
  local squad = key:sub(1, 6) == "squad:"
  o.guideBtn:SetShown(squad)
  local h = 28 + #list * 16 + (squad and 34 or 8)
  lg:SetHeight(h)
  local best, bestScore
  for _, pos in ipairs({ { "BOTTOMRIGHT", -10, 10 }, { "TOPRIGHT", -10, -10 }, { "BOTTOMLEFT", 10, 10 }, { "TOPLEFT", 10, -10 } }) do
    local x0 = pos[1]:find("LEFT") and 10 or (W0 - 10 - 250)
    local y0 = pos[1]:find("TOP") and 10 or (H0 - 10 - h)
    local rr = { x0, y0, x0 + 250, y0 + h }
    local score = 0
    for _, t in ipairs(taken) do if hit(rr, t) then score = score + 100 end end
    for _, c in ipairs(list) do local r = rectIn(o, c[1]); if r and hit(rr, r) then score = score + 1 end end
    if not bestScore or score < bestScore then best, bestScore = pos, score end
  end
  lg:ClearAllPoints()
  lg:SetPoint(best[1], o, best[1], best[2], best[3])
  o:Show()
  if o.EnableKeyboard then o:EnableKeyboard(true) end
end
function Help.Hide()
  local _, hide = Help.blizzard()
  if Help.plate and hide then pcall(hide); Help.plate = nil end
  if Help.overlay then
    if Help.overlay.EnableKeyboard then Help.overlay:EnableKeyboard(false) end
    Help.overlay:Hide()
  end
end
function Help.IsShown() return (Help.overlay and Help.overlay:IsShown()) or Help.plate ~= nil end
function Help.Toggle() if Help.IsShown() then Help.Hide() else Help.Show() end end

-- ------------------------------------------------------------------ the squad guide (3 steps)
local SP = function() return ns.SquadPages end
Help.SQUAD_STEPS = {
  { "Add your characters", "Your party, or characters by name.", function()
      local SPm = SP()
      if #SPm.partyMissing(ns.State.activeSquad(Core().db)) > 0 then
        return { "Add party", "Adds everyone in your party who is not in the squad yet.", function() SPm.addParty() end }
      end
      return { "Add name", "Shows the Add character line: type a name, pick a class, Add.", function()
        local f = UI.panels.squad.frames.main
        f.forceList = true; SPm.select(UI.panels.squad, "main"); Help.HideSquadGuide(); f.add.name:SetFocus() end }
    end },
  { "Pick the leader", "Click the crown next to the leader.", function()
      return { "I lead", "Makes this character the leader. Or close the guide and click another character's crown.", function()
        local _, me = Core().me(); SP().makeLeader(me) end }
    end },
  { "Send to your other characters", "Each one: Review, Import, then Place all.", function()
      return { "Send squad", "Offers this squad to your party. Nothing changes there until you click Review and Import on that client.",
        function() if ns.Sync then ns.Sync.sendSquad(ns.State.activeSquad(Core().db)) end end }
    end },
}

local function guideFrame()
  if Help.guide then return Help.guide end
  local p = UI.panels.squad
  local g = W.box(p, 0.11, 0.085, 0.05, 0.99)
  g:SetPoint("TOPLEFT", 60, -40)
  g:SetPoint("BOTTOMRIGHT", -60, 40)
  g:SetFrameLevel((p:GetFrameLevel() or 1) + 40)
  g:EnableMouse(true)
  g.wbxModal = true
  g.title = W.text(g, "GameFontNormalLarge", 16, W.GOLD)
  g.title:SetPoint("TOPLEFT", 20, -18)
  g.title:SetText("Squad guide")
  g.title.wbxCopy = "label"
  g.close = W.button(g, "Close", 70, 22, function() Help.HideSquadGuide() end, "Closes the guide. Open it again with the ? on the Squad page or the minimap menu.")
  g.close:SetPoint("TOPRIGHT", -12, -14)
  g.dots = {}
  for i = 1, #Help.SQUAD_STEPS do
    local d = g:CreateTexture(nil, "ARTWORK")
    d:SetSize(10, 10)
    d:SetPoint("TOPLEFT", 20 + (i - 1) * 16, -46)
    d:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
    g.dots[i] = d
  end
  g.step = W.text(g, "GameFontNormal", nil, W.GOLD)
  g.step:SetPoint("TOPLEFT", 20, -70)
  g.step.wbxCopy = "hint"
  g.text = W.text(g, "GameFontHighlight", nil, W.TEXT)
  g.text:SetPoint("TOPLEFT", 20, -94)
  g.text:SetPoint("TOPRIGHT", -20, -94)
  g.text.wbxCopy = "guide"
  g.act = W.button(g, "Add party", 110, 26, function() if g.fn then g.fn(); UI.Refresh() end end)
  g.act:SetPoint("TOPLEFT", 20, -130)
  W.tip(g.act, function() return g.act:GetText() end, function() return g.actTip end)
  g.back = W.button(g, "Back", 70, 24, function() Help.squadStep(g.i - 1) end, "Goes back one step.")
  g.back:SetPoint("BOTTOMLEFT", 14, 12)
  g.next = W.button(g, "Next", 80, 24, function()
    if g.i >= #Help.SQUAD_STEPS then Help.HideSquadGuide() else Help.squadStep(g.i + 1) end
  end, "Goes to the next step.")
  g.next:SetPoint("BOTTOMRIGHT", -14, 12)
  g:Hide()
  Help.guide = g
  return g
end

function Help.squadStep(i)
  local g = guideFrame()
  g.i = math.max(1, math.min(#Help.SQUAD_STEPS, i or 1))
  local s = Help.SQUAD_STEPS[g.i]
  g.step:SetText(g.i .. ". " .. s[1])
  g.text:SetText(s[2])
  local b = s[3]()
  W.setLabel(g.act, b[1]); g.actTip, g.fn = b[2], b[3]
  g.act:SetEnabled(not ns.Compat.inCombat())
  for k, d in ipairs(g.dots) do
    if k == g.i then d:SetVertexColor(1, 0.82, 0, 1) elseif k < g.i then d:SetVertexColor(0.56, 0.75, 0.42, 1) else d:SetVertexColor(0.35, 0.3, 0.22, 1) end
  end
  g.back:SetShown(g.i > 1)
  W.setLabel(g.next, g.i >= #Help.SQUAD_STEPS and "Done" or "Next")
  local st = settings()
  st.squadGuideStep = g.i
end
function Help.ShowSquadGuide()
  UI.Open("squad")
  local g = guideFrame()
  g:Show()
  Help.squadStep(1)
end
function Help.HideSquadGuide() if Help.guide then Help.guide:Hide() end end

-- offered once when a second character joins the party (a card with Open / Ignore; nothing opens by itself)
local ev = CreateFrame("Frame")
pcall(ev.RegisterEvent, ev, "GROUP_ROSTER_UPDATE")
ev:SetScript("OnEvent", function() Help.checkOffer() end)
function Help.checkOffer()
  local db = Core().db
  if not db or not ns.Sync then return false end
  local n = _G.GetNumGroupMembers and _G.GetNumGroupMembers() or 0
  if n < 2 or db.settings.squadGuideOffered then return false end
  db.settings.squadGuideOffered = true
  ns.Sync.offer({ kind = "guide", from = "", text = "Playing together? Set up your squad." })
  return true
end

return Help
