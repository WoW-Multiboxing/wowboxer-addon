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
local function modal(parent, w, h)
  local f = W.box(parent, 0.11, 0.085, 0.05, 0.99)
  f:SetSize(w, h)
  f:SetPoint("CENTER", 0, 0)
  f:SetFrameLevel((parent:GetFrameLevel() or 1) + 60)
  f:EnableMouse(true)
  f.wbxModal = true
  f:Hide()
  return f
end

function A.attachSwitch(f)
  local std = W.button(f, "Standard", 72, 18, function() A.setMode(false) end, "Standard mode: WoWBoxer's macros as they are. Your own changes stay active.")
  local adv = W.button(f, "Advanced", 72, 18, function() if not A.on() then A.confirm() end end,
    "Advanced mode: change who each macro casts on and edit macro text. Asks first.")
  std:SetPoint("TOPLEFT", 134, -12)
  adv:SetPoint("LEFT", std, "RIGHT", 2, 0)
  UI.modeStd, UI.modeAdv = std, adv
  if UI.whoHit then UI.whoHit:ClearAllPoints(); UI.whoHit:SetPoint("LEFT", adv, "RIGHT", 10, 0); UI.whoHit:SetPoint("RIGHT", f, "TOPRIGHT", -100, -21) end
  -- the confirm window (§1)
  local c = modal(f, 420, 200)
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
  c.tick:SetPoint("BOTTOMLEFT", 12, 44)
  c.go = W.button(c, "Turn on Advanced", 130, 24, function() if c.tick:GetChecked() then c:Hide(); A.setMode(true) end end,
    "Shows the advanced controls. Nothing changes in your macros until you change one.")
  c.go:SetPoint("BOTTOMRIGHT", -12, 12)
  c.go.wbxBig = true
  c.cancel = W.button(c, "Cancel", 70, 24, function() c:Hide() end, "Stays in Standard mode.")
  c.cancel:SetPoint("RIGHT", c.go, "LEFT", -6, 0)
  A.confirmFrame = c
end
function A.confirm()
  local c = A.confirmFrame
  c.tick:SetChecked(false)
  c:Show()
  A.refreshConfirm()
end
function A.refreshConfirm() local c = A.confirmFrame; c.go:SetEnabled(c.tick:GetChecked() and true or false) end
function A.setMode(on)
  Core().db.settings.advanced = on and true or nil
  Core().log("info", on and "advanced mode on" or "standard mode")
  Core().changed()
end
function A.refreshSwitch()
  if not UI.modeStd then return end
  local on = A.on()
  if on then UI.modeAdv:LockHighlight(); UI.modeStd:UnlockHighlight() else UI.modeStd:LockHighlight(); UI.modeAdv:UnlockHighlight() end
end

-- ------------------------------------------------------------------ Targeting window (§2)
local ROWS = 8
local function current(name)
  local ctx = Core().compute()
  for _, d in ipairs(ctx and ctx.desired or {}) do if d.name == name then return d end end
