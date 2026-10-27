--[[ WoWBoxer – the sequence strip on the action bars (docs/squad-overhaul.md §1.2). A macro has one icon, so on every
  visible Blizzard action button that holds a WBX sequence or priority key WoWBoxer draws a thin strip of its steps as
  mini icons along the bottom edge, frames the step that comes next, and puts a small "SEQ"/"PRI" badge in the corner.
  Purely visual: our own frames with textures, anchored to the button. It never changes the button's scripts or
  attributes, never clicks, casts or targets. Anchors change only out of combat; in combat it only updates which step
  is framed (QueryCastSequence / GetMacroSpell, when the client has them) and hides a strip whose button changed page.
  Updates come from events (cast succeeded, target, combat, bar changes), coalesced to one update per THROTTLE seconds.
  No Blizzard button visible for the slot (bar addons, hidden bar) = no strip. Setting: Setup > "Sequence strip". ]]
local _, ns = ...
local SS = {}
ns.SeqStrip = SS

SS.THROTTLE = 0.2
SS.MAX = 4
SS.strips = {}   -- button -> strip frame
local G = _G
local SLOTS = {}
for s = 1, 120 do SLOTS[#SLOTS + 1] = s end
for s = 145, 180 do SLOTS[#SLOTS + 1] = s end

function SS.enabled()
  local st = ns.Core.db and ns.Core.db.settings
  return not (st and st.seqStrip == false)
end

-- ------------------------------------------------------------------ what the bars hold
local function macroNameAt(slot)
  if G.GetActionText then
    local ok, t = pcall(G.GetActionText, slot)
    t = ok and ns.Compat.safe(t) or nil
    if type(t) == "string" and t ~= "" then return t end
  end
  if not G.GetActionInfo then return nil end
  local ok, kind, id = pcall(G.GetActionInfo, slot)
  if not ok or kind ~= "macro" or not id then return nil end
  return (ns.Compat.macroInfo(id))
end

--- The castsequence list of a macro body ("A, B, B"), without conditions; nil for other macros.
function SS.sequenceText(body)
  local rest = (body or ""):match("/castsequence ([^\n]+)")
  if not rest then return nil end
  rest = rest:gsub("^%b[]", ""):gsub("^%s*%b[]", ""):gsub("^%s*%b[]", ""):gsub("^%s*%b[]", ""):gsub("^%s+", "")
  return rest
end

--- Which step (index into d.steps) comes next, or nil when the client cannot tell.
function SS.nextStep(d)
  if not (d and d.steps) then return nil end
  if d.seq and d.seq.base == "sequence" then
    local text = SS.sequenceText(d.body)
    if text and G.QueryCastSequence then
      local ok, index = pcall(G.QueryCastSequence, text)
      index = ok and tonumber(ns.Compat.safe(index)) or nil
      if index and index >= 1 and index <= #d.steps then return index end
    end
    return nil
  end
  -- priority: the spell the macro would cast right now
  if G.GetMacroSpell then
    local idx = ns.Macros.findIndex(d.name)
    if not idx then return nil end
    local ok, a = pcall(G.GetMacroSpell, idx)
    a = ok and ns.Compat.safe(a) or nil
    if a == nil then return nil end
    for i, s in ipairs(d.steps) do
      if s.name == a then return i end
      for _, r in ipairs(s.ranks or {}) do if r.id == a then return i end end
    end
  end
  return nil
end

-- ------------------------------------------------------------------ one strip
local function newStrip()
  local o = CreateFrame("Frame", nil, UIParent)
  o.bg = o:CreateTexture(nil, "BACKGROUND")
  o.bg:SetColorTexture(0, 0, 0, 0.6)
  o.icons = {}
  for i = 1, SS.MAX do
    local t = o:CreateTexture(nil, "ARTWORK")
    if t.SetTexCoord then t:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
    o.icons[i] = t
  end
  o.mark = {}
  for i = 1, 4 do
    local t = o:CreateTexture(nil, "OVERLAY")
    t:SetColorTexture(1, 0.82, 0, 1)
    o.mark[i] = t
  end
  o.badgeBg = o:CreateTexture(nil, "OVERLAY")
  o.badgeBg:SetColorTexture(0.32, 0.2, 0.52, 0.9)
  o.badge = o:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  if o.badge.SetFont then local file, _, flags = o.badge:GetFont(); if file then o.badge:SetFont(file, 8, flags) end end
  o.badge:SetTextColor(0.9, 0.8, 1)
  o.badge:SetPoint("TOPLEFT", 2, -2)
  o.badgeBg:SetPoint("TOPLEFT", o.badge, "TOPLEFT", -1, 1)
  o.badgeBg:SetPoint("BOTTOMRIGHT", o.badge, "BOTTOMRIGHT", 1, -1)
  return o
end

--- Lay the strip out on its button (out of combat only: anchors).
local function place(o, btn)
  o:ClearAllPoints()
  o:SetAllPoints(btn)
  if o.SetFrameStrata and btn.GetFrameStrata then o:SetFrameStrata(btn:GetFrameStrata() or "MEDIUM") end
  if o.SetFrameLevel and btn.GetFrameLevel then o:SetFrameLevel((btn:GetFrameLevel() or 1) + 6) end
  local w = btn:GetWidth() or 36
  local size = math.max(6, math.floor((w - 4) / SS.MAX) - 1)
  o.size = size
  o.bg:ClearAllPoints()
  o.bg:SetPoint("BOTTOMLEFT", 1, 1)
  o.bg:SetPoint("BOTTOMRIGHT", -1, 1)
  o.bg:SetHeight(size + 2)
  for i, t in ipairs(o.icons) do
    t:ClearAllPoints()
    t:SetSize(size, size)
    t:SetPoint("BOTTOMLEFT", 2 + (i - 1) * (size + 1), 2)
  end
end

--- Pictures + the frame around the next step (safe in combat: textures only).
local function paint(o)
  local d = o.d
  local steps = d.steps or {}
  local nxt = SS.nextStep(d)
  local first = (nxt and nxt > SS.MAX) and (nxt - SS.MAX + 1) or 1
  for i, t in ipairs(o.icons) do
    local s = steps[first + i - 1]
    if s then ns.Widgets.setIcon(t, s.icon); t:Show() else t:Hide() end
  end
  local at = nxt and (nxt - first + 1) or nil
  o.next = nxt
  for _, m in ipairs(o.mark) do m:SetShown(at ~= nil) end
  if at then
    local icon = o.icons[at]
    local M = o.mark
    M[1]:ClearAllPoints(); M[1]:SetPoint("BOTTOMLEFT", icon, "TOPLEFT", -1, 0); M[1]:SetPoint("BOTTOMRIGHT", icon, "TOPRIGHT", 1, 0); M[1]:SetHeight(1)
    M[2]:ClearAllPoints(); M[2]:SetPoint("TOPLEFT", icon, "BOTTOMLEFT", -1, 0); M[2]:SetPoint("TOPRIGHT", icon, "BOTTOMRIGHT", 1, 0); M[2]:SetHeight(1)
    M[3]:ClearAllPoints(); M[3]:SetPoint("TOPRIGHT", icon, "TOPLEFT", 0, 1); M[3]:SetPoint("BOTTOMRIGHT", icon, "BOTTOMLEFT", 0, -1); M[3]:SetWidth(1)
    M[4]:ClearAllPoints(); M[4]:SetPoint("TOPLEFT", icon, "TOPRIGHT", 0, 1); M[4]:SetPoint("BOTTOMLEFT", icon, "BOTTOMRIGHT", 0, -1); M[4]:SetWidth(1)
  end
  o.badge:SetText(d.seq and d.seq.base == "priority" and "PRI" or "SEQ")
end

-- ------------------------------------------------------------------ update
--- The WBX sequence/priority keys of this character (re-computed only when SS.dirty: macros, spells, level, settings).
SS.dirty, SS.dirtyAt = true, -1
local cache = {}
function SS.markDirty() SS.dirty, SS.dirtyAt = true, ns.Core.ctxGen or 0 end
local function seqKeys()
  if not SS.dirty then return cache end
  SS.dirty = false
  local Core = ns.Core
  -- a plan computed after the change (the window refresh) is reused instead of computing again
  local ctx = ((Core.ctxGen or 0) > SS.dirtyAt and Core.lastCtx) or Core.compute()
  local out = {}
  cache = out
  if not ctx then return out end
  for _, d in ipairs(ctx.desired) do
    if d.seq and d.steps and #d.steps > 1 and d.seq.kind ~= "single" then out[d.name] = d end
  end
  return out
end

function SS.hideAll() for _, o in pairs(SS.strips) do o:Hide() end end

--- Full scan: which buttons hold a sequence key now (out of combat: may anchor new strips).
function SS.scan()
  SS.scans = (SS.scans or 0) + 1
  if not SS.enabled() then SS.hideAll(); return 0 end
  local keys = seqKeys()
  local used, n = {}, 0
  if next(keys) then
    for _, slot in ipairs(SLOTS) do
      local name = macroNameAt(slot)
      local d = name and keys[name]
      local btn = d and ns.Fly.buttonForSlot(slot)
      if btn and not used[btn] then
        local o = SS.strips[btn]
        if not o and not ns.Compat.inCombat() then o = newStrip(); SS.strips[btn] = o end
        if o then
          if not ns.Compat.inCombat() then place(o, btn) end
          o.d, o.slot, o.btn = d, slot, btn
          paint(o)
          o:Show()
          used[btn] = true
          n = n + 1
        end
      end
    end
  end
  for btn, o in pairs(SS.strips) do if not used[btn] then o:Hide() end end
  SS.shown = n
  return n
end

--- In combat: keep strips whose button still shows their slot, refresh the next step.
function SS.paintAll()
  for btn, o in pairs(SS.strips) do
    if o:IsShown() then
      if ns.Fly.buttonForSlot(o.slot) ~= btn then o:Hide() else paint(o) end
    end
  end
end

function SS.update()
  SS.pending = false
  SS.updates = (SS.updates or 0) + 1
  if ns.Compat.inCombat() then SS.paintAll() else SS.scan() end
end

--- Coalesce bursts of events into one update after THROTTLE seconds.
function SS.request()
  if SS.pending then return end
  SS.pending = true
  if G.C_Timer and G.C_Timer.After then G.C_Timer.After(SS.THROTTLE, SS.update) else SS.update() end
end

local f = CreateFrame("Frame")
SS.frame = f
function SS.Init()
  for _, ev in ipairs({ "PLAYER_ENTERING_WORLD", "ACTIONBAR_SLOT_CHANGED", "ACTIONBAR_PAGE_CHANGED", "UPDATE_BONUS_ACTIONBAR",
    "UPDATE_MACROS", "SPELLS_CHANGED", "PLAYER_LEVEL_UP", "PLAYER_TARGET_CHANGED", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED", "UNIT_SPELLCAST_SUCCEEDED" }) do
    pcall(f.RegisterEvent, f, ev)
  end
  SS.request()
end
f:SetScript("OnEvent", function(_, event, unit)
  if event == "UNIT_SPELLCAST_SUCCEEDED" and unit ~= "player" then return end
  if event == "UPDATE_MACROS" or event == "SPELLS_CHANGED" or event == "PLAYER_LEVEL_UP" then SS.markDirty() end
  SS.request()
end)

return SS
