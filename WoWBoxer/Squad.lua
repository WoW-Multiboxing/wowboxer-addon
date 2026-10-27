--[[ WoWBoxer – squad helpers for the Squad pages (docs/squad-overhaul.md §3): the live party, which unit holds the
  leader here, readiness per member, the key map ("same key, same job"), the levelling plan and the cheat sheet.
  Everything here only reads: the game (party units) and WoWBoxer's own data. Other clients' state comes from the
  display-only team messages (Team.lua). Nothing here acts for another client. ]]
local _, ns = ...
local SQ = {}
ns.Squad = SQ

local G = _G
local function Core() return ns.Core end
local function S() return ns.State end
local function C() return ns.Compat end

SQ.PARTY = { "party1", "party2", "party3", "party4" }
--- The key map columns: kit keys 1–8, the sequence keys, Follow and Assist.
SQ.KEYS = { { "K1", "1" }, { "K2", "2" }, { "K3", "3" }, { "K4", "4" }, { "K5", "5" }, { "K6", "6" }, { "K7", "7" }, { "K8", "8" },
  { "S1", "Seq" }, { "S2", "Heal" }, { "Follow", "Follow" }, { "Assist", "Assist" } }

local function unitName(u) local n = C().unitName(u); return type(n) == "string" and n or nil end

-- ------------------------------------------------------------------ the live party
--- {{name, cls, race, level, leader, unit}} – this character first, then party1–4. Secret/unknown values are left out.
function SQ.partyInfo()
  local out = {}
  local function add(u)
    local name = unitName(u)
    if not name then return end
    local okc, _, file = pcall(G.UnitClass, u)
    local cls = okc and C().safe(file)
    cls = type(cls) == "string" and cls:lower() or nil
    if not (cls and S().validClass(cls)) then return end
    local okr, _, rfile = pcall(G.UnitRace, u)
    local race = okr and C().raceKey and C().raceKey(C().safe(rfile)) or nil
    local okl, lvl = pcall(G.UnitLevel, u)
    local okg, lead = pcall(G.UnitIsGroupLeader or function() return false end, u)
    out[#out + 1] = { name = name:match("^([^%-]+)") or name, cls = cls, race = race, level = okl and tonumber(C().safe(lvl)) or nil,
      leader = okg and C().safe(lead) == true or false, unit = u }
  end
  add("player")
  for _, u in ipairs(SQ.PARTY) do add(u) end
  -- no group leader known (solo or old API): this character leads
  local any = false
  for _, x in ipairs(out) do if x.leader then any = true end end
  if not any and out[1] then out[1].leader = true end
  return out
end

--- Which party unit holds `name` on this client, or nil.
function SQ.unitOf(name)
  if not name then return nil end
  local l = name:lower()
  for _, u in ipairs(SQ.PARTY) do local n = unitName(u); if n and (n:match("^([^%-]+)") or n):lower() == l then return u end end
  return nil
end

--- This character follows and the leader is in another party slot here: the unit to use instead, or nil.
function SQ.unitHint()
  local s, m = Core().me()
  if not m or m.leader or m.unit == "focus" or not C().inParty() then return nil end
  local L = S().leaderOf(s)
  local u = L and SQ.unitOf(L.name)
  if u and u ~= m.unit then return u, L end
  return nil
end

-- ------------------------------------------------------------------ readiness of this character (sent to the others)
--- {keys = keys to create/update/place, unit = 1 ok / 0 wrong / 2 unknown, helpers = 1 when Follow/Assist are on a bar
--- (or not needed), cvars = game settings still to change}
function SQ.myReady(ctx)
  ctx = ctx or Core().compute()
  local s, m = Core().me()
  if not (ctx and m) then return nil end
  local r = { keys = ctx.macros.changes + ctx.bars.changes, unit = 2, helpers = 1, cvars = 0 }
  if m.leader then r.unit = 1
  elseif m.unit ~= "focus" and C().inParty() then
    local L = S().leaderOf(s)
    local n = unitName(m.unit)
    r.unit = (L and n and (n:match("^([^%-]+)") or n):lower() == L.name:lower()) and 1 or 0
  end
  for _, b in ipairs(ctx.bars.items) do
    if (b.name == "WBX Follow" or b.name == "WBX Assist") and b.status ~= "placed" then r.helpers = 0 end
  end
  local plan = Core().cvarPlan(Core().cdb.importCVars)
  for _, c in ipairs(plan) do if c.status == "change" then r.cvars = r.cvars + 1 end end
  return r
