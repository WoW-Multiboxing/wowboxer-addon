--[[ WoWBoxer – team status between your own clients (display only).
  Each client tells the party its own state: level, mana (10 % steps), following or not, its target's GUID and whether
  it is in combat, plus (message X) its gold and free bag slots. Every client shows the squad in a small panel and
  points out problems: "not following", "other target" (a follower hits something else than the leader), "low mana",
  "bags full", "away" (AFK/DND, read from the party unit), "no signal".
  Hard rule: these messages are only DISPLAYED. Nothing a message says ever makes this client act (no targeting,
  following, casting or key presses) – the player still presses every key himself.
  Traffic: one short addon message on change, at most one per MIN_GAP seconds, plus a heartbeat. Silent when solo,
  when the squad has one character, or when switched off (/wbx team off). ]]
local _, ns = ...
local TM = {}
ns.Team = TM

TM.PREFIX = "WBX1"
TM.MIN_GAP = 1.5     -- seconds between two messages from this client
TM.HEARTBEAT = 15    -- resend the same state this often so others know we are still there
TM.STALE = 40        -- no message for this long = "no signal"
TM.LOW_MANA = 20
TM.peers = {}
TM.extras = {}       -- name:lower() -> {gold, free, slots, at} from X messages
TM.BAGS_FULL = 2     -- free slots at or below this = "bags full"

local G = _G
local function Core() return ns.Core end
local function C() return ns.Compat end
local function now() return (G.GetTime and G.GetTime()) or 0 end

-- ------------------------------------------------------------------ settings + when to talk
function TM.enabled() local db = Core().db; return db ~= nil and db.settings.team ~= false end
--- True when this client should send and show: switched on, in a group, and its squad has more than one character.
function TM.active()
  if not TM.enabled() then return false end
  local s, m = Core().me()
  if not m or #s.members < 2 then return false end
  return C().inParty() and true or false
end
local function channel() return (G.IsInRaid and G.IsInRaid()) and "RAID" or "PARTY" end

-- ------------------------------------------------------------------ my state
TM.following = false
local function safeCall(f, ...)
  if not f then return nil end
  local ok, v = pcall(f, ...)
  if not ok then return nil end
  return C().safe(v)
end
local NO_MANA = { warrior = true, rogue = true }
function TM.collect()
  local st = { level = tonumber(safeCall(G.UnitLevel, "player")) or 0, follow = TM.following and 1 or 0 }
  st.combat = safeCall(G.UnitAffectingCombat, "player") and 1 or 0
  local cls = C().playerClass()
  local cur, mx = safeCall(G.UnitPower, "player", 0), safeCall(G.UnitPowerMax, "player", 0)
  if NO_MANA[cls or ""] or type(cur) ~= "number" or type(mx) ~= "number" or mx <= 0 then st.mana = -1
  else st.mana = math.floor(cur / mx * 10 + 0.5) * 10 end
  local guid = safeCall(G.UnitGUID, "target")
  if type(guid) == "string" and guid:match("^[%w%-:]+$") and #guid <= 64 then st.target = guid
  elseif safeCall(G.UnitExists, "target") then st.target = "?"   -- a target we may not identify (secret)
  else st.target = "-" end
  return st
end

-- ------------------------------------------------------------------ my readiness + version (Squad pages)
--- The WoWBoxer version of this client ("0.13.0-test.1" from the installed TOC without the " (sha)", else Core.VERSION).
function TM.version()
  local v = (ns.Core.addonVersion() or ""):match("^[%w%.%-]+")
  if not v then v = ns.Core.VERSION end
  return v:sub(1, 20)
end
--- R|version|keys to update|unit ok (1/0/2 unknown)|follow+assist on bars (1/0)|settings to change
function TM.encodeReady(r)
  return table.concat({ "R", TM.version(), math.min(99, r.keys or 0), r.unit or 2, r.helpers or 1, math.min(99, r.cvars or 0) }, "|")
