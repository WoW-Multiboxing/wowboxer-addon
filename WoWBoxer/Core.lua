--[[ WoWBoxer – core: saved variables, events, slash commands, combat queue, debug log, level-up offers.
  Every change to the game (macros, action bars, settings) is started by the player (a click or a /wbx command) and
  runs out of combat; in combat it waits for PLAYER_REGEN_ENABLED. ]]
local ADDON, ns = ...
local Core = {}
ns.Core = Core

local S, C, M, B, R, Sh, K = ns.State, ns.Compat, ns.Macros, ns.Bars, ns.Rules, ns.Share, ns.Kit

Core.VERSION = "0.1.0"
Core.LOG_MAX = 400

-- ------------------------------------------------------------------ chat + log
local function chat(msg)
  local f = _G.DEFAULT_CHAT_FRAME
  if f and f.AddMessage then f:AddMessage("|cff4fc3f7WoWBoxer|r: " .. tostring(msg)) end
end
Core.print = chat

--- Debug log in SavedVariables (WoWBoxerDB.log), readable after /reload or logout.
function Core.log(level, msg)
  local db = Core.db
  if not db then return end
  local entry = { t = time and time() or 0, c = Core.charKey or "?", l = level, m = tostring(msg) }
  local log = db.log
  log[#log + 1] = entry
  while #log > Core.LOG_MAX do table.remove(log, 1) end
  if db.settings.debug then chat("[" .. level .. "] " .. tostring(msg)) end
end

-- ------------------------------------------------------------------ combat queue
Core.queue = {}
--- Run fn now, or after combat. label is shown to the player.
function Core.whenSafe(label, fn)
  if C.inCombat() then
    for _, q in ipairs(Core.queue) do if q.label == label then q.fn = fn; return false end end
    Core.queue[#Core.queue + 1] = { label = label, fn = fn }
    chat(label .. ": waiting until combat ends.")
    Core.log("info", "queued until combat ends: " .. label)
    return false
  end
  local ok, err = pcall(fn)
  if not ok then Core.log("error", label .. ": " .. tostring(err)); chat("|cffff6060" .. label .. " failed:|r " .. tostring(err)) end
  return true
end
function Core.runQueue()
  local q = Core.queue
  Core.queue = {}
  for _, item in ipairs(q) do Core.whenSafe(item.label, item.fn) end
end

-- ------------------------------------------------------------------ who am I
function Core.playerInfo()
  return { name = C.playerName(), cls = C.playerClass(), race = C.playerRace(), level = C.playerLevel(), faction = C.playerFaction() }
end
--- squad, member for this character (synced with the live character), or nil
function Core.me()
  local db, cdb = Core.db, Core.cdb
  if not db then return nil end
  local info = Core.playerInfo()
  local s, m = S.findMe(db, cdb, info.name)
  if m then
    if S.syncFromGame(m, info) then Core.log("warn", "member " .. m.name .. " had another class; reset to " .. tostring(m.cls)) end
    S.applyLink(s)
  end
  return s, m
end
function Core.setMe(squadId, memberId)
  Core.cdb.squadId, Core.cdb.memberId = squadId, memberId
  Core.cdb.slots = {}
  Core.changed()
end

--- Desired macros + plans for this character. Returns ctx table or nil, reason.
function Core.compute()
  local s, m = Core.me()
  if not m then return nil, "This character is not in a squad yet." end
  local live = M.liveCheck()
  local L = C.playerLevel()
  local desired = M.desired(m, L, { live = live, extras = Core.cdb.extras })
  local mplan = M.plan(desired, Core.cdb.skip)
  local bplan = B.plan(desired, Core.cdb, Core.cdb.skip)
  return { squad = s, member = m, level = L, live = live, desired = desired, macros = mplan, bars = bplan,
    missing = M.missingFromBook(m, L, live) }
end

--- Create/update the macros, then place them on the bars. opts: {replace=bool, barsOnly=bool, macrosOnly=bool}
function Core.sync(opts)
  opts = opts or {}
  return Core.whenSafe("Update WoWBoxer keys", function()
    local ctx, why = Core.compute()
    if not ctx then chat(why); return end
    local mres = { created = 0, updated = 0, failed = {} }
    if not opts.barsOnly then mres = M.apply(ctx.macros) end
    local bres = { placed = 0, skipped = 0, failed = {} }
    if not opts.macrosOnly then
      local again = Core.compute() -- indices and statuses after creating macros
      bres = B.apply(again.bars, Core.cdb, opts.replace)
    end
    Core.cdb.lastSync = { level = ctx.level, at = time and time() or 0 }
    local msg = string.format("%d created, %d updated, %d placed on bars", mres.created, mres.updated, bres.placed)
    if ctx.macros.counts.noslot > 0 then msg = msg .. string.format(", %d without a free macro slot", ctx.macros.counts.noslot) end
    if bres.skipped > 0 then msg = msg .. string.format(", %d bar slots kept (occupied)", bres.skipped) end
    chat(msg .. ".")
    Core.log("info", "sync L" .. ctx.level .. ": " .. msg)
    for _, f in ipairs(mres.failed) do Core.log("error", "macro " .. f.name .. ": " .. f.err) end
    for _, f in ipairs(bres.failed) do Core.log("error", "bar " .. f.name .. ": " .. f.err) end
    if #mres.failed + #bres.failed > 0 then chat("|cffff6060Some changes failed|r – see /wbx log.") end
    Core.lastOffer = nil
    Core.changed()
  end)
end

-- ------------------------------------------------------------------ CVars
function Core.cvarPlan(overrides)
  local _, m = Core.me()
  local role = (m and not m.leader) and "follower" or "leader"
  local out = {}
  for _, c in ipairs(R.CVARS) do
    local cur = C.getCVar(c.name)
    local want = (overrides and overrides[c.name]) or c[role]
    out[#out + 1] = { name = c.name, label = c.label, why = c.why, current = cur, want = want, exists = cur ~= nil,
      backup = Core.cdb.cvarBackup[c.name], status = cur == nil and "missing" or (want == nil and "leave") or (tostring(cur) == want and "ok") or "change" }
  end
  return out, role
end
function Core.applyCVars(overrides)
  return Core.whenSafe("Apply settings", function()
    local n = 0
    for _, c in ipairs(Core.cvarPlan(overrides)) do
      if c.status == "change" and R.CVAR_BY_NAME[c.name] then
        if Core.cdb.cvarBackup[c.name] == nil then Core.cdb.cvarBackup[c.name] = tostring(c.current) end
        local ok = C.setCVar(c.name, c.want)
        if ok then n = n + 1 else Core.log("error", "SetCVar failed: " .. c.name) end
      end
    end
    chat(n .. " setting(s) changed. Restore puts the old values back.")
    Core.log("info", "cvars applied: " .. n)
    Core.changed()
  end)
end
function Core.restoreCVars()
  return Core.whenSafe("Restore settings", function()
    local n = 0
    for name, v in pairs(Core.cdb.cvarBackup) do
      if R.CVAR_BY_NAME[name] and C.setCVar(name, v) then n = n + 1 end
    end
    Core.cdb.cvarBackup = {}
    chat(n .. " setting(s) restored.")
    Core.log("info", "cvars restored: " .. n)
    Core.changed()
  end)
end

-- ------------------------------------------------------------------ import / export
function Core.importString(str)
  local res, err, warn = Sh.import(str, C.game())
  if not res then Core.log("warn", "import rejected: " .. tostring(err)); return nil, err end
  return res, nil, warn
end
--- Apply a validated import: replaces a squad with the same id, else adds it. Settings are not applied here.
function Core.applyImport(res)
  local db = Core.db
  local replaced = false
  for i, s in ipairs(db.squads) do if s.id == res.squad.id then db.squads[i] = res.squad; replaced = true end end
  if not replaced then db.squads[#db.squads + 1] = res.squad end
  db.active = res.squad.id
  if next(res.cvars) then Core.cdb.importCVars = res.cvars end
  if #res.addons > 0 then db.settings.addons = res.addons end
  Core.cdb.squadId, Core.cdb.memberId = nil, nil
  local _, m = Core.me()
  Core.log("info", "imported squad " .. res.squad.name .. " (" .. #res.squad.members .. " characters), me=" .. tostring(m and m.name))
  Core.changed()
  return m
end
function Core.exportString(squad)
  squad = squad or S.activeSquad(Core.db)
  if not squad then return nil end
  return Sh.export(squad, { game = C.game(), addons = Core.db.settings.addons })
end

-- ------------------------------------------------------------------ level-up offers
--- Compare what the character should have with what it has; offer an update (never applied without a click).
function Core.checkOffer(reason)
  local ctx = Core.compute()
  if not ctx then return end
  local n = ctx.macros.changes
  if n > 0 then
    local sig = ctx.level .. ":" .. n
    for _, it in ipairs(ctx.macros.items) do if it.status == "create" or it.status == "update" then sig = sig .. "|" .. it.name .. "=" .. it.body end end
    if Core.lastOffer ~= sig then
      Core.lastOffer = sig
      Core.log("info", "offer (" .. reason .. "): " .. n .. " key(s) changed at level " .. ctx.level)
      if Core.cdb.lastSync then -- only nag players who already use WoWBoxer keys
        chat(string.format("%d key(s) changed at level %d. Type |cffffd100/wbx sync|r or open |cffffd100/wbx|r to update them.", n, ctx.level))
        if ns.UI and ns.UI.ShowOffer then ns.UI.ShowOffer(ctx) end
      end
    end
  end
end

-- ------------------------------------------------------------------ change notification for the UI
function Core.changed() if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end end

-- ------------------------------------------------------------------ selftest (for testing without looking at the screen)
function Core.selftest()
  local db = Core.db
  local r = { at = time and time() or 0, version = Core.VERSION, probe = C.probe(), player = Core.playerInfo() }
  local ctx, why = Core.compute()
  if ctx then
    r.member = { name = ctx.member.name, cls = ctx.member.cls, role = ctx.member.role, leader = ctx.member.leader, unit = ctx.member.unit, seq = ctx.member.seq }
    r.macros = { counts = ctx.macros.counts, free = ctx.macros.free, charMax = ctx.macros.charMax, unused = ctx.macros.unused, items = {} }
    for _, it in ipairs(ctx.macros.items) do r.macros.items[#r.macros.items + 1] = { it.name, it.status, it.label, #it.body } end
    r.bars = { counts = ctx.bars.counts, items = {} }
    for _, it in ipairs(ctx.bars.items) do r.bars.items[#r.bars.items + 1] = { it.name, it.slot, it.status, it.current and (it.current.kind .. ":" .. tostring(it.current.name or it.current.id)) or "-" } end
    r.missing = {}
    for _, s in ipairs(ctx.missing) do r.missing[#r.missing + 1] = s.name end
  else r.error = why end
  local cv = Core.cvarPlan()
  r.cvars = {}
  for _, c in ipairs(cv) do r.cvars[c.name] = { cur = c.current, want = c.want, status = c.status } end
  r.addons = {}
  for _, a in ipairs(R.ADDONS) do r.addons[a.name] = C.addonState(a.name) end
  r.party = {}
  for i = 1, 4 do r.party["party" .. i] = C.unitName("party" .. i) or "-" end
  r.focus = C.unitName("focus") or "-"
  db.diag[Core.charKey or "?"] = r
  Core.log("info", "selftest written to WoWBoxerDB.diag[" .. tostring(Core.charKey) .. "]")
  chat("Selftest done. /reload (or log out) to save it to WTF\\...\\SavedVariables\\WoWBoxer.lua.")
  return r
end

-- ------------------------------------------------------------------ slash commands
local HELP = {
  "/wbx – open or close the window",
  "/wbx sync – create/update your WBX macros and place new ones on your bars",
  "/wbx show – list your keys and what would change",
  "/wbx cvars | /wbx cvars restore – apply recommended settings / put the old ones back",
  "/wbx selftest – write a diagnostic report to the saved variables",
  "/wbx log [n] – show the last n log lines; /wbx debug – toggle debug messages",
}
function Core.slash(msg)
  msg = (msg or ""):match("^%s*(.-)%s*$")
  local cmd, rest = msg:match("^(%S*)%s*(.-)$")
  cmd = (cmd or ""):lower()
  if cmd == "" then if ns.UI and ns.UI.Toggle then ns.UI.Toggle() else chat("window not available") end
  elseif cmd == "help" or cmd == "?" then for _, l in ipairs(HELP) do chat(l) end
  elseif cmd == "sync" then Core.sync({ replace = rest == "replace" })
  elseif cmd == "show" then
    local ctx, why = Core.compute()
    if not ctx then chat(why) return end
    chat(string.format("%s, level %d (%s): %d to create, %d to update, %d unchanged, %d free macro slots.", ctx.member.name, ctx.level,
      ctx.member.leader and "leader" or ("follows via " .. ctx.member.unit), ctx.macros.counts.create, ctx.macros.counts.update, ctx.macros.counts.same, ctx.macros.free))
    for _, it in ipairs(ctx.macros.items) do chat("  " .. it.name .. " – " .. it.label .. " [" .. it.status .. "]") end
  elseif cmd == "cvars" then if rest == "restore" then Core.restoreCVars() else Core.applyCVars(Core.cdb.importCVars) end
  elseif cmd == "selftest" then Core.selftest()
  elseif cmd == "debug" then Core.db.settings.debug = not Core.db.settings.debug; chat("debug " .. (Core.db.settings.debug and "on" or "off"))
  elseif cmd == "log" then
    local n = tonumber(rest) or 10
    local log = Core.db.log
    for i = math.max(1, #log - n + 1), #log do local e = log[i]; chat(date("%H:%M:%S", e.t) .. " " .. e.l .. " " .. e.m) end
  else chat("unknown command. /wbx help") end
end

-- ------------------------------------------------------------------ events
local frame = CreateFrame("Frame")
Core.frame = frame
local function safeRegister(ev) pcall(frame.RegisterEvent, frame, ev) end
safeRegister("ADDON_LOADED")
safeRegister("PLAYER_LOGIN")

local spellsTimer
function Core.onEvent(event, ...)
  if event == "ADDON_LOADED" then
    local name = ...
    if name ~= ADDON then return end
    Core.db, Core.cdb = S.initDB(_G.WoWBoxerDB, _G.WoWBoxerCharDB)
    _G.WoWBoxerDB, _G.WoWBoxerCharDB = Core.db, Core.cdb
  elseif event == "PLAYER_LOGIN" then
    Core.charKey = (C.playerName() or "?") .. "-" .. (GetRealmName and GetRealmName() or "?")
    Core.log("info", "login " .. Core.charKey .. " " .. C.buildString() .. " (" .. C.game() .. ", toc " .. C.interface() .. ")")
    safeRegister("PLAYER_LEVEL_UP")
    safeRegister("PLAYER_REGEN_ENABLED")
    safeRegister("SPELLS_CHANGED")
    safeRegister("LEARNED_SPELL_IN_TAB")
    safeRegister("LEARNED_SPELL_IN_SKILL_LINE")
    if C_Timer and C_Timer.After then C_Timer.After(3, function() Core.checkOffer("login") end) end
  elseif event == "PLAYER_REGEN_ENABLED" then
    Core.runQueue()
  elseif event == "PLAYER_LEVEL_UP" then
    local lvl = ...
    Core.log("info", "level up to " .. tostring(lvl))
    if C_Timer and C_Timer.After then C_Timer.After(1, function() Core.checkOffer("level " .. tostring(lvl)) end) else Core.checkOffer("level") end
  elseif event == "SPELLS_CHANGED" or event == "LEARNED_SPELL_IN_TAB" or event == "LEARNED_SPELL_IN_SKILL_LINE" then
    if spellsTimer then return end
    spellsTimer = true
    local function run() spellsTimer = nil; Core.checkOffer("spells") end
    if C_Timer and C_Timer.After then C_Timer.After(2, run) else run() end
  end
end
frame:SetScript("OnEvent", function(_, event, ...) Core.onEvent(event, ...) end)

_G.SLASH_WOWBOXER1 = "/wbx"
_G.SLASH_WOWBOXER2 = "/wowboxer"
_G.SlashCmdList["WOWBOXER"] = function(msg) Core.slash(msg) end

-- used by the UI
Core.K = K
