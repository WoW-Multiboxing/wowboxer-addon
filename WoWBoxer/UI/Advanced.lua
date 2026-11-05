--[[ WoWBoxer – Advanced mode UI (docs/advanced-mode.md): the Standard | Advanced switch with its confirm window, the
  Targeting window for one key (target list, options, live preview), the macro text editor, and Reset to default.
  Advanced mode only shows more controls; it never changes a key by itself. Every change is WoWBoxer data until the
  player presses Update / Place (out of combat), and every result goes through Rules.validateMacro. ]]
local _, ns = ...
local UI, W = ns.UI, ns.Widgets
local A = {}
ns.Advanced = A

local function Core() return ns.Core end
local function O() return ns.Override end

-- ------------------------------------------------------------------ the header switch + confirm
function A.on() return Core().advanced() end
local TH = ns.Theme
--- A dialog in the window style (docs/ui-redesign.md §3): panel fill, gold line border.
local function dialogLook(f)
  if W.themed() then local sk = TH.paint(f, "panel", "line"); sk.alpha = 1; TH.paint(f, "panel") end -- opaque
  return f
end
A.dialogLook = dialogLook
local function modal(parent, w, h)
  local f = dialogLook(W.box(parent, 0.11, 0.085, 0.05, 0.99))
  f:SetSize(w, h)
  f:SetPoint("CENTER", 0, 0)
  f:SetFrameLevel((parent:GetFrameLevel() or 1) + 60)
  f:EnableMouse(true)
  f.wbxModal = true
  f:Hide()
  return f
end

function A.attachSwitch(f)
  -- header, right side: [Standard | Advanced]  Reset  ?  x (docs/ui-redesign.md §3)
  local hdr = UI.header or f
  local seg = W.segmented(hdr, {
    { false, "Standard", "Standard mode: WoWBoxer's macros as they are. Your own changes stay active." },
    { true, "Advanced", "Advanced mode: change who each macro casts on and edit macro text. Asks first." },
  }, function() return A.on() end, function(v) if v then if not A.on() then A.confirm() end else A.leaveAdvanced() end end)
  UI.modeSeg = seg
  UI.modeStd, UI.modeAdv = seg.buttons[1], seg.buttons[2]
  -- Reset to default on every page (docs/feedback-2026-10-30-night.md §7)
  local rs = W.button(hdr, "Reset", 56, 24, function() A.openReset() end, "Reset to default: back to how this character was before WoWBoxer (asks twice).")
  UI.resetBtn = rs
  if UI.helpBtn then rs:SetPoint("RIGHT", UI.helpBtn, "LEFT", -10, 0) else rs:SetPoint("RIGHT", hdr, "RIGHT", -86, 0) end
  seg:SetPoint("RIGHT", rs, "LEFT", -10, 0)
  -- the confirm window (§1)
  local c = modal(f, 420, W.themed() and 226 or 200)
  c.title = W.text(c, "GameFontNormalLarge", 15, W.GOLD)
  c.title:SetPoint("TOPLEFT", 16, -14)
  c.title:SetText("Turn on Advanced mode?")
  c.title.wbxCopy = "hint"
  c.text = W.text(c, "GameFontHighlightSmall", nil, W.TEXT)
  c.text:SetPoint("TOPLEFT", 16, -40)
  c.text:SetPoint("TOPRIGHT", -16, -40)
  c.text:SetText("Advanced mode lets you change who each macro casts on and edit your macros' macro text.\n" ..
    "It is meant for experienced multiboxers: a wrong target can make a macro do nothing, or heal or hit the wrong unit.\n" ..
    "You can undo any change with \"Back to WoWBoxer's version\" on each macro, or Reset to default in Setup.")
  c.text.wbxCopy = "guide"
  c.tick = W.check(c, "I understand", function() A.refreshConfirm() end)
  if W.themed() then
    -- the whole row is the tick: a card that lifts when ticked (§2, board "Advanced confirm – off vs on")
    c.tickRow = CreateFrame("Frame", nil, c)
    c.tickRow:SetPoint("BOTTOMLEFT", 12, 44)
    c.tickRow:SetPoint("BOTTOMRIGHT", -12, 44)
    c.tickRow:SetHeight(32)
    c.tick:SetParent(c.tickRow)
    c.tick:SetPoint("LEFT", c.tickRow, "LEFT", 8, 0)
    W.role(c.tick.label, "bold", 12)
    c.tick.label:SetTextColor(TH.rgb("parchment"))
    W.tickRow(c.tick, c.tickRow)
  else
    c.tick:SetPoint("BOTTOMLEFT", 12, 44)
  end
  c.go = W.button(c, "Turn on Advanced", 130, 24, function() if c.tick:GetChecked() then c:Hide(); A.setMode(true) end end,
    "Shows the advanced controls. Nothing changes in your macros until you change one.")
  c.go:SetPoint("BOTTOMRIGHT", -12, 12)
  c.go.wbxBig = true
  W.primary(c.go) -- disabled: grey panel-3 with a grey edge; ticked: the red primary
  c.cancel = W.button(c, "Cancel", 70, 24, function() c:Hide() end, "Stays in Standard mode.")
  c.cancel:SetPoint("RIGHT", c.go, "LEFT", -6, 0)
  A.confirmFrame = c
  W.dialog(c, "WoWBoxerAdvancedConfirm")
end
function A.confirm()
  local c = A.confirmFrame
  c.tick:SetChecked(false)
  c:Show()
  A.refreshConfirm()
end
function A.refreshConfirm() local c = A.confirmFrame; c.go:SetEnabled(c.tick:GetChecked() and true or false) end
function A.setMode(on)
  W.closeMenus() -- a menu built for the other mode never stays open (§3)
  Core().db.settings.advanced = on and true or nil
  Core().log("info", on and "advanced mode on" or "standard mode")
  Core().changed()
end
--- Advanced → Standard (§2): never leave a half-advanced editor. An own macro stays open on its Spells tab (Standard
--- can edit it); any other macro closes. Unsaved targeting first asks: keep editing, or discard and switch.
function A.leaveAdvanced()
  local f = A.ef
  if not (f and f:IsShown()) then A.setMode(false); return end
  local function go()
    f.touched = false
    if f.own then A.setMode(false); A.showSection("spells") else f:Hide(); A.setMode(false) end
  end
  if not f.touched then go(); return end
  UI.Popup("Unsaved changes in the Macro editor.", {
    { "Keep editing", function() end, "Stays in Advanced mode; the Macro editor stays open with your changes." },
    { "Discard", go, "Drops the unsaved targeting changes and switches to Standard mode." } })
end
function A.refreshSwitch()
  if UI.modeSeg then UI.modeSeg.Refresh() end
end

