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

-- the real Forever layout (live log 6 Nov 2026, 2560x1369 window, UI 2244x1200 at 0.64): bar 1 two units above the
-- bottom edge, left of centre; bars 2 and 3 side by side above it; the bag and menu buttons right of bar 1.
-- Everything fits, so the fit scale must not be "none" (the margin bug), and the menu buttons are measured.
local function foreverReal(env)
  local main = env.CreateFrame("Frame", "MainMenuBar", env.UIParent); main:SetSize(562, 45); main:SetPoint("BOTTOM", env.UIParent, "BOTTOM", -320, 2)
  buttons(env, main, "ActionButton", 45, 2)
  local bl = env.CreateFrame("Frame", "MultiBarBottomLeft", main); bl:SetSize(562, 45); bl:SetPoint("BOTTOMLEFT", main, "TOPLEFT", 22, 25)
  buttons(env, bl, "MultiBarBottomLeftButton", 45, 2)
  local br = env.CreateFrame("Frame", "MultiBarBottomRight", main); br:SetSize(562, 45); br:SetPoint("LEFT", bl, "RIGHT", 22, 0)
  buttons(env, br, "MultiBarBottomRightButton", 45, 2)
  local menu = env.CreateFrame("Frame", "WbxTestMenu", main); menu:SetSize(617, 45); menu:SetPoint("LEFT", main, "RIGHT", 9, 0)
  local prev
  for _, n in ipairs({ "CharacterMicroButton", "SpellbookMicroButton", "QuestLogMicroButton", "MainMenuMicroButton", "HelpMicroButton",
    "CharacterBag3Slot", "CharacterBag2Slot", "CharacterBag1Slot", "CharacterBag0Slot", "MainMenuBarBackpackButton" }) do
    local b = env.CreateFrame("Button", n, menu); b:SetSize(40, 45)
    if prev then b:SetPoint("LEFT", prev, "RIGHT", 2, 0) else b:SetPoint("BOTTOMLEFT", menu, "BOTTOMLEFT", 0, 0) end
    prev = b
  end
  local hidden = env.CreateFrame("Button", "StoreMicroButton", menu); hidden:SetSize(40, 45); hidden:SetPoint("BOTTOMLEFT", env.UIParent, "BOTTOMLEFT", -500, 0); hidden:Hide()
end
do
  local W, ns = boot("forever", 2244, 1200)
  W.env.UIParent:SetScale(0.64)
  foreverReal(W.env)
  local m = ns.BarFit.update("test")
  H.eq(m.outside + m.covered, 0, "real forever layout fits as it is: " .. ns.BarFit.summary(m))
  H.ok(m.fitScale ~= nil, "and has a fit scale (bar 1 two units above the bottom edge is not 'outside'): " .. tostring(m.fitScale))
  local menu
  for _, b in ipairs(m.bars) do if b.key == "menu" then menu = b end end
  H.ok(menu ~= nil, "the bag and menu buttons are measured")
  H.eq(menu and menu.buttons, 10, "only the shown menu buttons count (a hidden shop button does not)")
  H.eq(menu and menu.anchor, "center/bottom", "the menu rides on the main bar")
  -- in a follower window (870x696 drawn at scale 1: 960x768 units) buttons are cut, like the owner's snapshot
  local W2, ns2 = boot("forever", 960, 768)
  foreverReal(W2.env)
  local m2 = ns2.BarFit.update("test")
  local cut = {}
  for _, b in ipairs(m2.bars) do if b.outside > 0 then cut[b.key] = true end end
  -- (the game pushes the clamped group against the left edge so the right end goes; this mock does not clamp, so bar 1's
  -- left end goes instead – the needed width is the same)
  H.ok(cut.bottomRight and cut.main, "follower window: buttons are cut: " .. ns2.BarFit.summary(m2))
  H.ok(m2.fitScale and m2.fitScale <= 0.80 and m2.fitScale >= 0.75, "follower window: a fit scale near the app's 0.79: " .. tostring(m2.fitScale))
end