end
local function targetingFrame(parent)
  if A.tf then
    if A.tf:GetParent() ~= parent then A.tf:SetParent(parent); A.tf:ClearAllPoints(); A.tf:SetPoint("CENTER", 0, 0); A.tf:SetFrameLevel((parent:GetFrameLevel() or 1) + 60) end
    return A.tf
  end
  local f = modal(parent, 600, 400)
  f.title = W.text(f, "GameFontNormal", nil, W.GOLD)
  f.title:SetPoint("TOPLEFT", 14, -12)
  f.title.wbxCopy = "data"
  local hl = W.text(f, "GameFontNormalSmall", nil, W.GOLD)
  hl:SetPoint("TOPLEFT", 14, -34)
  hl:SetText("Tries, top first")
  hl.wbxCopy = "label"
  f.rows = {}
  for i = 1, ROWS do
    local r = CreateFrame("Frame", nil, f)
    r:SetSize(572, 22)
    r:SetPoint("TOPLEFT", 14, -50 - (i - 1) * 24)
    r.bg = r:CreateTexture(nil, "BACKGROUND")
    r.bg:SetAllPoints()
    r.bg:SetColorTexture(0, 0, 0, i % 2 == 0 and 0.15 or 0.25)
    r.name = W.line(r, "GameFontHighlightSmall", nil, W.TEXT)
    r.name:SetPoint("LEFT", 6, 0)
    r.name:SetWidth(210)
    r.name.wbxCopy = "data"
    local hit = CreateFrame("Frame", nil, r)
    hit:SetAllPoints(r.name)
    W.tooltip(hit, function(GT)
      local t = f.targets and f.targets[i]
      if not t then return end
      local c = O().cond(t, f.ctx)
      GT:AddLine(O().label(t, f.ctx), 1, 0.82, 0)
      GT:AddLine(c or "Not in your party here – left out of the macro", 0.56, 0.85, 0.45)
      GT:AddLine(O().meaning(t, f.ctx) .. ".", 1, 1, 1, true)
    end)
    r.aim = W.button(r, "Friendly", 70, 20, function()
      local t = f.targets[i]; if not t then return end
      if t.help == true then t.help = false elseif t.help == false then t.help = nil else t.help = true end
      A.refreshTargeting()
    end, "Friendly: only friends. Enemy: only enemies. Either: both.")
    r.aim:SetPoint("LEFT", 222, 0)
    r.dead = W.check(r, "Skip if dead", function(_, v) local t = f.targets[i]; if t then t.nodead = v; A.refreshTargeting() end end)
    r.dead:SetPoint("LEFT", 300, 0)
    r.up = W.button(r, "Up", 40, 20, function() local t = f.targets; if i > 1 then t[i], t[i - 1] = t[i - 1], t[i]; A.refreshTargeting() end end, "Tries this one earlier.")
    r.up:SetPoint("LEFT", 404, 0)
    r.down = W.button(r, "Down", 50, 20, function() local t = f.targets; if t[i + 1] then t[i], t[i + 1] = t[i + 1], t[i]; A.refreshTargeting() end end, "Tries this one later.")
    r.down:SetPoint("LEFT", r.up, "RIGHT", 2, 0)
    r.remove = W.button(r, "x", 24, 20, function() table.remove(f.targets, i); A.refreshTargeting() end, { "Remove", "Takes this target out of the macro." })
    r.remove:SetPoint("RIGHT", -2, 0)
    f.rows[i] = r
  end
  local y = -50 - ROWS * 24 - 6
  f.add = W.dropdown(f, { width = 220, placeholder = "Add target",
    values = function() local v = {}; for k, c in ipairs(O().choices(f.ctx, f.help)) do v[#v + 1] = { k, c[1] } end return v end,
    get = function() return nil end,
    set = function(k) local c = O().choices(f.ctx, f.help)[k]; if c and #f.targets < O().MAX_TARGETS then f.targets[#f.targets + 1] = c[2]; A.refreshTargeting() end end })
  f.add:SetPoint("TOPLEFT", 14, y)
  W.ddTip(f.add, "Add target", "Mouseover, your target, the leader, the leader's target, each squad member and pet with its unit here, party1–4, focus, target of target, myself.")
  f.mod = W.dropdown(f, { width = 150,
    values = function() return { { "none", "No modifier" }, { "shift", "Shift = myself" }, { "ctrl", "Ctrl = myself" }, { "alt", "Alt = myself" } } end,
    get = function() return f.opts.mod or "none" end, set = function(v) f.opts.mod = v ~= "none" and v or nil; A.refreshTargeting() end })
  f.mod:SetPoint("LEFT", f.add, "RIGHT", 10, 0)
  W.ddTip(f.mod, "Modifier", "Hold Shift (Ctrl, Alt) while you press the macro to cast it on yourself.")
  local function tri(width, key, labels)
    return W.dropdown(f, { width = width, values = function() return { { "keep", labels[1] }, { "on", labels[2] }, { "off", labels[3] } } end,
      get = function() local v = f.opts[key]; return v == true and "on" or v == false and "off" or "keep" end,
      set = function(v)
        if v == "on" then f.opts[key] = true elseif v == "off" then f.opts[key] = false else f.opts[key] = nil end
        A.refreshTargeting()
      end })
  end
  f.start = tri(130, "startattack", { "Attack: as built", "Auto attack on", "Auto attack off" })
  f.start:SetPoint("LEFT", f.mod, "RIGHT", 10, 0)
  W.ddTip(f.start, "Auto attack", "Adds or removes /startattack (enemy macros).")
  f.pet = tri(130, "petattack", { "Pet: as built", "Pet attacks", "No pet line" })
  f.pet:SetPoint("TOPLEFT", 14, y - 28)
  W.ddTip(f.pet, "Pet", "Adds or removes /petattack (enemy macros).")
  f.reset = W.dropdown(f, { width = 160,
    values = function() local v = { { "keep", "Reset: as built" } }; for _, r in ipairs(O().RESETS) do v[#v + 1] = { r, "reset=" .. r } end return v end,
    get = function() return f.opts.reset or "keep" end, set = function(v) f.opts.reset = v ~= "keep" and v or nil; A.refreshTargeting() end })
  f.reset:SetPoint("LEFT", f.pet, "RIGHT", 10, 0)
  W.ddTip(f.reset, "Reset", "When a sequence macro starts over: after combat, on a new target, after some seconds.")
  f.preview = W.text(f, "GameFontHighlightSmall", 9, { 0.6, 0.66, 0.52 })
  f.preview:SetPoint("TOPLEFT", 14, y - 56)
  f.preview:SetPoint("TOPRIGHT", -14, y - 56)
  if f.preview.SetNonSpaceWrap then f.preview:SetNonSpaceWrap(true) end
  f.preview.wbxCopy = "data"
  f.info = W.text(f, "GameFontHighlightSmall", nil, W.MUTED)
  f.info:SetPoint("BOTTOMLEFT", 14, 40)
  f.info:SetPoint("BOTTOMRIGHT", -14, 40)
  f.info.wbxCopy = "data"
  f.save = W.button(f, "Save", 70, 24, function() A.saveTargeting() end, "Saves your targeting for this macro. Press Update macros afterwards to write the macro.")
  f.save:SetPoint("BOTTOMRIGHT", -12, 10)
  f.cancel = W.button(f, "Cancel", 70, 24, function() f:Hide() end, "Closes this. Nothing changes.")
  f.cancel:SetPoint("RIGHT", f.save, "LEFT", -6, 0)
  f.back = W.button(f, "WoWBoxer's version", 140, 24, function() Core().setOverride(f.name, nil); f:Hide() end,
    "Back to WoWBoxer's version: removes your targeting (and text) for this macro.")
  f.back:SetPoint("BOTTOMLEFT", 12, 10)
  A.tf = f
  return f
end
--- Open the Targeting window for key `name` (Advanced only).
function A.openTargeting(parent, name, label)
  local f = targetingFrame(parent)
  local d = current(name)
  if not d then return end
  f.name, f.label, f.ctx = name, label or name, O().ctx()
  local ov = Core().cdb.overrides[name]
  local base = d.engineBody or d.body
  f.base = base
  f.help = base:find("help", 1, true) and true or (base:find("harm", 1, true) and false or nil)
  f.targets, f.opts = {}, {}
  local src = (ov and ov.targets and #ov.targets > 0) and ov.targets or O().fromBody(base, f.ctx)
  for i, t in ipairs(src) do local c = {}; for k, v in pairs(t) do c[k] = v end; f.targets[i] = c end
  for _, k in ipairs({ "mod", "reset", "startattack", "petattack" }) do f.opts[k] = ov and ov[k] end
  f.title:SetText("Targeting – " .. f.label)
  f:Show()
  A.refreshTargeting()
end
function A.draft()
  local f = A.tf
  local ov = { targets = f.targets }
  for k, v in pairs(f.opts) do ov[k] = v end
  return O().clean(ov)
end
function A.refreshTargeting()
  local f = A.tf
  if not (f and f:IsShown()) then return end
  for i, r in ipairs(f.rows) do
    local t = f.targets[i]
    r:SetShown(t ~= nil)
    if t then
      local c = O().cond(t, f.ctx)
      local u = O().unitFor(t, f.ctx)
      r.name:SetText(O().label(t, f.ctx) .. (u and (" (" .. u .. ")") or " |cfff0b43c(not in party)|r"))
      W.setLabel(r.aim, t.help == true and "Friendly" or t.help == false and "Enemy" or "Either")
      r.dead:SetChecked(t.nodead and true or false)
      r.up:SetEnabled(i > 1); r.down:SetEnabled(f.targets[i + 1] ~= nil)
      r.name:SetTextColor(c and 1 or 0.6, c and 1 or 0.6, c and 1 or 0.6)
    end
  end
  f.add.Refresh(); f.mod.Refresh(); f.start.Refresh(); f.pet.Refresh(); f.reset.Refresh()
  f.add:SetEnabled(#f.targets < O().MAX_TARGETS)
  local ov = A.draft()
  local body, missing = f.base, {}
  if ov then body, missing = O().apply(f.base, ov, f.ctx) end
  f.preview:SetText(body)
  local ok, why = ns.Rules.validateMacro(f.name, body)
  local msg = #body .. "/255"
  if #body > 255 then msg = "|cffff8a80Too long (" .. #body .. "/255): remove a target or untick Skip if dead|r"
  elseif not ok then msg = "|cffff8a80" .. tostring(why) .. "|r"
  elseif #missing > 0 then msg = msg .. " · |cfff0b43c" .. table.concat(missing, ", ") .. " not in your party: left out|r" end
  if #f.targets == 0 then msg = msg .. " · no targets: WoWBoxer's own targeting stays" end
  f.info:SetText(msg)
  f.save:SetEnabled(ok and #body <= 255)
  f.back:SetEnabled(Core().cdb.overrides[f.name] ~= nil)
end
function A.saveTargeting()
  local f = A.tf
  Core().setOverride(f.name, A.draft())
  f:Hide()
end

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
--- Extra right-click entries for key cell c on book panel p.
function A.menuItems(p, c)
  local items = {}
  if not (c.name and c.item) then return items end
  local ov = Core().cdb.overrides[c.name]
  if A.on() then
    items[#items + 1] = { "Targeting…", function() A.openTargeting(p, c.name, c.label) end, "Choose who this macro casts on, in order." }
    if c.d and (c.d.engineBody or c.d.body or ""):find("help", 1, true) then
      for _, m in ipairs(O().squadPets(O().ctx())) do
        items[#items + 1] = { "Also heal " .. m.name .. "'s pet", function() Core().alsoHeal(c.name, m.name) end,
          "Adds " .. m.name .. "'s pet after the leader. Press Update macros afterwards." }
      end
    end
    items[#items + 1] = { "Edit macro text…", function() A.openText(p, c.name, c.label) end, "The last resort: write the macro yourself. The macro is then frozen on level-ups." }
  end
  if ov then items[#items + 1] = { "Back to WoWBoxer's version", function() Core().setOverride(c.name, nil) end, "Removes your targeting or text for this macro." } end
  return items
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
  local f = modal(UI.frame, 520, 330)
  f.title = W.text(f, "GameFontNormalLarge", 15, W.GOLD)
  f.title:SetPoint("TOPLEFT", 16, -14)
  f.title.wbxCopy = "hint"
  f.ticks = {}
  local defs = {
    { "char", "This character", "Settings, macro choices, overrides, bar memory and reminders of this character." },
    { "account", "All my squads and saved builds", "Every squad and every saved talent build on this account." },
    { "macros", "WoWBoxer macros on this character", "Only macros named WBX – yours are never touched; their buttons become empty." },
    { "cvars", "Game settings WoWBoxer changed", "Restore first puts back the values WoWBoxer saved, then the backup is forgotten." },
  }
  for i, dft in ipairs(defs) do
    local c = W.check(f, dft[2], function() A.refreshReset() end)
    c:SetPoint("TOPLEFT", 14, -40 - (i - 1) * 46)
    c.key = dft[1]
    c.sub = W.text(f, "GameFontHighlightSmall", nil, W.MUTED)
    c.sub:SetPoint("TOPLEFT", 40, -40 - (i - 1) * 46 - 22)
    c.sub:SetWidth(466)
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
  return f
end
--- Open the Reset to default window (Setup button, /wbx reset all). It never resets by itself.
function A.openReset()
  UI.Open("setup")
  local f = resetFrame()
  f.step = 1
  for _, c in ipairs(f.ticks) do c:SetChecked(c.key == "char") end
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
