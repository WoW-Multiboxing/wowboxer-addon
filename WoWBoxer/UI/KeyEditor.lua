--[[ WoWBoxer – custom key editor (the companion's "own keys", in game).
  A custom key is plain data {name, kind, aim, steps, filler, fills, reset}; the companion engine builds the macro
  (E.buildCustom) with the same targeting, pet, 255-character and warning rules as on the website. Spells are added
  from a list of learned spells or by dropping a spell from the spellbook onto the steps strip (GetCursorInfo: data
  only, nothing is cast). Saving only changes SavedVariables; the macro WBX C<n> is written by Place all
  or by dragging the key, like every other key. ]]
local _, ns = ...
local UI, W = ns.UI, ns.Widgets
local KE = {}
ns.KeyEditor = KE

local MAX_STEPS = 12
local KINDS = { { "sequence", "Sequence (/castsequence)" }, { "priority", "Priority list" } }
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
function KE.preview(m, c, L)
  local ctx = ns.Kit.memberCtx(m)
  local has = ns.Kit.seqHas(m, L, nil)
  local r = E().buildCustom(m.cls, c, ctx, has, { melee = ns.Kit.isMelee(m) })
  local sp = {}
  for _, n in ipairs(c.steps or {}) do local s = has(n); if s then sp[#sp + 1] = s end end
  local filler = (c.kind == "sequence" and c.filler and c.filler ~= "") and has(c.filler) or nil
  local warn = E().customWarnings(c.kind, sp, filler, c.aim, m.cls)
  return r, warn
end

--- Save a draft into the member's custom keys (index = nil adds a new one). Returns index or nil, reason.
function KE.save(m, c, index)
  local list = m.customSeq or {}
  if not index and #list >= ns.State.CUSTOM_MAX then return nil, "At most " .. ns.State.CUSTOM_MAX .. " own keys." end
  if #(c.steps or {}) == 0 and (c.filler or "") == "" then return nil, "Add at least one spell." end
  local copy = {}
  for i, v in ipairs(list) do copy[i] = v end
  copy[index or (#copy + 1)] = c
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

function KE.Build(parent)
  if KE.frame then return KE.frame end
  local f = W.box(parent, 0.1, 0.078, 0.055, 0.99)
  f:SetAllPoints()
  f:SetFrameLevel((parent:GetFrameLevel() or 1) + 20)
  f:EnableMouse(true)
  f.wbxModal = true
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
  W.ddTip(f.aim, "Aim", "Who the key casts on: an enemy (your or the leader's target) or a friend.")
  W.ddTip(f.reset, "Starts over", "When the sequence starts again from the first step.")
  W.ddTip(f.fills, "Filler", "How many times the filler spell is cast between the other steps.")

  -- steps strip: icons in order; click removes; drop a spell from the spellbook to add it
  local sl = W.text(f, "GameFontHighlightSmall", nil, W.MUTED)
  sl:SetPoint("TOPLEFT", 10, -112)
  sl:SetText("Steps (click to remove, drop spells here)")
  f.strip = W.box(f, 0.05, 0.04, 0.025, 0.95)
  f.strip:SetPoint("TOPLEFT", 10, -128)
  f.strip:SetSize(312, 34)
  f.strip:EnableMouse(true)
  local function drop()
    local name = spellFromCursor()
    if not name then return end
    ClearCursor()
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
  f.fillerText = W.text(f, "GameFontHighlightSmall", nil, W.TEXT)
  f.fillerText:SetPoint("TOPLEFT", f.strip, "BOTTOMLEFT", 0, -6)
  f.fillerText:SetWidth(312)

  -- spell picker (right)
  local pl = W.text(f, "GameFontNormal", nil, W.GOLD)
  pl:SetPoint("TOPLEFT", 340, -10)
  pl:SetText("Your spells")
  local sf, content = W.scroll(f, 250, 176)
  sf:SetPoint("TOPLEFT", 340, -30)
  f.pick = content
  f.pickPool = W.pool(content, function(par)
    local r = CreateFrame("Frame", nil, par)
    r:SetSize(246, 22)
    r.icon = W.icon(r, 18)
    r.icon:SetPoint("LEFT", 2, 0)
    r.fill = W.button(r, "Filler", 48, 18, function() f.draft.filler = r.spell.name; KE.Refresh() end,
      "Makes this spell the filler: it is cast between the steps (sequence keys only).")
    r.fill:SetPoint("RIGHT", 0, 0)
    r.add = W.button(r, "Add", 44, 18, function() KE.addStep(r.spell.name) end, "Adds this spell as the next step of the key.")
    r.add:SetPoint("RIGHT", r.fill, "LEFT", -4, 0)
    r.name = W.line(r, "GameFontHighlightSmall", nil, W.TEXT)
    r.name:SetPoint("LEFT", 24, 0)
    r.name:SetPoint("RIGHT", r.add, "LEFT", -4, 0)
    W.tooltip(r, function(GT) GT:AddLine(r.spell and r.spell.name or "", 1, 0.82, 0) end)
    return r
  end)

  -- preview + warnings
  local pv = W.box(f, 0.05, 0.04, 0.025, 0.95)
  pv:SetPoint("TOPLEFT", 10, -196)
  pv:SetSize(312, 86)
  f.body = W.text(pv, "GameFontHighlightSmall", 10, { 0.85, 0.94, 0.75 })
  f.body:SetPoint("TOPLEFT", 6, -6)
  f.body:SetPoint("BOTTOMRIGHT", -6, 6)
  f.body:SetJustifyV("TOP")
  f.info = W.text(f, "GameFontHighlightSmall", nil, W.MUTED)
  f.info:SetPoint("TOPLEFT", pv, "BOTTOMLEFT", 2, -4)
  f.info:SetWidth(310)
  f.warn = W.text(f, "GameFontHighlightSmall", nil, W.ORANGE)
  f.warn:SetPoint("TOPLEFT", 340, -214)
  f.warn:SetWidth(270)
  f.warn:SetJustifyV("TOP")

  f.save = W.button(f, "Save key", 100, 24, function()
    local _, m = Core().me()
    if not m then return end
    local idx, err = KE.save(m, f.draft, f.index)
    if not idx then Core().print("|cffff8a80" .. err .. "|r"); return end
    Core().log("info", "custom key C" .. idx .. " saved: " .. tostring(m.customSeq[idx] and m.customSeq[idx].name))
    KE.Close()
    if UI.panels and UI.panels.custom then UI.panels.custom.selected = "WBX C" .. idx end
    Core().changed()
  end, "Saves this own key. It is created in the game when you place it or press Place all.")
  f.save:SetPoint("BOTTOMRIGHT", -10, 8)
  f.cancel = W.button(f, "Cancel", 80, 24, function() KE.Close() end, "Closes the editor without saving.")
  f.cancel:SetPoint("RIGHT", f.save, "LEFT", -6, 0)
  f.delete = W.button(f, "Delete key", 90, 24, function(self)
    if not self.armed then self.armed = true; W.setLabel(self, "Sure?"); return end
    local _, m = Core().me()
    if m and f.index then KE.delete(m, f.index); Core().log("info", "custom key C" .. f.index .. " deleted") end
    KE.Close(); Core().changed()
  end, "Deletes this own key from WoWBoxer (click twice). The game macro is removed the next time you update your keys.")
  f.delete:SetPoint("BOTTOMLEFT", 10, 8)
  return f
end

function KE.addStep(name)
  local f = KE.frame
  if not f or not f.draft then return end
  if #f.draft.steps >= MAX_STEPS then Core().print("A key holds at most " .. MAX_STEPS .. " steps."); return end
  local _, m = Core().me()
  local known = false
  for _, s in ipairs(ns.Kit.spellsOf(m)) do if s.name == name then known = true end end
  if not known then Core().print("|cffff8a80" .. tostring(name) .. " is not in WoWBoxer's spell list for your class.|r"); return end
  f.draft.steps[#f.draft.steps + 1] = name
  KE.Refresh()
end

--- Open the editor for custom key `index` of this character (nil = new key).
function KE.Open(parent, index)
  local _, m = Core().me()
  if not m then return end
  local f = KE.Build(parent)
  if f:GetParent() ~= parent then f:SetParent(parent); f:ClearAllPoints(); f:SetAllPoints(parent); f:SetFrameLevel((parent:GetFrameLevel() or 1) + 20) end
  local src = index and m.customSeq and m.customSeq[index]
  f.index = src and index or nil
  f.draft = { id = src and src.id or nil, name = src and src.name or "My key", kind = src and src.kind or "sequence",
    aim = src and src.aim or "harm", steps = {}, filler = src and src.filler or "", fills = src and src.fills or 2,
    reset = src and src.reset or "combat" }
  for i, s in ipairs(src and src.steps or {}) do f.draft.steps[i] = s end
  f.name:SetText(f.draft.name)
  f.title:SetText(f.index and ("Edit own key " .. f.index) or "New own key")
  f.delete:SetShown(f.index ~= nil)
  f.delete.armed = false; W.setLabel(f.delete, "Delete key")
  f:Show()
  KE.Refresh()
end
function KE.Close() if KE.frame then KE.frame:Hide(); KE.frame.draft = nil end end
function KE.IsOpen() return KE.frame ~= nil and KE.frame:IsShown() end

function KE.Refresh()
  local f = KE.frame
  if not f or not f:IsShown() or not f.draft then return end
  local _, m = Core().me()
  if not m then return end
  local L = ns.Compat.playerLevel()
  local d = f.draft
  f.kind.Refresh(); f.aim.Refresh(); f.reset.Refresh(); f.fills.Refresh()
  local seq = d.kind == "sequence"
  f.reset:SetShown(seq); f.fills:SetShown(seq)
  local byName = {}
  for _, s in ipairs(ns.Kit.spellsOf(m)) do byName[s.name] = byName[s.name] or s end
  for i, b in ipairs(f.stepBtns) do
    local n = d.steps[i]
    b.i = i
    if n then W.setIcon(b.icon, byName[n] and byName[n].icon or nil); b:Show() else b:Hide() end
  end
  f.fillerText:SetText(seq and ("Filler: " .. ((d.filler ~= "" and ("|cffffd100" .. d.filler .. "|r")) or "|cff9d9d9dnone – pick one with Filler|r") ..
    "  ·  repeated " .. d.fills .. "×") or "Priority list: highest first, one /cast line per spell.")
  -- picker
  f.pickPool:reset()
  local y = 0
  for _, s in ipairs(KE.spellChoices(m, L)) do
    local r = f.pickPool:get()
    r.spell = s
    r:SetPoint("TOPLEFT", 0, -y)
    y = y + 23
    W.setIcon(r.icon, s.icon)
    r.name:SetText(s.name)
    r.fill:SetShown(seq)
  end
  f.pick:SetHeight(math.max(y, 10))
  -- preview
  local r, warn = KE.preview(m, d, L)
  if r.kind == "empty" then f.body:SetText("|cff9d9d9d(add spells: the macro appears here)|r"); f.info:SetText("")
  else
    f.body:SetText(r.macro)
    f.info:SetText(#r.macro .. " / 255 characters" .. (r.compact and " · shortened to fit" or "") .. (r.tooLong and " |cffff8a80too long|r" or ""))
  end
  f.warn:SetText(#warn > 0 and table.concat(warn, "\n") or "|cff8fbf6aNo warnings.|r")
  f.save:SetEnabled(#d.steps > 0 or (seq and d.filler ~= ""))
end

return KE
