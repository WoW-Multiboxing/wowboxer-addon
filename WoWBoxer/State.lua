--[[ WoWBoxer – squad state.
  Squads and members use the companion's schema (forever-companion/8-squad), sanitised the same way as the companion's
  newSquad / newMember / cleanCustom / sanitizeOrder, so a squad can travel between website, companion and addon. ]]
local _, ns = ...
local S = {}
ns.State = S

local E, K, R = ns.Engine, ns.Kit, ns.Rules
local floor, max, min = math.floor, math.max, math.min

S.MAX_MEMBERS = 10
S.CUSTOM_MAX = 8
local ROLES = { "tank", "healer", "melee", "ranged" }
S.ROLES = ROLES
S.ROLE_NAME = { tank = "Tank", healer = "Healer", melee = "Melee DPS", ranged = "Ranged DPS" }

local function D() return ns.Data end
local idCounter = 0
--- Random-ish id like the companion's uid(p): prefix + 7 base36 chars.
function S.uid(p)
  idCounter = idCounter + 1
  local n = floor((((time and time()) or 0) * 7919 + idCounter * 104729 + floor(math.random() * 1e6)) % 78364164096)
  local digits, s = "0123456789abcdefghijklmnopqrstuvwxyz", ""
  for _ = 1, 7 do local d = n % 36; s = digits:sub(d + 1, d + 1) .. s; n = floor(n / 36) end
  return p .. s
end
local function safeId(v, p)
  if type(v) == "string" and #v >= 1 and #v <= 24 and not v:find("[^%w]") then return v end
  return S.uid(p)
end
S.safeId = safeId
local function clampLvl(v) v = tonumber(v); if not v or v ~= v then return 1 end; return max(1, min(60, floor(v + 0.5))) end
local function clampT(v) v = tonumber(v); if not v or v ~= v then return 0 end; return max(0, min(5, floor(v + 0.5))) end
S.clampLvl, S.clampT = clampLvl, clampT

