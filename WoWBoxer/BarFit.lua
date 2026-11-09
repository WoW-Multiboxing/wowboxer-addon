--[[ WoWBoxer – measures the action bars for the window app's Auto-fit (WS-C; owner bug 6 Nov 2026: with bars 2 and 3
  on, some buttons are missing in the smaller windows of a layout).
  Read only: it reads where every action button of every visible bar really is (after Edit Mode on Forever, the
  classic layout on Era/TBC), counts the buttons that are outside the window or under another bar, and works out the
  largest UI scale at which every visible bar fits. Nothing on the bars changes (hard rule 4); the result goes into
  our own SavedVariables (WoWBoxerDB.bridge.bars, contract in docs/bridge.md) and the log.

  The fit model: each bar keeps its anchor to the window (left/centre/right, bottom/middle/top, found from its
  anchor chain up to UIParent). A smaller UI scale makes the window larger in UI units (W / k), so a centred bar moves
  by half the growth and a right-anchored bar by all of it; sizes in UI units stay the same. A scale fits when every
  button is inside the window (with a small margin) and no button of one bar lies on a button of another bar.
  The margin: 4 units to each window edge, except an edge the bar is anchored to and already sits closer to by design
  (Forever puts bar 1 two units above the bottom edge); there the bar keeps the room the game gave it. Without that,
  a bar Blizzard places at the edge never "fits" (live Forever log 6 Nov: "0 outside, 0 covered; fits all at scale none").
  The bag and menu buttons count as one more "bar" ("menu"): on Forever they ride on the main bar right of bar 1 and
  go missing first in a narrow window. ]]
local _, ns = ...
local BF = {}
ns.BarFit = BF

BF.MIN_SCALE, BF.MAX_SCALE, BF.STEP, BF.MARGIN = 0.64, 1.0, 0.01, 4

--- Every Blizzard action bar on both clients: key, the name players know, the button prefix (12 buttons each).
BF.BARS = {
  { key = "main", label = "Action Bar 1", prefix = "ActionButton" },
  { key = "bottomLeft", label = "Bottom Left bar (bar 2)", prefix = "MultiBarBottomLeftButton" },
  { key = "bottomRight", label = "Bottom Right bar (bar 3)", prefix = "MultiBarBottomRightButton" },
  { key = "right", label = "Right bar", prefix = "MultiBarRightButton" },
  { key = "left", label = "Right bar 2", prefix = "MultiBarLeftButton" },
  { key = "bar5", label = "Action Bar 5", prefix = "MultiBar5Button" },
  { key = "bar6", label = "Action Bar 6", prefix = "MultiBar6Button" },
  { key = "bar7", label = "Action Bar 7", prefix = "MultiBar7Button" },
  { key = "menu", label = "Bag and menu buttons", names = {
    "CharacterMicroButton", "SpellbookMicroButton", "PlayerSpellsMicroButton", "TalentMicroButton", "ProfessionMicroButton",
    "AchievementMicroButton", "QuestLogMicroButton", "SocialsMicroButton", "GuildMicroButton", "WorldMapMicroButton",
    "LFGMicroButton", "LFDMicroButton", "PVPMicroButton", "CollectionsMicroButton", "EJMicroButton", "StoreMicroButton",
    "MainMenuMicroButton", "HelpMicroButton", "KeyRingButton", "CharacterBag3Slot", "CharacterBag2Slot", "CharacterBag1Slot",
    "CharacterBag0Slot", "CharacterReagentBag0Slot", "MainMenuBarBackpackButton" } },
}

--- The buttons of a bar definition, in order (12 numbered buttons, or a list of names).
local function buttonNames(def)
  if def.names then return def.names end
  local list = {}
  for i = 1, 12 do list[i] = def.prefix .. i end
  return list
end

local function G() return _G end
local function num(v) return type(v) == "number" and v == v and v or nil end

--- A button counts when its bar is shown: the button itself, or (an empty slot with the grid off) its parent bar.
local function counted(btn)
  if type(btn) ~= "table" or not btn.GetLeft then return false end
  if btn.IsVisible and btn:IsVisible() then return true end
  local p = btn.GetParent and btn:GetParent()
  return p ~= nil and p.IsVisible ~= nil and p:IsVisible() and true or false