end
function TM.decodeReady(text)
  if type(text) ~= "string" or #text > 80 then return nil end
  local ver, keys, unit, helpers, cvars = text:match("^R|([%w%.%-]+)|(%d+)|([012])|([01])|(%d+)$")
  if not ver or #ver > 20 then return nil end
  return { version = ver, keys = tonumber(keys), unit = tonumber(unit), helpers = tonumber(helpers), cvars = tonumber(cvars) }
end

-- ------------------------------------------------------------------ wire format: S|level|mana|follow|combat|target
function TM.encode(st) return table.concat({ "S", st.level, st.mana, st.follow, st.combat, st.target }, "|") end
--- Data only: a fixed pattern, numbers and a GUID-shaped string. Anything else is ignored.
function TM.decode(text)
  if type(text) ~= "string" or #text > 120 then return nil end
  local lvl, mana, follow, combat, target = text:match("^S|(%d+)|(%-?%d+)|([01])|([01])|([%w%-:%?]+)$")
  if not lvl then return nil end
  return { level = tonumber(lvl), mana = tonumber(mana), follow = tonumber(follow), combat = tonumber(combat), target = target }
end

-- ------------------------------------------------------------------ gold and bags: X|gold|free|slots
local function freeSlots()
  local CC = G.C_Container
  local nslots = (CC and CC.GetContainerNumSlots) or G.GetContainerNumSlots
  local nfree = (CC and CC.GetContainerNumFreeSlots) or G.GetContainerNumFreeSlots
  if not (nslots and nfree) then return nil, nil end
  local free, total = 0, 0
  for bag = 0, 4 do
    local okS, n = pcall(nslots, bag)
    local okF, fr, kind = pcall(nfree, bag)
    if okS and okF and type(n) == "number" and type(fr) == "number" and (kind == nil or kind == 0) then
      total, free = total + n, free + fr     -- normal bags only (not quivers, soul bags, herb bags)
    end
  end
  return free, total
end
function TM.collectExtra()
  local money = tonumber(safeCall(G.GetMoney)) or 0
  local free, total = freeSlots()
  return { gold = math.floor(money / 10000), free = free or -1, slots = total or -1 }
end
function TM.encodeExtra(x) return table.concat({ "X", math.min(x.gold, 9999999), x.free, x.slots }, "|") end
function TM.decodeExtra(text)
  if type(text) ~= "string" or #text > 40 then return nil end
  local gold, free, slots = text:match("^X|(%d+)|(%-?%d+)|(%-?%d+)$")
  if not gold then return nil end
  return { gold = tonumber(gold), free = tonumber(free), slots = tonumber(slots) }
end
function TM.sendExtra(force)
  if not TM.active() then return false end
  local msg = TM.encodeExtra(TM.collectExtra())
  local t = now()
  if not force and msg == TM.lastExtra and t - (TM.lastExtraAt or -1e9) < TM.HEARTBEAT then return false end
  if not force and t - (TM.lastExtraAt or -1e9) < TM.MIN_GAP then return false end
  local CI = G.C_ChatInfo
  local send = (CI and CI.SendAddonMessage) or G.SendAddonMessage
  if not send then return false end
  local ok = pcall(send, TM.PREFIX, msg, channel())
  if ok then TM.lastExtra, TM.lastExtraAt = msg, t end
  return ok
end

-- ------------------------------------------------------------------ sending (throttled)
function TM.send(force)
  if not TM.active() then return false end
  local msg = TM.encode(TM.collect())
  local t = now()
  if not force and msg == TM.lastMsg and t - (TM.lastAt or -1e9) < TM.HEARTBEAT then return false end
  if t - (TM.lastAt or -1e9) < TM.MIN_GAP then TM.schedule(); return false end
  local CI = G.C_ChatInfo
  local send = (CI and CI.SendAddonMessage) or G.SendAddonMessage
  if not send then return false end
  local ok = pcall(send, TM.PREFIX, msg, channel())
  if ok then TM.lastMsg, TM.lastAt = msg, t; TM.sent = (TM.sent or 0) + 1 end
  return ok