function S.validClass(cls) return type(cls) == "string" and D().classes[cls] ~= nil end
function S.racesFor(cls)
  local out = {}
  for _, r in ipairs(D().races) do if E.contains(r.c, cls) then out[#out + 1] = r end end
  return out
end

--- Keep only talent keys of the class; repair the order so every point is legal (companion sanitizeOrder).
function S.sanitizeOrder(cls, order)
  local T = K.tree(cls)
  if type(order) ~= "table" or not T then return {} end
  local o = {}
  for _, k in ipairs(order) do if type(k) == "string" and T.byKey[k] and #o < 51 then o[#o + 1] = k end end
  if not E.validateOrder(T, o) then return o end
  local rest, out, c = E.slice(o), {}, E.newCounts()
  local progress = true
  while #rest > 0 and progress do
    progress = false
    for i = 1, #rest do
      if not E.addBlocker(T, c, rest[i]) then
        local k = table.remove(rest, i); out[#out + 1] = k; E.bump(c, k); progress = true; break
      end
    end
  end
  return out
end

function S.cleanCustom(list)
  if type(list) ~= "table" then return {} end
  local out, seen = {}, {}
  local function str(v) if v == nil then return "" end v = tostring(v); return v:sub(1, 40) end
  for _, c in ipairs(list) do
    if type(c) == "table" and #out < S.CUSTOM_MAX then
      local steps = {}
      if type(c.steps) == "table" then
        for i, s in ipairs(c.steps) do if i > 12 then break end local v = str(s); if v ~= "" then steps[#steps + 1] = v end end
      end
      local fills = floor((tonumber(c.fills) or 1) + 0.5)
      if fills == 0 then fills = 1 end
      local x = { id = safeId(c.id, "q"), name = (R.cleanText(c.name, 24) or ""), kind = E.contains(E.CUSTOM_KINDS, c.kind) and c.kind or "sequence",
        aim = E.contains(E.CUSTOM_AIMS, c.aim) and c.aim or "harm", steps = steps, filler = str(c.filler),
        fills = max(1, min(6, fills)), reset = E.contains(E.CUSTOM_RESETS, c.reset) and c.reset or "combat" }
      if x.name == "" then x.name = "My key" end
      if seen[x.id] then x.id = S.uid("q") end
      seen[x.id] = true
      out[#out + 1] = x
    end
  end
  return out
end

function S.newMember(o)
  o = type(o) == "table" and o or {}
  local cls = S.validClass(o.cls) and o.cls or "warrior"
  local races = S.racesFor(cls)
  local race = races[1].k
  for _, r in ipairs(races) do if r.k == o.race then race = o.race end end
  local roles = D().classes[cls].roles
  local role = E.contains(roles, o.role) and o.role or roles[1]
  local guide = (type(o.guide) == "string" and K.guide(cls, o.guide)) and o.guide or K.defaultGuideFor(cls, role)
  local pins = {}
  if type(o.pins) == "table" then for _, p in ipairs(o.pins) do if type(p) == "string" and #pins < 24 then pins[#pins + 1] = p end end end
  local name = R.cleanText(o.name, 24)
  if not name or name == "" then name = D().classes[cls].n end
  return { id = safeId(o.id, "m"), name = name, cls = cls, race = race, role = role, level = clampLvl(o.level or 1), leader = not not o.leader,
    unit = E.contains(E.UNITS, o.unit) and o.unit or "party1", talented = clampT(o.talented), build = S.sanitizeOrder(cls, o.build or {}),
    guide = guide, seq = E.contains(E.SEQ_TIERS, o.seq) and o.seq or "off", seqTarget = not not o.seqTarget,
    seqTier = (E.contains(E.SEQ_TIERS, o.seqTier) and o.seqTier ~= "off") and o.seqTier or nil, customSeq = S.cleanCustom(o.customSeq), pins = pins }
end

function S.fixLeader(s)
  local any = false
  for _, m in ipairs(s.members) do if m.leader then any = true end end
  if #s.members > 0 and not any then s.members[1].leader = true end
  local seen = false
  for _, m in ipairs(s.members) do if m.leader then if seen then m.leader = false end seen = true end end
end
function S.leaderOf(s) for _, m in ipairs(s and s.members or {}) do if m.leader then return m end end return nil end
function S.applyLink(s)
  local L = S.leaderOf(s)
  if s and s.linkLevels and L then for _, m in ipairs(s.members) do m.level = L.level end end
end

function S.newSquad(o)
  o = type(o) == "table" and o or {}
  local name = R.cleanText(o.name, 40)
  if not name or name == "" then name = "New squad" end
  local s = { id = safeId(o.id, "s"), name = name, faction = o.faction == "alliance" and "alliance" or "horde", linkLevels = not not o.linkLevels, members = {}, current = nil }
  local seen = {}
  if type(o.members) == "table" then
    for _, m in ipairs(o.members) do
      if #s.members >= S.MAX_MEMBERS then break end
      local x = S.newMember(m)
      if seen[x.id] then x.id = S.uid("m") end
      seen[x.id] = true
      s.members[#s.members + 1] = x
    end
  end
  S.fixLeader(s)
  s.current = (s.members[1] and s.members[1].id) or nil
  for _, m in ipairs(s.members) do if m.id == o.current then s.current = o.current end end
  S.applyLink(s)
  return s
end

-- ------------------------------------------------------------------ DB
function S.initDB(db, cdb)
  db = type(db) == "table" and db or {}
  cdb = type(cdb) == "table" and cdb or {}
  db.v = 1
  local squads = {}
  if type(db.squads) == "table" then
    for i, s in ipairs(db.squads) do if i <= 30 then squads[#squads + 1] = S.newSquad(s) end end
  end
  db.squads = squads
  local activeOk = false
  for _, s in ipairs(squads) do if s.id == db.active then activeOk = true end end
  if not activeOk then db.active = squads[1] and squads[1].id or nil end
  db.settings = type(db.settings) == "table" and db.settings or {}
  db.log = type(db.log) == "table" and db.log or {}
  db.diag = type(db.diag) == "table" and db.diag or {}
  cdb.v = 1
  -- nil until chosen: Core picks a default per class at login (stance/form classes avoid bar 1)
  cdb.primaryBar = tonumber(cdb.primaryBar)
  cdb.secondaryBar = tonumber(cdb.secondaryBar)
  cdb.slots = type(cdb.slots) == "table" and cdb.slots or {}
  cdb.skip = type(cdb.skip) == "table" and cdb.skip or {}
  cdb.extras = type(cdb.extras) == "table" and cdb.extras or {}
  cdb.cvarBackup = type(cdb.cvarBackup) == "table" and cdb.cvarBackup or {}
  return db, cdb
end

function S.squad(db, id) for _, s in ipairs(db.squads) do if s.id == id then return s end end return nil end
function S.activeSquad(db) return S.squad(db, db.active) or db.squads[1] end
function S.member(s, id) for _, m in ipairs(s and s.members or {}) do if m.id == id then return m end end return nil end

--- Find the member that is this character: stored link first, then by name (active squad first).
function S.findMe(db, cdb, playerName)
  local s = S.squad(db, cdb.squadId)
  local m = s and S.member(s, cdb.memberId)
  if m then return s, m end
  if not playerName then return nil end
  local lname = playerName:lower()
  local order = { S.activeSquad(db) }
  for _, x in ipairs(db.squads) do if x ~= order[1] then order[#order + 1] = x end end
  for _, x in ipairs(order) do
    for _, mm in ipairs(x and x.members or {}) do
      if mm.name:lower() == lname then cdb.squadId, cdb.memberId = x.id, mm.id; return x, mm end
    end
  end
  return nil
end

--- Make the member match the live character (class, race, level). Returns true if the class changed.
function S.syncFromGame(m, info)
  local changed = false
  if info.cls and S.validClass(info.cls) and m.cls ~= info.cls then
    m.cls = info.cls; changed = true
    m.role = D().classes[m.cls].roles[1]
    m.build, m.customSeq, m.pins = {}, {}, {}
    m.guide = K.defaultGuideFor(m.cls, m.role)
    if not E.contains(E.SEQ_TIERS, m.seq) or not E.seqSupported(m.cls) then m.seq = "off" end
  end
  if info.race then
    for _, r in ipairs(S.racesFor(m.cls)) do if r.k == info.race then m.race = info.race end end
  end
  if info.level then m.level = clampLvl(info.level) end
  return changed
end

--- Quick start: a squad with just this character as leader.
function S.quickStart(db, cdb, info)
  local s = S.newSquad({ name = (info.name or "My") .. "'s squad", faction = info.faction,
    members = { { name = info.name, cls = info.cls, race = info.race, level = info.level, leader = true } } })
  db.squads[#db.squads + 1] = s
  db.active = s.id
  cdb.squadId, cdb.memberId = s.id, s.members[1].id
  return s, s.members[1]
end