-- ------------------------------------------------------------------ the Macro editor (docs/feedback-2026-10-29-late.md §3)
-- One window for every macro: 1 Spells · 2 Targeting (drag and drop) · 3 Options · 4 Preview. The same on every client –
-- leader, followers on party1–4, focus users: nothing here checks the role, only what this client can see.
local function current(name)
  local ctx = Core().compute()
  for _, d in ipairs(ctx and ctx.desired or {}) do if d.name == name then return d end end
end
A.ROW_H = 24
local ICON = { mouseover = "Ability_EyeOfTheOwl", target = "Ability_Hunter_SniperShot", leadertarget = "Ability_Hunter_SniperShot",
  focus = "Spell_Holy_MindVision", targettarget = "Ability_Hunter_SniperShot", mypet = "Ability_Hunter_BeastTaming", unit = "INV_Misc_GroupLooking" }
--- The picture of an available target: class icon for members, a paw for pets, an eye for mouseover, a crosshair for
--- targets, the portrait for myself.
function A.iconOf(tex, t, ctx)
  if t.who == "player" then
    if _G.SetPortraitTexture then pcall(_G.SetPortraitTexture, tex, "player"); return end
    W.setIcon(tex, "INV_Misc_Head_Human_01"); return
  end
  if t.pet or (t.who == "unit" and t.unit:find("pet", 1, true)) then W.setIcon(tex, ICON.mypet); return end
  if t.who == "member" or t.who == "leader" then
    local m
    for _, x in ipairs(ctx.squad and ctx.squad.members or {}) do
      if (t.who == "member" and ns.Compat.sameName(x.name, t.name)) or (t.who == "leader" and x.leader) then m = x end
    end
    if m and ns.SquadPages then ns.SquadPages.setClassIcon(tex, m.cls); return end
  end
  W.setIcon(tex, ICON[t.who] or "INV_Misc_QuestionMark")
end

--- One plain line per row: "Bo's pet – the pet of party1 (party1pet)", "Anna – party2", "Your mouseover";
--- a unit missing here: "Bo is not in your party – skipped".
function A.rowText(t, ctx)
  local u = O().unitFor(t, ctx)
  local w = t.who
  if not u then
    local who = (w == "member" and t.name) or ((w == "leader" or w == "leadertarget") and "The leader") or O().label(t, ctx)
    return who .. " is not in your party – skipped", false
  end
  if w == "mouseover" then return "Your mouseover", true end
  if w == "target" then return "Your target", true end
  if w == "player" then return "Yourself – player", true end
  if w == "mypet" then return "Your pet – pet", true end
  if w == "focus" then return "Your focus – focus", true end
  if w == "targettarget" then return "Target of target – targettarget", true end
  if w == "leadertarget" then return "The leader's target – " .. u, true end
  if w == "unit" then return u, true end
  if t.pet then
    local base = u:gsub("pet$", "")
    return O().label(t, ctx) .. " – the pet of " .. (base == "" and "you" or base) .. " (" .. u .. ")", true
  end
  return O().label(t, ctx) .. " – " .. u, true
end