end

--- {l, b, r, t} of frame f in UIParent units, or nil.
local function rectOf(f, ui)
  local l, r, b, t = num(f:GetLeft()), num(f:GetRight()), num(f:GetBottom()), num(f:GetTop())
  if not (l and r and b and t) then return nil end
  local k = (num(f.GetEffectiveScale and f:GetEffectiveScale()) or 1) / ui
  return { l * k, b * k, r * k, t * k }
end

--- Which edges frame f is anchored to, following its anchor chain up to UIParent: h = "left"|"center"|"right",
--- v = "bottom"|"middle"|"top". A frame anchored to another frame inherits that frame's anchor.
function BF.anchorOf(f, depth)
  depth = depth or 0
  local UIParent = G().UIParent
  if depth > 15 or type(f) ~= "table" or not f.GetPoint then return "center", "bottom" end
  local n = (f.GetNumPoints and f:GetNumPoints()) or 0
  if n == 0 then
    local p = f.GetParent and f:GetParent()
    if p and p ~= UIParent then return BF.anchorOf(p, depth + 1) end
    return "center", "bottom"
  end
  local point, rel, relPoint = f:GetPoint(1)
  if type(rel) == "string" then rel = G()[rel] end
  rel = rel or (f.GetParent and f:GetParent())
  if rel and rel ~= UIParent then return BF.anchorOf(rel, depth + 1) end
  local rp = tostring(relPoint or point or "CENTER")
  local h = rp:find("LEFT", 1, true) and "left" or rp:find("RIGHT", 1, true) and "right" or "center"
  local v = rp:find("TOP", 1, true) and "top" or rp:find("BOTTOM", 1, true) and "bottom" or "middle"
  return h, v
end

local function pointPos(l, b, r, t, point)
  point = tostring(point or "CENTER")
  local x = point:find("LEFT", 1, true) and l or point:find("RIGHT", 1, true) and r or (l + r) / 2
  local y = point:find("TOP", 1, true) and t or point:find("BOTTOM", 1, true) and b or (b + t) / 2
  return x, y
end

--- How far the game pushed frame f (and the frames it is anchored to) away from where its anchors say, in UI units:
--- a frame kept on the screen in a too small window (live Forever 9 Nov: in a 870x696 window bar 1 sat at the left
--- edge, bar 3 at the right edge on top of bar 2). 0, 0 when nothing was pushed or the chain cannot be read.
function BF.pushOf(f, ui, W, H, depth)
  depth = depth or 0
  local UIParent = G().UIParent
  if depth > 15 or type(f) ~= "table" or not f.GetPoint then return 0, 0 end
  local n = (f.GetNumPoints and f:GetNumPoints()) or 0
  if n == 0 then
    local p = f.GetParent and f:GetParent()
    if p and p ~= UIParent then return BF.pushOf(p, ui, W, H, depth + 1) end
    return 0, 0
  end
  if n > 1 then return 0, 0 end -- sized by two anchors: no single place to compare
  local point, rel, relPoint, x, y = f:GetPoint(1)
  if type(rel) == "string" then rel = G()[rel] end
  rel = rel or (f.GetParent and f:GetParent()) or UIParent
  local r = rectOf(f, ui)
  if not r then return 0, 0 end
  local tx, ty
  if rel == UIParent then
    tx, ty = pointPos(0, 0, W, H, relPoint or point)
  else
    local rr = rel.GetLeft and rectOf(rel, ui)
    if not rr then return 0, 0 end
    tx, ty = pointPos(rr[1], rr[2], rr[3], rr[4], relPoint or point)
  end
  local k = (num(f.GetEffectiveScale and f:GetEffectiveScale()) or 1) / ui
  local ax, ay = pointPos(r[1], r[2], r[3], r[4], point)
  local dx, dy = ax - (tx + (num(x) or 0) * k), ay - (ty + (num(y) or 0) * k)
  if rel ~= UIParent then
    local px, py = BF.pushOf(rel, ui, W, H, depth + 1)
    dx, dy = dx + px, dy + py
  end
  return dx, dy
end

local function overlaps(a, b)
  local e = 1 -- touching edges do not count
  return a[1] < b[3] - e and b[1] < a[3] - e and a[2] < b[4] - e and b[2] < a[4] - e
