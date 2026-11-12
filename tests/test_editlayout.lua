-- The per-window bar layout through Edit Mode (owner 12 Nov 2026, test.11): WoWBoxer writes a Character layout
-- "WoWBoxer" and lets Edit Mode apply it. The mock below models Blizzard's Edit Mode from its source (Gethe
-- wow-ui-source, classic_era/live Oct 2026): IconSize scales each button's container, the bags and the XP bar scale
-- themselves, the micro menu scales inside its container, every system is placed by its anchorInfo, and Edit Mode
-- applies the saved active layout when it is closed. Windows are real pixel sizes at UI scales 0.64 … 1.0.
local dir = (arg[0]:match("^(.*)/[^/]+$") or ".")
local H = dofile(dir .. "/harness.lua")
local Mock = dofile(dir .. "/wowmock.lua")

local function units(wpx, hpx, scale) local h = 768 / scale; return h * wpx / hpx, h end
local function copy(t) if type(t) ~= "table" then return t end local o = {} for k, v in pairs(t) do o[k] = copy(v) end return o end

local ENUM = {
  EditModeSystem = { ActionBar = 0, ChatFrame = 8, MicroMenu = 13, Bags = 14, StatusTrackingBar = 15 },
  EditModeActionBarSystemIndices = { MainBar = 1, Bar2 = 2, Bar3 = 3, RightBar1 = 4, RightBar2 = 5, StanceBar = 11, PetActionBar = 12 },
  EditModeActionBarSetting = { Orientation = 0, NumRows = 1, NumIcons = 2, IconSize = 3, IconPadding = 4, VisibleSetting = 5, HideBarArt = 6 },
  EditModeLayoutType = { Preset = 0, Account = 1, Character = 2, Override = 3 },
  EditModeMicroMenuSetting = { Orientation = 0, Order = 1, Size = 2, EyeSize = 3 },
  EditModeBagsSetting = { Orientation = 0, Direction = 1, Size = 2, BagSlotPadding = 3 },
  EditModeStatusTrackingBarSetting = { Height = 0, Width = 1, TextSize = 2, Size = 3 },
  EditModeStatusTrackingBarSystemIndices = { StatusTrackingBar1 = 1, StatusTrackingBar2 = 2 },
  ActionBarOrientation = { Horizontal = 0, Vertical = 1 },
}
local S, A, AB = ENUM.EditModeSystem, ENUM.EditModeActionBarSystemIndices, ENUM.EditModeActionBarSetting

