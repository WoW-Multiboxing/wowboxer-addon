-- Bug sweep 9 Nov 2026, point 3: click through every page and dialog in the simulator – Standard and Advanced mode,
-- squads of 1, 3 and 5, Forever two-part names (UnitName "Rip" + realm "And") and Classic Era. Every step runs in
-- pcall: a Lua error anywhere is a finding, as is an error line in the log, a layout problem (tests/layout.lua) or a
-- text that shows a Lua value ("nil", "table: 0x…") or an unfilled placeholder.
local dir = (arg[0]:match("^(.*)/[^/]+$") or ".")
local H = dofile(dir .. "/harness.lua")
local Mock = dofile(dir .. "/wowmock.lua")
local Layout = dofile(dir .. "/layout.lua")

local CLASSES = { { "Rip", "PALADIN", "tank" }, { "Rup", "PRIEST", "healer" }, { "Rap", "WARLOCK", "ranged" },
  { "Rop", "MAGE", "ranged" }, { "Ryp", "HUNTER", "ranged" } }

local function scenario(size, advanced, game)
  local tag = game .. " squad of " .. size .. (advanced and " Advanced" or " Standard") .. ": "
  local party, info = {}, {}
  for i = 2, size do
    party["party" .. (i - 1)] = CLASSES[i][1]
    info["party" .. (i - 1)] = { class = CLASSES[i][2], race = "Human", level = 24, realm = game == "forever" and "And" or nil }
  end
  local W = Mock.new(H, { name = "Rip", class = "PALADIN", race = "Human", faction = "Alliance", level = 24,
    toc = game == "era" and 11509 or nil, spellbookStyle = game == "era" and "classic" or nil, party = party, partyInfo = info,
    screen = { w = 1365, h = 768 } })
  W.player.leader = true
  local ns = H.loadAddon({ env = W.env })
  local problems = {}
  local checks = 0
  local function step(what, fn, roots)
    local ok, err = pcall(fn)
    if not ok then problems[#problems + 1] = what .. ": Lua error " .. tostring(err) end
    local okL, list = pcall(Layout.check, W, roots or { ns.UI.frame })
    if okL then for _, m in ipairs(list) do problems[#problems + 1] = what .. ": " .. m end
    else problems[#problems + 1] = what .. ": layout check failed " .. tostring(list) end
    checks = checks + 1
    for _, f in ipairs(W.frames) do
      local t = f._text
      if type(t) == "string" and f:IsVisible() and (t:find("table: ", 1, true) or t:find("function: ", 1, true) or t:find("%f[%w]nil%f[%W]")
        or t:find("%%[sd]") or t:find("{%w+}")) then
        problems[#problems + 1] = what .. ": odd text \"" .. t:sub(1, 80) .. "\""
      end
    end
  end
  W.fire("ADDON_LOADED", "WoWBoxer"); W.fire("PLAYER_LOGIN")
  for _, s in ipairs(ns.Data.spells.paladin) do if s.level <= 24 then W.known[s.name] = true end end
  local UI, Core, SP = ns.UI, ns.Core, ns.SquadPages
  step("open", function() UI.Open("keys") end)
  step("squad setup", function()
    local s = Core.me()
    for i = 2, size do
      s.members[#s.members + 1] = ns.State.newMember({ name = CLASSES[i][1], cls = CLASSES[i][2]:lower(), race = "human", role = CLASSES[i][3],
        unit = "party1", level = 24 })
    end
    Core.changed()
  end)
  if advanced then step("advanced on", function() ns.Advanced.confirm(); ns.Advanced.confirmFrame.tick:Click(); ns.Advanced.confirmFrame.go:Click() end) end
  -- team messages from the others (Forever: "Rup And"), so the panel and the readiness have data
  step("team messages", function()
    for i = 2, size do
      local sender = CLASSES[i][1] .. (game == "forever" and " And" or "")
      W.fire("CHAT_MSG_ADDON", "WBX1", "S|24|60|1|0|-", "PARTY", sender)
      W.fire("CHAT_MSG_ADDON", "WBX1", "X|12|4|80", "PARTY", sender)
    end
  end)
  for _, t in ipairs(UI.tabs) do step("tab " .. t.key, function() UI.Select(t.key) end) end
  UI.Select("squad")
  for _, def in ipairs(SP.pages) do step("squad " .. def.key, function() SP.select(UI.panels.squad, def.key) end) end
  step("squad: inline editor", function() SP.select(UI.panels.squad, "main"); local r = UI.panels.squad.frames.main.pool.rows[math.min(2, size)]; if r then r:Click() end end)
  step("cheat sheet", function() SP.select(UI.panels.squad, "keymap"); SP.showCheatSheet(UI.panels.squad.frames.keymap) end)
  pcall(function() UI.panels.squad.frames.keymap.sheet:Hide() end)
  for _, key in ipairs({ "keys", "spells", "custom", "setup", "share", "talents", "automation" }) do
    step("help " .. key, function() UI.Select(key); UI.helpBtn:Click() end)
    pcall(ns.Help.Hide)
  end
  step("place all", function() UI.Select("keys"); Core.sync({}) end)
  step("key editor", function() UI.Select("custom"); UI.panels.custom.cells[1]:Click("LeftButton") end)
  pcall(ns.KeyEditor.Close)
  local A = ns.Advanced
  if advanced then
    step("targeting window", function()
      local kp = UI.panels.keys
      UI.Select("keys")
      for _, b in ipairs(kp.cells) do if b:IsShown() and b.cell and b.cell.name then A.openTargeting(kp, b.cell.name, b.cell.label); break end end
    end)
    pcall(function() A.ef:Hide() end)
  end
  step("reset window", function() UI.Select("keys"); A.openReset() end)
  step("reset step 2", function() A.rf.next:Click() end)
  pcall(function() A.rf:Hide() end)
  -- dialogs outside the window
  step("popup", function() UI.Popup("Automation is off – turn on Default squad values?", { { "Yes", function() end }, { "Choose…", function() end }, { "Not now", function() end } }) end,
    { UI.popup })
  pcall(function() UI.popup:Hide() end)
  step("settings card", function()
    ns.Sync.offer({ kind = "settings", from = "Rup", t = {}, n = 3, text = "Advanced mode Advanced, Automation 14 on, Accept from Squad, friends, guild",
      diff = { { "Advanced mode", "Standard", "Advanced" } } })
  end, { ns.Sync.frame })
  pcall(ns.Sync.dismiss)
  step("push card", function() ns.Settings.ask() end, { ns.Sync.frame })
  pcall(ns.Sync.dismiss)
  step("session card", function() ns.Sync.sessionCard() end, { ns.Sync.frame })
  pcall(ns.Sync.dismiss)
  if size > 1 then
    step("team panel", function() ns.TeamFrame.Refresh() end, { ns.TeamFrame.frame })
    step("team panel paused", function()
      W.env.C_ChatInfo.SendAddonMessage = function() return 11 end
      W.now = (W.now or 0) + 100
      ns.Team.send(true)
      ns.TeamFrame.Refresh()
    end, { ns.TeamFrame.frame })
    W.env.C_ChatInfo.SendAddonMessage = function() return 0 end
    pcall(ns.Compat.flush)
  end
  step("copy settings", function() UI.Select("setup"); ns.Settings.send() end)
  step("back to Standard", function() A.setMode(false); for _, t in ipairs(UI.tabs) do UI.Select(t.key) end end)
  for _, e in ipairs(Core.db.log) do if e.l == "error" then problems[#problems + 1] = "log error: " .. tostring(e.m) end end
  H.ok(checks >= 25, tag .. "the steps ran (" .. checks .. ")")
  return tag, problems
end

local shown = 0
for _, game in ipairs({ "forever", "era" }) do
  for _, size in ipairs({ 1, 3, 5 }) do
    for _, adv in ipairs({ false, true }) do
      local tag, probs = scenario(size, adv, game)
      for _, m in ipairs(probs) do if shown < 40 then shown = shown + 1; print("  " .. tag .. m) end end
      H.eq(#probs, 0, tag .. "no Lua errors, layout problems or odd texts")
    end
  end
end

-- the in-game findings of 9 Nov (Forever layout audit)
do
  local W = Mock.new(H, { name = "Rup", class = "PRIEST", race = "Human", level = 15, screen = { w = 960, h = 768 }, fontFactor = 0.62 })
  local ns = H.loadAddon({ env = W.env })
  W.fire("ADDON_LOADED", "WoWBoxer"); W.fire("PLAYER_LOGIN")
  for _, s in ipairs(ns.Data.spells.priest) do if s.level <= 15 then W.known[s.name] = true end end
  ns.UI.Open("keys")
  ns.Core.sync({})
  W.player.level = 16
  for _, s in ipairs(ns.Data.spells.priest) do if s.level <= 16 then W.known[s.name] = true end end
  W.fire("PLAYER_LEVEL_UP", 16); W.fire("SPELLS_CHANGED"); W.flush()
  local step = ns.Book.nextStep(ns.Core.compute(), "keys")
  H.ok(step.short and not step.short:find("Level", 1, true), "the level-up banner has a short form: " .. tostring(step.short))
  -- the banner never shows cut: the long form only when it fits
  for _, key in ipairs({ "keys", "spells", "custom" }) do
    ns.UI.Select(key)
    local p = ns.UI.panels[key]
    local t = p.stepText
    H.ok(not t:IsTruncated(), key .. ": the banner text is not cut (" .. tostring(t:GetText()) .. ", " .. tostring(t:GetStringWidth()) .. " in " .. tostring(t:GetWidth()) .. " h " .. tostring(t:GetHeight()) .. ")")
  end
  -- the audit: rows of a scrolled list are clipped to their scroll frame, not "overlap" or "outside"
  ns.UI.Select("talents")
  local p = ns.UI.panels.talents
  local found = ns.Audit.scan(ns.UI.frame, "talents")
  local bad = {}
  for _, x in ipairs(found) do if x.kind == "overlap" or x.kind == "outside" then bad[#bad + 1] = x.text end end
  H.eq(#bad, 0, "talents: no overlap/outside findings for scrolled rows: " .. table.concat(bad, "; "))
  local _ = p
end

H.report("sweep")