end
--- My readiness (keys, unit, Follow/Assist, settings) – on the heartbeat and after a change, never more often than MIN_GAP.
function TM.sendReady(force)
  if not TM.active() or (ns.Compat.inCombat() and not force) then return false end
  local ok, r = pcall(ns.Squad.myReady)
  if not ok or not r then return false end
  local msg = TM.encodeReady(r)
  local t = now()
  if not force and msg == TM.lastReady and t - (TM.lastReadyAt or -1e9) < TM.HEARTBEAT then return false end
  local CI = G.C_ChatInfo
  local send = (CI and CI.SendAddonMessage) or G.SendAddonMessage
  if not send then return false end
  local sent = pcall(send, TM.PREFIX, msg, channel())
  if sent then TM.lastReady, TM.lastReadyAt = msg, t end
  return sent
end

--- Bag and money changes come in bursts (looting, selling): one X message after MIN_GAP.
function TM.scheduleExtra()
  if TM.pendingExtra then return end
  TM.pendingExtra = true
  local function run() TM.pendingExtra = false; TM.sendExtra(); if ns.TeamFrame then ns.TeamFrame.Refresh() end end
  if G.C_Timer and G.C_Timer.After then G.C_Timer.After(TM.MIN_GAP, run) else run() end
end
--- Coalesce bursts (power updates, target changes) into one message after MIN_GAP.
function TM.schedule()
  if TM.pending then return end
  TM.pending = true
  local function run() TM.pending = false; TM.send() end
  if G.C_Timer and G.C_Timer.After then G.C_Timer.After(TM.MIN_GAP, run) else run() end
end

-- ------------------------------------------------------------------ receiving (display only)
function TM.receive(prefix, text, _, sender)
  if prefix ~= TM.PREFIX then return end
  local name = C().safe(sender)
  if type(name) ~= "string" then return end
  name = name:match("^([^%-]+)") or name
  if name:lower() == (C().playerName() or ""):lower() then return end
  if type(text) ~= "string" then return end
  local kind = text:sub(1, 2)
  if kind == "R|" then
    local r = TM.decodeReady(text)
    if not r then return end
    local p = TM.peers[name:lower()] or { name = name, level = 0, mana = -1, follow = 0, combat = 0, target = "-" }
    p.ready, p.version, p.at, p.name = r, r.version, now(), name
    TM.peers[name:lower()] = p
    TM.changed()
    return
  end
  if kind == "X|" then
    local x = TM.decodeExtra(text)
    if not x then return end
    x.at = now()
    TM.extras[name:lower()] = x
    TM.changed()
    return
  end
  if kind == "Q|" or kind == "P|" then
    if ns.Sync then ns.Sync.receive(text, name) end
    return
  end
  local st = TM.decode(text)
  if not st then return end
  local old = TM.peers[name:lower()]
  st.at, st.name = now(), name
  if old then st.ready, st.version = old.ready, old.version end
  TM.peers[name:lower()] = st
  TM.changed()
end
--- The last state another client reported (nil when none or older than STALE).
function TM.peer(name)
  local p = name and TM.peers[name:lower()]
  if p and now() - (p.at or 0) > TM.STALE then return nil end
  return p
end
--- Something from another client arrived: refresh what shows it.
function TM.changed()
  if ns.TeamFrame then ns.TeamFrame.Refresh() end
  if ns.UI and ns.UI.frame and ns.UI.frame:IsShown() and ns.UI.current == "squad" then ns.UI.Refresh() end
end

