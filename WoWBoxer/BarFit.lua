--[[ WoWBoxer – measures the action bars (WS-C; owner bug 6 Nov 2026: with bars 2 and 3 on, some buttons are missing
  in the smaller windows of a layout) and, since 12 Nov 2026, fits them to each window (second half of this file).
  The measurement reads where every action button of every visible bar really is (after Edit Mode on Forever, the
  classic layout on Era/TBC), counts the buttons that are outside the window or under another bar, and works out the
  largest UI scale at which every visible bar fits. It goes into our own SavedVariables (WoWBoxerDB.bridge.bars,
  contract in docs/bridge.md) and the log.

  The fit model: each bar keeps its anchor to the window (left/centre/right, bottom/middle/top, found from its
  anchor chain up to UIParent). A smaller UI scale makes the window larger in UI units (W / k), so a centred bar moves
  by half the growth and a right-anchored bar by all of it; sizes in UI units stay the same. A scale fits when every
  button is inside the window (with a small margin) and no button of one bar lies on a button of another bar.
  The margin: 4 units to each window edge, except an edge the bar is anchored to and already sits closer to by design
  (Forever puts bar 1 two units above the bottom edge); there the bar keeps the room the game gave it. Without that,
  a bar Blizzard places at the edge never "fits" (live Forever log 6 Nov: "0 outside, 0 covered; fits all at scale none").
  The bag and menu buttons count as one more "bar" ("menu"): on Forever they ride on the main bar right of bar 1 and
  go missing first in a narrow window, or lie on bar 1 once the game pushes bar 1 against the left edge.
  (Until 1.3.0-test.7 a login popup offered to lower the shared UI Scale; the per-window fit below replaces it.) ]]
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

--- A real overlap for the bag and menu buttons: at least a third of the smaller button deep in both directions.
--- Their tall frames (Era micro buttons are 58 high, the art in the lower part) touch the bars above by design, a few
--- units deep; on Forever in a narrow window the whole menu lies on bar 1 (owner 10 Nov: menu x 445–960 on bar 1 x 0–562).
function BF.deepOverlap(a, b)
  local w = math.min(a[3], b[3]) - math.max(a[1], b[1])
  local h = math.min(a[4], b[4]) - math.max(a[2], b[2])
  return w >= math.min(a[3] - a[1], b[3] - b[1]) / 3 and h >= math.min(a[4] - a[2], b[4] - b[2]) / 3
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
      -- the menu and bag buttons count only when they really lie on a bar: their tall frames touch the bars above (Era)
      local menu = bars[x.bi].key == "menu" or bars[y.bi].key == "menu"
      if x.bi ~= y.bi and overlaps(x.r, y.r) and (not menu or BF.deepOverlap(x.r, y.r)) then
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

-- ------------------------------------------------------------------ fit the bars to this window (owner 12 Nov 2026)
--[[ UI Scale is one value for every client of an install (and never below 0.64), so it cannot fit every window shape
  (owner 12 Nov: two 1280x1392 followers, "even the smallest UI Scale can't fit them all"). Instead WoWBoxer lays the
  bottom bars out for each window itself:
  1. It finds the bottom group: bar 1, the bottom-left and bottom-right bars, the bag and menu buttons and the XP bar,
     each as the frame that holds them under UIParent (a "unit": on Era the 1024-wide main bar art holds bar 1, the
     bags and the menu; on Forever each Edit Mode bar is its own unit).
  2. If the group does not fit the window's width (GetScreenWidth) it scales every unit by the same factor around the
     bottom centre, just enough to fit. Below the smallest size (setting, 70 %) it stacks the units instead: each row
     of the default layout wraps into more rows (bar 2 above bar 1, bar 3 above bar 2, the bags above …), at the
     largest size that fits. Never onto the chat, the unit frames or the side bars, unless they already sat there.
  3. Nothing fits even stacked: the default layout stays and one chat line says so (no popup).
  Rules: only out of combat (it waits for PLAYER_REGEN_ENABLED), only SetScale/SetPoint on the bar frames (never a
  protected action, a CVar or a saved Edit Mode layout; nothing persists), off when Bartender4, Dominos or another
  bar addon is loaded, paused while Edit Mode is open, and every frame goes back to its own points and scale when the
  setting is turned off. Setting "Fit action bars to this window" (Setup, on by default, per character).
  [AFKLAR: that SetScale/SetPoint on Forever's Edit Mode bars out of combat causes no taint warnings, and that
  Blizzard's own re-layouts are all caught by the SetPoint/SetScale hooks – both checked in the owner's test build] ]]