end

--- One row per member: {m, me, inParty, signal, level, ready={…}|nil, version}. Other members from team messages.
function SQ.readiness()
  local s, me = Core().me()
  local out = {}
  if not me then return out end
  local TM = ns.Team
  for _, m in ipairs(s.members) do
    local row = { m = m, me = m == me }
    if m == me then
      row.inParty, row.signal, row.level, row.ready, row.version = C().inParty() or #s.members == 1, true, C().playerLevel(), SQ.myReady(), TM.version()
    else
      row.inParty = SQ.unitOf(m.name) ~= nil
      local p = TM.peer(m.name)
      row.signal = p ~= nil
      row.level = p and p.level or m.level
      row.ready = p and p.ready or nil
      row.version = p and p.version or nil
      row.st = p
    end
    out[#out + 1] = row
  end
  return out
end

-- ------------------------------------------------------------------ key map: same key, same job
--- {cols = SQ.KEYS, rows = {{m, cells = {[key] = {label, icon}|false}}}, gaps = n}
function SQ.keyMap(s)
  local rows, gaps = {}, 0
  for _, m in ipairs(s and s.members or {}) do
    local cells = {}
    for _, d in ipairs(ns.Macros.desired(m, m.level, {})) do
      cells[d.key] = { label = d.label, icon = ns.Book and ns.Book.iconFor(d, d) or nil }
    end
    for _, k in ipairs(SQ.KEYS) do if not cells[k[1]] then cells[k[1]] = false end end
    rows[#rows + 1] = { m = m, cells = cells }
  end
  -- a gap: a kit key some members have and others not
  for _, k in ipairs(SQ.KEYS) do
    local any, missing = false, 0
    for _, r in ipairs(rows) do if r.cells[k[1]] then any = true else missing = missing + 1 end end
    if any and k[1]:match("^K") then gaps = gaps + missing end
  end
  return { cols = SQ.KEYS, rows = rows, gaps = gaps }
end

--- The key map as plain text for a cheat sheet (copy with Ctrl+C).
function SQ.cheatSheet(s)
  local map = SQ.keyMap(s)
  local lines = { "WoWBoxer squad \"" .. (s and s.name or "?") .. "\" – same key, same job" }
  for _, k in ipairs(map.cols) do
    local parts = {}
    for _, r in ipairs(map.rows) do
      local c = r.cells[k[1]]
      if c then parts[#parts + 1] = r.m.name .. ": " .. c.label end
    end
    if #parts > 0 then lines[#lines + 1] = (k[2]:match("^%d$") and ("Key " .. k[2]) or k[2]) .. " – " .. table.concat(parts, " · ") end
  end
  return table.concat(lines, "\n")
end

-- ------------------------------------------------------------------ levelling plan
--- The next level at which the member learns something new at the trainer: level, {names} (or nil).
function SQ.nextTrainer(m)
  local K = ns.Kit
  for L = (m.level or 1) + 1, 60 do
    local names = {}
    for _, s in ipairs(K.spellsOf(m)) do
      if s.gate ~= "talent" and s.gate ~= "racial" and s.action ~= "passive" then
        local new = s.level == L
        if not new then for _, r in ipairs(s.ranks or {}) do if r.l == L and s.level < L then new = true end end end
        if new and #names < 3 then names[#names + 1] = s.name end
      end
    end
    if #names > 0 then return L, names end
  end
  return nil
end

--- The member's next talent point from the guide: {level, name} or nil.
function SQ.nextTalent(m)
  local K, E = ns.Kit, ns.Engine
  local order = K.plan(m)
  local T = K.tree(m.cls)
  local have = E.pointsAt(m.level or 1, m.talented)
  local k = order[have + 1]
  if not (k and T and T.byKey[k]) then return nil end
  return { level = E.levelForPoint(have, m.talented), name = T.byKey[k].n }
end

return SQ