-- the game keeps bars on the screen in a too small window: it pushes them (live Forever 9 Nov, 960x768 units: bar 1
-- at the left edge, bar 3 at the right edge on top of bar 2). Simulated: the frames sit pushed, GetPoint still says
-- where the anchors put them. The measurement says how far (dx), and the fit scale uses the anchored places.
do
  local W, ns = boot("forever", 960, 768)
  foreverReal(W.env)
  local main, br = W.env.MainMenuBar, W.env.MultiBarBottomRight
  main:ClearAllPoints(); main:SetPoint("BOTTOM", W.env.UIParent, "BOTTOM", -199, 2)          -- left end at 0
  main.GetPoint = function() return "BOTTOM", W.env.UIParent, "BOTTOM", -320, 2 end
  br:ClearAllPoints(); br:SetPoint("LEFT", W.env.MultiBarBottomLeft, "RIGHT", -186, 0)         -- right end at 960
  br.GetPoint = function() return "LEFT", W.env.MultiBarBottomLeft, "RIGHT", 22, 0 end
  local m = ns.BarFit.update("test")
  local by = {}
  for _, b in ipairs(m.bars) do by[b.key] = b end
  H.eq(by.main.left, 0, "bar 1 sits at the left edge")
  H.eq(by.main.dx, 121, "pushed 121 units right")
  H.eq(by.bottomRight.right, 960, "bar 3 sits at the right edge")
  H.eq(by.bottomRight.dx, -87, "pushed back 208 left of its anchor, net of bar 1's push: " .. tostring(by.bottomRight.dx))
  H.ok(by.bottomRight.covered > 0, "and lies on bar 2")
  H.eq(m.squeezed, true, "the measurement says it was squeezed")
  H.ok(m.fitScale and m.fitScale >= 0.75 and m.fitScale <= 0.80, "the fit scale comes from the anchored places: " .. tostring(m.fitScale))
  -- a big window: nothing pushed
  local W2, ns2 = boot("forever", 2244, 1200)
  W2.env.UIParent:SetScale(0.64)
  foreverReal(W2.env)
  local m2 = ns2.BarFit.update("test")
  H.eq(m2.squeezed, false, "big window: not squeezed")
  for _, b in ipairs(m2.bars) do H.ok(b.dx == 0 and b.dy == 0, "big window: " .. b.key .. " not pushed") end
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

-- the owner's follower (live Forever 10 Nov, 870x696 at scale 1 = 960x768 units): bar 1 pushed against the left edge,
-- the bag and menu box at the right edge on top of bar 1. Until 1.3.0-test.3 the menu never counted as covered.
local function ownerFollower(W)
  foreverReal(W.env)
  local env = W.env
  local main, br, menu = env.MainMenuBar, env.MultiBarBottomRight, env.WbxTestMenu
  main:ClearAllPoints(); main:SetPoint("BOTTOM", env.UIParent, "BOTTOM", -199, 2)
  main.GetPoint = function() return "BOTTOM", env.UIParent, "BOTTOM", -320, 2 end
  br:ClearAllPoints(); br:SetPoint("LEFT", env.MultiBarBottomLeft, "RIGHT", -186, 0)
  br.GetPoint = function() return "LEFT", env.MultiBarBottomLeft, "RIGHT", 22, 0 end
  -- the menu stays where its (centre) anchor puts it, 4.5 right of bar 1's anchored end; only bar 1 was pushed onto it
  menu:ClearAllPoints(); menu:SetPoint("BOTTOMLEFT", env.UIParent, "BOTTOM", -34.5, 2)
end
do
  local W, ns = boot("forever", 960, 768)
  ownerFollower(W)
  local m = ns.BarFit.update("test")
  local by = {}
  for _, b in ipairs(m.bars) do by[b.key] = b end
  H.ok(by.menu.covered > 0, "the menu box lying on bar 1 counts as covered: " .. ns.BarFit.summary(m))
  H.ok(by.main.covered > 0, "and bar 1 is covered by it")
  H.eq(m.squeezed, true, "squeezed")
  H.ok(m.fitScale and m.fitScale >= 0.70 and m.fitScale <= 0.80, "a fit scale near the app's 0.79: " .. tostring(m.fitScale))
end

-- Era: the tall micro buttons (28x58, art in the lower part) touch bar 3 above them by a few units: not covered
do
  local W, ns = boot("era", 1707, 960)
  eraBars(W.env, { bottomLeft = true, bottomRight = true })
  local b = W.env.CreateFrame("Button", "CharacterMicroButton", W.env.MainMenuBar); b:SetSize(28, 58)
  b:SetPoint("BOTTOMLEFT", W.env.MainMenuBar, "BOTTOMLEFT", 552, 2)
  local m = ns.BarFit.update("test")
  H.eq(m.covered, 0, "era: a micro button touching bar 3 is not 'covered': " .. ns.BarFit.summary(m))
  H.eq(m.squeezed, false, "era big window: nothing to fit")
end

