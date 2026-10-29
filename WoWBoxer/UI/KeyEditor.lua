--[[ WoWBoxer – custom key editor (the companion's "own keys", in game).
  A custom key is plain data {name, kind, aim, steps, filler, fills, reset}; the companion engine builds the macro
  (E.buildCustom) with the same targeting, pet, 255-character and warning rules as the rest of WoWBoxer. Spells are added
  from a list of learned spells or by dropping a spell from the spellbook onto the steps strip (GetCursorInfo: data
  only, nothing is cast). Saving only changes SavedVariables; the macro WBX C<n> is written by Place all
  or by dragging the key, like every other key. ]]
local _, ns = ...
local UI, W = ns.UI, ns.Widgets
local KE = {}
ns.KeyEditor = KE

local MAX_STEPS = 12
local KINDS = { { "single", "Single spell" }, { "sequence", "Sequence (/castsequence)" }, { "priority", "Priority list" } }
local AIMS = { { "harm", "Enemy" }, { "help", "Friendly" } }
local RESETS = { { "combat", "Reset after combat" }, { "target/combat", "Reset on new target" }, { "combat/12", "Reset after 12 s" } }

local function Core() return ns.Core end
local function E() return ns.Engine end

--- Spells that can go into a key: learned (by the companion's rules), active, with ranks, no racials or Auto Shot.
function KE.spellChoices(m, L)
  local out = {}
  for _, s in ipairs(ns.Kit.spellsOf(m)) do
    if ns.Kit.learned(m, s, L) and s.action ~= "passive" and s.action ~= "autoshot" and s.gate ~= "racial" and #(s.ranks or {}) > 0 then
      out[#out + 1] = s
    end
  end
  table.sort(out, function(a, b) if a.level ~= b.level then return a.level < b.level end return a.name < b.name end)
  return out
end

--- Macro + warnings for the draft key (what the book will show after saving).
--- The engine's view of a draft: "single" is the custom priority kind with one step.
function KE.engineDraft(c)
  if c.kind ~= "single" then return c end
  local x = {}
  for k, v in pairs(c) do x[k] = v end
  x.kind, x.steps, x.filler = "priority", { c.steps[1] }, ""
  return x
end
function KE.preview(m, c, L)
  c = KE.engineDraft(c)
  local ctx = ns.Kit.memberCtx(m)
  local has = ns.Kit.seqHas(m, L, nil)
  local r = E().buildCustom(m.cls, c, ctx, has, { melee = ns.Kit.isMelee(m) })
  local sp = {}
  for _, n in ipairs(c.steps or {}) do local s = has(n); if s then sp[#sp + 1] = s end end
  local filler = (c.kind == "sequence" and c.filler and c.filler ~= "") and has(c.filler) or nil
  local warn = E().customWarnings(c.kind, sp, filler, c.aim, m.cls)
  for _, w in ipairs(KE.extraWarnings(c, sp, filler)) do warn[#warn + 1] = w end
  return r, warn
end

--- Warnings the addon adds on top of the companion's (docs: the owner's warlock key with Demon Skin + Summon Imp).
function KE.extraWarnings(c, sp, filler)
  local out = {}
  if c.aim ~= "harm" then return out end
  local buffs, slow = {}, {}
  for _, s in ipairs(sp) do
    if s.action == "self" or s.action == "petself" then buffs[#buffs + 1] = s.name end
    if (tonumber(s.castLast) or 0) >= 5 then slow[#slow + 1] = s.name .. " (" .. s.castLast .. " s)" end
  end
  if #buffs > 0 then
    out[#out + 1] = table.concat(buffs, ", ") .. (#buffs == 1 and " is a buff or summon" or " are buffs or summons") ..
      ": in an Enemy macro every fight starts with " .. (#buffs == 1 and "it" or "them") .. ", and if one fails the sequence waits there. Put " ..
      (#buffs == 1 and "it" or "them") .. " on " .. (#buffs == 1 and "its" or "their") .. " own macro."
  end
  if #slow > 0 then out[#out + 1] = "Long casts: " .. table.concat(slow, ", ") .. " – the macro does nothing else meanwhile." end
  local _ = filler
  return out
end

--- One short line for a warning (the full text goes into the tooltip).
function KE.shortWarning(w)
  local one = w:match("^(.-) is a buff or summon:")
  local many = w:match("^(.-) are buffs or summons:")
  if one then return one .. ": a buff – put it on its own macro" end
  if many then return many .. ": buffs – put them on their own macro" end
  local slow = w:match("^Long casts: (.-) – ")
  if slow then return "Long cast: " .. slow end
  local head = w:match("^(.-)[:;]") or w:match("^(.-)%.%s") or w
  local words, out = 0, {}
  for word in head:gmatch("%S+") do
    words = words + 1
    if words > 12 then out[#out + 1] = "…"; break end
    out[#out + 1] = word
  end
  return table.concat(out, " ")
end

--- Save a draft into the member's custom keys (index = nil adds a new one). Returns index or nil, reason.
function KE.save(m, c, index)
  local list = m.customSeq or {}
  if not index and #list >= ns.State.CUSTOM_MAX then return nil, "At most " .. ns.State.CUSTOM_MAX .. " own macros." end
  if #(c.steps or {}) == 0 and (c.filler or "") == "" then return nil, "Add at least one spell." end
  local copy = {}
  for i, v in ipairs(list) do copy[i] = v end
  copy[index or (#copy + 1)] = KE.engineDraft(c)
  local clean = ns.State.cleanCustom(copy)
  m.customSeq = clean
  return index or #clean
end

function KE.delete(m, index)
  local list = m.customSeq or {}
  if list[index] then table.remove(list, index) end
  m.customSeq = ns.State.cleanCustom(list)
end

-- ------------------------------------------------------------------ the editor frame (overlays the book)
local function spellFromCursor()
  if not _G.GetCursorInfo then return nil end
  local kind, a, b, c = _G.GetCursorInfo()
  if kind ~= "spell" then return nil end
  local id = tonumber(c) or tonumber(b) or tonumber(a)
  local name
  if _G.C_Spell and _G.C_Spell.GetSpellName and id then name = _G.C_Spell.GetSpellName(id)
  elseif _G.GetSpellInfo and id then name = _G.GetSpellInfo(id) end
  return ns.Compat.safe(name)
end

--- The Spells section of the Macro editor (UI/Advanced.lua): there is no separate window any more.
function KE.Build(parent)
  if KE.frame then return KE.frame end
  local f = CreateFrame("Frame", nil, parent)
  f:SetAllPoints()
  f:Hide()
  KE.frame = f

  f.title = W.text(f, "GameFontNormal", nil, W.GOLD)
  f.title:SetPoint("TOPLEFT", 10, -10)
  local nl = W.text(f, "GameFontHighlightSmall", nil, W.MUTED)
  nl:SetPoint("TOPLEFT", 10, -34)
  nl:SetText("Name")
  f.name = W.frame("EditBox", f, "InputBoxTemplate")
  f.name:SetSize(150, 20)
  f.name:SetAutoFocus(false)
  f.name:SetMaxLetters(24)
  f.name:SetPoint("LEFT", nl, "RIGHT", 10, 0)
  f.name:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  f.name:SetScript("OnTextChanged", function(self, user) if user and f.draft then f.draft.name = self:GetText(); KE.Refresh() end end)

  local function cyc(width, values, key)
    return W.dropdown(f, { width = width, values = function() return values end, get = function() return f.draft and f.draft[key] end,
      set = function(v) f.draft[key] = v; KE.Refresh() end })
  end
  f.kind = cyc(190, KINDS, "kind")
  f.kind:SetPoint("TOPLEFT", 10, -58)
  f.aim = cyc(110, AIMS, "aim")
  f.aim:SetPoint("LEFT", f.kind, "RIGHT", 6, 0)
  f.reset = cyc(170, RESETS, "reset")
  f.reset:SetPoint("TOPLEFT", 10, -84)
  f.fills = W.dropdown(f, { width = 110, values = function() local v = {}; for i = 1, 6 do v[#v + 1] = { i, "Filler × " .. i } end return v end,
    get = function() return f.draft and f.draft.fills end, set = function(v) f.draft.fills = v; KE.Refresh() end })
  f.fills:SetPoint("LEFT", f.reset, "RIGHT", 6, 0)
  W.ddTip(f.kind, "Kind", "Sequence: each press casts the next step. Priority: each press casts the first step that is ready.")
  W.ddTip(f.aim, "Aim", "Who the macro casts on: an enemy (your or the leader's target) or a friend.")
  f.aim:Hide()
  f.preset = W.dropdown(f, { width = 130, values = function() return KE.presetValues() end,
    get = function() return f.draft and f.draft.preset end,
    set = function(v) f.draft.preset = v; f.draft.aim = v == "enemy" and "harm" or "help"; KE.Refresh() end })
  f.preset:SetPoint("LEFT", f.kind, "RIGHT", 6, 0)
  W.ddTip(f.preset, "Targets", "Enemy: mouseover > the leader's target > your target. Friendly: mouseover > the leader > you. Myself. Or a squad pet. In Advanced mode the Macro editor has the full target list.")
  -- Advanced mode: full targeting and options, and the macro text itself (saved keys only)
  f.targeting = W.button(f, "Edit macro…", 100, 24, function()
    if f.index then local n, l, par = "WBX C" .. f.index, f.draft and f.draft.name, f:GetParent(); KE.Close(); ns.Advanced.openEditor(par, n, l) end
  end, "Advanced: the Macro editor – drag and drop targets, options and the macro text. Save this macro first.")
  f.targeting:SetPoint("BOTTOMLEFT", 258, 8)
  f.textBtn = f.targeting -- one entry point now (the Macro editor has Edit text)
  -- New macro: first the choice, Single spell or Sequence (Priority under More)
  local ch = W.box(f, 0.11, 0.085, 0.05, 1)
  ch:SetAllPoints()
  ch:SetFrameLevel((f:GetFrameLevel() or 1) + 5)
  ch:EnableMouse(true)
  ch.wbxModal = true
  ch.q = W.text(ch, "GameFontNormalLarge", 15, W.GOLD, "CENTER")
  ch.q:SetPoint("TOP", 0, -80)
  ch.q:SetText("What should the new macro do?")
  ch.q.wbxCopy = "hint"
  local function choose(kind) f.draft.kind = kind; ch:Hide(); KE.Refresh() end
  ch.single = W.button(ch, "Single spell", 150, 34, function() choose("single") end, "One spell, cast on the target you choose (enemy, friend, yourself or a squad pet).")
  ch.single:SetPoint("TOPRIGHT", ch, "TOP", -8, -120)
  ch.seq = W.button(ch, "Sequence", 150, 34, function() choose("sequence") end, "Several spells: each press casts the next one (DoTs first, then a filler).")
  ch.seq:SetPoint("TOPLEFT", ch, "TOP", 8, -120)
  ch.more = W.button(ch, "Priority", 90, 22, function() choose("priority") end, "More: a priority list – each press casts the first spell that is ready.")
  ch.more:SetPoint("TOP", 0, -170)
  ch.cancel = W.button(ch, "Cancel", 80, 24, function() KE.Close() end, "Closes this. Nothing is made.")
  ch.cancel:SetPoint("BOTTOMRIGHT", -10, 8)
  ch:Hide()
  f.choice = ch
  W.ddTip(f.reset, "Starts over", "When the sequence starts again from the first step.")
  W.ddTip(f.fills, "Filler", "How many times the filler spell is cast between the other steps.")

  -- steps strip: icons in order; click removes; drop a spell from the spellbook to add it
  local sl = W.text(f, "GameFontNormalSmall", nil, W.GOLD)
  sl:SetPoint("TOPLEFT", 10, -112)
  sl:SetText("Steps")
  sl.wbxCopy = "label"
  local slHit = CreateFrame("Frame", nil, f)
  slHit:SetAllPoints(sl)
  W.tip(slHit, "Steps", "The spells of this macro in order. Click a step to remove it; drop a spell from your spellbook here to add it.")
  f.strip = W.box(f, 0.05, 0.04, 0.025, 0.95)
  f.strip:SetPoint("TOPLEFT", 10, -128)
  f.strip:SetSize(312, 34)
  f.strip:EnableMouse(true)
  local function drop()
    local name = spellFromCursor()
    if not name then return end
    ns.Bars.clearCursor("macro editor: spell dropped")
    KE.addStep(name)
  end
  f.strip:SetScript("OnReceiveDrag", drop)
  f.strip:SetScript("OnMouseUp", drop)
  f.stepBtns = {}
  for i = 1, MAX_STEPS do
    local b = CreateFrame("Button", nil, f.strip)
    b:SetSize(24, 24)
    b:SetPoint("LEFT", 5 + (i - 1) * 25, 0)
    b.icon = W.icon(b, 22, true)
    b.icon:SetPoint("CENTER")
    b:SetScript("OnClick", function(self) table.remove(f.draft.steps, self.i); KE.Refresh() end)
    b:SetScript("OnReceiveDrag", drop)
    W.tooltip(b, function(GT) GT:AddLine(f.draft.steps[b.i] or "", 1, 0.82, 0); GT:AddLine("Click to remove", 0.66, 0.6, 0.49) end)
    f.stepBtns[i] = b
  end
  f.fillerText = W.line(f, "GameFontHighlightSmall", nil, W.TEXT)
  f.fillerText:SetPoint("TOPLEFT", f.strip, "BOTTOMLEFT", 0, -6)
  f.fillerText:SetWidth(312)
  f.fillerText.wbxCopy = "hint"
  local fHit = CreateFrame("Frame", nil, f)
  fHit:SetAllPoints(f.fillerText)
  W.tip(fHit, "Filler", "A sequence macro can repeat one spell between the other steps. Pick it with Filler in the spell list; set how often with Filler × N.")

  -- spell picker (right)
  local pl = W.text(f, "GameFontNormal", nil, W.GOLD)
  pl:SetPoint("TOPLEFT", 340, -10)
  pl:SetText("Your spells")
  pl.wbxCopy = "label"
  local sf, content = W.scroll(f, 290, 250)
  sf:SetPoint("TOPLEFT", 340, -30)
  f.pick, f.pickSf = content, sf
  f.pickPool = W.pool(content, function(par)
    local r = CreateFrame("Frame", nil, par)
    r:SetSize(286, 22)
    r.icon = W.icon(r, 18)
    r.icon:SetPoint("LEFT", 2, 0)
    r.fill = W.button(r, "Filler", 48, 18, function() f.draft.filler = r.spell.name; KE.Refresh() end,
      "Makes this spell the filler: it is cast between the steps (sequence macros only).")
    r.fill:SetPoint("RIGHT", 0, 0)
    r.add = W.button(r, "Add", 44, 18, function() KE.addStep(r.spell.name) end, "Adds this spell as the next step of the macro.")
    r.add:SetPoint("RIGHT", r.fill, "LEFT", -4, 0)
    r.check = r:CreateTexture(nil, "OVERLAY")
    r.check:SetSize(14, 14)
    r.check:SetPoint("RIGHT", r.add, "LEFT", -2, 0)
    r.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    r.name = W.line(r, "GameFontHighlightSmall", nil, W.TEXT)
    r.name:SetPoint("LEFT", 24, 0)
    r.name:SetPoint("RIGHT", r.check, "LEFT", -2, 0)
    r.name.wbxCopy = "data"
    W.tooltip(r, function(GT)
      GT:AddLine(r.spell and r.spell.name or "", 1, 0.82, 0)
      if r.inKey then GT:AddLine("Already in this macro", 0.56, 0.75, 0.42) end
    end)
    return r
  end)

  -- the macro as WoW will run it: one command per line, wraps inside the box, grows downwards with a scroll bar
  local pv = W.box(f, 0.05, 0.04, 0.025, 0.95)
  pv:SetPoint("TOPLEFT", 10, -186)
  pv:SetSize(312, 186)
  local MW = 312 - 12 - W.SCROLLBAR
  local msf, mc = W.scroll(pv, MW, 186 - 12)
  msf:SetPoint("TOPLEFT", 6, -6)
  f.macroSf, f.macroContent = msf, mc
  f.body = W.text(mc, "GameFontHighlightSmall", 10, { 0.72, 0.8, 0.62 })
  f.body:SetPoint("TOPLEFT", 0, 0)
  f.body:SetWidth(MW)
  f.body:SetJustifyV("TOP")
  if f.body.SetNonSpaceWrap then f.body:SetNonSpaceWrap(true) end
  f.body.wbxCopy = "data"
  f.info = W.text(f, "GameFontHighlightSmall", nil, W.MUTED)
  f.info:SetPoint("TOPLEFT", pv, "BOTTOMLEFT", 2, -4)
  f.info.wbxCopy = "status"
  local iHit = CreateFrame("Frame", nil, f)
  iHit:SetAllPoints(f.info)
  W.tooltip(iHit, function(GT) GT:AddLine("Characters", 1, 0.82, 0); GT:AddLine(f.infoTip or "A macro holds at most 255 characters.", 1, 1, 1, true) end)
  -- warnings: an orange ! and at most two short lines; the full text in the tooltip
  f.warnIcon = f:CreateTexture(nil, "ARTWORK")
  f.warnIcon:SetSize(16, 16)
  f.warnIcon:SetPoint("TOPLEFT", 340, -292)
  f.warnIcon:SetTexture("Interface\\DialogFrame\\UI-Dialog-Icon-AlertNew")
  f.warn = W.text(f, "GameFontHighlightSmall", nil, W.ORANGE)
  f.warn:SetPoint("TOPLEFT", 362, -294)
  f.warn:SetWidth(290)
  f.warn:SetJustifyV("TOP")
  if f.warn.SetMaxLines then f.warn:SetMaxLines(2) end
  f.warn.wbxCopy = "warn"
  local wHit = CreateFrame("Frame", nil, f)
  wHit:SetAllPoints(f.warn)
  W.tooltip(wHit, function(GT)
    GT:AddLine("Warnings", 1, 0.54, 0.24)
    for _, w in ipairs(f.warnList or {}) do GT:AddLine(w, 1, 1, 1, true) end
  end)

  f.save = W.button(f, "Save macro", 100, 24, function()
    local _, m = Core().me()
    if not m then return end
    local idx, err = KE.save(m, f.draft, f.index)
    if not idx then Core().print("|cffff8a80" .. err .. "|r"); return end
    KE.applyPreset(idx, f.draft.preset)
    Core().log("info", "own macro: C" .. idx .. " saved as " .. tostring(m.customSeq[idx] and m.customSeq[idx].name) .. " (" .. tostring(m.customSeq[idx] and m.customSeq[idx].kind) .. ")")
    KE.Close()
    if UI.panels and UI.panels.custom then UI.panels.custom.selected = "WBX C" .. idx end
    Core().changed()
  end, "Saves this own macro. It is created in the game when you place it or press Place all.")
  f.save:SetPoint("BOTTOMRIGHT", -10, 8)
  f.cancel = W.button(f, "Cancel", 80, 24, function() KE.Close() end, "Closes the editor without saving.")
  f.cancel:SetPoint("RIGHT", f.save, "LEFT", -6, 0)
  f.delete = W.button(f, "Delete macro", 90, 24, function(self)
    if not self.armed then self.armed = true; W.setLabel(self, "Sure?"); return end
    local _, m = Core().me()
    if m and f.index then KE.delete(m, f.index); Core().log("info", "own macro: deleted C" .. f.index) end
    KE.Close(); Core().changed()
  end, "Deletes this own macro from WoWBoxer (click twice). The game macro is removed the next time you update your macros.")
  f.paste = W.button(f, "Paste…", 70, 24, function()
    ns.CopyBox.ShowPaste(function(d) KE.usePasted(d) end)
  end, "Paste a macro someone gave you (a WoWBoxer macro or plain macro text). Only the spell names are used.")
  f.paste:SetPoint("BOTTOMLEFT", 10, 8)
  f.copy = W.button(f, "Copy…", 70, 24, function()
    local _, m = Core().me()
    if not (m and f.draft) then return end
    local r = KE.preview(m, f.draft, ns.Compat.playerLevel())
    ns.CopyBox.ShowCopy("Copy \"" .. (f.draft.name or "My macro") .. "\"", r.macro, ns.Share.encodeKey(f.draft, m.cls))
  end, "Shows the macro text and a WoWBoxer macro, ready to copy and give to others.")
  f.copy:SetPoint("LEFT", f.paste, "RIGHT", 6, 0)
  f.delete:SetPoint("LEFT", f.copy, "RIGHT", 6, 0)
  -- the Macro editor's Save / Cancel / Edit macro… do this now (one window for every macro)
  f.save:SetScript("OnClick", function() ns.Advanced.saveEditor() end); f.save:Hide()
  f.cancel:SetScript("OnClick", function() KE.Close() end); f.cancel:Hide()
  f.targeting:Hide()
  return f
end

--- Put a pasted key into the draft: spells this class does not have are left out (and named).
function KE.usePasted(d)
  local f = KE.frame
  local _, m = Core().me()
  if not (f and f.draft and m) then return end
  local known = {}
  for _, s in ipairs(ns.Kit.spellsOf(m)) do known[s.name] = true end
  local steps, dropped = {}, {}
  for _, n in ipairs(d.steps or {}) do if known[n] and #steps < MAX_STEPS then steps[#steps + 1] = n else dropped[#dropped + 1] = n end end
  local filler = d.filler or ""
  if filler ~= "" and not known[filler] then dropped[#dropped + 1] = filler; filler = "" end
  local x = f.draft
  x.kind, x.aim, x.steps, x.filler, x.fills, x.reset = d.kind, d.aim, steps, filler, d.fills or 1, d.reset or "combat"
  if d.name and d.name ~= "" and d.name ~= "Pasted macro" then x.name = d.name; f.name:SetText(d.name) end
  if #dropped > 0 then Core().print("|cfff0b43cLeft out (not a " .. (ns.Data.classes[m.cls] and ns.Data.classes[m.cls].n or m.cls) .. " spell):|r " .. table.concat(dropped, ", ")) end
  Core().log("info", "pasted macro: " .. #steps .. " steps")
  KE.Refresh()
end

function KE.addStep(name)
  local f = KE.frame
  if not f or not f.draft then return end
  if #f.draft.steps >= MAX_STEPS then Core().print("A macro holds at most " .. MAX_STEPS .. " steps."); return end
  local _, m = Core().me()
  local known = false
  for _, s in ipairs(ns.Kit.spellsOf(m)) do if s.name == name then known = true end end
  if not known then Core().print("|cffff8a80" .. tostring(name) .. " is not in WoWBoxer's spell list for your class.|r"); return end
  if f.draft.kind == "single" then f.draft.steps = { name } else f.draft.steps[#f.draft.steps + 1] = name end
  KE.Refresh()
end

--- Targeting presets: Enemy, Friendly, Myself and each squad pet (Hunters and Warlocks in the squad).
function KE.presetValues()
  local v = { { "enemy", "Enemy" }, { "friendly", "Friendly" }, { "self", "Myself" } }
  for _, m in ipairs(ns.Override.squadPets(ns.Override.ctx())) do v[#v + 1] = { "pet:" .. m.name, "Friendly: " .. m.name .. "'s pet" } end
  return v
end
--- The preset of a saved macro (from its aim and its override).
function KE.presetOf(index, aim)
  local ov = Core().cdb.overrides["WBX C" .. index]
  local t = ov and ov.targets
  if t and #t == 1 and t[1].who == "player" then return "self" end
  if t and #t == 2 and t[2].who == "member" and t[2].pet then return "pet:" .. t[2].name end
  return aim == "help" and "friendly" or "enemy"
end
--- After saving: the preset as WoWBoxer data (Myself / a pet = an override; Enemy / Friendly = the engine's own).
function KE.applyPreset(index, preset)
  local name = "WBX C" .. index
  local pet = preset and preset:match("^pet:(.+)$")
  if preset == "self" then Core().cdb.overrides[name] = ns.Override.clean({ targets = { { who = "player", help = true } } })
  elseif pet then Core().cdb.overrides[name] = ns.Override.clean({ targets = { { who = "mouseover", help = true, nodead = true }, { who = "member", name = pet, pet = true, help = true, nodead = true } } })
  else
    local ov = Core().cdb.overrides[name]
    if ov and not ov.text and not (ns.Advanced and ns.Advanced.on()) then Core().cdb.overrides[name] = nil end
  end
end

--- Open the editor for custom key `index` of this character (nil = new key).
function KE.Open(parent, index)
  local _, m = Core().me()
  if not m then return end
  local f = KE.Build(parent)
  if f:GetParent() ~= parent then f:SetParent(parent); f:ClearAllPoints(); f:SetAllPoints(parent); f:SetFrameLevel((parent:GetFrameLevel() or 1) + 20) end
  local src = index and m.customSeq and m.customSeq[index]
  f.index = src and index or nil
  f.draft = { id = src and src.id or nil, name = src and src.name or "My macro", kind = src and ((src.kind == "priority" and #src.steps == 1) and "single" or src.kind) or "sequence",
    aim = src and src.aim or "harm", steps = {}, filler = src and src.filler or "", fills = src and src.fills or 2,
    reset = src and src.reset or "combat" }
  for i, s in ipairs(src and src.steps or {}) do f.draft.steps[i] = s end
  f.draft.preset = index and src and KE.presetOf(index, src.aim) or "enemy"
  f.choice:SetShown(f.index == nil) -- a new macro starts with the choice
  f.name:SetText(f.draft.name)
  f.title:SetText(f.index and ("Edit own macro " .. f.index) or "New macro")
  f.delete:SetShown(f.index ~= nil)
  f.targeting:SetShown(false); f.save:Hide(); f.cancel:Hide()
  f.targeting:SetEnabled(f.index ~= nil); f.textBtn:SetEnabled(f.index ~= nil)
  f.delete.armed = false; W.setLabel(f.delete, "Delete macro")
  f:Show()
  KE.Refresh()
end
function KE.Close()
  if KE.frame then KE.frame:Hide(); KE.frame.draft = nil end
  if ns.Advanced and ns.Advanced.ef then ns.Advanced.ef:Hide() end
end
--- Save the draft (the Macro editor's Save). Returns the own macro's index or nil, reason.
function KE.commit()
  local f = KE.frame
  local _, m = Core().me()
  if not (f and f.draft and m) then return nil, "Nothing to save." end
  local idx, err = KE.save(m, f.draft, f.index)
  if not idx then return nil, err end
  KE.applyPreset(idx, f.draft.preset)
  f.index = idx
  Core().log("info", "own macro: C" .. idx .. " saved as " .. tostring(m.customSeq[idx] and m.customSeq[idx].name) .. " (" .. tostring(m.customSeq[idx] and m.customSeq[idx].kind) .. ")")
  return idx
end
function KE.IsOpen() return KE.frame ~= nil and KE.frame:IsShown() end

function KE.Refresh()
  local f = KE.frame
  if not f or not f:IsShown() or not f.draft then return end
  local _, m = Core().me()
  if not m then return end
  local L = ns.Compat.playerLevel()
  local d = f.draft
  f.kind.Refresh(); f.aim.Refresh(); f.reset.Refresh(); f.fills.Refresh(); f.preset.Refresh()
  local seq = d.kind == "sequence"
  f.reset:SetShown(seq); f.fills:SetShown(seq)
  local byName = {}
  for _, s in ipairs(ns.Kit.spellsOf(m)) do byName[s.name] = byName[s.name] or s end
  for i, b in ipairs(f.stepBtns) do
    local n = d.steps[i]
    b.i = i
    if n then W.setIcon(b.icon, byName[n] and byName[n].icon or nil); b:Show() else b:Hide() end
  end
  f.fillerText:SetText(seq and ((d.filler ~= "" and ("Filler: |cffffd100" .. d.filler .. "|r ×" .. d.fills)) or "|cff9d9d9dNo filler|r")
    or "Top spell first")
  -- picker
  f.pickPool:reset()
  local inKey = {}
  for _, n in ipairs(d.steps) do inKey[n] = true end
  if d.filler ~= "" then inKey[d.filler] = true end
  local y = 0
  for _, s in ipairs(KE.spellChoices(m, L)) do
    local r = f.pickPool:get()
    r.spell, r.inKey = s, inKey[s.name] or false
    r:SetPoint("TOPLEFT", 0, -y)
    y = y + 23
    W.setIcon(r.icon, s.icon)
    r.name:SetText(s.name)
    local c = r.inKey and W.GOLD or W.TEXT
    r.name:SetTextColor(c[1], c[2], c[3])
    r.check:SetShown(r.inKey)
    r.fill:SetShown(seq)
  end
  f.pick:SetHeight(math.max(y, 10))
  W.tidyScroll(f.pickSf, y)
  -- preview
  local r, warn = KE.preview(m, d, L)
  if r.kind == "empty" then f.body:SetText("|cff9d9d9dAdd spells|r"); f.info:SetText(""); f.infoTip = nil
  else
    f.body:SetText(r.macro)
    f.info:SetText((r.tooLong and "|cffff8a80" or "") .. #r.macro .. "/255" .. (r.tooLong and "|r" or ""))
    f.infoTip = #r.macro .. " of 255 characters." .. (r.compact and " Shortened to fit." or "") .. (r.tooLong and " Too long: remove a step." or "")
  end
  local th = f.body:GetStringHeight() or 10
  f.macroContent:SetHeight(math.max(10, math.ceil(th)))
  W.tidyScroll(f.macroSf, th)
  f.warnList = warn
  local short = {}
  for i, w in ipairs(warn) do if i <= 2 then short[#short + 1] = KE.shortWarning(w) end end
  if #warn > 2 then short[2] = short[2] .. " (+" .. (#warn - 2) .. ")" end
  f.warn:SetText(table.concat(short, "\n"))
  f.warnFull = table.concat(warn, "\n")
  f.warnIcon:SetShown(#warn > 0)
  f.save:SetEnabled(#d.steps > 0 or (seq and d.filler ~= ""))
end

return KE