end

--- Rects of bar i moved for a window k times smaller in scale (W / k by H / k).
local function moved(bar, W, H, k)
  local dw, dh = W / k - W, H / k - H
  local dx = bar.h == "center" and dw / 2 or bar.h == "right" and dw or 0
  local dy = bar.v == "middle" and dh / 2 or bar.v == "top" and dh or 0
  local out = {}
  for i, r in ipairs(bar.rects) do out[i] = { r[1] + dx, r[2] + dy, r[3] + dx, r[4] + dy } end
  return out
end

--- The margins {left, bottom, right, top} bar i needs in a W x H window: `margin`, or less on an edge the bar is
--- anchored to and sits closer to as laid out now (that gap does not change with the scale).
local function margins(bar, W, H, margin)
  local l, b, r, t = math.huge, math.huge, -math.huge, -math.huge
  for _, x in ipairs(bar.rects) do l = math.min(l, x[1]); b = math.min(b, x[2]); r = math.max(r, x[3]); t = math.max(t, x[4]) end
  local function fixed(gap) return math.max(0, math.min(margin, gap)) end
  return bar.h == "left" and fixed(l) or margin, bar.v == "bottom" and fixed(b) or margin,
    bar.h == "right" and fixed(W - r) or margin, bar.v == "top" and fixed(H - t) or margin
end

