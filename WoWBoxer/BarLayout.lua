--[[ WoWBoxer – lays the bottom action bars out for THIS window through Edit Mode (owner 12 Nov 2026, test.11).

  Why: test.9/10 scaled and moved Blizzard's bar frames themselves. On Forever (and Classic Era 1.15.9) those frames
  belong to Edit Mode: it puts them back on every bar refresh, the XP bar lost its width and the rows ended on top of
  each other (owner's screenshots 12 Nov 11:10). So the bars are not moved by hand any more. WoWBoxer writes an Edit
  Mode layout of its own for this character – each window is one character – and lets Edit Mode apply it, exactly as
  if the player had set it up in Edit Mode: Blizzard's own buttons (keybinds, macros and action slots unchanged),
  Blizzard's own art (end caps, XP and reputation bar), Blizzard's own vehicle, possess and override bars.

  The layout ("WoWBoxer", a Character layout) is a copy of the layout that was active, with only the bottom group
  changed: bar 1, the bottom-left and bottom-right bars, the stance and pet bars, the micro menu, the bags and the XP
  and reputation bars. For this window's width (UIParent in UI units, i.e. GetScreenWidth at the current UI scale)
  it picks the arrangement and icon size that fit:
    2 rows (the default look): bar 1 + menu + bags, the XP bar, bar 2 + bar 3
    3 rows: bar 1 + menu + bags, the XP bar, bar 2, bar 3
    4 rows: menu + bags, bar 1, the XP bar, bar 2, bar 3
  at the largest icon size Edit Mode offers (100 % down to the smallest setting, 10 % steps), fewest rows first on a
  tie. The XP and reputation bars are sized to the button area (Edit Mode's bar size, 5 % steps). The stance and pet
  bars sit above the top row. Nothing goes onto the chat, the unit frames or the side bars, and nothing above 45 % of
  the window height. Nothing fits even at the smallest size: the layout is left alone, one chat line says so.

  Applying: C_EditMode.SaveLayouts (+ SetActiveLayout the first time), then Edit Mode is opened and closed through
  ShowUIPanel/HideUIPanel, so Blizzard's own secure code applies the saved layout (the same way LibEditModeOverride
  applies layouts). Only out of combat, never while Edit Mode is open, never with Bartender4/Dominos/ElvUI etc.
  Turning the setting off makes the layout that was active before active again and deletes ours: the default layout
  comes back exactly. If the player picks another layout in Edit Mode, WoWBoxer leaves it alone (paused).
  [AFKLAR: Forever's Edit Mode accepts a saved Character layout from an addon and applies it on the open/close; the
  bar widths match Blizzard's grid (buttons × icon size + padding); no "blocked action" from the apply – checked in
  the owner's test build. The setting ranges are Blizzard's EditModeSettingDisplayInfo (classic_era/live, Oct 2026).] ]]
local _, ns = ...
local BL = {}
ns.BarLayout = BL

BL.NAME = "WoWBoxer"
BL.MARGIN, BL.GAP, BL.ROW_GAP, BL.BASE_Y = 4, 4, 4, 2
BL.TOP_SHARE = 0.45
--- Edit Mode's slider ranges (min, max, step): stored value = (percent - min) / step
BL.RANGE = { icon = { 50, 200, 10 }, micro = { 70, 200, 5 }, bags = { 75, 200, 5 }, status = { 50, 130, 5 } }
BL.MAX_CHARACTER_LAYOUTS = 5
BL.ARRANGEMENTS = {
  { name = "2 rows", rows = 2, layout = { { "bar1", "micro", "bags" }, "status", { "bar2", "bar3" } } },
  { name = "3 rows", rows = 3, layout = { { "bar1", "micro", "bags" }, "status", { "bar2" }, { "bar3" } } },
  { name = "4 rows", rows = 4, layout = { { "micro", "bags" }, { "bar1" }, "status", { "bar2" }, { "bar3" } } },
}
BL.OBSTACLE_NAMES = { "ChatFrame1", "PlayerFrame", "TargetFrame", "FocusFrame", "PartyFrame", "CompactPartyFrame",
  "PartyMemberFrame1", "MultiBarRight", "MultiBarLeft", "MultiBar5", "MultiBar6", "MultiBar7" }

local function G() return _G end
local function num(v) return type(v) == "number" and v == v and v or nil end
local function Core() return ns.Core end
local function log(level, msg) local c = Core(); if c and c.log then c.log(level, msg) end end
local function eff(f) return num(f and f.GetEffectiveScale and f:GetEffectiveScale()) or 1 end
local function round(v, d) local m = 10 ^ (d or 1); return math.floor(v * m + 0.5) / m end

local function copy(t)
  if type(t) ~= "table" then return t end
  local o = {}
  for k, v in pairs(t) do o[k] = copy(v) end
  return o
end

--- Is Edit Mode there to work with? (both games since Oct 2026; probed, never assumed)
function BL.available()
  local g = G()
  local C, E, M = g.C_EditMode, g.Enum, g.EditModeManagerFrame
  return type(C) == "table" and type(C.GetLayouts) == "function" and type(C.SaveLayouts) == "function"
    and type(E) == "table" and type(E.EditModeSystem) == "table" and type(E.EditModeActionBarSystemIndices) == "table"
    and type(M) == "table" and type(M.registeredSystemFrames) == "table"
    and type(g.ShowUIPanel) == "function" and type(g.HideUIPanel) == "function" or false
end

-- the systems we lay out: key -> system, system index (nil for systems that have one frame)
local function systems()
  local E = G().Enum
  local S, A = E.EditModeSystem, E.EditModeActionBarSystemIndices
  local T = E.EditModeStatusTrackingBarSystemIndices or { StatusTrackingBar1 = 1, StatusTrackingBar2 = 2 }
  return {
    bar1 = { S.ActionBar, A.MainBar, kind = "bar" }, bar2 = { S.ActionBar, A.Bar2, kind = "bar" },
    bar3 = { S.ActionBar, A.Bar3, kind = "bar" }, stance = { S.ActionBar, A.StanceBar, kind = "bar" },
    pet = { S.ActionBar, A.PetActionBar, kind = "bar" }, micro = { S.MicroMenu, nil, kind = "micro" },
    bags = { S.Bags, nil, kind = "bags" }, xp = { S.StatusTrackingBar, T.StatusTrackingBar1, kind = "status" },
    rep = { S.StatusTrackingBar, T.StatusTrackingBar2, kind = "status" },
  }
end
BL.KEYS = { "bar1", "bar2", "bar3", "stance", "pet", "micro", "bags", "xp", "rep" }

local function frameFor(sys, idx)
  local list = G().EditModeManagerFrame.registeredSystemFrames
  for _, f in ipairs(list) do
    if type(f) == "table" and f.system == sys and (idx == nil or f.systemIndex == idx) then return f end
  end
  return nil
end
local function systemInfo(layout, sys, idx)
  for _, s in ipairs(layout and layout.systems or {}) do
    if s.system == sys and (idx == nil or s.systemIndex == idx) then return s end
  end
  return nil
end
local function settingOf(info, setting)
  for _, x in ipairs(info and info.settings or {}) do if x.setting == setting then return x.value end end
  return nil
end
local function setSetting(info, setting, value)
  for _, x in ipairs(info.settings) do if x.setting == setting then x.value = value; return end end
  info.settings[#info.settings + 1] = { setting = setting, value = value }
end
function BL.toValue(range, pct) return math.floor((pct - range[1]) / range[3] + 0.5) end
function BL.toPct(range, value) return range[1] + (num(value) or 0) * range[3] end

--- The layouts the way Blizzard indexes them: the presets first, then the saved ones (activeLayout counts the presets).
function BL.layouts()
  local g = G()
  local ok, info = pcall(g.C_EditMode.GetLayouts)
  if not ok or type(info) ~= "table" or type(info.layouts) ~= "table" then return nil end
  local all = {}
  local P = g.EditModePresetLayoutManager
  if type(P) == "table" and type(P.GetCopyOfPresetLayouts) == "function" then
    local ok2, presets = pcall(P.GetCopyOfPresetLayouts, P)
    if ok2 and type(presets) == "table" then for _, l in ipairs(presets) do all[#all + 1] = l end end
  end
  for _, l in ipairs(info.layouts) do all[#all + 1] = l end
  info.layouts = all
  return info
end
local function find(info, name, ltype)
  for i, l in ipairs(info.layouts) do
    if l.layoutName == name and (ltype == nil or l.layoutType == ltype) then return i end
  end
  return nil
end

-- {l, b, r, t} of a frame in UIParent units
local function rectOf(f, ui)
  if type(f) ~= "table" or not f.GetLeft then return nil end
  local l, r, b, t = num(f:GetLeft()), num(f:GetRight()), num(f:GetBottom()), num(f:GetTop())
  if not (l and r and b and t) then return nil end
  local k = eff(f) / ui
  return { l * k, b * k, r * k, t * k }
end
local function hitsUI(a, b) return a[1] < b[3] - 0.5 and b[1] < a[3] - 0.5 and a[2] < b[4] - 0.5 and b[2] < a[4] - 0.5 end
local function shown(f) return type(f) == "table" and f.IsShown and f:IsShown() and true or false end

--- What the bottom group needs, at 100 % (from the frames as they are and the active layout's settings).
--- Returns m = { W, H, ui, items = {key = {w = fn(pct), h = fn(pct), ...}}, obstacles = {rects}, bars = {...} } or nil, why.
function BL.measure()
  local g = G()
  local U = g.UIParent
  if not (U and U.GetWidth) then return nil, "no UIParent" end
  local ui = eff(U)
  local W, H = num(U:GetWidth()) or 0, num(U:GetHeight()) or 0
  local info = BL.layouts()
  if not info then return nil, "no Edit Mode layouts yet" end
  local active = info.layouts[info.activeLayout]
  if not active then return nil, "no active Edit Mode layout" end
  local E = g.Enum
  local AB = E.EditModeActionBarSetting
  local m = { W = W, H = H, ui = ui, items = {}, obstacles = {}, frames = {}, activeName = active.layoutName }
  local sy = systems()
  for _, key in ipairs(BL.KEYS) do
    local d = sy[key]
    local f = d[1] ~= nil and frameFor(d[1], d[2]) or nil
    local si = f and systemInfo(active, d[1], d[2])
    m.frames[key] = f
    if f and si then
      local r = rectOf(f, ui)
      local it = { key = key, kind = d.kind, frame = f, info = si }
      if d.kind == "bar" then
        local pct = BL.toPct(BL.RANGE.icon, settingOf(si, AB.IconSize) or 5)
        local btns = type(f.actionButtons) == "table" and f.actionButtons or {}
        local b1 = btns[1]
        local k = eff(f) / ui
        local bw = (b1 and num(b1.GetWidth and b1:GetWidth()) or 45) * k
        local bh = (b1 and num(b1.GetHeight and b1:GetHeight()) or bw / k) * k
        local n = num(f.numButtonsShowable) or #btns
        if key == "stance" or key == "pet" then
          -- the small bars: only the buttons that are shown (a warrior has 3 stances, a hunter's pet bar 10)
          local c = 0
          for _, b in ipairs(btns) do if b.IsShown and b:IsShown() then c = c + 1 end end
          n = c
        end
        if n < 1 then n = 12 end
        local pad = (num(f.buttonPadding) or num(settingOf(si, AB.IconPadding)) or 2) * k
        local cur = n * bw * pct / 100 + (n - 1) * pad
        local extra = r and math.max(0, (r[3] - r[1]) - cur) or 0
        -- the end caps (gryphons) of bar 1 reach past its buttons; Edit Mode scales them down with the icons
        local caps, capH = 0, 0
        local artOff = settingOf(si, AB.HideBarArt) == 1 and not BL.weHidArt()
        if key == "bar1" and not artOff and type(f.EndCaps) == "table" and type(f.EndCaps.LeftEndCap) == "table" then
          local c = f.EndCaps.LeftEndCap
          caps = math.max(0, ((num(c.GetWidth and c:GetWidth()) or 0) - 28)) * k
          capH = (num(c.GetHeight and c:GetHeight()) or 0) * k
        end
        it.capH = capH
        it.n, it.bw, it.bh, it.pad, it.extra, it.caps, it.pct = n, bw, bh, pad, extra, caps, pct
        it.core = function(p) return n * bw * p / 100 + (n - 1) * pad + extra end
        it.w = function(p, noCaps) return it.core(p) + (noCaps and 0 or 2 * caps * math.min(1, p / 100)) end
        it.h = function(p) return bh * p / 100 end
        it.k = k
        it.on = key == "bar1" or shown(f)
        if key == "stance" then it.on = n > 0 and (shown(f) or (g.GetNumShapeshiftForms and (g.GetNumShapeshiftForms() or 0) > 0)) end
        if key == "pet" then it.on = n > 0 and shown(f) end
      else
        local range = BL.RANGE[d.kind]
        local setting = d.kind == "micro" and E.EditModeMicroMenuSetting and E.EditModeMicroMenuSetting.Size
          or d.kind == "bags" and E.EditModeBagsSetting and E.EditModeBagsSetting.Size
          or d.kind == "status" and E.EditModeStatusTrackingBarSetting and E.EditModeStatusTrackingBarSetting.Size
        local pct = setting and settingOf(si, setting) and BL.toPct(range, settingOf(si, setting)) or 100
        local w100 = r and (r[3] - r[1]) * 100 / pct or 0
        local h100 = r and (r[4] - r[2]) * 100 / pct or 0
        it.setting, it.range, it.pct, it.w100, it.h100 = setting, range, pct, w100, h100
        it.w = function(p) return w100 * p / 100 end
        it.h = function(p) return h100 * p / 100 end
        -- offsets of a frame that is scaled itself (bags, XP bar) are in its own units; the micro menu scales inside
        it.k = eff(f) / ui / (d.kind == "micro" and 1 or pct / 100)
        it.on = shown(f) and w100 > 1
      end
      m.items[key] = it
    end
  end
  if not (m.items.bar1 and m.items.bar1.frame) then return nil, "bar 1 is not an Edit Mode bar here" end
  for _, n in ipairs(BL.OBSTACLE_NAMES) do
    local f = g[n]
    local mine = false
    for _, it in pairs(m.items) do if it.frame == f then mine = true end end
    if not mine and shown(f) and f.IsVisible and f:IsVisible() then
      local r = rectOf(f, ui)
      if r and r[3] - r[1] > 1 and r[4] - r[2] > 1 then m.obstacles[#m.obstacles + 1] = { name = n, r = r } end
    end
  end
  return m
end

local hits = hitsUI

--- Lay the group out in arrangement arr at icon size p (percent). Returns places {key = {x, y, w, h, pct}}, the rects
--- and the widest row, or nil when an item cannot be sized (menu/bags below their smallest size are kept at it).
function BL.place(m, arr, p, noCaps)
  local places, rects, widest, y = {}, {}, 0, BL.BASE_Y
  local b1 = m.items.bar1
  local capW = (not noCaps and b1 and b1.caps or 0) * math.min(1, p / 100)
  local core = 0 -- the widest row of buttons, end caps not counted (the XP bar's width)
  local function sizeOf(key)
    local it = m.items[key]
    if not (it and it.on) then return nil end
    if it.kind == "bar" then return it.w(p, noCaps), it.h(p), p end
    local r = it.range
    local pct = math.max(r[1], math.min(100, math.floor(p / r[3] + 0.5) * r[3]))
    return it.w(pct), it.h(pct), pct
  end
  local rowsOut = {}
  -- the rows of buttons first: their width decides the XP bar's
  for _, row in ipairs(arr.layout) do
    if type(row) == "table" then
      local list, rw, rh = {}, 0, 0
      for _, key in ipairs(row) do
        local w, h, pct = sizeOf(key)
        if w then
          list[#list + 1] = { key = key, w = w, h = h, pct = pct }
          rw = rw + w + (#list > 1 and BL.GAP or 0); rh = math.max(rh, h)
        end
      end
      local hasBar1 = false
      for _, it in ipairs(list) do if it.key == "bar1" then hasBar1 = true end end
      rowsOut[#rowsOut + 1] = { items = list, w = rw, h = rh, bar1 = hasBar1 }
      widest = math.max(widest, rw)
      core = math.max(core, rw - (hasBar1 and 2 * capW or 0))
    else
      rowsOut[#rowsOut + 1] = "status"
    end
  end
  -- the stance and pet bars: one more row on top, from the left edge of the widest row
  local small = {}
  for _, key in ipairs({ "stance", "pet" }) do
    local w, h, pct = sizeOf(key)
    if w then small[#small + 1] = { key = key, w = w, h = h, pct = pct } end
  end
  for _, row in ipairs(rowsOut) do
    if row == "status" then
      for _, key in ipairs({ "xp", "rep" }) do
        local it = m.items[key]
        if it and it.on and it.w100 > 0 then
          local r = it.range
          local pct = math.floor(core / it.w100 * 100 / r[3]) * r[3]
          pct = math.max(r[1], math.min(r[2], pct))
          local w, h = it.w(pct), it.h(pct)
          places[key] = { x = -w / 2, y = y, w = w, h = h, pct = pct }
          rects[#rects + 1] = { -w / 2, y, w / 2, y + h, key = key }
          y = y + h
        end
      end
      y = y + 1
    elseif #row.items > 0 then
      local x = -row.w / 2
      for _, it in ipairs(row.items) do
        -- bar 1's end caps sit outside its buttons: the bar frame starts after the left cap
        local capL = it.key == "bar1" and capW or 0
        places[it.key] = { x = x + capL, y = y, w = it.w - 2 * capL, h = it.h, pct = it.pct }
        rects[#rects + 1] = { x + capL, y, x + it.w - capL, y + it.h, key = it.key }
        if capL > 0 then
          -- the gryphons stand up beside bar 1 (Era): the rows above have to fit between them
          local cs = math.min(1, p / 100)
          local ch = (b1.capH or 0) * cs
          rects[#rects + 1] = { x, y - 3 * cs, x + capL + 28 * cs, y - 3 * cs + ch, key = "caps" }
          rects[#rects + 1] = { x + it.w - capL - 28 * cs, y - 3 * cs, x + it.w, y - 3 * cs + ch, key = "caps" }
        end
        x = x + it.w + BL.GAP
      end
      y = y + row.h + BL.ROW_GAP
    end
  end
  if #small > 0 then
    local sw, rh = 0, 0
    for i, it in ipairs(small) do sw = sw + it.w + (i > 1 and BL.GAP * 2 or 0); rh = math.max(rh, it.h) end
    widest = math.max(widest, sw)
    local x = -widest / 2
    for _, it in ipairs(small) do
      places[it.key] = { x = x, y = y, w = it.w, h = it.h, pct = it.pct }
      rects[#rects + 1] = { x, y, x + it.w, y + it.h, key = it.key }
      x = x + it.w + BL.GAP * 2
    end
    y = y + rh
  end
  -- the rows above may not run into the gryphons
  if capW > 0 then
    for _, c in ipairs(rects) do
      if c.key == "caps" then
        for _, r in ipairs(rects) do
          if r.key ~= "caps" and r.key ~= "bar1" and hitsUI(c, r) then return places, rects, widest, y, true end
        end
      end
    end
  end
  return places, rects, widest, y
end

--- Does a placement fit window W x H (UI units, centre-bottom origin) without touching an obstacle?
function BL.fits(m, rects, widest, top)
  if widest > m.W - 2 * BL.MARGIN then return false, "too wide" end
  if top > m.H * BL.TOP_SHARE then return false, "too high" end
  for _, r in ipairs(rects) do
    local a = { r[1] + m.W / 2, r[2], r[3] + m.W / 2, r[4] }
    for _, o in ipairs(m.obstacles) do
      if hits(a, o.r) then return false, "on " .. o.name end
    end
  end
  return true
end

--- The best layout: the largest icon size, fewest rows on a tie. minPct = the smallest icon size allowed.
function BL.plan(m, minPct)
  minPct = math.max(BL.RANGE.icon[1], minPct or BL.RANGE.icon[1])
  local best, why
  for p = 100, minPct, -BL.RANGE.icon[3] do
    for _, arr in ipairs(BL.ARRANGEMENTS) do
      -- with the gryphons where the rows above fit between them, else without (Edit Mode's "hide bar art")
      for _, noCaps in ipairs({ false, true }) do
        local places, rects, widest, top, capsClash = BL.place(m, arr, p, noCaps)
        if not capsClash then
          local ok, w = BL.fits(m, rects, widest, top)
          if ok then
            best = { arrangement = arr.name, rows = arr.rows, pct = p, places = places, width = widest, top = top,
              hideArt = noCaps and (m.items.bar1.caps or 0) > 0 or nil }
            break
          end
          why = why or w
        end
        if (m.items.bar1.caps or 0) == 0 then break end
      end
      if best then break end
    end
    if best then break end
  end
  if not best then return { mode = "nofit", why = why } end
  best.mode = "layout"
  return best
end

--- Does the game's own (active) layout fit as it is? Uses the bar measurement (BarFit.measure: no button outside the
--- window or on another bar, nothing pushed). Returns fits, the group's width in UI units.
function BL.defaultFits()
  local BF = ns.BarFit
  local ok, m0 = pcall(BF.measure)
  if not ok or not m0 or #m0.bars == 0 then return false end
  local l, r = math.huge, -math.huge
  for _, b in ipairs(m0.bars) do
    if b.key == "main" or b.key == "bottomLeft" or b.key == "bottomRight" or b.key == "menu" then
      l = math.min(l, b.left - b.dx); r = math.max(r, b.right - b.dx)
    end
  end
  local fits = (m0.outside or 0) + (m0.covered or 0) == 0 and not m0.squeezed
  return fits, r > l and (r - l) or nil
end

--- One string for "nothing that decides the layout changed".
function BL.inputs(m)
  local parts = { math.floor(m.W + 0.5), math.floor(m.H + 0.5), math.floor(m.ui * 1000 + 0.5) }
  for _, key in ipairs(BL.KEYS) do
    local it = m.items[key]
    if key ~= "pet" then parts[#parts + 1] = key .. "=" .. (it and it.on and (it.n or 1) or 0) end
  end
  for _, o in ipairs(m.obstacles) do parts[#parts + 1] = o.name .. "@" .. math.floor(o.r[2] + 0.5) .. "/" .. math.floor(o.r[3] + 0.5) end
  return table.concat(parts, ",")
end

--- Write the plan into layout L (our copy): only the bottom group's systems change.
function BL.writeInto(L, m, plan)
  local E = G().Enum
  local AB = E.EditModeActionBarSetting
  for key, pl in pairs(plan.places) do
    local it = m.items[key]
    local si = it and systemInfo(L, it.info.system, it.info.systemIndex)
    if si then
      si.settings = si.settings or {}
      local k = it.k
      if it.kind == "bar" then
        setSetting(si, AB.IconSize, BL.toValue(BL.RANGE.icon, pl.pct))
        if key == "bar1" and (it.caps or 0) > 0 and AB.HideBarArt then
          setSetting(si, AB.HideBarArt, plan.hideArt and 1 or 0)
          BL.setHidArt(plan.hideArt)
        end
        if key == "bar1" or key == "bar2" or key == "bar3" then
          if AB.NumRows then setSetting(si, AB.NumRows, 1) end
          local O = E.ActionBarOrientation
          if AB.Orientation then setSetting(si, AB.Orientation, O and O.Horizontal or 0) end
        end
      elseif it.setting then
        setSetting(si, it.setting, BL.toValue(it.range, pl.pct))
        if it.kind ~= "micro" then k = k * pl.pct / 100 end
      end
      si.anchorInfo = { point = "BOTTOMLEFT", relativeTo = "UIParent", relativePoint = "BOTTOM",
        offsetX = round(pl.x / k, 1), offsetY = round(pl.y / k, 1) }
      si.anchorInfo2 = nil
      si.isInDefaultPosition = false
    end
  end
end

-- Blizzard applies the saved layout itself: Edit Mode opened and closed through the secure panel code
local function applyNow()
  local g = G()
  local M = g.EditModeManagerFrame
  if type(M.CanEnterEditMode) == "function" then
    local okc, can = pcall(M.CanEnterEditMode, M)
    if okc and not can then
      BL.applyLater = true
      log("info", "bar layout: saved; Edit Mode can't open right now – applied on the next check or /reload")
      return false
    end
  end
  BL.applyLater = nil
  if ns.Probe then ns.Probe.note("apply", "Edit Mode apply") end
  BL.applying = true
  local ok, err = pcall(function()
    -- LibEditModeOverride's guard: a tainted dropdown list would taint Edit Mode's own dropdown
    if g.DropDownList1 and g.issecurevariable and g.AddonList and not g.issecurevariable(g.DropDownList1, "numButtons") then
      g.ShowUIPanel(g.AddonList); g.HideUIPanel(g.AddonList)
    end
    g.ShowUIPanel(g.EditModeManagerFrame)
    g.HideUIPanel(g.EditModeManagerFrame)
  end)
  BL.applying = false
  if not ok then log("warn", "bar layout apply: " .. tostring(err)) end
  return ok
end

local function bridge(state)
  local c = Core()
  if not (c and c.db) then return end
  local b = type(c.db.bridge) == "table" and c.db.bridge or {}
  -- the window app's handshake (docs/bridge.md): "addon" = the bars are laid out per window, leave UI Scale alone
  b.barFit = state.on and "addon" or false
  b.barMode = state.mode
  b.barRows = state.rows
  b.barScale = state.pct and state.pct / 100 or nil
  c.db.bridge = b
end

--- The smallest icon size: Edit Mode's own smallest (50 %) unless the player set one (/wbx barfit min N).
function BL.minPct()
  local c = Core()
  local v = tonumber(c and c.cdb and c.cdb.barFitMin)
  return v and math.floor(v * 100 + 0.5) or BL.RANGE.icon[1]
end
function BL.weHidArt() local c = Core(); return c and c.cdb and c.cdb.barLayoutHidArt and true or false end
function BL.setHidArt(on) local c = Core(); if c and c.cdb then c.cdb.barLayoutHidArt = on and true or nil end end
function BL.isPaused() local c = Core(); return c and c.cdb and c.cdb.barLayoutPaused and true or false end
function BL.setPaused(on) local c = Core(); if c and c.cdb then c.cdb.barLayoutPaused = on and true or nil end end

--- Lay the bars out for this window. Returns the state (mode = layout|unchanged|nofit|paused|…).
function BL.fit(reason)
  local c = Core()
  local M = G().EditModeManagerFrame
  if M.layoutInfo == nil and M.accountSettings == nil then
    -- before EDIT_MODE_LAYOUTS_UPDATED at login: Edit Mode has no layouts yet (that event asks again)
    BL.state = { mode = "none", why = "Edit Mode not ready" }
    return BL.state
  end
  local m, why = BL.measure()
  if not m then BL.state = { mode = "none", why = why }; return BL.state end
  local info = BL.layouts()
  local ours = info and find(info, BL.NAME, G().Enum.EditModeLayoutType.Character)
  -- the player picked another layout in Edit Mode: that is his choice, leave it
  if ours and info.activeLayout ~= ours and BL.isPaused() then
    BL.state = { mode = "paused", layout = m.activeName }; bridge({ on = false, mode = "paused" }); return BL.state
  end
  -- the game's own layout fits this window: change nothing (Era keeps its classic main-bar art)
  local ourActive = ours and info.activeLayout == ours
  local winKey = math.floor(m.W + 0.5) .. "x" .. math.floor(m.H + 0.5)
  BL.badAt = BL.badAt or {}
  if not ourActive then
    local fitsAsIs, width = BL.defaultFits()
    if fitsAsIs then
      if c and c.cdb then c.cdb.barLayoutOrigW = width end
      BL.state = { mode = "fits", w = math.floor(m.W + 0.5), h = math.floor(m.H + 0.5) }
      bridge({ on = true, mode = "fits", pct = 100 })
      if BL.lastLine ~= "fits " .. winKey then BL.lastLine = "fits " .. winKey; log("info", "bar layout: the game's layout fits " .. winKey .. " – nothing changed (" .. tostring(reason) .. ")") end
      return BL.state
    end
    BL.badAt[winKey] = true
  else
    local ow = c and c.cdb and tonumber(c.cdb.barLayoutOrigW)
    if ow and ow <= m.W - 2 * BL.MARGIN and not BL.badAt[winKey] then
      -- the window grew: the game's own layout fits again
      BL.off("the game's layout fits " .. winKey)
      return BL.fit(reason)
    end
  end
  local inputs = BL.inputs(m)
  if ours and info.activeLayout == ours and inputs == BL.lastInputs and BL.state and BL.state.mode ~= "none" and not BL.applyLater then
    return BL.state
  end
  local minPct = BL.minPct()
  local plan = BL.plan(m, minPct)
  BL.lastInputs = inputs
  if plan.mode == "nofit" then
    BL.state = { mode = "nofit", why = plan.why, w = math.floor(m.W + 0.5), h = math.floor(m.H + 0.5) }
    bridge({ on = true, mode = "nofit" })
    local key = BL.state.w .. "x" .. BL.state.h
    if BL.hinted ~= key and c then
      BL.hinted = key
      c.print("Your action bars don't fit this window even at the smallest size. Make the window wider, move the chat up or turn off a bar.")
    end
    log("info", string.format("bar layout: nothing fits %dx%d (%s)", BL.state.w, BL.state.h, tostring(plan.why)))
    return BL.state
  end
  local ok, err = BL.save(info, m, plan)
  if not ok then
    BL.state = { mode = "none", why = err }
    log("warn", "bar layout: " .. tostring(err))
    return BL.state
  end
  if err ~= "same" or BL.applyLater then applyNow() end
  BL.state = { mode = "layout", rows = plan.rows, pct = plan.pct, arrangement = plan.arrangement,
    w = math.floor(m.W + 0.5), h = math.floor(m.H + 0.5) }
  bridge({ on = true, mode = "layout", rows = plan.rows, pct = plan.pct })
  log("info", string.format("bar layout: %s at %d %% in %dx%d (%s)", plan.arrangement, plan.pct, BL.state.w, BL.state.h, tostring(reason)))
  BL.diag(m, plan)
  return BL.state
end

--- Save our layout with the plan (created as a copy of the active layout the first time, then made active).
function BL.save(info, m, plan)
  local g = G()
  local LT = g.Enum.EditModeLayoutType
  local c = Core()
  local ours = find(info, BL.NAME, LT.Character)
  local switched = false
  if not ours then
    local src = info.layouts[info.activeLayout]
    if not src then return false, "no active layout" end
    local nChar, lastChar, lastAcc = 0, nil, nil
    for i, l in ipairs(info.layouts) do
      if l.layoutType == LT.Character then nChar = nChar + 1; lastChar = i end
      if l.layoutType == LT.Account then lastAcc = i end
    end
    if nChar >= BL.MAX_CHARACTER_LAYOUTS then return false, "this character has the most Edit Mode layouts already (5)" end
    local L = copy(src)
    L.layoutName, L.layoutType = BL.NAME, LT.Character
    -- where Blizzard puts a new character layout: after the last one, else after the account layouts
    local at = (lastChar or lastAcc or #info.layouts) + 1
    table.insert(info.layouts, at, L)
    if at <= info.activeLayout then info.activeLayout = info.activeLayout + 1 end
    if c and c.cdb then c.cdb.barLayoutPrev = { name = src.layoutName, type = src.layoutType } end
    ours = at
  end
  if info.activeLayout ~= ours then
    local prev = info.layouts[info.activeLayout]
    if c and c.cdb and prev then c.cdb.barLayoutPrev = { name = prev.layoutName, type = prev.layoutType } end
    info.activeLayout = ours
    switched = true
  end
  local before = BL.serialize(info.layouts[ours])
  BL.writeInto(info.layouts[ours], m, plan)
  if not switched and before == BL.serialize(info.layouts[ours]) then BL.wasActive = true; return true, "same" end
  local ok, err = pcall(g.C_EditMode.SaveLayouts, info)
  if not ok then return false, "SaveLayouts: " .. tostring(err) end
  if switched and g.C_EditMode.SetActiveLayout then
    local ok2, err2 = pcall(g.C_EditMode.SetActiveLayout, ours)
    if not ok2 then return false, "SetActiveLayout: " .. tostring(err2) end
  end
  BL.wasActive = true
  return true
end

--- A layout as one string (to see whether writing the plan changed anything).
function BL.serialize(L)
  local out = {}
  local function walk(v, pre)
    if type(v) ~= "table" then out[#out + 1] = pre .. "=" .. tostring(v); return end
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    for _, k in ipairs(keys) do walk(v[k], pre .. "." .. tostring(k)) end
  end
  walk(L, "")
  return table.concat(out, ";")
end

--- Off: the layout that was active before is active again, ours is deleted. Returns true when done (or nothing to do).
function BL.off(reason)
  local g = G()
  if not BL.available() then return true end
  local info = BL.layouts()
  if not info then return true end
  local LT = g.Enum.EditModeLayoutType
  local ours = find(info, BL.NAME, LT.Character)
  BL.lastInputs, BL.wasActive = nil, nil
  BL.setPaused(false)
  BL.setHidArt(false)
  if not ours then return true end
  if ns.Compat.inCombat() then return false end
  local c = Core()
  local prevInfo = c and c.cdb and c.cdb.barLayoutPrev
  local prev = prevInfo and find(info, prevInfo.name, prevInfo.type)
  if not prev or prev == ours then prev = 1 end
  local wasActive = info.activeLayout == ours
  table.remove(info.layouts, ours)
  if prev > ours then prev = prev - 1 end
  if wasActive then info.activeLayout = prev elseif info.activeLayout > ours then info.activeLayout = info.activeLayout - 1 end
  local ok, err = pcall(g.C_EditMode.SaveLayouts, info)
  if ok and g.C_EditMode.OnLayoutDeleted then pcall(g.C_EditMode.OnLayoutDeleted, ours) end
  if ok and wasActive and g.C_EditMode.SetActiveLayout then pcall(g.C_EditMode.SetActiveLayout, info.activeLayout) end
  if not ok then log("warn", "bar layout off: " .. tostring(err)); return false end
  applyNow()
  if c and c.cdb then c.cdb.barLayoutPrev = nil end
  BL.state = { mode = "off" }
  bridge({ on = false, mode = "off" })
  log("info", "bar layout: your own layout is back (" .. tostring(reason) .. ")")
  return true
end

--- Edit Mode closed or the layouts changed without us: did the player pick another layout?
function BL.onLayoutsUpdated()
  if BL.applying or not BL.available() then return end
  local info = BL.layouts()
  if not info then return end
  local ours = find(info, BL.NAME, G().Enum.EditModeLayoutType.Character)
  if ours and info.activeLayout ~= ours and BL.wasActive then
    BL.setPaused(true)
    log("info", "bar layout: you picked another Edit Mode layout – WoWBoxer leaves the bars alone (tick Fit action bars again to resume)")
  end
end

--- What the layout looks like, for the diagnose (read by tools/read_log.py).
function BL.diag(m, plan)
  local c = Core()
  if not (c and c.db) then return end
  local d = { at = (G().time and G().time()) or 0, window = { w = round(m.W), h = round(m.H) }, active = m.activeName,
    plan = plan and { mode = plan.mode, arrangement = plan.arrangement, pct = plan.pct, width = plan.width and round(plan.width), top = plan.top and round(plan.top) } or nil,
    items = {}, obstacles = {} }
  for key, it in pairs(m.items) do
    d.items[key] = { on = it.on, n = it.n, bw = it.bw and round(it.bw), pad = it.pad and round(it.pad), extra = it.extra and round(it.extra),
      caps = it.caps and round(it.caps), pct = it.pct, w100 = it.w100 and round(it.w100), h100 = it.h100 and round(it.h100),
      place = plan and plan.places and plan.places[key] and { x = round(plan.places[key].x), y = round(plan.places[key].y), pct = plan.places[key].pct } or nil }
  end
  for _, o in ipairs(m.obstacles) do d.obstacles[#d.obstacles + 1] = o.name .. " " .. round(o.r[1]) .. "," .. round(o.r[2]) .. "," .. round(o.r[3]) .. "," .. round(o.r[4]) end
  local b = type(c.db.bridge) == "table" and c.db.bridge or {}
  b.barLayout = d
  c.db.bridge = b
end