-- the fit offer (owner 10 Nov): one popup at login when the bars overlap; nothing changes without the click
local function offerBoot(w, h, setup)
  local W, ns = boot("forever", w, h)
  W.cvars.useUiScale, W.cvars.uiScale = "0", "1.0"
  ;(setup or ownerFollower)(W)
  W.popups = {}
  ns.UI.Popup = function(text, buttons) W.popups[#W.popups + 1] = { text = text, buttons = buttons } end
  return W, ns
end
local function click(W, label)
  local p = W.popups[#W.popups]
  for _, b in ipairs(p and p.buttons or {}) do if b[1] == label then b[2]() return true end end
  return false
end
do
  local W, ns = offerBoot(960, 768)
  local BF = ns.BarFit
  H.eq(ns.Core.loginChecks(), true, "login checks show the fit offer")
  H.eq(#W.popups, 1, "one popup")
  local p = W.popups[1]
  local fit = string.format("%.2f", ns.Core.db.bridge.bars.fitScale)
  H.ok(p.text:find("Action bars overlap in this window.", 1, true) and p.text:find("sets UI Scale to " .. fit, 1, true), "the text names the scale: " .. p.text)
  H.ok(p.text:find("Auto-fit does the same for all clients", 1, true) ~= nil, "and mentions the window app's Auto-fit")
  H.eq(p.buttons[1][1], "Fit now", "first button Fit now")
  H.eq(p.buttons[2][1], "Not now", "second button Not now")
  H.eq(W.cvars.uiScale, "1.0", "asking writes nothing (rule 4)")
  H.eq(W.cvars.useUiScale, "0", "asking writes nothing (useUiScale)")
  click(W, "Not now")
  H.eq(W.cvars.uiScale, "1.0", "Not now writes nothing")
  H.eq(BF.offer(), false, "asks once per login")
  ns.Core.loginChecks()
  H.eq(#W.popups, 1, "login checks do not ask again this login")

  -- the next login: Fit now sets useUiScale 1 and the fit scale, read back
  BF.asked = nil
  H.eq(BF.offer(), true, "asks again at the next login while it does not fit")
  click(W, "Fit now")
  H.eq(W.cvars.useUiScale, "1", "Fit now: useUiScale 1")
  H.eq(W.cvars.uiScale, fit, "Fit now: uiScale " .. fit)
  local okLog = false
  for _, e in ipairs(ns.Core.db.log) do if e.l == "info" and e.m:find("fit: useUiScale 1", 1, true) then okLog = true end end
  H.ok(okLog, "logged with the read-back")
end
-- combat: the popup waits for combat to end; a click in combat is queued until then
do
  local W, ns = offerBoot(960, 768)
  W.combat = true
  H.eq(ns.BarFit.offer(), false, "in combat: no popup")
  H.eq(#W.popups, 0, "nothing shown in combat")
  W.combat = false
  W.fire("PLAYER_REGEN_ENABLED")
  H.eq(#W.popups, 1, "shown when combat ends")
  W.combat = true
  click(W, "Fit now")
  H.eq(W.cvars.uiScale, "1.0", "Fit now in combat: nothing yet")
  W.combat = false
  W.fire("PLAYER_REGEN_ENABLED")
  H.ok(W.cvars.uiScale ~= "1.0" and W.cvars.useUiScale == "1", "applied after combat: " .. tostring(W.cvars.uiScale))
  H.eq(#W.popups, 1, "and not asked again")
end
-- bars that fit: no popup; already at the fit scale: no popup
do
  local W, ns = offerBoot(2244, 1200, function(W) W.env.UIParent:SetScale(0.64); foreverReal(W.env) end)
  H.eq(ns.BarFit.offer(), false, "bars fit: no popup")
  H.eq(#W.popups, 0, "nothing shown")
  H.eq(ns.BarFit.needsFit({ bars = { {} }, squeezed = true, outside = 0, covered = 1, scale = 0.79, fitScale = 0.79 }), false,
    "already at the fit scale: nothing to offer")
  local need, fit = ns.BarFit.needsFit({ bars = { {} }, squeezed = true, outside = 3, covered = 0, scale = 1, fitScale = nil })
  H.ok(need and fit == nil, "not even the minimum: still told")
end
-- not even the minimum scale fits: a plain notice, no Fit button, nothing written
do
  local W, ns = offerBoot(400, 300, function(W) foreverReal(W.env) end)
  H.eq(ns.BarFit.offer(), true, "tiny window: told")
  local p = W.popups[1]
  H.ok(p.text:find("even the smallest UI Scale", 1, true) ~= nil, "says even the smallest scale is not enough: " .. p.text)
  H.eq(#p.buttons, 1, "only OK")
  click(W, "OK")
  H.eq(W.cvars.uiScale, "1.0", "nothing written")
end
-- the read-back: a client that does not take the value says so in chat (no silent success)
do
  local W, ns = offerBoot(960, 768)
  local printed = {}
  W.env.DEFAULT_CHAT_FRAME = { AddMessage = function(_, t) printed[#printed + 1] = t end }
  local set = W.env.C_CVar.SetCVar
  W.env.C_CVar.SetCVar = function(n, v) if n == "uiScale" then return true end return set(n, v) end
  H.eq(ns.BarFit.applyFit(0.79), false, "uiScale did not stick: not ok")
  H.ok(table.concat(printed, "\n"):find("Could not set the UI Scale", 1, true) ~= nil, "and says so: " .. table.concat(printed, " | "))
  W.env.C_CVar.SetCVar = set
  H.eq(ns.BarFit.applyFit(0.79), true, "a value read back as 0.79 is ok")
  W.env.C_CVar.SetCVar = function(n, v) if n == "uiScale" then W.cvars.uiScale = "0.790000" return true end return set(n, v) end
  H.eq(ns.BarFit.applyFit(0.79), true, "read back as 0.790000: still ok (numeric compare)")
end

H.report("barfit")