BF.FIT_MIN, BF.FIT_FLOOR = 0.70, 0.50
BF.BOTTOM_KEYS = { main = true, bottomLeft = true, bottomRight = true, menu = true }
--- XP and reputation bars: they ride with the group when they sit at the bottom (Era: inside the main bar already)
BF.STATUS_NAMES = { "MainStatusTrackingBarContainer", "SecondaryStatusTrackingBarContainer", "StatusTrackingBarManager",
  "MainMenuExpBar", "ReputationWatchBar" }
--- The frames the bars must not be moved onto (when they did not already overlap the default layout)
BF.OBSTACLE_NAMES = { "ChatFrame1", "PlayerFrame", "TargetFrame", "FocusFrame", "PartyFrame", "CompactPartyFrame",
  "PartyMemberFrame1", "PartyMemberFrame2", "PartyMemberFrame3", "PartyMemberFrame4" }
--- Bar addons that own the bars: WoWBoxer does nothing while one is loaded
BF.BAR_ADDONS = { "Bartender4", "Dominos", "ElvUI", "Tukui", "NDui", "Neuron", "MoveAny", "SpartanUI", "LUI", "RealUI",
  "ConsolePort_Bar", "Bartender4_Classic" }

local function eff(f) return num(f and f.GetEffectiveScale and f:GetEffectiveScale()) or 1 end
local function union(list)
  local l, b, r, t = math.huge, math.huge, -math.huge, -math.huge
  for _, x in ipairs(list) do l = math.min(l, x[1]); b = math.min(b, x[2]); r = math.max(r, x[3]); t = math.max(t, x[4]) end
  return { l, b, r, t }
end
local function shift(r, dx, dy) return { r[1] - dx, r[2] - dy, r[3] - dx, r[4] - dy } end
local function frameName(f)
  if type(f) ~= "table" or not f.GetName then return "?" end
  local ok, n = pcall(f.GetName, f)
  return ok and type(n) == "string" and n or "?"
end

--- The frame right under UIParent that holds f (what moves when the bar moves), or nil.
function BF.rootOf(f)
  local UIParent = G().UIParent
  for _ = 1, 20 do
    if type(f) ~= "table" or not f.GetParent then return nil end
    local p = f:GetParent()
    if p == UIParent then return f end
    if not p then return nil end
    f = p
  end
  return nil
end