--- A client with Edit Mode. game = "forever" (45-unit buttons, padding 2, no end caps) or "era" (36-unit buttons,
--- padding 6, gryphon end caps 128 wide). on = { bar2, bar3, stance = n, pet = n, rep }.
local function client(game, wpx, hpx, scale, on, opts)
  opts = opts or {}
  local w, h = units(wpx, hpx, scale)
  local W = Mock.new(H, { toc = game == "forever" and 16001 or 11509, screen = { w = w, h = h }, addons = opts.addons })
  local ns = H.loadAddon({ env = W.env, gameType = game == "forever" and "camelot" or nil })
  W.fire("ADDON_LOADED", "WoWBoxer"); W.fire("PLAYER_LOGIN")
  local env, U = W.env, W.env.UIParent
  env.Enum = setmetatable(copy(ENUM), { __index = env.Enum })
  for k, v in pairs(ENUM) do env.Enum[k] = copy(v) end
  local BW, PAD = game == "forever" and 45 or 36, game == "forever" and 2 or 6
  local frames, byKey = {}, {}
  local function sysFrame(f, sys, idx) f.system, f.systemIndex = sys, idx; frames[#frames + 1] = f; return f end
  local function bar(name, idx, n, prefix, bw)
    local f = sysFrame(env.CreateFrame("Frame", name, U), S.ActionBar, idx)
    f.actionButtons, f.numButtonsShowable, f.buttonPadding = {}, n, PAD
    for i = 1, n do
      local c = env.CreateFrame("Frame", name .. "ButtonContainer" .. i, f); c:SetSize(bw, bw)
      local b = env.CreateFrame("CheckButton", prefix .. i, c); b:SetSize(bw, bw); b:SetPoint("CENTER", c, "CENTER", 0, 0)
      b.container = c
      f.actionButtons[i] = b
    end
    f._bw = bw
    return f
  end
  byKey.bar1 = bar("MainActionBar", A.MainBar, 12, "ActionButton", BW)
  byKey.bar2 = bar("MultiBarBottomLeft", A.Bar2, 12, "MultiBarBottomLeftButton", BW)
  byKey.bar3 = bar("MultiBarBottomRight", A.Bar3, 12, "MultiBarBottomRightButton", BW)
  byKey.stance = bar("StanceBar", A.StanceBar, 10, "StanceButton", 30)
  byKey.pet = bar("PetActionBar", A.PetActionBar, 10, "PetActionButton", 30)
  for i = 1, 10 do byKey.stance.actionButtons[i]:SetShown(i <= (on.stance or 0)); byKey.pet.actionButtons[i]:SetShown(i <= (on.pet or 0)) end
  if (on.stance or 0) == 0 then byKey.stance:Hide() end
  if (on.pet or 0) == 0 then byKey.pet:Hide() end
  if game == "era" then
    local caps = env.CreateFrame("Frame", "WbxEndCaps", byKey.bar1); caps:SetAllPoints(byKey.bar1)
    local l = env.CreateFrame("Frame", "WbxLeftCap", caps); l:SetSize(128, 128); l:SetPoint("BOTTOMRIGHT", caps, "BOTTOMLEFT", 28, -3)
    local r = env.CreateFrame("Frame", "WbxRightCap", caps); r:SetSize(128, 128); r:SetPoint("BOTTOMLEFT", caps, "BOTTOMRIGHT", -28, -3)
    byKey.bar1.EndCaps = caps; caps.LeftEndCap, caps.RightEndCap = l, r
  end
  local mc = sysFrame(env.CreateFrame("Frame", "MicroMenuContainer", U), S.MicroMenu, nil)
  local MW, MH, MS = game == "forever" and 394 or 232, game == "forever" and 32 or 36, game == "forever" and 49 or 29
  local mm = env.CreateFrame("Frame", "MicroMenu", mc); mm:SetSize(MW, MH); mm:SetPoint("BOTTOMLEFT", mc, "BOTTOMLEFT", 0, 0)
  local MICRO = { "CharacterMicroButton", "SpellbookMicroButton", "TalentMicroButton", "QuestLogMicroButton", "SocialsMicroButton",
    "WorldMapMicroButton", "MainMenuMicroButton", "HelpMicroButton" }
  for i, n in ipairs(MICRO) do local b = env.CreateFrame("Button", n, mm); b:SetSize(MS - 1, MH); b:SetPoint("BOTTOMLEFT", mm, "BOTTOMLEFT", (i - 1) * MS, 0) end
  byKey.micro = mc
  local BS = game == "forever" and 41 or 37
  local bags = sysFrame(env.CreateFrame("Frame", "BagsBar", U), S.Bags, nil); bags:SetSize(5 * BS + 4 * 5, BS)
  local BAGS = { "CharacterBag3Slot", "CharacterBag2Slot", "CharacterBag1Slot", "CharacterBag0Slot", "MainMenuBarBackpackButton" }
  for i, n in ipairs(BAGS) do local b = env.CreateFrame("Button", n, bags); b:SetSize(BS, BS); b:SetPoint("BOTTOMLEFT", bags, "BOTTOMLEFT", (i - 1) * (BS + 5), 0) end
  byKey.bags = bags
  local xp = sysFrame(env.CreateFrame("Frame", "MainStatusTrackingBarContainer", U), S.StatusTrackingBar, 1); xp:SetSize(571, 12)
  local rep = sysFrame(env.CreateFrame("Frame", "SecondaryStatusTrackingBarContainer", U), S.StatusTrackingBar, 2); rep:SetSize(571, 12)
  if not on.rep then rep:Hide() end
  byKey.xp, byKey.rep = xp, rep
  if not on.bar2 then byKey.bar2:Hide() end
  if not on.bar3 then byKey.bar3:Hide() end
  local chat = env.CreateFrame("Frame", "ChatFrame1", U); chat:SetSize(430, 120); chat:SetPoint("BOTTOMLEFT", U, "BOTTOMLEFT", 32, opts.chatY or 140)
  local pf = env.CreateFrame("Frame", "PlayerFrame", U); pf:SetSize(232, 100); pf:SetPoint("TOPLEFT", U, "TOPLEFT", 20, -20)

  -- Blizzard's apply: every system of the active layout placed and sized
  local function setting(si, s, def) for _, x in ipairs(si.settings) do if x.setting == s then return x.value end end return def end
  local function frameOf(si) for _, f in ipairs(frames) do if f.system == si.system and (si.systemIndex == nil or f.systemIndex == si.systemIndex) then return f end end end
  local function applySystem(si)
    local f = frameOf(si)
    if not f then return end
    if si.system == S.ActionBar then
      local p = (50 + setting(si, AB.IconSize, 5) * 10) / 100
      local x = 0
      for _, b in ipairs(f.actionButtons) do
        local c = b.container
        c:SetScale(p); c:ClearAllPoints(); c:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", x / p, 0)
        if b:IsShown() or f ~= byKey.stance and f ~= byKey.pet then x = x + f._bw * p + PAD end
      end
      f:SetSize(math.max(1, x - PAD), f._bw * p)
      -- Blizzard (Classic): in the default place and size the big main-bar art is the end caps, else the gryphons
      if rawget(f, "EndCaps") then f.EndCaps:SetScale(math.min(1, p)); f.EndCaps:SetShown(setting(si, AB.HideBarArt, 0) ~= 1 and not si.isInDefaultPosition) end
    elseif si.system == S.MicroMenu then
      local pct = (70 + setting(si, ENUM.EditModeMicroMenuSetting.Size, 6) * 5) / 100
      mm:SetScale(pct); mc:SetSize(MW * pct, MH * pct)
    elseif si.system == S.Bags then
      f:SetScale((75 + setting(si, ENUM.EditModeBagsSetting.Size, 5) * 5) / 100)
    elseif si.system == S.StatusTrackingBar then
      f:SetScale((50 + setting(si, ENUM.EditModeStatusTrackingBarSetting.Size, 10) * 5) / 100)
    end
    local a = si.anchorInfo
    f:ClearAllPoints(); f:SetPoint(a.point, env[a.relativeTo] or U, a.relativePoint, a.offsetX, a.offsetY)
  end
  local function sys(system, idx, x, y, settings)
    return { system = system, systemIndex = idx, isInDefaultPosition = true, settings = settings or {},
      anchorInfo = { point = "BOTTOMLEFT", relativeTo = "UIParent", relativePoint = "BOTTOM", offsetX = x, offsetY = y } }
  end
  local function barSettings() return { { setting = AB.Orientation, value = 0 }, { setting = AB.NumRows, value = 1 }, { setting = AB.NumIcons, value = 12 },
    { setting = AB.IconSize, value = 5 }, { setting = AB.IconPadding, value = PAD }, { setting = AB.HideBarArt, value = 0 } } end
  -- the default layout (Forever as measured on the owner's clients: bar 1 at −601, bars 2/3 side by side 72 up)
  local b1w = 12 * BW + 11 * PAD
  local MSZ = { { setting = ENUM.EditModeMicroMenuSetting.Size, value = 6 } }
  local BSZ = { { setting = ENUM.EditModeBagsSetting.Size, value = 5 } }
  local function SSZ() return { { setting = ENUM.EditModeStatusTrackingBarSetting.Size, value = 10 } } end
  local preset
  if game == "forever" then
    preset = { layoutName = "Classic", layoutType = 0, systems = {
      sys(S.ActionBar, A.MainBar, -b1w - 39, 2, barSettings()),
      sys(S.ActionBar, A.Bar2, -b1w - 17, 72, barSettings()),
      sys(S.ActionBar, A.Bar3, 5, 72, barSettings()),
      sys(S.ActionBar, A.StanceBar, -b1w - 17, 120, barSettings()),
      sys(S.ActionBar, A.PetActionBar, -b1w + 200, 120, barSettings()),
      sys(S.MicroMenu, nil, -35, 2, MSZ), sys(S.Bags, nil, 365, 2, BSZ),
      sys(S.StatusTrackingBar, 1, -285, 47, SSZ()), sys(S.StatusTrackingBar, 2, -285, 59.5, SSZ()),
    } }
  else
    -- Era: the 1024-wide main bar – bar 1, menu and bags in one row, the XP bar on top, bars 2 and 3 above it
    preset = { layoutName = "Classic", layoutType = 0, systems = {
      sys(S.ActionBar, A.MainBar, -504, 4, barSettings()),
      sys(S.ActionBar, A.Bar2, -504, 57, barSettings()),
      sys(S.ActionBar, A.Bar3, 6, 57, barSettings()),
      sys(S.ActionBar, A.StanceBar, -504, 107, barSettings()),
      sys(S.ActionBar, A.PetActionBar, -300, 107, barSettings()),
      sys(S.MicroMenu, nil, 40, 2, MSZ), sys(S.Bags, nil, 300, 2, BSZ),
      sys(S.StatusTrackingBar, 1, -285, 41, SSZ()), sys(S.StatusTrackingBar, 2, -285, 94, SSZ()),
    } }
  end
  local modern = copy(preset); modern.layoutName = "Modern"
  local EM = { saved = {}, active = 2, saves = 0, applies = 0 }
  W.em = EM
  local function all() local t = { copy(modern), copy(preset) } for _, l in ipairs(EM.saved) do t[#t + 1] = copy(l) end return t end
  local function apply() EM.applies = EM.applies + 1; for _, si in ipairs(all()[EM.active].systems) do applySystem(si) end end
  W.applyEditMode = apply
  env.C_EditMode = {
    GetLayouts = function() return { layouts = copy(EM.saved), activeLayout = EM.active } end,
    SaveLayouts = function(info)
      EM.saves = EM.saves + 1
      EM.saved = {}
      for _, l in ipairs(info.layouts) do if l.layoutType ~= 0 then EM.saved[#EM.saved + 1] = copy(l) end end
    end,
    SetActiveLayout = function(i) EM.active = i end,
    OnLayoutDeleted = function() end,
  }
  env.EditModePresetLayoutManager = { GetCopyOfPresetLayouts = function() return { copy(modern), copy(preset) } end }
  local M = env.CreateFrame("Frame", "EditModeManagerFrame", U)
  M.registeredSystemFrames = frames
  M.layoutInfo = {}
  M.CanEnterEditMode = function() return not W.combat end
  M:Hide()
  M.IsEditModeActive = function(self) return self._active and true or false end
  M:SetScript("OnShow", function(self) self._active = true end)
  M:SetScript("OnHide", function(self) self._active = false; apply() end) -- ExitEditMode → RevertAllChanges → the saved layout
  env.ShowUIPanel = function(f) if W.combat then error("ShowUIPanel in combat") end f:Show() end
  env.HideUIPanel = function(f) f:Hide() end
  apply()
  ns.BarFit.inited = nil; ns.BarFit.Init()
  return W, ns, byKey, w, h
end

local function settle(W) for _ = 1, 4 do W.flush() end end
local function fit(W, ns, reason) ns.BarFit.request(reason or "test"); settle(W) end

local BOTTOM = { { "bar1", "ActionButton" }, { "bar2", "MultiBarBottomLeftButton" }, { "bar3", "MultiBarBottomRightButton" },
  { "stance", "StanceButton" }, { "pet", "PetActionButton" } }
local function hit(a, b) return a[1] < b[3] - 0.5 and b[1] < a[3] - 0.5 and a[2] < b[4] - 0.5 and b[2] < a[4] - 0.5 end
--- Everything the player sees at the bottom, as {group, rect}.
local function drawn(W, by)
  local out = {}
  for _, b in ipairs(BOTTOM) do
    local f = by[b[1]]
    if f:IsShown() then for i = 1, 12 do local x = W.env[b[2] .. i]; if x and x:IsVisible() then out[#out + 1] = { g = b[1], r = W.rect(x) } end end end
  end
  for _, n in ipairs({ "CharacterMicroButton", "SpellbookMicroButton", "TalentMicroButton", "QuestLogMicroButton", "SocialsMicroButton",
    "WorldMapMicroButton", "MainMenuMicroButton", "HelpMicroButton" }) do out[#out + 1] = { g = "micro", r = W.rect(W.env[n]) } end
  for _, n in ipairs({ "CharacterBag3Slot", "CharacterBag2Slot", "CharacterBag1Slot", "CharacterBag0Slot", "MainMenuBarBackpackButton" }) do
    out[#out + 1] = { g = "bags", r = W.rect(W.env[n]) } end
  for _, k in ipairs({ "xp", "rep" }) do if by[k]:IsShown() then out[#out + 1] = { g = k, r = W.rect(by[k]) } end end
  if rawget(by.bar1, "EndCaps") and by.bar1.EndCaps:IsShown() then
    out[#out + 1] = { g = "bar1cap", r = W.rect(by.bar1.EndCaps.LeftEndCap) }
    out[#out + 1] = { g = "bar1cap", r = W.rect(by.bar1.EndCaps.RightEndCap) }
  end
  return out
end
--- outside, on each other, on the chat / player frame
local function problems(W, by, w, h)
  local list = drawn(W, by)
  local out, each, other = 0, 0, 0
  for _, x in ipairs(list) do
    if x.g ~= "bar1cap" and (x.r[1] < -0.5 or x.r[3] > w + 0.5 or x.r[2] < -0.5 or x.r[4] > h + 0.5) then out = out + 1 end
    if x.g == "bar1cap" and (x.r[1] < -0.5 or x.r[3] > w + 0.5) then out = out + 1 end
  end
  for i = 1, #list do for j = i + 1, #list do
    local a, b = list[i], list[j]
    local same = a.g == b.g or (a.g == "bar1cap" and b.g == "bar1") or (b.g == "bar1cap" and a.g == "bar1")
    if not same and hit(a.r, b.r) then each = each + 1 end
  end end
  for _, n in ipairs({ "ChatFrame1", "PlayerFrame" }) do
    local f = W.env[n]
    for _, x in ipairs(list) do if hit(x.r, W.rect(f)) then other = other + 1 end end
  end
  return out, each, other
end
local function snapshot(by)
  local t = {}
  for k, f in pairs(by) do
    local a, _, c, d, e = f:GetPoint(1)
    t[k] = table.concat({ tostring(a), tostring(c), tostring(d), tostring(e), tostring(f:GetScale()) }, ",")
  end
  return t
end

-- 1. Every window the owner uses, every UI scale, every bar set, both games: it fits, at the best size
local WINDOWS = { { 870, 696 }, { 1000, 1080 }, { 640, 1080 }, { 1690, 1392 }, { 2560, 1440 }, { 1280, 1392 } }
local SCALES = { 0.64, 0.69, 0.74, 0.85, 1.0 }
local SETS = {
  { "bar 1", {} }, { "bars 1+2", { bar2 = true } }, { "bars 1+2+3", { bar2 = true, bar3 = true } },
  { "bars 1+2+3, stance, pet, rep", { bar2 = true, bar3 = true, stance = 3, pet = 10, rep = true } },
}
local results = {}
for _, game in ipairs({ "forever", "era" }) do
  for _, win in ipairs(WINDOWS) do
    for _, sc in ipairs(SCALES) do
      for _, set in ipairs(SETS) do
        local W, ns, by, w, h = client(game, win[1], win[2], sc, set[2])
        local before = snapshot(by)
        fit(W, ns, "login")
        local st = ns.BarLayout.state or {}
        local who = string.format("%s %dx%d @%.2f %s: ", game, win[1], win[2], sc, set[1])
        results[#results + 1] = who .. tostring(st.mode) .. " " .. tostring(st.arrangement) .. " " .. tostring(st.pct)
        if st.mode == "fits" then
          local o, e, x = problems(W, by, w, h)
          H.eq(o + e, 0, who .. "the game's own layout fits: left as it is")
          H.eq(W.em.saves, 0, who .. "fits as it is: no layout written")
          H.eq(ns.Core.db.bridge.barFit, "addon", who .. "the window app is told (fits)")
        elseif st.mode == "layout" then
          local o, e, x = problems(W, by, w, h)
          H.eq(o + e + x, 0, who .. "fits: nothing outside, on each other or on the chat (" .. o .. "/" .. e .. "/" .. x .. ", " .. st.arrangement .. " " .. st.pct .. "%)")
          H.eq(ns.Core.db.bridge.barFit, "addon", who .. "the window app is told")
          -- the XP bar spans the button area (Edit Mode's 5 % steps), centred
          local xr = W.rect(by.xp)
          local b1 = W.rect(W.env.ActionButton1)
          H.ok(xr[2] >= b1[4] - 0.5, who .. "the XP bar sits above bar 1")
          H.ok(math.abs((xr[1] + xr[3]) / 2 - w / 2) < 1, who .. "the XP bar is centred")
          -- a layout that fits as it was is the default look (2 rows), at full size where the window allows it
          local L = W.em.saved[#W.em.saved]
          H.eq(L and L.layoutName, "WoWBoxer", who .. "our layout is saved")
          H.eq(L and L.layoutType, 2, who .. "as a Character layout (this window's character)")
          H.eq(W.em.active, 3, who .. "and active")
          -- a second request with nothing changed does nothing
          local saves, applies = W.em.saves, W.em.applies
          fit(W, ns, "again")
          H.eq(W.em.saves .. "/" .. W.em.applies, saves .. "/" .. applies, who .. "nothing changed: not saved or applied again")
          -- off: the layout that was active before, ours deleted, every frame where it was
          ns.BarFit.setFit(false); settle(W)
          H.eq(W.em.active, 2, who .. "off: the previous layout is active again")
          H.eq(#W.em.saved, 0, who .. "off: our layout is deleted")
          local after = snapshot(by)
          local diff = {}
          for k, v in pairs(before) do if after[k] ~= v then diff[#diff + 1] = k end end
          H.eq(table.concat(diff, ","), "", who .. "off: every bar exactly where the game had it")
        else
          H.eq(st.mode, "nofit", who .. "no fit is said so, not half done")
          H.eq(W.em.saves, 0, who .. "nothing saved when nothing fits")
        end
      end
    end
  end
end

-- 2. The expected answers for the owner's windows
local function case(game, wpx, hpx, sc, on, opts)
  local W, ns, by, w, h = client(game, wpx, hpx, sc, on, opts)
  fit(W, ns, "login")
  return ns.BarLayout.state or {}, W, ns, by, w, h
end
do
  local st = case("forever", 1280, 1392, 0.69, { bar2 = true, bar3 = true })
  H.eq(st.mode .. " " .. tostring(st.arrangement), "layout 2 rows", "owner's followers 1280x1392 @0.69: the default look, two rows")
  H.eq(st.pct, 80, "owner's followers: icons at 80 %")
  st = case("forever", 870, 696, 0.74, { bar2 = true, bar3 = true })
  H.eq(st.mode, "fits", "870x696 @0.74 (1297 wide): the game's own layout fits – nothing changed")
  st = case("forever", 640, 1080, 0.74, { bar2 = true, bar3 = true })
  H.eq(st.mode, "layout", "640x1080 portrait: still laid out (" .. tostring(st.arrangement) .. " " .. tostring(st.pct) .. ")")
  H.ok((st.rows or 0) >= 3, "640x1080: more rows")
  st = case("forever", 400, 1080, 0.64, { bar2 = true, bar3 = true }, { chatY = 40 })
  H.eq(st.mode, "nofit", "a very narrow window with the chat at the bottom: no fit, said once")
end

-- 3. Combat: nothing is applied in combat; it is done when combat ends
do
  local W, ns = client("forever", 1280, 1392, 0.69, { bar2 = true, bar3 = true })
  W.combat = true
  fit(W, ns, "login")
  H.eq(W.em.saves, 0, "combat: nothing saved")
  W.combat = false
  W.fire("PLAYER_REGEN_ENABLED"); settle(W)
  H.eq(ns.BarLayout.state and ns.BarLayout.state.mode, "layout", "after combat: laid out")
  W.combat = true
  ns.BarFit.setFit(false); settle(W)
  H.eq(W.em.active, 3, "off in combat: waits")
  W.combat = false
  W.fire("PLAYER_REGEN_ENABLED"); settle(W)
  H.eq(W.em.active, 2, "off after combat: the previous layout is back")
end

-- 4. A bar addon owns the bars: nothing is done; one that loads later turns ours off
do
  local W, ns = client("forever", 1280, 1392, 0.69, { bar2 = true, bar3 = true }, { addons = { Bartender4 = "loaded" } })
  fit(W, ns, "login")
  H.eq(W.em.saves, 0, "Bartender4: no layout written")
  H.eq(ns.BarFit.state and ns.BarFit.state.mode, "addon", "Bartender4: said so")
end

-- 5. The player opens Edit Mode and picks another layout: WoWBoxer leaves it; ticking the setting again resumes
do
  local W, ns, by = client("forever", 1280, 1392, 0.69, { bar2 = true, bar3 = true })
  fit(W, ns, "login")
  local M = W.env.EditModeManagerFrame
  W.env.ShowUIPanel(M)
  fit(W, ns, "while open")
  H.eq(W.em.applies, 2, "Edit Mode open: nothing applied over the player's editing")
  W.env.C_EditMode.SetActiveLayout(1) -- the player picks "Modern"
  W.env.HideUIPanel(M); settle(W)
  H.eq(W.em.active, 1, "the player's choice stays")
  H.eq(ns.BarLayout.state.mode, "paused", "paused")
  H.ok(ns.BarFit.fitSummary():find("paused", 1, true) ~= nil, "summary: " .. ns.BarFit.fitSummary())
  W.fire("DISPLAY_SIZE_CHANGED"); settle(W); for _ = 1, 3 do W.flush() end
  H.eq(W.em.active, 1, "a new window size does not take it back")
  ns.BarFit.setFit(false); settle(W); ns.BarFit.setFit(true); settle(W)
  H.eq(W.em.active, #W.em.saved + 2, "ticked again: ours is active again")
end

-- 6. Dragging a spell: nothing is applied while something is on the cursor; bars toggled: laid out again
do
  local W, ns, by, w, h = client("forever", 1280, 1392, 0.69, { bar2 = true })
  fit(W, ns, "login")
  local a1 = ns.BarLayout.state.arrangement .. ns.BarLayout.state.pct
  W.cursor = { kind = "spell" }
  by.bar3:Show(); settle(W)
  local applies = W.em.applies
  fit(W, ns, "bars changed")
  H.eq(W.em.applies, applies, "spell on the cursor: nothing applied")
  W.cursor = nil
  W.fire("CURSOR_CHANGED"); settle(W)
  H.ok(W.em.applies > applies, "dropped: bar 3 is laid out now")
  local o, e, x = problems(W, by, w, h)
  H.eq(o + e + x, 0, "bar 3 on: everything fits (" .. ns.BarLayout.state.arrangement .. " " .. ns.BarLayout.state.pct .. "%)")
  H.ok(a1 ~= "", "before: " .. a1)
end

-- 7. The setting, the summary, /wbx barfit, the diagnose
do
  local W, ns = client("forever", 1280, 1392, 0.69, { bar2 = true, bar3 = true })
  fit(W, ns, "login")
  H.ok(ns.BarFit.fitSummary():find("Edit Mode layout", 1, true) ~= nil, "summary: " .. ns.BarFit.fitSummary())
  local d = ns.Core.db.bridge.barLayout
  H.ok(d and d.plan and d.plan.pct == 80, "diagnose: the plan is in the bridge for read_log")
  H.eq(ns.Core.db.bridge.barRows, 2, "bridge: rows")
  H.eq(ns.Core.db.bridge.barScale, 0.8, "bridge: icon size")
  ns.Core.slash("barfit off"); settle(W)
  H.eq(ns.Core.db.bridge.barFit, false, "/wbx barfit off: the bridge says so")
  H.eq(W.em.active, 2, "/wbx barfit off: the previous layout")
  H.eq(W.cvars.uiScale, nil, "UI Scale is never written")
end

-- 8. A character with all 5 character layouts used: nothing is written, the reason is logged
do
  local W, ns = client("forever", 1280, 1392, 0.69, { bar2 = true, bar3 = true })
  for i = 1, 5 do W.em.saved[i] = { layoutName = "Mine" .. i, layoutType = 2, systems = {} } end
  fit(W, ns, "login")
  H.eq(W.em.saves, 0, "5 character layouts: none added")
  H.ok(tostring(ns.BarLayout.state.why):find("5", 1, true) ~= nil, "the reason: " .. tostring(ns.BarLayout.state.why))
end

-- 9. Era: the window shrinks and grows again – the gryphons go where they clash and come back after
do
  local W, ns, by, w, h = client("era", 1690, 1392, 0.69, { bar2 = true, bar3 = true })
  fit(W, ns, "login")
  local caps0 = by.bar1.EndCaps:IsShown()
  local st0 = tostring(ns.BarLayout.state.arrangement) .. " " .. tostring(ns.BarLayout.state.pct)
  local nw, nh = units(700, 1392, 0.69)
  W.screen.w, W.screen.h = nw, nh
  W.env.UIParent:SetSize(nw, nh)
  W.fire("DISPLAY_SIZE_CHANGED"); for _ = 1, 6 do W.flush() end
  local o, e, x = problems(W, by, nw, nh)
  H.eq(o + e + x, 0, "era narrow: fits (" .. ns.BarLayout.state.arrangement .. " " .. ns.BarLayout.state.pct .. "%, gryphons " .. tostring(by.bar1.EndCaps:IsShown()) .. ")")
  W.screen.w, W.screen.h = w, h
  W.env.UIParent:SetSize(w, h)
  W.fire("DISPLAY_SIZE_CHANGED"); for _ = 1, 6 do W.flush() end
  H.eq(tostring(ns.BarLayout.state.arrangement) .. " " .. tostring(ns.BarLayout.state.pct), st0, "era wide again: the same as before")
  H.eq(by.bar1.EndCaps:IsShown(), caps0, "era wide again: the gryphons as before")
end

-- 10. Edit Mode can't open right now (another panel blocks it): saved, applied on the next check
do
  local W, ns, by = client("forever", 1280, 1392, 0.69, { bar2 = true, bar3 = true })
  local can = false
  W.env.EditModeManagerFrame.CanEnterEditMode = function() return can end
  fit(W, ns, "login")
  H.eq(W.em.saves, 1, "blocked: the layout is saved")
  H.eq(W.em.applies, 1, "blocked: not applied yet")
  can = true
  fit(W, ns, "later")
  H.eq(W.em.applies, 2, "next check: applied")
end

if os.getenv("WBX_LAYOUT_TABLE") then for _, r in ipairs(results) do print(r) end end
H.report("editlayout")
