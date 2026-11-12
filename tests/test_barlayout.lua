-- Fit the action bars to each window (owner 12 Nov 2026): UI Scale is one value for every client of an install and
-- cannot fit every window shape, so WoWBoxer scales the bottom bars of this window just enough to fit, stacks them
-- in more rows below the smallest size (70 %), never onto the chat, the unit frames or the side bars, only out of
-- combat, and puts the game's layout back when turned off. Windows are real pixel sizes at the owner's UI scales.
local dir = (arg[0]:match("^(.*)/[^/]+$") or ".")
local H = dofile(dir .. "/harness.lua")
local Mock = dofile(dir .. "/wowmock.lua")

--- A window of wpx x hpx pixels drawn at UI scale `scale`: UIParent is 768 / scale units high (the game's rule).
local function units(wpx, hpx, scale)
  local h = 768 / scale
  return h * wpx / hpx, h
end
local function boot(game, w, h, opts)
  opts = opts or {}
  local W = Mock.new(H, { toc = game == "forever" and 16001 or 11509, screen = { w = w, h = h }, addons = opts.addons })
  local ns = H.loadAddon({ env = W.env, gameType = game == "forever" and "camelot" or nil })
  W.fire("ADDON_LOADED", "WoWBoxer"); W.fire("PLAYER_LOGIN")
  return W, ns
end

local function buttons(env, bar, prefix, n, size, gap, vertical)
  local list = {}
  for i = 1, n do
    local name = type(prefix) == "table" and prefix[i] or (prefix .. i)
    local b = env.CreateFrame("CheckButton", name, bar)
    b:SetSize(size, size)
    if i == 1 then b:SetPoint(vertical and "TOPLEFT" or "BOTTOMLEFT", bar, vertical and "TOPLEFT" or "BOTTOMLEFT", 0, 0)
    elseif vertical then b:SetPoint("TOP", list[i - 1], "BOTTOM", 0, -gap)
    else b:SetPoint("LEFT", list[i - 1], "RIGHT", gap, 0) end
    list[i] = b
  end
  return list
end

local MICRO = { "CharacterMicroButton", "SpellbookMicroButton", "TalentMicroButton", "AchievementMicroButton", "QuestLogMicroButton",
  "SocialsMicroButton", "GuildMicroButton", "WorldMapMicroButton", "LFDMicroButton", "CollectionsMicroButton", "MainMenuMicroButton",
  "HelpMicroButton" }
local BAGS = { "CharacterBag3Slot", "CharacterBag2Slot", "CharacterBag1Slot", "CharacterBag0Slot", "MainMenuBarBackpackButton" }

--- Forever's Edit Mode bars, as measured on the owner's clients (12 Nov): every bar its own frame under UIParent,
--- bar 1 at centre − 601, bars 2 and 3 side by side 72 up, the menu and bags right of bar 1 (centre − 35 … + 590).
--- on = {bottomLeft, bottomRight, right, left}
local function forever(env, on)
  local U = env.UIParent
  local function bar(name, x, y, w)
    local f = env.CreateFrame("Frame", name, U); f:SetSize(w, 45); f:SetPoint("BOTTOMLEFT", U, "BOTTOM", x, y)
    return f
  end
  buttons(env, bar("MainMenuBar", -601, 2, 562), "ActionButton", 12, 45, 2)
  local bl = bar("MultiBarBottomLeft", -579, 72, 562); buttons(env, bl, "MultiBarBottomLeftButton", 12, 45, 2)
  local br = bar("MultiBarBottomRight", 5, 72, 562); buttons(env, br, "MultiBarBottomRightButton", 12, 45, 2)
  buttons(env, bar("MicroMenuContainer", -35, 2, 394), MICRO, 12, 32, 1)
  buttons(env, bar("BagsBar", 365, 2, 225), BAGS, 5, 41, 5)
  local r = env.CreateFrame("Frame", "MultiBarRight", U); r:SetSize(45, 562); r:SetPoint("RIGHT", U, "RIGHT", -5, 0)
  buttons(env, r, "MultiBarRightButton", 12, 45, 2, true)
  local l = env.CreateFrame("Frame", "MultiBarLeft", U); l:SetSize(45, 562); l:SetPoint("RIGHT", r, "LEFT", -2, 0)
  buttons(env, l, "MultiBarLeftButton", 12, 45, 2, true)
  local chat = env.CreateFrame("Frame", "ChatFrame1", U); chat:SetSize(430, 120); chat:SetPoint("BOTTOMLEFT", U, "BOTTOMLEFT", 32, 140)
  local pf = env.CreateFrame("Frame", "PlayerFrame", U); pf:SetSize(232, 100); pf:SetPoint("TOPLEFT", U, "TOPLEFT", 20, -20)
  if not on.bottomLeft then bl:Hide() end
  if not on.bottomRight then br:Hide() end
  if not on.right then r:Hide() end
  if not on.left then l:Hide() end
end

--- Classic Era: one 1024-wide main bar (art) holds bar 1, bars 2 and 3, the menu and the bags.
local function era(env, on)
  local U = env.UIParent
  local main = env.CreateFrame("Frame", "MainMenuBar", U); main:SetSize(1024, 53); main:SetPoint("BOTTOM", U, "BOTTOM", 0, 0)
  local art = env.CreateFrame("Frame", "MainMenuBarArtFrame", main); art:SetAllPoints(main)
  local row = env.CreateFrame("Frame", "WbxRow", art); row:SetSize(498, 36); row:SetPoint("BOTTOMLEFT", main, "BOTTOMLEFT", 8, 4)
  buttons(env, row, "ActionButton", 12, 36, 6)
  local menu = env.CreateFrame("Frame", "WbxMenu", art); menu:SetSize(480, 36); menu:SetPoint("BOTTOMLEFT", main, "BOTTOMLEFT", 540, 4)
  buttons(env, menu, MICRO, 8, 28, 1)
  local bl = env.CreateFrame("Frame", "MultiBarBottomLeft", main); bl:SetSize(498, 36); bl:SetPoint("BOTTOMLEFT", main, "BOTTOMLEFT", 8, 53)
  buttons(env, bl, "MultiBarBottomLeftButton", 12, 36, 6)
  local br = env.CreateFrame("Frame", "MultiBarBottomRight", main); br:SetSize(498, 36); br:SetPoint("LEFT", bl, "RIGHT", 12, 0)
  buttons(env, br, "MultiBarBottomRightButton", 12, 36, 6)
  local r = env.CreateFrame("Frame", "MultiBarRight", U); r:SetSize(36, 498); r:SetPoint("BOTTOMRIGHT", U, "BOTTOMRIGHT", -6, 98)
  buttons(env, r, "MultiBarRightButton", 12, 36, 6, true)
  if not on.bottomLeft then bl:Hide() end
  if not on.bottomRight then br:Hide() end
  if not on.right then r:Hide() end
end

local BOTTOM = { "ActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton" }
--- Every shown bottom button's rect, by bar.
local function bottomRects(W)
  local out = {}
  local function add(key, b) if b and b:IsVisible() then out[#out + 1] = { key = key, r = W.rect(b), name = b:GetName() } end end
  for _, p in ipairs(BOTTOM) do for i = 1, 12 do add(p, W.env[p .. i]) end end
  for _, n in ipairs(MICRO) do add("menu", W.env[n]) end
  for _, n in ipairs(BAGS) do add("bags", W.env[n]) end
  return out
end
local function hit(a, b) return a[1] < b[3] - 1 and b[1] < a[3] - 1 and a[2] < b[4] - 1 and b[2] < a[4] - 1 end
--- Problems in the window as it is drawn now: buttons outside, bars on each other, bars on the chat / side bars.
local function check(W, w, h)
  local list = bottomRects(W)
  local outside, onEach, onOther = 0, 0, 0
  for _, x in ipairs(list) do
    if x.r[1] < -0.5 or x.r[3] > w + 0.5 or x.r[2] < -0.5 or x.r[4] > h + 0.5 then outside = outside + 1 end
  end
  for i = 1, #list do for j = i + 1, #list do
    if list[i].key ~= list[j].key and hit(list[i].r, list[j].r) then onEach = onEach + 1 end
  end end
  for _, n in ipairs({ "ChatFrame1", "PlayerFrame" }) do
    local f = W.env[n]
    if f and f:IsVisible() then for _, x in ipairs(list) do if hit(x.r, W.rect(f)) then onOther = onOther + 1 end end end
  end
  for i = 1, 12 do
    local b = W.env["MultiBarRightButton" .. i]
    if b and b:IsVisible() then for _, x in ipairs(list) do if hit(x.r, W.rect(b)) then onOther = onOther + 1 end end end
  end
  return outside, onEach, onOther
end
local function snapshot(env)
  local t = {}
  for _, n in ipairs({ "MainMenuBar", "MultiBarBottomLeft", "MultiBarBottomRight", "MicroMenuContainer", "BagsBar" }) do
    local f = env[n]
    if f then
      local pts = {}
      for i = 1, f:GetNumPoints() do local a, b, c, d, e = f:GetPoint(i); pts[i] = table.concat({ a, tostring(b), c, d, e }, ",") end
      t[n] = table.concat(pts, ";") .. " @" .. f:GetScale()
    end
  end
  return t
end
local function fit(W, ns)
  ns.BarFit.request("test")
  for _ = 1, 4 do W.flush() end
  return ns.BarFit.state
end

-- 1. The window sizes the owner uses, every bar combination, both games
local WINDOWS = { { 870, 696 }, { 1000, 1080 }, { 640, 1080 }, { 1690, 1392 }, { 2560, 1440 }, { 1280, 1392 } }
local SETS = {
  { name = "bar 1", on = {} },
  { name = "bars 1+2", on = { bottomLeft = true } },
  { name = "bars 1+2+3", on = { bottomLeft = true, bottomRight = true } },
  { name = "bars 1+2+3 + side bars", on = { bottomLeft = true, bottomRight = true, right = true, left = true } },
}
local GAMES = { { "forever", forever, 0.74 }, { "forever", forever, 0.69 }, { "era", era, 1 } }
local seen = {}
for _, gm in ipairs(GAMES) do
  local game, build, scale = gm[1], gm[2], gm[3]
  for _, set in ipairs(SETS) do
    for _, win in ipairs(WINDOWS) do
      local w, h = units(win[1], win[2], scale)
      local W, ns = boot(game, w, h)
      build(W.env, set.on)
      local who = string.format("%s %dx%d at UI scale %.2f, %s: ", game, win[1], win[2], scale, set.name)
      local o0, e0 = check(W, w, h)
      local before = snapshot(W.env)
      local st = fit(W, ns)
      local o, e, x = check(W, w, h)
      seen[st.mode] = (seen[st.mode] or 0) + 1
      if st.mode == "nofit" then
        H.eq(snapshot(W.env).MainMenuBar, before.MainMenuBar, who .. "nothing fits even stacked: the default layout stays")
        local said = false
        for _, l in ipairs(W.chat) do if l:find("don't fit this window, even stacked", 1, true) then said = true end end
        H.ok(said, who .. "one short chat line says so")
      else
        H.eq(o, 0, who .. st.mode .. ": no button outside the window")
        H.eq(e, 0, who .. st.mode .. ": no bar on another bar")
        H.eq(x, 0, who .. st.mode .. ": nothing on the chat, the unit frames or the side bars")
        if st.mode == "none" then
          H.eq(o0 + e0, 0, who .. "it fitted already, nothing moved")
          H.eq(snapshot(W.env).MainMenuBar, before.MainMenuBar, who .. "bar 1 untouched")
        else
          H.ok(o0 + e0 > 0 or st.mode ~= "none", who .. "it needed fitting")
          H.ok(st.scale >= 0.70 - 1e-6 and st.scale <= 1, who .. "the size is " .. st.scale .. " (never below 70 %)")
          H.eq(ns.Core.db.bridge.barFit, true, who .. "the window app is told (bridge.barFit)")
          H.eq(ns.Core.db.bridge.barScale, st.scale, who .. "and the size (bridge.barScale)")
          -- turning it off puts back exactly the game's layout
          ns.BarFit.setFit(false)
          local after = snapshot(W.env)
          for k, v in pairs(before) do H.eq(after[k], v, who .. "off: " .. k .. " back to its own points and scale") end
          H.eq(ns.Core.db.bridge.barFit, false, who .. "off: the bridge says so")
        end
      end
    end
  end
end
H.ok((seen.none or 0) > 0 and (seen.scale or 0) > 0 and (seen.stack or 0) > 0, "every mode is covered: none " ..
  tostring(seen.none) .. ", scale " .. tostring(seen.scale) .. ", stack " .. tostring(seen.stack) .. ", nofit " .. tostring(seen.nofit))

-- 2. The expected answers for the owner's windows
local function case(game, wpx, hpx, scale, on)
  local w, h = units(wpx, hpx, scale)
  local W, ns = boot(game, w, h)
  ;(game == "forever" and forever or era)(W.env, on or { bottomLeft = true, bottomRight = true })
  return W, ns, fit(W, ns), w, h
end
do
  local _, _, st = case("forever", 1280, 1392, 0.69, { bottomLeft = true, bottomRight = true, right = true })
  H.eq(st.mode, "scale", "the owner's 1280x1392 followers (UI scale 0.69): scaled, not stacked")
  H.ok(st.scale >= 0.84 and st.scale <= 0.86, "to about 85 % (1016 of 1190 units): " .. st.scale)
  local _, _, st2 = case("forever", 870, 696, 0.74)
  H.eq(st2.mode, "none", "870x696 at 0.74: fits as it is (1297 units wide)")
  -- a narrow 640x1080 window: a stack would lie on the chat (bottom left, 140 up): the hint instead
  local _, _, stN = case("forever", 640, 1080, 0.74)
  H.eq(stN.mode, "nofit", "640x1080 with the chat at the bottom left: not stacked onto the chat")
  -- with the chat moved up, the same window stacks
  local w3, h3 = units(640, 1080, 0.74)
  local W3, ns3 = boot("forever", w3, h3)
  forever(W3.env, { bottomLeft = true, bottomRight = true })
  W3.env.ChatFrame1:ClearAllPoints(); W3.env.ChatFrame1:SetPoint("BOTTOMLEFT", W3.env.UIParent, "BOTTOMLEFT", 32, 400)
  local st3 = fit(W3, ns3)
  H.eq(st3.mode, "stack", "640x1080, chat moved up: stacked")
  H.ok(st3.scale >= 0.7, "stacked at " .. st3.scale)
  -- stacked: bar 2 above bar 1, bar 3 above bar 2, centred
  local b1, b2, b3 = W3.rect(W3.env.ActionButton1), W3.rect(W3.env.MultiBarBottomLeftButton1), W3.rect(W3.env.MultiBarBottomRightButton1)
  H.ok(b2[2] > b1[4] and b3[2] > b2[4], "stacked rows: bar 1, then bar 2, then bar 3 above it")
  local l, r = W3.rect(W3.env.ActionButton1)[1], W3.rect(W3.env.ActionButton12)[3]
  H.ok(math.abs((l + r) / 2 - w3 / 2) < 1, "bar 1 stays at the bottom centre")
  local _, _, st4 = case("era", 870, 696, 1)
  H.eq(st4.mode, "scale", "era 870x696: scaled")
  H.ok(st4.scale >= 0.92 and st4.scale <= 0.94, "to about 93 % (952 of 1024 units): " .. st4.scale)
end

-- 3. Combat: nothing moves in combat; it is done when combat ends
do
  local w, h = units(1280, 1392, 0.69)
  local W, ns = boot("forever", w, h)
  forever(W.env, { bottomLeft = true, bottomRight = true })
  local before = snapshot(W.env)
  W.combat = true
  fit(W, ns)
  H.eq(snapshot(W.env).MainMenuBar, before.MainMenuBar, "in combat: nothing moves")
  H.eq(ns.BarFit.pending, "fit", "it waits for combat to end")
  W.combat = false
  W.fire("PLAYER_REGEN_ENABLED")
  for _ = 1, 4 do W.flush() end
  H.eq(ns.BarFit.state.mode, "scale", "fitted when combat ends")
  local o, e = check(W, w, h)
  H.eq(o + e, 0, "and everything fits")
  -- turned off in combat: back to the default once combat ends
  W.combat = true
  ns.BarFit.setFit(false)
  H.ok(snapshot(W.env).MainMenuBar ~= before.MainMenuBar, "off in combat: not yet")
  W.combat = false
  W.fire("PLAYER_REGEN_ENABLED")
  H.eq(snapshot(W.env).MainMenuBar, before.MainMenuBar, "off: restored after combat")
end

-- 4. A bar addon owns the bars: nothing is done
do
  local w, h = units(1280, 1392, 0.69)
  local W, ns = boot("forever", w, h)
  forever(W.env, { bottomLeft = true, bottomRight = true })
  W.env.C_AddOns.IsAddOnLoaded = function(n) return n == "Bartender4" end
  local before = snapshot(W.env)
  local st = fit(W, ns)
  H.eq(st.mode, "addon", "Bartender4 loaded: nothing done")
  H.eq(snapshot(W.env).MainMenuBar, before.MainMenuBar, "bars untouched")
  H.ok(ns.BarFit.fitSummary():find("Bartender4", 1, true) ~= nil, "/wbx barfit says why")
end

-- 5. Edit Mode: open = the game's layout back (to edit it), closed = fitted again
do
  local w, h = units(1280, 1392, 0.69)
  local W, ns = boot("forever", w, h)
  local E = W.env.CreateFrame("Frame", "EditModeManagerFrame", W.env.UIParent); E:Hide()
  E.IsEditModeActive = function(self) return self:IsShown() end
  forever(W.env, { bottomLeft = true, bottomRight = true })
  ns.BarFit.inited = nil; ns.BarFit.Init()
  local before = snapshot(W.env)
  fit(W, ns)
  H.eq(ns.BarFit.state.mode, "scale", "fitted")
  E:Show()
  H.eq(snapshot(W.env).MainMenuBar, before.MainMenuBar, "Edit Mode opened: the game's layout is back")
  fit(W, ns)
  H.eq(ns.BarFit.state.mode, "editmode", "no fitting while Edit Mode is open")
  E:Hide()
  for _ = 1, 4 do W.flush() end
  H.eq(ns.BarFit.state.mode, "scale", "Edit Mode closed: fitted again")
end

-- 6. Bars turned on and off, and the game moving a bar itself
do
  local w, h = units(1280, 1392, 0.69)
  local W, ns = boot("forever", w, h)
  W.now = 100 -- the game's clock (the mock's own clock ticks on every log line)
  forever(W.env, { bottomLeft = true })
  ns.BarFit.inited = nil; ns.BarFit.Init()
  local st = fit(W, ns)
  local s1 = st.scale
  W.env.MultiBarBottomRight:Show()
  for _ = 1, 4 do W.flush() end
  local o, e = check(W, w, h)
  H.eq(o + e, 0, "bar 3 turned on: refitted, everything fits (" .. ns.BarFit.state.mode .. " " .. ns.BarFit.state.scale .. ")")
  H.ok(s1 >= ns.BarFit.state.scale, "bar 1+2 needed no smaller size than 1+2+3")
  -- the game re-anchors bar 2 (an Edit Mode re-layout): that is its own layout now, and it is fitted from there
  local bl = W.env.MultiBarBottomLeft
  bl:ClearAllPoints(); bl:SetPoint("BOTTOMLEFT", W.env.UIParent, "BOTTOM", -579, 72)
  H.eq(ns.BarFit.managed[bl] and ns.BarFit.managed[bl].points, nil, "the game's points are kept, not overwritten later")
  for _ = 1, 4 do W.flush() end
  o, e = check(W, w, h)
  H.eq(o + e, 0, "fitted again after the game's re-layout")
  ns.BarFit.setFit(false)
  local p1, _, p3, x, y = bl:GetPoint(1)
  H.ok(p1 == "BOTTOMLEFT" and p3 == "BOTTOM" and x == -579 and y == 72, "off: bar 2 at the game's last place")
  -- a game that keeps moving it back wins: no endless fight
  ns.BarFit.setFit(true)
  for _ = 1, 4 do W.flush() end
  for _ = 1, 10 do bl:SetPoint("BOTTOMLEFT", W.env.UIParent, "BOTTOM", -579, 72); W.flush() end
  H.eq(ns.BarFit.gaveUp, true, "stops after a few rounds")
end

-- 7. No popup at login any more, the setting is on by default, the summary
do
  local w, h = units(1280, 1392, 0.69)
  local W, ns = boot("forever", w, h)
  forever(W.env, { bottomLeft = true, bottomRight = true })
  local popups = 0
  ns.UI.Popup = function() popups = popups + 1 end
  W.cvars.uiScale = "0.69"
  H.eq(ns.Core.loginChecks(), false, "login checks: no fit popup")
  for _ = 1, 4 do W.flush() end
  H.eq(popups, 0, "no popup")
  H.eq(W.cvars.uiScale, "0.69", "UI Scale is never written")
  H.eq(ns.BarFit.fitOn(), true, "on by default")
  H.ok(ns.BarFit.fitSummary():find("scaled to", 1, true) ~= nil, "summary: " .. ns.BarFit.fitSummary())
  ns.Core.slash("barfit off")
  H.eq(ns.Core.cdb.barFit, false, "/wbx barfit off")
  ns.Core.slash("barfit min 80")
  H.eq(ns.Core.cdb.barFitMin, 0.8, "/wbx barfit min 80")
  ns.Core.slash("barfit on")
  H.eq(ns.Core.cdb.barFit, nil, "/wbx barfit on (the default is stored as nothing)")
end

-- 8. The planner alone: a single unit wider than the window can't stack
do
  local units1 = { { box = { 0, 0, 1024, 53 }, rects = { { 0, 0, 1024, 53 } } } }
  local p = (function() local W, ns = boot("era", 600, 768); return ns.BarFit.plan(units1, {}, 600, 768, 0.7, 4) end)()
  H.eq(p.mode, "nofit", "one 1024-wide unit in 600 units: no fit at 70 %")
end

-- 9. The XP bar between the two rows: it moves with the group when it follows the bottom centre; on a frame of its own
-- that does not, it is left alone and does not block the fit
for _, centred in ipairs({ true, false }) do
  local w, h = units(1280, 1392, 0.69)
  local W, ns = boot("forever", w, h)
  forever(W.env, { bottomLeft = true, bottomRight = true })
  local xp = W.env.CreateFrame("Frame", "MainStatusTrackingBarContainer", W.env.UIParent); xp:SetSize(1180, 12)
  if centred then xp:SetPoint("BOTTOM", W.env.UIParent, "BOTTOM", -6, 54) else xp:SetPoint("BOTTOMLEFT", W.env.UIParent, "BOTTOMLEFT", 0, 54) end
  local st = fit(W, ns)
  local who = centred and "XP bar at the bottom centre: " or "XP bar anchored elsewhere: "
  H.eq(st.mode, "scale", who .. "scaled")
  if centred then
    local x, b1, b2 = W.rect(xp), W.rect(W.env.ActionButton1), W.rect(W.env.MultiBarBottomLeftButton1)
    H.ok(x[2] >= b1[4] - 0.5 and x[4] <= b2[2] + 0.5, who .. "still between bar 1 and bar 2")
    H.ok(x[1] >= 0 and x[3] <= w, who .. "inside the window")
  end
end

H.report("barlayout")