--- Buttons outside the window and buttons under another bar, for bars laid out in a W x H window.
function BF.problems(bars, W, H, k, margin)
  k, margin = k or 1, margin or 0
  local outside, covered = {}, {}
  local all = {}
  local edge = {}
  for bi, bar in ipairs(bars) do
    edge[bi] = { margins(bar, W, H, margin) }
    for i, r in ipairs(moved(bar, W, H, k)) do all[#all + 1] = { bi = bi, i = i, r = r } end
  end
  local w, h = W / k, H / k
  for _, x in ipairs(all) do
    local r, m = x.r, edge[x.bi]
    if r[1] < m[1] - 0.5 or r[2] < m[2] - 0.5 or r[3] > w - m[3] + 0.5 or r[4] > h - m[4] + 0.5 then
      outside[x.bi] = (outside[x.bi] or 0) + 1
    end
  end
  for a = 1, #all do
    for b = a + 1, #all do
      local x, y = all[a], all[b]
      -- the menu and bag buttons only count when cut: their tall frames touch the bars above by design (Era)
      if x.bi ~= y.bi and bars[x.bi].key ~= "menu" and bars[y.bi].key ~= "menu" and overlaps(x.r, y.r) then
        covered[x.bi] = (covered[x.bi] or 0) + 1
        covered[y.bi] = (covered[y.bi] or 0) + 1
      end
    end
  end
  return outside, covered
end

local function total(t) local n = 0 for _, v in pairs(t) do n = n + v end return n end

--- The largest UI scale in [MIN_SCALE, MAX_SCALE] at which every visible bar fits, or nil when even the minimum does
--- not. scale = the current UIParent scale; W, H = the window in UI units now.
function BF.fitScale(bars, W, H, scale)
  if #bars == 0 or not (W and H and scale) or W <= 0 or H <= 0 or scale <= 0 then return nil end
  local s = BF.MAX_SCALE
  while s >= BF.MIN_SCALE - 1e-9 do
    local out, cov = BF.problems(bars, W, H, s / scale, BF.MARGIN)
    if total(out) == 0 and total(cov) == 0 then return math.floor(s * 100 + 0.5) / 100 end
    s = s - BF.STEP
  end
  return nil
end

--- Measure now. Returns the table that goes into bridge.bars.
function BF.measure()
  local g = G()
  local UIParent = g.UIParent
  if not (UIParent and UIParent.GetWidth) then return nil end
  local ui = num(UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()) or 1
  local W, H = num(UIParent:GetWidth()) or 0, num(UIParent:GetHeight()) or 0
  local bars = {}
  for _, def in ipairs(BF.BARS) do
    local rects, first = {}, nil
    for _, name in ipairs(buttonNames(def)) do
      local btn = g[name]
      -- menu and bag buttons count only when shown themselves (a hidden one, e.g. a shop button, has no real place)
      if def.names and btn and btn.IsVisible and btn:IsVisible() and btn.GetLeft or not def.names and counted(btn) then
        local r = rectOf(btn, ui)
        if r then rects[#rects + 1] = r; first = first or btn end
      end
    end
    if #rects > 0 then
      local frame = first.GetParent and first:GetParent() or first
      local h, v = BF.anchorOf(frame)
      local dx, dy = 0, 0
      if def.key ~= "menu" then dx, dy = BF.pushOf(frame, ui, W, H) end
      if math.abs(dx) < 0.5 then dx = 0 end
      if math.abs(dy) < 0.5 then dy = 0 end
      bars[#bars + 1] = { key = def.key, label = def.label, rects = rects, h = h, v = v, dx = dx, dy = dy }
    end
  end
  local outside, covered = BF.problems(bars, W, H, 1, 0)
  -- the bars where their anchors put them (what a larger window shows), for the fit scale
  local anchored, squeezed = {}, false
  for i, b in ipairs(bars) do
    if b.dx ~= 0 or b.dy ~= 0 then squeezed = true end
    local rs = {}
    for j, x in ipairs(b.rects) do rs[j] = { x[1] - b.dx, x[2] - b.dy, x[3] - b.dx, x[4] - b.dy } end
    anchored[i] = { key = b.key, rects = rs, h = b.h, v = b.v }
  end
  local pw, ph
  if g.GetPhysicalScreenSize then pw, ph = g.GetPhysicalScreenSize() end
  local list = {}
  for i, b in ipairs(bars) do
    local l, bo, r, t = math.huge, math.huge, -math.huge, -math.huge
    for _, x in ipairs(b.rects) do l = math.min(l, x[1]); bo = math.min(bo, x[2]); r = math.max(r, x[3]); t = math.max(t, x[4]) end
    local function rd(v) return math.floor(v * 10 + 0.5) / 10 end
    list[#list + 1] = { key = b.key, label = b.label, buttons = #b.rects, outside = outside[i] or 0, covered = covered[i] or 0,
      left = rd(l), bottom = rd(bo), right = rd(r), top = rd(t), anchor = b.h .. "/" .. b.v, dx = rd(b.dx), dy = rd(b.dy) }
  end
  local fit = BF.fitScale(anchored, W, H, ui)
  return {
    version = 1, measuredAt = (g.time and g.time()) or 0, game = ns.Compat and ns.Compat.game and ns.Compat.game() or nil,
    window = { w = num(pw), h = num(ph) }, scale = math.floor(ui * 1000 + 0.5) / 1000,
    ui = { w = math.floor(W + 0.5), h = math.floor(H + 0.5) },
    bars = list, outside = total(outside), covered = total(covered), squeezed = squeezed or total(outside) + total(covered) > 0,
    fitScale = fit, fitsAtMin = fit ~= nil, minScale = BF.MIN_SCALE,
  }
end

--- One line for the log and /wbx barfit.
function BF.summary(m)
  if not m then return "bars: not measured" end
  local names = {}
  for _, b in ipairs(m.bars) do names[#names + 1] = b.key .. (b.outside > 0 and (" " .. b.outside .. " outside") or "") .. (b.covered > 0 and (" " .. b.covered .. " covered") or "") end
  return string.format("bars: window %sx%s, UI %dx%d at scale %.3f; %s; %d outside, %d covered; fits all at scale %s",
    tostring(m.window.w or "?"), tostring(m.window.h or "?"), m.ui.w, m.ui.h, m.scale, table.concat(names, ", "),
    m.outside, m.covered, m.fitScale and string.format("%.2f", m.fitScale) or ("none (not even " .. m.minScale .. ")"))
end

--- Measure, store in the bridge, log when it changed. Safe to call any time (reads only).
function BF.update(reason)
  local Core = ns.Core
  if not (Core and Core.db) then return nil end
  local ok, m = pcall(BF.measure)
  if not ok then Core.log("error", "bar measure: " .. tostring(m)); return nil end
  if not m then return nil end
  local b = type(Core.db.bridge) == "table" and Core.db.bridge or {}
  b.bars = m
  Core.db.bridge = b
  local line = BF.summary(m)
  if line ~= BF.lastLine then BF.lastLine = line; Core.log("info", line .. " (" .. tostring(reason) .. ")") end
  return m
end