--- The bottom group as units and the rects to keep clear, all in UI units where their anchors put them (pushes
--- undone). Returns units, obstacles, W, H, why (why = a reason nothing can be fitted).
function BF.collect()
  local g = G()
  local UIParent = g.UIParent
  if not (UIParent and UIParent.GetWidth) then return nil, nil, 0, 0, "no UIParent" end
  local ui = eff(UIParent)
  local W, H = num(UIParent:GetWidth()) or 0, num(UIParent:GetHeight()) or 0
  local units, byRoot, obstacles = {}, {}, {}
  local function unitFor(root)
    local u = byRoot[root]
    if not u then u = { root = root, name = frameName(root), keys = {}, rects = {} }; byRoot[root] = u; units[#units + 1] = u end
    return u
  end
  for _, def in ipairs(BF.BARS) do
    for _, name in ipairs(buttonNames(def)) do
      local btn = g[name]
      local shown
      if def.names then shown = btn and btn.IsVisible and btn:IsVisible() and btn.GetLeft and true or false
      else shown = counted(btn) end
      local r = shown and rectOf(btn, ui)
      if r then
        if BF.BOTTOM_KEYS[def.key] then
          local root = BF.rootOf(btn)
          if root then local u = unitFor(root); u.keys[def.key] = true; u.rects[#u.rects + 1] = r end
        else
          obstacles[#obstacles + 1] = { key = def.key, r = r }
        end
      end
    end
  end
  if not byRoot[BF.rootOf(g.ActionButton1) or false] then return nil, nil, W, H, "bar 1 not found" end
  for _, name in ipairs(BF.STATUS_NAMES) do
    local f = g[name]
    if type(f) == "table" and f.IsVisible and f:IsVisible() and f.GetLeft then
      local r, root = rectOf(f, ui), BF.rootOf(f)
      if r and root and r[2] < H * 0.35 and r[3] - r[1] > 1 then local u = unitFor(root); u.keys.status = true; u.rects[#u.rects + 1] = r end
    end
  end
  local keep = {}
  for _, u in ipairs(units) do
    local root = u.root
    local dx, dy = BF.pushOf(root, ui, W, H)
    if math.abs(dx) < 0.5 then dx = 0 end
    if math.abs(dy) < 0.5 then dy = 0 end
    for i, r in ipairs(u.rects) do u.rects[i] = shift(r, dx, dy) end
    local box = union(u.rects)
    local rr = rectOf(root, ui)
    if rr then
      rr = shift(rr, dx, dy)
      -- the unit's own art (Era's 1024-wide main bar, Forever's end caps) stays visible when it is about the bar's size
      if rr[3] - rr[1] <= (box[3] - box[1]) * 1.25 + 60 and rr[4] - rr[2] <= (box[4] - box[2]) + 60 then
        box = union({ box, rr })
      end
    end
    u.box, u.rootRect = box, rr
    u.h, u.v = BF.anchorOf(root)
    u.scale = num(root.GetScale and root:GetScale()) or 1
    u.k = eff(root) / ui
    u.points = {}
    for i = 1, (root.GetNumPoints and root:GetNumPoints()) or 0 do u.points[i] = { root:GetPoint(i) } end
    u.ok = rr ~= nil and u.h == "center" and u.v == "bottom" and box[2] < H * 0.35 and rr[4] - rr[2] < 400 and #u.points > 0
    if u.ok then keep[#keep + 1] = u
    elseif u.keys.main then return nil, nil, W, H, "bar 1 is not at the bottom centre (" .. u.name .. ", " .. u.h .. "/" .. u.v .. ")"
    elseif u.keys.status and not (u.keys.bottomLeft or u.keys.bottomRight or u.keys.menu) then
      -- an XP bar on its own frame that does not follow the bottom centre: left alone, and no obstacle either (it sits
      -- between the bar rows, so as an obstacle it would block every smaller layout)
    else for _, r in ipairs(u.rects) do obstacles[#obstacles + 1] = { key = u.name, r = r } end end
  end
  for _, name in ipairs(BF.OBSTACLE_NAMES) do
    local f = g[name]
    if type(f) == "table" and f.IsVisible and f:IsVisible() and f.GetLeft and not byRoot[f] then
      local r = rectOf(f, ui)
      if r and r[3] - r[1] > 1 and r[4] - r[2] > 1 then obstacles[#obstacles + 1] = { key = name, r = r } end
    end
  end
  return keep, obstacles, W, H, nil
end

-- the rects of unit u placed with its box at X, Y at size s
local function placed(u, X, Y, s, r)
  local b = u.box
  return { X + (r[1] - b[1]) * s, Y + (r[2] - b[2]) * s, X + (r[3] - b[1]) * s, Y + (r[4] - b[2]) * s }
end

--- Stacked places for size s (natural rows wrap to the window): {[i] = {x, y}} with x relative to the centre, y from
--- the bottom, both in the units' own size; nil when a unit alone is wider than the window.
function BF.stackPlaces(units, W, s, margin)
  local A = (W - 2 * margin) / s
  local order = {}
  for i = 1, #units do order[i] = i end
  table.sort(order, function(a, b)
    local x, y = units[a].box, units[b].box
    if math.abs(x[2] - y[2]) >= 12 then return x[2] < y[2] end
    return x[1] < y[1]
  end)
  local rows = {}
  for _, i in ipairs(order) do
    local bx = units[i].box
    local row = rows[#rows]
    if row and math.abs(bx[2] - row.b) < 12 then row.items[#row.items + 1] = i; row.t = math.max(row.t, bx[4])
    else rows[#rows + 1] = { b = bx[2], t = bx[4], items = { i } } end
  end
  local places, top, prevT = {}, nil, nil
  for _, row in ipairs(rows) do
    local lines, line, prev = {}, { w = 0, h = 0, items = {} }, nil
    for _, i in ipairs(row.items) do
      local bx = units[i].box
      local w = bx[3] - bx[1]
      if w > A + 0.01 then return nil end
      local gap = prev and math.max(2, math.min(24, bx[1] - units[prev].box[3])) or 0
      if #line.items > 0 and line.w + gap + w > A then lines[#lines + 1] = line; line = { w = 0, h = 0, items = {} }; gap = 0 end
      line.items[#line.items + 1] = { i = i, off = line.w + gap }
      line.w, line.h = line.w + gap + w, math.max(line.h, bx[4] - bx[2])
      prev = i
    end
    lines[#lines + 1] = line
    for li, ln in ipairs(lines) do
      local y
      if not top then y = row.b
      elseif li == 1 then y = top + math.max(4, math.min(40, row.b - prevT))
      else y = top + 4 end
      for _, it in ipairs(ln.items) do places[it.i] = { x = -ln.w / 2 + it.off, y = y } end
      top = y + ln.h
    end
    prevT = row.t
  end
  return places
end

--- The layout for this window: {mode = "none"|"scale"|"stack"|"nofit", scale, place = {[i] = {X, Y}} (box corner in
--- UI units)}. Pure: units/obstacles from BF.collect, W x H the window in UI units.
function BF.plan(units, obstacles, W, H, minScale, margin)
  margin = margin or BF.MARGIN
  minScale = minScale or BF.FIT_MIN
  if not units or #units == 0 or W <= 0 or H <= 0 then return { mode = "none", scale = 1 } end
  local all = {}
  for _, u in ipairs(units) do all[#all + 1] = u.box end
  local g = union(all)
  -- an obstacle that already overlaps the default layout is the player's own arrangement: it does not count
  local obs = {}
  for _, o in ipairs(obstacles or {}) do
    local hit = false
    for _, u in ipairs(units) do for _, r in ipairs(u.rects) do if overlaps(o.r, r) then hit = true end end end
    if not hit then obs[#obs + 1] = o.r end
  end
  local function fits(place, s)
    for i, u in ipairs(units) do
      local p = place[i]
      local b = placed(u, p.X, p.Y, s, u.box)
      if b[1] < margin - 0.5 or b[3] > W - margin + 0.5 or b[4] > H * 0.5 then return false end
      for _, r in ipairs(u.rects) do
        local q = placed(u, p.X, p.Y, s, r)
        for _, o in ipairs(obs) do if overlaps(q, o) then return false end end
      end
    end
    return true
  end
  if g[1] >= margin - 0.5 and g[3] <= W - margin + 0.5 then
    local place = {}
    for i, u in ipairs(units) do place[i] = { X = u.box[1], Y = u.box[2] } end
    if fits(place, 1) then return { mode = "none", scale = 1 } end
  end
  local cx = (g[1] + g[3]) / 2
  local function steps(fn)
    local s = 1
    while s >= minScale - 1e-9 do
      local r = fn(math.floor(s * 100 + 0.5) / 100)
      if r then return r end
      s = s - BF.STEP
    end
  end
  local best = steps(function(s)
    local place = {}
    for i, u in ipairs(units) do place[i] = { X = W / 2 + (u.box[1] - cx) * s, Y = u.box[2] * s } end
    if fits(place, s) then return { mode = "scale", scale = s, place = place } end
  end)
  if best then return best end
  best = steps(function(s)
    local p = BF.stackPlaces(units, W, s, margin)
    if not p then return nil end
    local place = {}
    for i in ipairs(units) do place[i] = { X = W / 2 + p[i].x * s, Y = p[i].y * s } end
    if fits(place, s) then return { mode = "stack", scale = s, place = place } end
  end)
  return best or { mode = "nofit", scale = 1 }
end

-- ------------------------------------------------------------------ applying it
BF.managed = {}      -- [root frame] = { points = {{GetPoint}}, scale = n, name = "MainMenuBar" } – the frame's own layout
BF.hooked = {}       -- [root frame] = true once the SetPoint/SetScale hooks are on
BF.state = { mode = "off" }

local function Core() return ns.Core end
function BF.fitOn() local c = Core() and Core().cdb; return not (c and c.barFit == false) end
function BF.fitMin()
  local c = Core() and Core().cdb
  local v = tonumber(c and c.barFitMin) or BF.FIT_MIN
  return math.max(BF.FIT_FLOOR, math.min(1, v))
end
--- The loaded bar addon that owns the bars, or nil.
function BF.barAddon()
  local C = ns.Compat
  for _, n in ipairs(BF.BAR_ADDONS) do if C and C.addonState(n) == "loaded" then return n end end
  return nil
end
local function editMode()
  local E = G().EditModeManagerFrame
  if not E then return false end
  if E.IsEditModeActive then local ok, a = pcall(E.IsEditModeActive, E); if ok then return a and true or false end end
  return E.IsShown and E:IsShown() and true or false
end

--- Our own writes, so the hooks can tell them from Blizzard's re-layouts.
local function write(fn)
  BF.writing = true
  local ok, err = pcall(fn)
  BF.writing = false
  if not ok and Core() then Core().log("warn", "bar fit write: " .. tostring(err)) end
  return ok
end

--- Blizzard moved or scaled a frame we manage (Edit Mode, a bar turned on): what it set is the frame's own layout
--- now (never put our old copy back over it); fit again. A game that keeps moving the bars back wins after 6 rounds.
local function onBlizzardMove(root, what)
  if BF.writing then return end
  local m = BF.managed[root]
  if m then
    m[what] = nil
    if m.points == nil and m.scale == nil then BF.managed[root] = nil end
  end
  local now = (G().GetTime and G().GetTime()) or 0
  if BF.fightAt and now - BF.fightAt < 10 then BF.fights = (BF.fights or 0) + 1 else BF.fightAt, BF.fights = now, 1 end
  if BF.fights > 6 then
    if not BF.gaveUp and Core() then BF.gaveUp = true; Core().log("warn", "bar fit: the game keeps moving " .. frameName(root) .. " back; stopped until /reload") end
    BF.restore("gave up")
    return
  end
  BF.request("moved by the game: " .. frameName(root))
end
local function hook(root)
  if BF.hooked[root] or not G().hooksecurefunc then return end
  BF.hooked[root] = true
  pcall(G().hooksecurefunc, root, "SetPoint", function(self) onBlizzardMove(self, "points") end)
  pcall(G().hooksecurefunc, root, "SetScale", function(self) onBlizzardMove(self, "scale") end)
end

--- Put every frame back to its own points and scale. Out of combat only (returns false in combat).
function BF.restore(reason)
  if next(BF.managed) == nil then return true end
  if ns.Compat.inCombat() then BF.pending = "restore"; return false end
  write(function()
    for root, m in pairs(BF.managed) do
      if m.points then
        root:ClearAllPoints()
        for _, p in ipairs(m.points) do root:SetPoint(p[1], p[2], p[3], p[4], p[5]) end
      end
      if m.scale then root:SetScale(m.scale) end
    end
  end)
  BF.managed = {}
  if Core() then Core().log("info", "bar fit: default layout (" .. tostring(reason) .. ")") end
  return true
end

local function bridge(on, plan)
  local c = Core()
  if not (c and c.db) then return end
  local b = type(c.db.bridge) == "table" and c.db.bridge or {}
  -- the window app's handshake (docs/bridge.md): while this is on it leaves UI Scale alone for this client
  b.barFit = on and true or false
  b.barScale = on and plan and plan.mode ~= "nofit" and plan.scale or nil
  b.barMode = plan and plan.mode or nil
  c.db.bridge = b
end

--- Lay the bars out for this window now (from their own layout). Returns the plan, or nil and why.
function BF.fitNow(reason)
  local c = Core()
  if not (c and c.db) then return nil, "not loaded" end
  if not BF.fitOn() then BF.restore("off"); BF.state = { mode = "off" }; bridge(false); return nil, "off" end
  local addon = BF.barAddon()
  if addon then
    BF.restore("bar addon"); BF.state = { mode = "addon", addon = addon }; bridge(false)
    if BF.lastWhy ~= addon then BF.lastWhy = addon; c.log("info", "bar fit: " .. addon .. " owns the bars, nothing done") end
    return nil, addon
  end
  if editMode() then BF.restore("Edit Mode"); BF.state = { mode = "editmode" }; return nil, "Edit Mode" end
  if BF.gaveUp then return nil, "gave up" end
  if ns.Compat.inCombat() then BF.pending = "fit"; return nil, "combat" end
  -- always from the frames' own layout: put them back, and measure on the next round, once the game has placed them
  -- [AFKLAR: whether GetLeft already reads the new place in the same frame; one round later is safe either way]
  if next(BF.managed) ~= nil then
    BF.restore("refit")
    BF.request(reason)
    return nil, "restoring"
  end
  local units, obstacles, W, H, why = BF.collect()
  if not units then
    BF.state = { mode = "none", why = why }; bridge(true, nil)
    if BF.lastWhy ~= why then BF.lastWhy = why; c.log("info", "bar fit: " .. tostring(why)) end
    return nil, why
  end
  local plan = BF.plan(units, obstacles, W, H, BF.fitMin(), BF.MARGIN)
  if plan.mode == "scale" or plan.mode == "stack" then
    write(function()
      for i, u in ipairs(units) do
        local p, root, s = plan.place[i], u.root, plan.scale
        BF.managed[root] = BF.managed[root] or { points = u.points, scale = u.scale, name = u.name }
        local rr = u.rootRect
        local L = p.X + (rr[1] - u.box[1]) * s
        local B = p.Y + (rr[2] - u.box[2]) * s
        local k = u.k * s
        root:SetScale(u.scale * s)
        root:ClearAllPoints()
        root:SetPoint("BOTTOMLEFT", G().UIParent, "BOTTOM", (L - W / 2) / k, B / k)
      end
    end)
    for _, u in ipairs(units) do hook(u.root) end
  end
  local names = {}
  for _, u in ipairs(units) do names[#names + 1] = u.name end
  BF.state = { mode = plan.mode, scale = plan.scale, units = #units, w = math.floor(W + 0.5), h = math.floor(H + 0.5) }
  bridge(true, plan)
  local line = string.format("bar fit: %s at %d %% in %dx%d (%s)", plan.mode, math.floor(plan.scale * 100 + 0.5),
    BF.state.w, BF.state.h, table.concat(names, ", "))
  if line ~= BF.lastLine2 then BF.lastLine2 = line; c.log("info", line .. " (" .. tostring(reason) .. ")") end
  if plan.mode == "nofit" then
    local key = BF.state.w .. "x" .. BF.state.h
    if BF.hinted ~= key then
      BF.hinted = key
      c.print("Your action bars don't fit this window, even stacked. Make the window wider, move the chat up or turn off a bar.")
    end
  end
  BF.update(reason)
  return plan
end

--- Fit again a moment later (many events come at once; Blizzard's own layout settles first).
function BF.request(reason)
  if BF.waiting then return end
  BF.waiting = true
  local function run()
    BF.waiting = false
    local ok, err = pcall(BF.fitNow, reason)
    if not ok and Core() then Core().log("error", "bar fit: " .. tostring(err)) end
  end
  if G().C_Timer and G().C_Timer.After then G().C_Timer.After(0.2, run) else run() end
end

--- The setting (Setup, /wbx barfit on|off): off puts the default layout back at once (or after combat).
function BF.setFit(on)
  local c = Core()
  if on then c.cdb.barFit = nil else c.cdb.barFit = false end
  if on then BF.gaveUp, BF.fights = nil, 0; BF.request("turned on")
  else BF.restore("turned off"); BF.state = { mode = "off" }; bridge(false) end
end

--- Hooks that tell us when bars come and go and when Edit Mode opens and closes (post-hooks only: no taint).
function BF.Init()
  if BF.inited then return end
  BF.inited = true
  local g = G()
  for _, n in ipairs({ "MultiBarBottomLeft", "MultiBarBottomRight", "MultiBarRight", "MultiBarLeft", "MultiBar5", "MultiBar6",
    "MultiBar7", "MainMenuBarBackpackButton", "MainStatusTrackingBarContainer", "MainMenuExpBar" }) do
    local f = g[n]
    if type(f) == "table" and f.HookScript then
      pcall(f.HookScript, f, "OnShow", function() BF.request("shown: " .. n) end)
      pcall(f.HookScript, f, "OnHide", function() BF.request("hidden: " .. n) end)
    end
  end
  local E = g.EditModeManagerFrame
  if type(E) == "table" and E.HookScript then
    pcall(E.HookScript, E, "OnShow", function() BF.restore("Edit Mode opened"); BF.state = { mode = "editmode" } end)
    pcall(E.HookScript, E, "OnHide", function() BF.request("Edit Mode closed") end)
  end
  if g.hooksecurefunc and type(g.MultiActionBar_Update) == "function" then
    pcall(g.hooksecurefunc, "MultiActionBar_Update", function() BF.request("bars changed") end)
  end
end

--- Login, /reload, a new window size or UI scale.
function BF.offer()
  BF.request("login")
  return false -- never blocks the other login checks: there is no popup any more
end

--- Does measurement m need a smaller UI scale? (for the bridge and /wbx barfit) true, fit.
function BF.needsFit(m)
  if not (m and m.bars and #m.bars > 0) then return false end
  if not (m.squeezed or (m.outside or 0) + (m.covered or 0) > 0) then return false end
  if m.fitScale and m.fitScale >= (m.scale or 1) - 0.005 then return false end
  return true, m.fitScale
end

--- After combat: whatever waited for it.
function BF.afterCombat()
  local p = BF.pending
  BF.pending = nil
  if p == "restore" and not BF.fitOn() then BF.restore("after combat")
  elseif p then BF.request("after combat") end
end

--- One line for /wbx barfit.
function BF.fitSummary()
  local s = BF.state or {}
  if not BF.fitOn() then return "Fit action bars: off (/wbx barfit on)" end
  if s.mode == "addon" then return "Fit action bars: " .. s.addon .. " owns the bars – nothing done" end
  if s.mode == "editmode" then return "Fit action bars: paused while Edit Mode is open" end
  if s.mode == "scale" then return string.format("Fit action bars: scaled to %d %% for this %dx%d window", math.floor(s.scale * 100 + 0.5), s.w, s.h) end
  if s.mode == "stack" then return string.format("Fit action bars: stacked at %d %% for this %dx%d window", math.floor(s.scale * 100 + 0.5), s.w, s.h) end
  if s.mode == "nofit" then return "Fit action bars: they don't fit this window even stacked – default layout kept" end
  if s.why then return "Fit action bars: on – " .. s.why end
  return string.format("Fit action bars: on – they fit as they are (smallest size %d %%)", math.floor(BF.fitMin() * 100 + 0.5))
end
