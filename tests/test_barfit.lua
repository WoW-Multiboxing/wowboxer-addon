-- Bar fit (owner bug 6 Nov 2026): with action bars 2 and 3 (and the right-side bars) on, some buttons are missing in
-- the smaller windows of a layout. The addon measures where every button of every visible bar really is, counts the
-- ones outside the window or under another bar, and finds the largest UI scale at which everything fits
-- (WoWBoxerDB.bridge.bars for the window app's Auto-fit, docs/bridge.md). Read only.
-- The bars are modelled on each client's default layout:
--   Era/TBC: 1024-wide main bar at the bottom centre, bars 2 and 3 side by side above it (inside the 1024), the right
--            bars at the bottom right, 98 up.
--   Forever: Edit Mode bars of 45 px buttons stacked at the bottom centre (1, 2, 3), the right bars at the middle right.
local dir = (arg[0]:match("^(.*)/[^/]+$") or ".")
local H = dofile(dir .. "/harness.lua")
local Mock = dofile(dir .. "/wowmock.lua")

local function boot(game, w, h)
  local W = Mock.new(H, { toc = game == "forever" and 16001 or 11509, screen = { w = w, h = h } })
  local ns = H.loadAddon({ env = W.env, gameType = game == "forever" and "camelot" or nil })
  W.fire("ADDON_LOADED", "WoWBoxer"); W.fire("PLAYER_LOGIN")
  W.env.GetPhysicalScreenSize = function() return math.floor(W.screen.w * 1.2), math.floor(W.screen.h * 1.2) end
  return W, ns
end
local function resize(W, w, h) W.screen.w, W.screen.h = w, h; W.env.UIParent._w, W.env.UIParent._h = w, h end

--- A row/column of 12 buttons inside frame `bar` (horizontal: LEFT to RIGHT; vertical: TOP to BOTTOM).
local function buttons(env, bar, prefix, size, gap, vertical)
  for i = 1, 12 do
    local b = env.CreateFrame("CheckButton", prefix .. i, bar)
    b:SetSize(size, size)
    if i == 1 then b:SetPoint(vertical and "TOPLEFT" or "BOTTOMLEFT", bar, vertical and "TOPLEFT" or "BOTTOMLEFT", 0, 0)
    elseif vertical then b:SetPoint("TOP", env[prefix .. (i - 1)], "BOTTOM", 0, -gap)
    else b:SetPoint("LEFT", env[prefix .. (i - 1)], "RIGHT", gap, 0) end
  end
end

--- on = {bottomLeft=, bottomRight=, right=, left=}
local function eraBars(env, on)
  local main = env.CreateFrame("Frame", "MainMenuBar", env.UIParent)
  main:SetSize(1024, 53); main:SetPoint("BOTTOM", env.UIParent, "BOTTOM", 0, 0)
  local art = env.CreateFrame("Frame", "MainMenuBarArtFrame", main); art:SetAllPoints(main)
  local row = env.CreateFrame("Frame", "WbxTestMainRow", art); row:SetSize(498, 36); row:SetPoint("BOTTOMLEFT", main, "BOTTOMLEFT", 8, 4)
  buttons(env, row, "ActionButton", 36, 6)
  local bl = env.CreateFrame("Frame", "MultiBarBottomLeft", main); bl:SetSize(498, 36); bl:SetPoint("BOTTOMLEFT", env.ActionButton1, "TOPLEFT", 0, 13)
  buttons(env, bl, "MultiBarBottomLeftButton", 36, 6)
  local br = env.CreateFrame("Frame", "MultiBarBottomRight", main); br:SetSize(498, 36); br:SetPoint("LEFT", bl, "RIGHT", 12, 0)
  buttons(env, br, "MultiBarBottomRightButton", 36, 6)
  local r = env.CreateFrame("Frame", "MultiBarRight", env.UIParent); r:SetSize(36, 498); r:SetPoint("BOTTOMRIGHT", env.UIParent, "BOTTOMRIGHT", -6, 98)
  buttons(env, r, "MultiBarRightButton", 36, 6, true)
  local l = env.CreateFrame("Frame", "MultiBarLeft", env.UIParent); l:SetSize(36, 498); l:SetPoint("TOPRIGHT", r, "TOPLEFT", -5, 0)
  buttons(env, l, "MultiBarLeftButton", 36, 6, true)
  if not on.bottomLeft then bl:Hide() end
  if not on.bottomRight then br:Hide() end
  if not on.right then r:Hide() end
  if not on.left then l:Hide() end
end
local function foreverBars(env, on)
  local function bar(name, y)
    local f = env.CreateFrame("Frame", name, env.UIParent); f:SetSize(562, 45); f:SetPoint("BOTTOM", env.UIParent, "BOTTOM", 0, y)
    return f
  end
  local main = bar("MainMenuBar", 41); buttons(env, main, "ActionButton", 45, 2)
  local bl = bar("MultiBarBottomLeft", 90); buttons(env, bl, "MultiBarBottomLeftButton", 45, 2)
  local br = bar("MultiBarBottomRight", 139); buttons(env, br, "MultiBarBottomRightButton", 45, 2)
  local r = env.CreateFrame("Frame", "MultiBarRight", env.UIParent); r:SetSize(45, 562); r:SetPoint("RIGHT", env.UIParent, "RIGHT", -5, -77)
  buttons(env, r, "MultiBarRightButton", 45, 2, true)
  local l = env.CreateFrame("Frame", "MultiBarLeft", env.UIParent); l:SetSize(45, 562); l:SetPoint("RIGHT", r, "LEFT", -2, 0)
  buttons(env, l, "MultiBarLeftButton", 45, 2, true)
  if not on.bottomLeft then bl:Hide() end
  if not on.bottomRight then br:Hide() end
  if not on.right then r:Hide() end
  if not on.left then l:Hide() end
end

local SETS = {
  { name = "bar 1", on = {} },
  { name = "bars 1+2", on = { bottomLeft = true } },
  { name = "bars 1+2+3", on = { bottomLeft = true, bottomRight = true } },
  { name = "bars 1+2+3 + right bars", on = { bottomLeft = true, bottomRight = true, right = true, left = true } },
}
-- windows in UI units at scale 1: a big main window and small follower windows (5:4)
local WINDOWS = { { name = "large", w = 1707, h = 960 }, { name = "small", w = 900, h = 720 }, { name = "tiny", w = 640, h = 512 } }

for _, game in ipairs({ "era", "forever" }) do
  for _, set in ipairs(SETS) do
    for _, win in ipairs(WINDOWS) do
      local W, ns = boot(game, win.w, win.h)
      local BF = ns.BarFit
      ;(game == "era" and eraBars or foreverBars)(W.env, set.on)
      local who = game .. ", " .. set.name .. ", " .. win.name .. " window: "
      local m = BF.update("test")
      H.ok(m ~= nil, who .. "measured")
      local want = 1 + (set.on.bottomLeft and 1 or 0) + (set.on.bottomRight and 1 or 0) + (set.on.right and 1 or 0) + (set.on.left and 1 or 0)
      H.eq(#m.bars, want, who .. "every enabled bar is seen, no other")
      for _, b in ipairs(m.bars) do H.eq(b.buttons, 12, who .. b.key .. " has 12 buttons") end
      H.eq(ns.Core.db.bridge.bars, m, who .. "stored in the bridge")
      if win.name == "large" then
        H.eq(m.outside + m.covered, 0, who .. "everything fits as it is")
      end
      if game == "era" and win.name ~= "large" then
        H.ok(m.outside > 0, who .. "the 1024-wide main bar does not fit: buttons outside (" .. m.outside .. ")")
      end
      if m.fitScale then
        H.ok(m.fitScale >= BF.MIN_SCALE and m.fitScale <= BF.MAX_SCALE, who .. "fit scale within the game's range: " .. m.fitScale)
        -- the proof: lay the same bars out again in the window as it is at that scale, and nothing is missing
        local k = m.fitScale / m.scale
        resize(W, win.w / k, win.h / k)
        local again = BF.measure()
        H.eq(again.outside, 0, who .. "at scale " .. m.fitScale .. " no button is outside")
        H.eq(again.covered, 0, who .. "at scale " .. m.fitScale .. " no button is under another bar")
        -- and it is the largest such scale: one step more and something is missing (unless already at the maximum)
        if m.fitScale < BF.MAX_SCALE then
          local k2 = (m.fitScale + BF.STEP) / m.scale
          resize(W, win.w / k2, win.h / k2)
          local more = BF.measure()
          H.ok(more.fitScale == nil or more.fitScale < 1, who .. "one step larger does not fit with the margin (" .. tostring(more.fitScale) .. ")")
          H.eq(again.fitScale, 1, who .. "the fitted layout itself needs no further shrinking")
        end
      else
        -- not even the minimum: at 0.64 something is still missing, and the log says so in words
        local k = BF.MIN_SCALE / m.scale
        resize(W, win.w / k, win.h / k)
        local again = BF.measure()
        H.ok(again.outside + again.covered > 0, who .. "really does not fit at the minimum scale")
        H.ok(BF.summary(m):find("not even 0.64", 1, true) ~= nil, who .. "summary says it: " .. BF.summary(m))
      end
    end
  end
end

-- expected numbers for the cases the owner sees (scale 1 = UI units are the window's)
do
  local W, ns = boot("era", 900, 720)
  eraBars(W.env, { bottomLeft = true, bottomRight = true })
  local m = ns.BarFit.update("test")
  -- the bottom bars need 1012 + 2 x margin units: 900 / 1020 = 0.88
  H.eq(m.fitScale, 0.88, "era 900x720, bars 1+2+3: fit scale 0.88")
  local W2, ns2 = boot("forever", 900, 720)
  foreverBars(W2.env, { bottomLeft = true, bottomRight = true, right = true, left = true })
  local m2 = ns2.BarFit.update("test")
  H.eq(m2.outside + m2.covered, 0, "forever 900x720 with all bars fits as it is: " .. ns2.BarFit.summary(m2))
  local W3, ns3 = boot("forever", 640, 512)
  foreverBars(W3.env, { bottomLeft = true, bottomRight = true, right = true, left = true })
  local m3 = ns3.BarFit.update("test")
  H.ok(m3.covered > 0, "forever 640x512 with all bars: the right bars lie on bars 1-3 (" .. m3.covered .. ")")
  H.ok(m3.fitScale and m3.fitScale < 1, "forever 640x512: a smaller scale fits: " .. tostring(m3.fitScale))
end

-- a UI scale already below 1 (Auto-fit wrote 0.93): the fit scale is an absolute UI scale, not relative
do
  local W, ns = boot("era", 900, 720)
  W.env.UIParent:SetScale(0.93)
  eraBars(W.env, { bottomLeft = true, bottomRight = true })
  local m = ns.BarFit.update("test")
  H.eq(m.scale, 0.93, "the current UI scale is reported")
  -- same window in UI units as above at scale 1, so the needed shrink factor is the same: 0.93 x 0.88 = 0.82
  H.ok(m.fitScale and math.abs(m.fitScale - 0.82) <= 0.011, "fit scale is absolute: " .. tostring(m.fitScale))
end

-- empty slots with the grid off: the buttons are hidden but the bar is on, so they still count
do
  local W, ns = boot("era", 1707, 960)
  eraBars(W.env, { bottomLeft = true })
  for i = 1, 6 do W.env["MultiBarBottomLeftButton" .. i]:Hide() end
  local m = ns.BarFit.update("test")
  local bl
  for _, b in ipairs(m.bars) do if b.key == "bottomLeft" then bl = b end end
  H.eq(bl and bl.buttons, 12, "empty buttons of a shown bar count")
end

-- no bars at all (another addon replaces them): nothing to fit, no error
do
  local W, ns = boot("forever", 900, 720)
  local m = ns.BarFit.update("test")
  H.eq(#m.bars, 0, "no Blizzard bars: an empty list")
  H.eq(m.fitScale, nil, "and no fit scale")
  local errs = 0
  for _, e in ipairs(ns.Core.db.log) do if e.l == "error" then errs = errs + 1 end end
  H.eq(errs, 0, "no errors")
end

-- read only: measuring never moves, scales or hides a bar
do
  local W, ns = boot("era", 900, 720)
  eraBars(W.env, { bottomLeft = true, bottomRight = true, right = true, left = true })
  local before = {}
  for _, n in ipairs({ "MainMenuBar", "MultiBarBottomLeft", "MultiBarBottomRight", "MultiBarRight", "MultiBarLeft" }) do
    local f = W.env[n]; before[n] = { f:GetScale(), f._shown, #f._points }
  end
  ns.BarFit.update("test")
  for n, b in pairs(before) do
    local f = W.env[n]
    H.ok(f:GetScale() == b[1] and f._shown == b[2] and #f._points == b[3], n .. " is untouched")
  end
end

-- /wbx barfit prints the summary and one line per bar
do
  local W, ns = boot("era", 900, 720)
  eraBars(W.env, { bottomLeft = true })
  local printed = {}
  W.env.DEFAULT_CHAT_FRAME = { AddMessage = function(_, t) printed[#printed + 1] = t end }
  ns.Core.slash("barfit")
  local all = table.concat(printed, "\n")
  H.ok(all:find("fits all at scale", 1, true) ~= nil, "/wbx barfit prints the summary: " .. all)
  H.ok(all:find("Bottom Left bar (bar 2): 12 buttons", 1, true) ~= nil, "/wbx barfit lists each bar")
end

H.report("barfit")