--- Rows for the panel: one per squad character, with problems. {{name, cls, me, leader, st, flags = {{text, level}}}}
function TM.rows()
  local s, me = Core().me()
  if not me then return {} end
  local t = now()
  local function stateOf(m)
    if m == me then local st = TM.collect(); st.at = t; return st end
    local st = TM.peers[m.name:lower()]
    if st and t - st.at > TM.STALE then return nil end
    return st
  end
  local leader = ns.State.leaderOf(s)
  local lst = leader and stateOf(leader)
  local rows = {}
  for _, m in ipairs(s.members) do
    local st = stateOf(m)
    local flags = {}
    if not st then flags[#flags + 1] = { "no signal", "muted" }
    else
      if not m.leader and st.follow == 0 and st.combat == 0 then flags[#flags + 1] = { "not following", "warn" } end
      if not m.leader and lst and (st.combat == 1 or lst.combat == 1) and lst.target ~= "-" and lst.target ~= "?" and
        st.target ~= "?" and st.target ~= lst.target then flags[#flags + 1] = { st.target == "-" and "no target" or "other target", "warn" } end
      if st.mana >= 0 and st.mana <= TM.LOW_MANA then flags[#flags + 1] = { "low mana", "bad" } end
    end
    -- gold / bags (mine live, others from their X message) and away (AFK/DND straight from the unit)
    local x = m == me and TM.collectExtra() or TM.extras[m.name:lower()]
    if x and m ~= me and t - (x.at or 0) > TM.STALE then x = nil end
    if x and x.free >= 0 and x.slots > 0 and x.free <= TM.BAGS_FULL then flags[#flags + 1] = { "bags full", "warn" } end
    local unit = m == me and "player" or ns.Squad.unitOf(m.name)
    if unit and ((G.UnitIsAFK and C().safe(G.UnitIsAFK(unit))) or (G.UnitIsDND and C().safe(G.UnitIsDND(unit)))) then
      table.insert(flags, 1, { "away", "muted" })
    end
    rows[#rows + 1] = { name = m.name, cls = m.cls, me = m == me, leader = m.leader, st = st, flags = flags, extra = x }
  end
  return rows
end

-- ------------------------------------------------------------------ events
local f = CreateFrame("Frame")
TM.frame = f
local function reg(ev) pcall(f.RegisterEvent, f, ev) end
function TM.Init()
  local CI = G.C_ChatInfo
  local regp = (CI and CI.RegisterAddonMessagePrefix) or G.RegisterAddonMessagePrefix
  if regp then pcall(regp, TM.PREFIX) end
  for _, ev in ipairs({ "CHAT_MSG_ADDON", "AUTOFOLLOW_BEGIN", "AUTOFOLLOW_END", "PLAYER_TARGET_CHANGED", "UNIT_POWER_UPDATE",
    "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "GROUP_ROSTER_UPDATE", "PLAYER_LEVEL_UP", "PLAYER_MONEY", "BAG_UPDATE",
    "PLAYER_FLAGS_CHANGED" }) do reg(ev) end
  TM.heartbeat()
end
function TM.heartbeat()
  TM.send()
  TM.sendReady()
  TM.sendExtra()
  if ns.TeamFrame then ns.TeamFrame.Refresh() end
  if G.C_Timer and G.C_Timer.After then G.C_Timer.After(TM.HEARTBEAT, TM.heartbeat) end
end
f:SetScript("OnEvent", function(_, event, a, b, c, d)
  if event == "CHAT_MSG_ADDON" then TM.receive(a, b, c, d); return end
  if event == "AUTOFOLLOW_BEGIN" then TM.following = true
  elseif event == "AUTOFOLLOW_END" then TM.following = false
  elseif event == "UNIT_POWER_UPDATE" and a ~= "player" then return end
  if event == "GROUP_ROSTER_UPDATE" and ns.TeamFrame then ns.TeamFrame.Refresh() end
  if event == "PLAYER_FLAGS_CHANGED" then TM.changed(); return end
  if event == "PLAYER_MONEY" or event == "BAG_UPDATE" then TM.scheduleExtra(); return end
  TM.schedule()
end)

return TM