local function editorFrame(parent)
  local f = A.ef
  if f then
    if f:GetParent() ~= parent then f:SetParent(parent); f:ClearAllPoints(); f:SetAllPoints(parent); f:SetFrameLevel((parent:GetFrameLevel() or 1) + 60) end
    return f
  end
  f = dialogLook(W.box(parent, 0.11, 0.085, 0.05, 0.99))
  f:SetAllPoints(parent)
  f:SetFrameLevel((parent:GetFrameLevel() or 1) + 60)
  f:EnableMouse(true)
  f.wbxModal = true
  f:Hide()
  A.ef = f
  local themed = W.themed()
  f.parts = {} -- sections 2–4 (shown on the Targeting tab); section 1 for own macros is the spells box
  local function part(x) f.parts[#f.parts + 1] = x; return x end
  local function head(text, x, y)
    local h = W.text(f, "GameFontNormalSmall", 10, themed and { TH.rgb("gold") } or W.GOLD)
    h:SetPoint("TOPLEFT", x, y)
    h:SetText(text)
    h.wbxCopy = "hint"
    return part(h)
  end
  f.title = W.text(f, themed and "GameFontNormalLarge" or "GameFontNormal", themed and 14 or nil, W.GOLD)
  f.title:SetPoint("TOPLEFT", 10, -7)
  f.title.wbxCopy = "data"
  -- 1 Spells
  head("1 Spells", 10, -28)
  f.spells = W.line(f, "GameFontHighlightSmall", nil, W.TEXT)
  f.spells:SetPoint("TOPLEFT", 70, -28)
  f.spells:SetWidth(480)
  f.spells.wbxCopy = "data"
  part(f.spells)
  f.editSpells = W.button(f, "Edit spells", 84, 20, function() A.showSection("spells") end, "Steps, filler and kind of this own macro.")
  f.editSpells:SetPoint("TOPRIGHT", -10, -24)
  part(f.editSpells)
  -- 2 Targeting: Available targets (left) → This macro tries, in order (right)
  head("2 Targeting – drag a target into the list", 10, -50)
  f.avail = part(CreateFrame("Frame", nil, f))
  f.avail:SetPoint("TOPLEFT", 10, -66)
  f.avail:SetSize(268, 8 * A.ROW_H)
  f.availBg = f.avail:CreateTexture(nil, "BACKGROUND")
  f.availBg:SetAllPoints()
  f.availBg:SetColorTexture(0, 0, 0, themed and 0 or 0.25)
  if themed then TH.box(f.avail, "night2", "lineSoft", 6) end
  -- every target, grouped (Common · Squad · Party · Raid), scrolling with the mouse wheel and the flat bar
  f.availSF, f.availContent = W.scroll(f.avail, 268 - 8 - W.SCROLLBAR + 8, 8 * A.ROW_H - 8)
  f.availSF:SetPoint("TOPLEFT", 4, -4)
  f.availW = 268 - 8 - W.SCROLLBAR + 8
  f.heads = {}
  f.tiles = {}
  f.list = part(CreateFrame("Frame", nil, f))
  f.list:SetPoint("TOPLEFT", 290, -66)
  f.list:SetPoint("TOPRIGHT", -10, -66)
  f.list:SetHeight(8 * A.ROW_H)
  f.listBg = f.list:CreateTexture(nil, "BACKGROUND")
  f.listBg:SetAllPoints()
  f.listBg:SetColorTexture(0.2, 0.15, 0.05, themed and 0 or 0.35)
  if themed then TH.box(f.list, "night2", "line", 6) end
  f.listHead = W.text(f, "GameFontNormalSmall", nil, W.GOLD)
  f.listHead:SetPoint("BOTTOMLEFT", f.list, "TOPLEFT", 0, 3)
  f.listHead:SetText("This macro tries, in order")
  f.listHead.wbxCopy = "hint"
  part(f.listHead)
  f.empty = W.text(f.list, "GameFontHighlightSmall", nil, W.MUTED, "CENTER")
  f.empty:SetPoint("CENTER", 0, 0)
  f.empty:SetText("Drag targets here")
  f.empty.wbxCopy = "hint"
  f.rows = {}
  for i = 1, O().MAX_TARGETS do
    local r = CreateFrame("Button", nil, f.list)
    r:SetSize(10, A.ROW_H - 2)
    r:SetPoint("TOPLEFT", 0, -(i - 1) * A.ROW_H)
    r:SetPoint("TOPRIGHT", f.list, "TOPRIGHT", 0, -(i - 1) * A.ROW_H)
    r:RegisterForDrag("LeftButton")
    r.bg = r:CreateTexture(nil, "BACKGROUND")
    r.bg:SetAllPoints()
    r.bg:SetColorTexture(0, 0, 0, themed and 0 or (i % 2 == 0 and 0.15 or 0.3))
    if themed then
      -- a numbered row card (the order the macro tries)
      TH.box(r, "panel3", "line", 4)
      r.num = W.text(r, "GameFontNormalLarge", 11, { TH.rgb("gold") }, "CENTER")
      r.num:SetPoint("LEFT", 2, 0)
      r.num:SetWidth(14)
      r.num:SetText(tostring(i))
      r.num.wbxCopy = "data"
    end
    r.icon = W.icon(r, 18)
    r.icon:SetPoint("LEFT", themed and 18 or 3, 0)
    r.name = W.line(r, "GameFontHighlightSmall", nil, W.TEXT)
    r.name:SetPoint("LEFT", themed and 40 or 25, 0)
    r.name:SetWidth(themed and 155 or 170)
    r.name.wbxCopy = "data"
    r.aim = W.button(r, "Friendly", 62, 20, function()
      local t = f.targets[i]; if not t then return end
      if t.help == true then t.help = false elseif t.help == false then t.help = nil else t.help = true end
      f.touched = true
      A.refreshEditor()
    end, "Friendly: only friends. Enemy: only enemies. Either: both.")
    r.aim:SetPoint("LEFT", 198, 0)
    r.dead = W.frame("CheckButton", r, "UICheckButtonTemplate")
    r.dead:SetSize(20, 20)
    r.dead:SetPoint("LEFT", r.aim, "RIGHT", 2, 0)
    r.dead:SetScript("OnClick", function(self) local t = f.targets[i]; if t then f.touched = true; t.nodead = self:GetChecked() and true or false; A.refreshEditor() end end)
    W.tip(r.dead, "Skip if dead", "Ticked: skips this target when it is dead (untick for resurrection).")
    local function arrow(tex, d, tipText)
      local b = CreateFrame("Button", nil, r)
      b:SetSize(16, 16)
      b:SetNormalTexture(tex)
      b:SetScript("OnClick", function() A.moveRow(i, i + d) end)
      W.tip(b, tipText, "Without dragging: moves this target one place.")
      return b
    end
    r.up = arrow("Interface\\ChatFrame\\UI-ChatIcon-ScrollUp-Up", -1, "Up")
    r.down = arrow("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up", 1, "Down")
    r.remove = W.button(r, "x", 22, 20, function() f.touched = true; table.remove(f.targets, i); A.refreshEditor() end, { "Remove", "Takes this target out (or drag it out of the list)." })
    r.remove:SetPoint("RIGHT", -2, 0)
    r.down:SetPoint("RIGHT", r.remove, "LEFT", -2, 0)
    r.up:SetPoint("RIGHT", r.down, "LEFT", -1, 0)
    r:SetScript("OnDragStart", function() A.drag = { kind = "row", index = i } end)
    r:SetScript("OnDragStop", function() A.drop() end)
    W.tooltip(r, function(GT)
      local t = f.targets[i]
      if not t then return end
      GT:AddLine((A.rowText(t, f.ctx)), 1, 0.82, 0)
      GT:AddLine(O().cond(t, f.ctx) or "Left out of the macro while it is missing here", 0.56, 0.85, 0.45)
      GT:AddLine((O().meaning(t, f.ctx):gsub("^Casts on [^w]+ when", "when")) .. ".", 1, 1, 1, true)
      GT:AddLine("Drag to reorder, drag out to remove", 0.66, 0.6, 0.49)
    end)
    f.rows[i] = r
  end
  -- 3 Options
  local oy = -66 - 8 * A.ROW_H - 10
  head("3 Options", 10, oy)
  f.mod = W.dropdown(f, { width = 130,
    values = function() return { { "none", "No modifier" }, { "shift", "Shift = myself" }, { "ctrl", "Ctrl = myself" }, { "alt", "Alt = myself" } } end,
    get = function() return f.opts.mod or "none" end, set = function(v) f.touched = true; f.opts.mod = v ~= "none" and v or nil; A.refreshEditor() end })
  f.mod:SetPoint("TOPLEFT", 80, oy + 4)
  part(f.mod)
  W.ddTip(f.mod, "Modifier", "Hold Shift (Ctrl, Alt) while you press the macro's keybind to cast it on yourself.")
  local function tri(width, key, labels, title, tip)
    local d = W.dropdown(f, { width = width, values = function() return { { "keep", labels[1] }, { "on", labels[2] }, { "off", labels[3] } } end,
      get = function() local v = f.opts[key]; return v == true and "on" or v == false and "off" or "keep" end,
      set = function(v)
        if v == "on" then f.opts[key] = true elseif v == "off" then f.opts[key] = false else f.opts[key] = nil end
        f.touched = true
        A.refreshEditor()
      end })
    W.ddTip(d, title, tip)
    return d
  end
  f.start = tri(130, "startattack", { "Attack: as built", "Auto attack on", "Auto attack off" }, "Auto attack", "Adds or removes /startattack (enemy macros).")
  f.start:SetPoint("LEFT", f.mod, "RIGHT", 8, 0)
  part(f.start)
  f.pet = tri(120, "petattack", { "Pet: as built", "Pet attacks", "No pet line" }, "Pet", "Adds or removes /petattack (enemy macros).")
  f.pet:SetPoint("LEFT", f.start, "RIGHT", 8, 0)
  part(f.pet)
  f.reset = W.dropdown(f, { width = 130,
    values = function() local v = { { "keep", "Reset: as built" } }; for _, r in ipairs(O().RESETS) do v[#v + 1] = { r, "reset=" .. r } end return v end,
    get = function() return f.opts.reset or "keep" end, set = function(v) f.touched = true; f.opts.reset = v ~= "keep" and v or nil; A.refreshEditor() end })
  f.reset:SetPoint("LEFT", f.pet, "RIGHT", 8, 0)
  part(f.reset)
  W.ddTip(f.reset, "Reset", "When a sequence macro starts over: after combat, on a new target, after some seconds.")
  -- 4 Preview
  local py = oy - 30
  head("4 Preview", 10, py)
  f.preview = W.text(f, "GameFontHighlightSmall", 9, themed and W.TEXT or { 0.6, 0.66, 0.52 })
  W.gameFont(f.preview)
  f.preview:SetPoint("TOPLEFT", themed and 86 or 80, py - (themed and 4 or 0))
  f.preview:SetPoint("TOPRIGHT", themed and -16 or -10, py - (themed and 4 or 0))
  f.preview:SetPoint("BOTTOM", f, "BOTTOM", 0, themed and 58 or 52)
  if themed then
    -- the macro text in a tooltip-style box (§3)
    f.previewBox = CreateFrame("Frame", nil, f)
    f.previewBox:SetPoint("TOPLEFT", f.preview, "TOPLEFT", -6, 5)
    f.previewBox:SetPoint("BOTTOMRIGHT", f.preview, "BOTTOMRIGHT", 6, -5)
    TH.box(f.previewBox, "ttBg", "ttEdge", 6)
    f.previewBox:SetFrameLevel(f:GetFrameLevel() or 1)
    part(f.previewBox)
  end
  f.preview:SetJustifyV("TOP")
  if f.preview.SetNonSpaceWrap then f.preview:SetNonSpaceWrap(false) end -- W.wrapMacro breaks at , ] ; or spaces
  f.preview.wbxCopy = "data"
  part(f.preview)
  f.info = W.line(f, "GameFontHighlightSmall", nil, W.MUTED)
  f.info:SetPoint("BOTTOMLEFT", 10, 36)
  f.info:SetPoint("BOTTOMRIGHT", -10, 36)
  f.info.wbxCopy = "data"
  f.save = W.button(f, "Save", 70, 24, function() A.saveEditor() end, "Saves your targeting and options. Press Update macros afterwards to write the macro.")
  W.primary(f.save)
  f.save:SetPoint("BOTTOMRIGHT", -10, 8)
  f.cancel = W.button(f, "Cancel", 70, 24, function() f:Hide() end, "Closes this. Nothing changes.")
  f.cancel:SetPoint("RIGHT", f.save, "LEFT", -6, 0)
  f.back = W.button(f, "WoWBoxer's version", 140, 24, function() Core().setOverride(f.name, nil); f:Hide() end,
    "Back to WoWBoxer's version: removes your targeting (and text) for this macro.")
  f.back:SetPoint("BOTTOMLEFT", 10, 8)
  W.setStyle(f.back, "ghost")
  f.text = W.button(f, "Edit text", 80, 24, function() local n, l = f.name, f.label; f:Hide(); A.openText(parent, n, l) end,
    "The last resort: write the macro text yourself (checked live). The macro is then frozen on level-ups.")
  f.text:SetPoint("LEFT", f.back, "RIGHT", 6, 0)
  -- the section tabs: 1 Spells (own macros: steps, filler, kind, presets) · 2–4 Targeting, Options, Preview
  f.tabTarget = W.button(f, "Targeting", 84, 20, function() A.showSection("target") end, "Targeting (drag and drop), options and the preview.")
  f.tabTarget:SetPoint("TOPRIGHT", -10, -4)
  f.tabSpells = W.button(f, "Spells", 64, 20, function() A.showSection("spells") end, "The spells of this macro: single spell, sequence or priority.")
  f.tabSpells:SetPoint("RIGHT", f.tabTarget, "LEFT", -4, 0)
  if themed then
    -- tabs with a gold underline (§3)
    for _, b in ipairs({ f.tabSpells, f.tabTarget }) do
      W.setStyle(b, "segment")
      b.line = TH.fill(b, "gold", "ARTWORK")
      b.line:SetPoint("BOTTOMLEFT", 6, 0)
      b.line:SetPoint("BOTTOMRIGHT", -6, 0)
      b.line:SetHeight(2)
    end
  end
  -- Targeting greyed in Standard (own macros): the reason next to the tabs, like the greyed menu item
  f.tabNote = W.text(f, "GameFontHighlightSmall", 10, W.MUTED, "RIGHT")
  f.tabNote:SetPoint("RIGHT", f.tabSpells, "LEFT", -8, 0)
  f.tabNote:SetText("Advanced mode")
  f.tabNote.wbxCopy = "status"
  f.tabNote:Hide()
  W.tip(f.tabTarget, "Targeting", function()
    return (A.on() or not f.own) and "Who the macro casts on (drag and drop), options and the preview."
      or "Advanced mode: turn on Advanced in the window header to choose who this macro casts on. In Standard, the target presets are on the Spells tab."
  end)
  f.spellsBox = CreateFrame("Frame", nil, f)
  f.spellsBox:SetPoint("TOPLEFT", 0, -26)
  f.spellsBox:SetPoint("BOTTOMRIGHT", 0, 34)
  f.spellsBox:Hide()
  -- Spells of a recommended macro: what it casts (WoWBoxer builds it for your level), read-only
  f.spellsInfo = CreateFrame("Frame", nil, f)
  f.spellsInfo:SetPoint("TOPLEFT", 0, -26)
  f.spellsInfo:SetPoint("BOTTOMRIGHT", 0, 34)
  f.spellsInfo:Hide()
  f.spellsInfo.head = W.text(f.spellsInfo, "GameFontNormalSmall", 10, themed and { TH.rgb("gold") } or W.GOLD)
  f.spellsInfo.head:SetPoint("TOPLEFT", 10, -6)
  f.spellsInfo.head:SetText("What this macro casts")
  f.spellsInfo.head.wbxCopy = "label"
  f.spellsInfo.text = W.text(f.spellsInfo, "GameFontHighlight", 12, W.PARCHMENT)
  f.spellsInfo.text:SetPoint("TOPLEFT", 10, -24)
  f.spellsInfo.text:SetPoint("TOPRIGHT", -10, -24)
  f.spellsInfo.text.wbxCopy = "data"
  f.spellsInfo.hint = W.text(f.spellsInfo, "GameFontHighlightSmall", 11, W.MUTED)
  f.spellsInfo.hint:SetPoint("TOPLEFT", f.spellsInfo.text, "BOTTOMLEFT", 0, -10)
  f.spellsInfo.hint:SetPoint("RIGHT", -10, 0)
  f.spellsInfo.hint:SetText("WoWBoxer picks these spells for your level and updates them when you level up. Choose who it casts on under Targeting.")
  f.spellsInfo.hint.wbxCopy = "guide"
  f:SetScript("OnHide", function() local K = ns.KeyEditor.frame; if K then K:Hide(); K.draft = nil end end)
  return f
end

--- Show one section of the editor: "spells" (own macros) or "target" (targeting, options, preview).
--- One tab bar for every macro and entry point: Spells · Targeting. Switching keeps the unsaved draft (the Spells
--- draft and the targets live on while their section is hidden); Save and Cancel apply to both.
--- Targeting needs Advanced mode for own macros (Standard: the presets on Spells); it is shown greyed then.
function A.canTarget(f) return A.on() or not f.own end
function A.showSection(which)
  local f = A.ef
  if not f then return end
  if which == "target" and not A.canTarget(f) then which = "spells" end
  f.section = which
  local spells = which == "spells"
  f.spellsBox:SetShown(spells and f.own ~= nil)
  f.spellsInfo:SetShown(spells and f.own == nil)
  for _, x in ipairs(f.parts) do x:SetShown(not spells) end
  f.editSpells:Hide() -- the Spells tab does this now (one owner per control)
  f.tabSpells:Show(); f.tabTarget:Show()
  W.setSelected(f.tabSpells, spells); W.setSelected(f.tabTarget, not spells)
  if f.tabSpells.line then f.tabSpells.line:SetShown(spells); f.tabTarget.line:SetShown(not spells) end
  f.tabTarget:SetEnabled(A.canTarget(f))
  f.tabNote:SetShown(not A.canTarget(f))
  A.refreshEditor()
end

--- An available target tile (left side): drag it into the list, or click it to add it at the end.
local function tile(f, i)
  local t = f.tiles[i]
  if t then return t end
  t = CreateFrame("Button", nil, f.availContent)
  t:SetSize(132, A.ROW_H - 2)
  t:RegisterForDrag("LeftButton")
  if W.themed() then
    TH.box(t, "panel2", "lineSoft", 4)
    W.onHover(t, function(self) TH.paint(self, "panel3", "line") end, function(self) TH.paint(self, "panel2", "lineSoft") end)
  else
    local hl = t:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 0.82, 0, 0.15)
  end
  t.icon = W.icon(t, 18)
  t.icon:SetPoint("LEFT", 2, 0)
  t.name = W.line(t, "GameFontHighlightSmall", nil, W.TEXT)
  t.name:SetPoint("LEFT", 23, 0)
  t.name:SetPoint("RIGHT", -2, 0)
  t.name.wbxCopy = "data"
  t:SetScript("OnDragStart", function() if t.target then A.drag = { kind = "new", target = t.target } end end)
  t:SetScript("OnDragStop", function() A.drop() end)
  t:SetScript("OnClick", function() if t.target then A.insert(t.target, #f.targets + 1) end end)
  W.tooltip(t, function(GT)
    if not t.target then return end
    GT:AddLine(t.full or "", 1, 0.82, 0) -- the whole label, also when the tile cuts it
    local about = O().about(t.target, f.ctx)
    if about ~= "" then GT:AddLine(O().label(t.target, f.ctx) .. " – " .. about, 1, 1, 1, true) end
    GT:AddLine(O().cond(t.target, f.ctx) or "Not in your party here", 0.56, 0.85, 0.45)
    GT:AddLine("Drag into the list on the right (or click to add it last)", 0.66, 0.6, 0.49, true)
  end)
  f.tiles[i] = t
  return t
end

--- A small group heading in the available-targets list (Raid: a click folds / unfolds it).
local function heading(f, i)
  local h = f.heads[i]
  if h then return h end
  h = CreateFrame("Button", nil, f.availContent)
  h:SetHeight(16)
  h.text = W.text(h, "GameFontNormalSmall", 10, W.themed() and { TH.rgb("gold") } or W.GOLD)
  h.text:SetPoint("LEFT", 2, 0)
  h.text.wbxCopy = "label"
  h:SetScript("OnClick", function(self) if self.key == "raid" then f.raidOpen = not f.raidOpen; A.refreshEditor() end end)
  W.tooltip(h, function(GT) GT:AddLine(h.title or "", 1, 0.82, 0); if h.tip then GT:AddLine(h.tip, 1, 1, 1, true) end end)
  f.heads[i] = h
  return h
end
A.heading = heading

local function copy(t) local c = {}; for k, v in pairs(t) do c[k] = v end return c end
function A.insert(t, at)
  local f = A.ef
  f.touched = true
  if #f.targets >= O().MAX_TARGETS then return false end
  at = math.max(1, math.min(#f.targets + 1, at or (#f.targets + 1)))
  table.insert(f.targets, at, copy(t))
  A.refreshEditor()
  return true
end
function A.moveRow(i, j)
  local f = A.ef
  f.touched = true
  if not f.targets[i] then return end
  j = math.max(1, math.min(#f.targets, j))
  if i == j then return end
  local t = table.remove(f.targets, i)
  table.insert(f.targets, j, t)
  A.refreshEditor()
end
--- Where the cursor is over the list: an index 1..#targets+1, or nil when outside the list.
function A.dropIndex()
  local f = A.ef
  local x, y = _G.GetCursorPosition()
  local k = f.list:GetEffectiveScale() or 1
  x, y = x / k, y / k
  local l, r, top, bottom = f.list:GetLeft(), f.list:GetRight(), f.list:GetTop(), f.list:GetBottom()
  if not (l and r and top and bottom) or x < l or x > r or y > top or y < bottom then return nil end
  return math.floor((top - y) / A.ROW_H) + 1
end
--- A drag ends: new tile → insert where dropped; a row → move there, or remove when dropped outside the list.
function A.drop()
  local d = A.drag
  A.drag = nil
  if not d then return end
  local f = A.ef
  local at = A.dropIndex()
  if d.kind == "new" then
    if at then A.insert(d.target, at) end
  elseif d.kind == "row" then
    if at then A.moveRow(d.index, math.min(at, #f.targets)) else f.touched = true; table.remove(f.targets, d.index); A.refreshEditor() end
  end
end

--- Open the Macro editor for macro `name` (any macro: recommended, sequence, squad or own).
--- The base macro the targeting works on: for an own macro the draft being edited, else the engine's macro.
local function baseOf(f)
  if f.own and ns.KeyEditor.frame and ns.KeyEditor.frame.draft then
    local _, m = Core().me()
    local ok, r = pcall(ns.KeyEditor.preview, m, ns.KeyEditor.frame.draft, ns.Compat.playerLevel())
    if ok and r and r.macro and r.macro ~= "" then return r.macro end
  end
  local d = f.name and current(f.name)
  return d and (d.engineBody or d.body) or ""
end
A.baseOf = baseOf
--- Log one step of an own-macro flow (the diagnose shows them: docs/feedback-2026-10-30-night.md §1).
function A.flow(step) Core().log("info", "own macro: " .. step) end

--- New macro: the same Macro editor, starting with "Single spell or Sequence".
function A.openNew(parent)
  local f = editorFrame(parent)
  f.name, f.label, f.own, f.ctx, f.touched = nil, "New macro", "new", O().ctx(), false
  f.targets, f.opts, f.base, f.help = {}, {}, "", nil
  f.title:SetText("Macro editor – New macro")
  ns.KeyEditor.Open(f.spellsBox, nil)
  f:Show()
  A.flow("new")
  A.showSection("spells")
  return true
end

function A.openEditor(parent, name, label)
  local own = name and tonumber(name:match("^WBX C(%d)$"))
  local d = current(name)
  if not d and not own then return false end
  local f = editorFrame(parent)
  f.own, f.touched = own, false
  if own then
    local _, m = Core().me()
    if not (m and m.customSeq and m.customSeq[own]) then return false end
    ns.KeyEditor.Open(f.spellsBox, own)
    label = label or m.customSeq[own].name
    A.flow("open C" .. own)
  end
  d = d or { body = "", label = label }
  f.name, f.label, f.ctx = name, label or name, O().ctx()
  local ov = Core().cdb.overrides[name]
  local base = own and baseOf({ own = own, name = name }) or (d.engineBody or d.body)
  f.base = base
  f.help = base:find("help", 1, true) and true or (base:find("harm", 1, true) and false or nil)
  f.targets, f.opts = {}, {}
  local src = (ov and ov.targets and #ov.targets > 0) and ov.targets or O().fromBody(base, f.ctx)
  for i, t in ipairs(src) do f.targets[i] = copy(t) end
  for _, k in ipairs({ "mod", "reset", "startattack", "petattack" }) do f.opts[k] = ov and ov[k] end
  -- 1 Spells: what the macro casts
  local kind = (d.seq and d.seq.base == "priority") and "Priority" or (d.seq and "Sequence") or "Single spell"
  local names = {}
  for _, s in ipairs(d.steps or {}) do names[#names + 1] = s.name end
  if #names == 0 and d.spell then names[1] = d.spell.name end
  if #names == 0 and d.seq and d.seq.spells then for _, n in ipairs(d.seq.spells) do names[#names + 1] = n end end
  if #names == 0 then names[1] = d.label end
  f.spells:SetText(kind .. ": " .. table.concat(names, " › "))
  f.spellsInfo.text:SetText(kind .. ": " .. table.concat(names, " › "))
  f.title:SetText("Macro editor – " .. f.label)
  f:Show()
  -- own macros start on their spells (Standard: spells only; the presets are there); others on the targeting
  A.showSection((own and not A.on()) and "spells" or (own and "spells") or "target")
  return true
end
A.openTargeting = A.openEditor -- 0.9.9 name
function A.draft()
  local f = A.ef
  local ov = { targets = f.targets }
  for k, v in pairs(f.opts) do ov[k] = v end
  return O().clean(ov)
end
function A.refreshEditor()
  local f = A.ef
  if not (f and f:IsShown()) then return end
  f.back:SetShown(f.name ~= nil); f.text:SetShown(f.name ~= nil and A.on())
  if f.own then
    f.base = baseOf(f)
    f.help = f.base:find("help", 1, true) and true or (f.base:find("harm", 1, true) and false or nil)
  end
  -- available targets: every target this client can use, in groups (Common, Squad, Party, Raid folded); Common and
  -- Squad tiles take the full width (long names), Party and Raid two columns; the list scrolls
  local W2, pitch = f.availW, A.ROW_H
  local half = math.floor((W2 - 4) / 2)
  local y, ti, hi = 0, 0, 0
  f.groups = O().groups(f.ctx, f.help)
  for _, g in ipairs(f.groups) do
    hi = hi + 1
    local h = heading(f, hi)
    h.key, h.title, h.tip = g.key, g.title, g.tip
    local open = not g.folded or f.raidOpen
    h.text:SetText(g.folded and ((open and "– " or "+ ") .. g.title:upper() .. " (" .. #g.items .. ")") or g.title:upper())
    if g.folded then h.tip = g.tip .. (open and " Click to fold." or " Click to show.") end
    h:ClearAllPoints(); h:SetPoint("TOPLEFT", 0, -y); h:SetWidth(W2)
    h:Show()
    g.open = open
    y = y + 18
    if open then
      local wide = g.key == "common" or g.key == "squad"
      for k, c in ipairs(g.items) do
        ti = ti + 1
        local t = tile(f, ti)
        t.target, t.full, t.group = c[2], c[1], g.key
        t.name:SetText(c[1])
        A.iconOf(t.icon, c[2], f.ctx)
        local ok = O().unitFor(c[2], f.ctx) ~= nil
        t.name:SetTextColor(ok and 1 or 0.55, ok and 1 or 0.55, ok and 1 or 0.55)
        t:ClearAllPoints()
        if wide then
          t:SetSize(W2, pitch - 2); t:SetPoint("TOPLEFT", 0, -y); y = y + pitch
        else
          local col = (k - 1) % 2
          t:SetSize(half, pitch - 2); t:SetPoint("TOPLEFT", col * (half + 4), -y)
          if col == 1 or k == #g.items then y = y + pitch end
        end
        t:Show()
      end
    end
    y = y + 4
  end
  for i = ti + 1, #f.tiles do f.tiles[i]:Hide(); f.tiles[i].target = nil end
  for i = hi + 1, #f.heads do f.heads[i]:Hide() end
  f.availContent:SetHeight(math.max(10, y))
  W.tidyScroll(f.availSF, y)
  for i, r in ipairs(f.rows) do
    local t = f.targets[i]
    r:SetShown(t ~= nil)
    if t then
      local text, here = A.rowText(t, f.ctx)
      r.name:SetText(text)
      local c = here and 1 or 0.55
      r.name:SetTextColor(c, c, c)
      A.iconOf(r.icon, t, f.ctx)
      if r.icon.SetDesaturated then r.icon:SetDesaturated(not here) end
      W.setLabel(r.aim, t.help == true and "Friendly" or t.help == false and "Enemy" or "Either")
      r.dead:SetChecked(t.nodead and true or false)
      r.up:SetEnabled(i > 1); r.down:SetEnabled(f.targets[i + 1] ~= nil)
    end
  end
  f.empty:SetShown(#f.targets == 0)
  f.mod.Refresh(); f.start.Refresh(); f.pet.Refresh(); f.reset.Refresh()
  local ov = A.draft()
  local body, missing = f.base, {}
  if ov then body, missing = O().apply(f.base, ov, f.ctx) end
  f.body = body
  f.preview:SetText(W.wrapMacro(body, f.preview:GetWidth() or 560, 9))
  local ok, why = ns.Rules.validateMacro(f.name or "WBX C1", body)
  if f.own and body == "" then ok, why = true, nil end -- a new macro: its spells come first (the Spells section says so)
  local msg = #body .. "/255"
  if #body > 255 then msg = "|cffff8a80Too long (" .. #body .. "/255): remove a target or untick Skip if dead|r"
  elseif not ok then msg = "|cffff8a80" .. tostring(why) .. "|r"
  elseif #missing > 0 then msg = msg .. " · |cfff0b43c" .. table.concat(missing, ", ") .. " skipped (not in your party)|r" end
  if #f.targets == 0 then msg = msg .. " · no targets: WoWBoxer's own targeting stays" end
  f.info:SetText(msg)
  f.save:SetEnabled(ok and #body <= 255)
  f.back:SetEnabled(Core().cdb.overrides[f.name] ~= nil)
end
A.refreshTargeting = A.refreshEditor
--- Save: an own macro saves its spells first (and its preset), then the targeting when it was changed here.
function A.saveEditor()
  local f = A.ef
  if f.own then
    local idx, err = ns.KeyEditor.commit()
    if not idx then Core().print("|cffff8a80" .. tostring(err) .. "|r"); A.flow("save failed: " .. tostring(err)); return end
    f.name = "WBX C" .. idx
    A.flow("saved C" .. idx .. (f.touched and " with targeting" or ""))
    if f.touched and A.on() then Core().setOverride(f.name, A.draft()) end
    if ns.UI.panels and ns.UI.panels.custom then ns.UI.panels.custom.selected = f.name end
    Core().changed()
  else
    Core().setOverride(f.name, A.draft())
  end
  f:Hide()
end
--- Closing the editor closes its Spells section too (the draft is dropped).
A.saveTargeting = A.saveEditor

-- ------------------------------------------------------------------ Edit macro text (§3, the last resort)
local function textFrame(parent)
  if A.xf then
    if A.xf:GetParent() ~= parent then A.xf:SetParent(parent); A.xf:ClearAllPoints(); A.xf:SetPoint("CENTER", 0, 0); A.xf:SetFrameLevel((parent:GetFrameLevel() or 1) + 60) end
    return A.xf
  end
  local f = modal(parent, 560, 300)
  f.title = W.text(f, "GameFontNormal", nil, W.GOLD)
  f.title:SetPoint("TOPLEFT", 14, -12)
  f.title.wbxCopy = "data"
  local sf, eb = W.editBox(f, 520, 150)
  sf:SetPoint("TOPLEFT", 16, -36)
  f.sf, f.edit = sf, eb
  eb:SetMaxLetters(400)
  eb:SetScript("OnTextChanged", function() A.refreshText() end)
  f.info = W.text(f, "GameFontHighlightSmall", nil, W.MUTED)
  f.info:SetPoint("TOPLEFT", 16, -196)
  f.info:SetPoint("TOPRIGHT", -16, -196)
  if f.info.SetMaxLines then f.info:SetMaxLines(4) end
  f.info.wbxCopy = "data"
  f.note = W.text(f, "GameFontHighlightSmall", nil, W.ORANGE)
  f.note:SetPoint("BOTTOMLEFT", 14, 44)
  f.note:SetText("A macro with your own text is frozen: level-ups no longer update it.")
  f.note.wbxCopy = "sentence"
  f.save = W.button(f, "Save", 70, 24, function()
    local ok = O().checkText(f.name, f.edit:GetText())
    if ok then Core().setOverride(f.name, { text = f.edit:GetText() }); f:Hide() end
  end, "Saves this text as the macro's macro. Press Update macros afterwards to write it.")
  f.save:SetPoint("BOTTOMRIGHT", -12, 10)
  f.cancel = W.button(f, "Cancel", 70, 24, function() f:Hide() end, "Closes this. Nothing changes.")
  f.cancel:SetPoint("RIGHT", f.save, "LEFT", -6, 0)
  f.back = W.button(f, "WoWBoxer's version", 140, 24, function() Core().setOverride(f.name, nil); f:Hide() end,
    "Back to WoWBoxer's version: removes your text and unfreezes the macro.")
  f.back:SetPoint("BOTTOMLEFT", 12, 10)
  A.xf = f
  W.dialog(f, "WoWBoxerTextDialog")
  return f
end
function A.openText(parent, name, label)
  local d = current(name)
  if not d then return end
  local f = textFrame(parent)
  f.name = name
  f.title:SetText("Macro text – " .. (label or name))
  f.edit:SetText(d.body)
  f:Show()
  A.refreshText()
end
function A.refreshText()
  local f = A.xf
  if not (f and f:IsShown()) then return end
  local body = f.edit:GetText() or ""
  local ok, probs = O().checkText(f.name, body)
  f.info:SetText(ok and ("|cff8fbf6a" .. #body .. "/255 · OK|r") or ("|cffff8a80" .. table.concat(probs, "\n") .. "|r"))
  f.save:SetEnabled(ok)
  f.back:SetEnabled(Core().cdb.overrides[f.name] ~= nil)
end

-- ------------------------------------------------------------------ the book: menu entries, marks (Advanced only)
--- Right-click entries for book cell c on panel p – the same for the leader and every follower (no role check).
--- Advanced: "Edit macro…" on every macro and every spell (a spell without a macro first becomes an own single-spell
--- macro), "Also heal <pet>" on friendly macros. Standard: "Edit macro… (Advanced mode)" greyed with a tip.
function A.menuItems(p, c)
  local items = {}
  local isSpell = c.kind == "spell" and c.spell ~= nil
  if not (c.name or isSpell) or c.kind == "new" or c.kind == "squadkey" then return items end
  local own = c.name and c.name:match("^WBX C%d$")
  if not A.on() and own then
    items[#items + 1] = { "Edit macro…", function() A.editCell(p, c) end, "Spells, kind and targeting preset of this own macro." }
  elseif not A.on() then
    items[#items + 1] = { "Edit macro… (Advanced mode)", function() end, "Turn on Advanced in the window header to change who this macro casts on.", true }
  else
    items[#items + 1] = { "Edit macro…", function() A.editCell(p, c) end, "Spells, targeting (drag and drop), options and a live preview of this macro." }
    local body = c.d and (c.d.engineBody or c.d.body) or ""
    if c.name and body:find("help", 1, true) then
      for _, m in ipairs(O().squadPets(O().ctx())) do
        items[#items + 1] = { "Also heal " .. m.name .. "'s pet", function() Core().alsoHeal(c.name, m.name) end,
          "Adds " .. m.name .. "'s pet after the leader. Press Update macros afterwards." }
      end
    end
  end
  if c.name and Core().cdb.overrides[c.name] then
    items[#items + 1] = { "Back to WoWBoxer's version", function() Core().setOverride(c.name, nil) end, "Removes your targeting or text for this macro." }
  end
  return items
end
--- Edit macro… on a cell: its macro, or a spell without one becomes an own single-spell macro first.
function A.editCell(p, c)
  if c.name then return A.openEditor(p, c.name, c.label) end
  local i, why = Core().newSingle(c.spell)
  if not i then Core().print("|cffff8a80" .. tostring(why) .. "|r"); return false end
  return A.openEditor(p, "WBX C" .. i, c.spell.name)
end
--- Tooltip lines for a key with an override.
function A.tooltip(GT, c)
  local d = c.d
  if not (d and d.override) then return end
  if d.frozen then GT:AddLine("Edited by you – not updated on level-up", 1, 0.6, 0.2, true)
  else GT:AddLine("Your targeting: " .. O().summary(d.override, O().ctx()), 1, 0.6, 0.2, true) end
  if d.ovMissing then GT:AddLine(table.concat(d.ovMissing, ", ") .. " not in your party: left out", 1, 0.54, 0.5, true) end
end
--- How many keys use the player's own targeting or text.
function A.count()
  local n = 0
  for _ in pairs(Core().cdb.overrides or {}) do n = n + 1 end
  return n
end

-- ------------------------------------------------------------------ Reset to default (§5)
local function resetFrame()
  if A.rf then return A.rf end
  local f = modal(UI.frame, 520, 350)
  f.title = W.text(f, "GameFontNormalLarge", 15, W.GOLD)
  f.title:SetPoint("TOPLEFT", 16, -14)
  f.title.wbxCopy = "hint"
  f.ticks = {}
  local defs = {
    { "char", "This character", "Settings, macro choices, overrides, keybinds, reminders, Advanced and Automation." },
    { "bars", "Action bars as before", "Puts back what your buttons held before WoWBoxer changed them." },
    { "account", "All my squads and saved builds", "Every squad and every saved talent build on this account." },
    { "macros", "WoWBoxer macros on this character", "Only macros named WBX – yours are never touched; their buttons become empty." },
    { "cvars", "Game settings WoWBoxer changed", "Restore first puts back the values WoWBoxer saved, then the backup is forgotten." },
  }
  for i, dft in ipairs(defs) do
    local c = W.check(f, dft[2], function() A.refreshReset() end)
    c:SetPoint("TOPLEFT", 14, -36 - (i - 1) * 40)
    c.key = dft[1]
    c.sub = W.text(f, "GameFontHighlightSmall", nil, W.MUTED)
    c.sub:SetPoint("TOPLEFT", 40, -36 - (i - 1) * 40 - 20)
    c.sub:SetWidth(470)
    W.role(c.sub, "body", 10)
    c.sub:SetText(dft[3])
    c.sub.wbxCopy = "sentence"
    f.ticks[i] = c
  end
  f.summary = W.text(f, "GameFontHighlight", nil, W.TEXT)
  f.summary:SetPoint("TOPLEFT", 16, -44)
  f.summary:SetPoint("TOPRIGHT", -16, -44)
  f.summary.wbxCopy = "data"
  f.typeLabel = W.text(f, "GameFontNormalSmall", nil, W.GOLD)
  f.typeLabel:SetPoint("TOPLEFT", 16, -150)
  f.typeLabel:SetText("Type RESET to confirm")
  f.typeLabel.wbxCopy = "hint"
  f.typed = W.frame("EditBox", f, "InputBoxTemplate")
  f.typed:SetSize(120, 20)
  f.typed:SetAutoFocus(false)
  f.typed:SetMaxLetters(10)
  f.typed:SetPoint("LEFT", f.typeLabel, "RIGHT", 12, 0)
  f.typed:SetScript("OnTextChanged", function() A.refreshReset() end)
  f.note = W.text(f, "GameFontHighlightSmall", nil, W.MUTED)
  f.note:SetPoint("TOPLEFT", 16, -180)
  f.note:SetPoint("TOPRIGHT", -16, -180)
  f.note:SetText("Your squads on other characters are not touched unless you ticked them.")
  f.note.wbxCopy = "sentence"
  f.next = W.button(f, "Next", 80, 24, function() f.step = 2; f.typed:SetText(""); A.refreshReset() end, "Shows exactly what will be removed.")
  f.next:SetPoint("BOTTOMRIGHT", -12, 12)
  f.go = W.button(f, "Reset", 80, 24, function() A.doReset() end, "Removes what is listed above. Out of combat only.")
  f.go:SetPoint("BOTTOMRIGHT", -12, 12)
  f.go.wbxBig = true -- "Not in combat" in combat
  f.reload = W.button(f, "Reload UI now", 120, 24, function() if _G.ReloadUI then _G.ReloadUI() end end, "Reloads the game's interface so everything starts fresh.")
  f.reload:SetPoint("BOTTOMRIGHT", -12, 12)
  f.reload.wbxBig = true
  f.cancel = W.button(f, "Cancel", 70, 24, function() f:Hide() end, "Closes this. Nothing is removed.")
  f.cancel:SetPoint("BOTTOMLEFT", 12, 12)
  f.back = W.button(f, "Back", 60, 24, function() f.step = 1; A.refreshReset() end, "Back to the choices.")
  f.back:SetPoint("LEFT", f.cancel, "RIGHT", 6, 0)
  A.rf = f
  W.dialog(f, "WoWBoxerResetDialog")
  return f
end
--- Open the Reset to default window (Setup button, /wbx reset all). It never resets by itself.
function A.openReset()
  UI.Open()
  local f = resetFrame()
  f.step = 1
  for _, c in ipairs(f.ticks) do c:SetChecked(c.key == "char" or c.key == "bars" or c.key == "macros" or c.key == "cvars") end
  f:Show()
  A.refreshReset()
end
function A.choices()
  local out = {}
  for _, c in ipairs(A.rf.ticks) do out[c.key] = c:GetChecked() and true or false end
  return out
end
function A.refreshReset()
  local f = A.rf
  if not (f and f:IsShown()) then return end
  local step = f.step
  local combat = ns.Compat.inCombat()
  for _, c in ipairs(f.ticks) do c:SetShown(step == 1); c.sub:SetShown(step == 1) end
  f.summary:SetShown(step == 2); f.typeLabel:SetShown(step == 2); f.typed:SetShown(step == 2); f.note:SetShown(step == 2)
  f.next:SetShown(step == 1); f.go:SetShown(step == 2); f.back:SetShown(step == 2); f.reload:SetShown(step == 3)
  f.cancel:SetShown(step ~= 3)
  if step == 1 then
    f.title:SetText("What do you want to reset?")
    local any = false
    for _, v in pairs(A.choices()) do if v then any = true end end
    f.next:SetEnabled(any)
  elseif step == 2 then
    f.title:SetText("Are you sure?")
    f.summary:SetText("Removes: " .. Core().resetSummary(A.choices()) .. ".")
    local ok = (f.typed:GetText() or "") == "RESET"
    f.go:SetEnabled(ok and not combat)
    W.setLabel(f.go, combat and "Not in combat" or "Reset")
  else
    f.title:SetText("Done")
    f.summary:Show(); f.summary:SetText(f.done or "")
  end
end
function A.doReset()
  local f = A.rf
  if ns.Compat.inCombat() then return end
  f.done = Core().resetToDefault(A.choices())
  f.step = 3
  A.refreshReset()
end

return A
