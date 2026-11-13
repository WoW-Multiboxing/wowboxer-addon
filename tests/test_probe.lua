-- Tooltip flicker at the bar ends (owner, 12 Nov 2026, 1.3.0-test.11): /wbx probe hover (read-only, 5 s at 10 per
-- second: mouse foci, tooltip owner, our bar fit requests and team panel refreshes), and the team panel can never sit
-- over action buttons (LOW strata, below the bars) nor re-lay itself out on a refresh that changes nothing.
local dir = (arg[0]:match("^(.*)/[^/]+$") or ".")
local H = dofile(dir .. "/harness.lua")
local Mock = dofile(dir .. "/wowmock.lua")

local function boot(opts)
  local W = Mock.new(H, opts)
  local ns = H.loadAddon({ env = W.env, gameType = opts.gameType })
  W.fire("ADDON_LOADED", "WoWBoxer"); W.fire("PLAYER_LOGIN")
  ns.Core.cdb.guide = "done"
  ns.Core.ensureMe()
  return W, ns
end
local function lines(ns, prefix)
  local out = {}
  for _, e in ipairs(ns.Core.db.log) do if e.m:sub(1, #prefix) == prefix then out[#out + 1] = e.m end end
  return out
end
local function errors(ns)
  local n = {}
  for _, e in ipairs(ns.Core.db.log) do if e.l == "error" then n[#n + 1] = e.m end end
  return n
end

-- ------------------------------------------------------------------ the probe
do
  local W, ns = boot({ name = "Rip", class = "PALADIN", race = "Human", level = 26, toc = 16001, gameType = "camelot" })
  W.flush()
  local btn = W.env.CreateFrame("Button", "MultiBarBottomLeftButton12", W.env.UIParent)
  btn:SetFrameStrata("MEDIUM"); btn:SetFrameLevel(4)
  local xp = W.env.CreateFrame("Frame", "MainStatusTrackingBarContainer", W.env.UIParent)
  local under = { btn, xp }
  W.env.GetMouseFoci = function() return under end
  W.env.GameTooltip.GetOwner = function() return btn end
  -- nothing the probe does may move, size, show or hide a frame
  local writes = 0
  for _, f in ipairs({ btn, xp, W.env.GameTooltip }) do
    for _, m in ipairs({ "SetPoint", "ClearAllPoints", "SetScale", "SetHeight", "SetWidth", "SetFrameLevel", "SetFrameStrata" }) do
      local orig = f[m]
      f[m] = function(...) writes = writes + 1; if orig then return orig(...) end end
    end
  end
  local logBefore = #ns.Core.db.log
  W.env.SlashCmdList.WOWBOXER("probe hover")
  H.ok(ns.Probe.run ~= nil, "probe runs")
  H.eq(#lines(ns, "probe: hover start"), 1, "start line")
  local steps = 0
  while ns.Probe.run and steps < 200 do
    steps = steps + 1
    if steps == 3 then ns.BarFit.request("bars changed"); ns.BarFit.request("bars changed") end
    if steps == 7 then W.env.GameTooltip:Hide() end
    if steps == 8 then W.env.GameTooltip:Show(); under = { xp } end
    W.flush()
  end
  local s = lines(ns, "probe: t=")
  H.eq(#s, 50, "5 s at 10 per second = 50 samples")
  H.eq(#lines(ns, "probe: done"), 1, "done line")
  H.ok(s[1]:find("foci=MultiBarBottomLeftButton12@MEDIUM:4>MainStatusTrackingBarContainer", 1, true) ~= nil, "foci top first with strata:level: " .. s[1])
  H.ok(s[1]:find("tip=MultiBarBottomLeftButton12", 1, true) ~= nil, "tooltip owner")
  local fitLine
  for _, l in ipairs(s) do if l:find("fit=2", 1, true) then fitLine = l end end
  H.ok(fitLine ~= nil and fitLine:find("why=fit:bars changed;fit:bars changed", 1, true) ~= nil, "bar fit requests counted with their reasons: " .. tostring(fitLine))
  local sawHidden, sawXp = false, false
  for _, l in ipairs(s) do
    if l:find("tip=- ", 1, true) then sawHidden = true end
    if l:find("foci=MainStatusTrackingBarContainer", 1, true) then sawXp = true end
  end
  H.ok(sawHidden and sawXp, "a hidden tooltip and a new focus show up")
  H.eq(writes, 0, "the probe writes nothing to any frame")
  H.ok(#ns.Core.db.log - logBefore <= 60, "fits the log (400 lines)")
  -- the bar fit request itself stays a no-op for the probe when no probe runs
  ns.BarFit.request("after"); W.flush()
  H.eq(#lines(ns, "probe: t="), 50, "no samples after the run")
  -- old clients: GetMouseFocus only
  W.env.GetMouseFoci = nil
  W.env.GetMouseFocus = function() return btn end
  H.ok(ns.Probe.foci():find("MultiBarBottomLeftButton12", 1, true) == 1, "GetMouseFocus fallback")
  W.env.GetMouseFocus = nil
  H.eq(ns.Probe.foci(), "-", "no focus API: '-'")
  W.env.SlashCmdList.WOWBOXER("probe")
  H.eq(#errors(ns), 0, "no errors " .. table.concat(errors(ns), " | "))
end

-- ------------------------------------------------------------------ the team panel
do
  local W, ns = boot({ name = "Talex", class = "MAGE", race = "Human", level = 20, party = { party1 = "Dorin" },
    partyInfo = { party1 = { class = "PALADIN", race = "Human", level = 20, leader = true } } })
  ns.Core.setPlaysAs("party1")
  ns.Core.me().members[1].name = "Dorin"
  ns.TeamFrame.Refresh()
  local f = ns.TeamFrame.frame
  H.ok(f and f:IsShown(), "team panel shown while grouped")
  H.eq(f:GetFrameStrata(), "LOW", "team panel sits below the action bars (MEDIUM)")
  local sized, shows = 0, 0
  local sh, so = f.SetHeight, f.Show
  f.SetHeight = function(...) sized = sized + 1; return sh(...) end
  f.Show = function(...) shows = shows + 1; return so(...) end
  for _ = 1, 20 do ns.TeamFrame.Refresh() end
  H.eq(sized, 0, "a refresh that changes nothing never resizes the panel")
  H.eq(shows, 0, "nor shows it again")
  H.eq(#errors(ns), 0, "no errors (team) " .. table.concat(errors(ns), " | "))
end

H.report("probe")
