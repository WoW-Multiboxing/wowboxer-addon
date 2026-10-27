-- Parity: the Lua engine/kit must give exactly the output of the companion's JavaScript (tests/vectors from tools/export_vectors.js).
local H = dofile((arg[0]:match("^(.*)/[^/]+$") or ".") .. "/harness.lua")
local ns = H.loadAddon({ files = {
  "Data/Common.lua", "Data/Class_warrior.lua", "Data/Class_paladin.lua", "Data/Class_hunter.lua", "Data/Class_rogue.lua",
  "Data/Class_priest.lua", "Data/Class_shaman.lua", "Data/Class_mage.lua", "Data/Class_warlock.lua", "Data/Class_druid.lua",
  "Engine.lua", "Kit.lua", "Json.lua" } })
local E, K, Json, D = ns.Engine, ns.Kit, ns.Json, ns.Data

local function vec(name)
  local txt = H.readFile(H.root .. "/tests/vectors/" .. name .. ".json")
  assert(txt, "missing vectors – run: node tools/export_vectors.js")
  local v, err = Json.decode(txt)
  assert(v ~= nil, err)
  return v
end
local CTX = { { leader = true, unit = "party1" } }
for _, u in ipairs(E.UNITS) do CTX[#CTX + 1] = { leader = false, unit = u } end

local only = arg[1]
local t0 = os.clock()

-- 1. macros ------------------------------------------------------------
if not only or only == "macros" then
  local spellIndex = {}
  for cls, list in pairs(D.spells) do for _, s in ipairs(list) do spellIndex[s.id] = s end end
  for _, v in ipairs(vec("macros")) do
    local s
    if v.engage then s = K.engage()
    elseif v.race then for _, r in ipairs(K.racialsOf({ race = v.race, cls = v.cls })) do if r.id == v.id then s = r end end
    else s = spellIndex[v.id] end
    if H.ok(s ~= nil, "spell not found " .. tostring(v.id)) then
      if v.strCtx then
        for i = 1, #v.out do H.eq(E.makeMacro(s, v.strCtx[i]), v.out[i], "macro " .. v.id .. " strctx " .. i) end
      else
        for i, c in ipairs(CTX) do H.eq(E.makeMacro(s, c), v.out[i], "macro " .. v.id .. " ctx " .. i) end
      end
    end
  end
end

-- 2. talents -------------------------------------------------------------
if not only or only == "talents" then
  local tv = vec("talents")
  local trees = K.trees()
  for n, v in ipairs(tv.ops) do
    local T = trees[v.cls]
    local id = v.cls .. " op " .. n
    H.deqMsg(E.validateOrder(T, v.order), v.validate, id .. " validate")
    H.deqMsg(E.repairOrder(T, v.order), v.repair, id .. " repair")
    H.deqMsg(E.addPoint(T, v.order, v.add.key, v.add.cap), v.add.out, id .. " add")
    if v.remove then H.deqMsg(E.removePoint(T, v.order, v.remove.key), v.remove.out, id .. " remove " .. v.remove.key) end
    if v.code then
      H.eq(E.stateBlocker(T, E.countsOf(v.order)), v.state, id .. " state")
      H.eq(E.encodeBuild(T, v.cls, v.order), v.code, id .. " encode")
      H.deqMsg(E.decodeBuild(trees, v.code), v.decode, id .. " decode")
    end
    local g = K.guide(v.cls, v.guide)
    H.deqMsg(E.guideNext(T, g.order, v.order), v.next, id .. " next")
    H.deqMsg(E.offGuide(g.order, v.order), v.off, id .. " off")
    local c = E.countsOf(v.order, v.countsLimit)
    local plain = {}; for k, x in pairs(c) do plain[k] = x end
    H.deqMsg(plain, v.counts, id .. " counts")
    H.deqMsg(E.treePoints(T, E.countsOf(v.order)), v.trees, id .. " treePoints")
  end
  for _, d in ipairs(tv.decode) do H.deqMsg(E.decodeBuild(trees, d.code), d.out, "decode '" .. d.code .. "'") end
  for _, p in ipairs(tv.points) do
    H.eq(E.pointsAt(p[1], p[2]), p[3], "pointsAt " .. p[1] .. "," .. p[2])
    H.eq(E.firstPointLevel(p[2]), p[4], "firstPointLevel " .. p[2])
    H.eq(E.levelForPoints(p[1], p[2]), p[5], "levelForPoints " .. p[1] .. "," .. p[2])
  end
end

-- 3. kit ------------------------------------------------------------------
local function ids(list, star) local o = {}; for i, s in ipairs(list) do o[i] = s.id .. ((star and s.fromTalent) and "*" or "") end return o end
if not only or only == "kit" then
  local kv = vec("kit")
  for n, v in ipairs(kv.members) do
    local m = v.m
    local id = m.cls .. "/" .. m.role .. "/" .. m.race .. " #" .. n
    for _, b in ipairs(v.core) do
      for L = b.from, b.to do H.deqMsg(ids(K.coreList(m, L)), b.v, id .. " coreList L" .. L) end
    end
    for _, b in ipairs(v.lists) do
      for L = b.from, b.to do
        m.level = L
        local x = K.kitLists(m)
        H.deqMsg({ p = ids(x.primary), o = ids(x.others, true) }, b.v, id .. " kitLists L" .. L)
      end
    end
  end
  for _, g in ipairs(kv.guides) do
    H.eq(K.defaultGuide(g.cls), g.def, "defaultGuide " .. g.cls)
    H.eq(K.defaultGuideFor(g.cls, g.role), g.out, "defaultGuideFor " .. g.cls .. "/" .. g.role)
  end
end

-- 4. built-in sequences ----------------------------------------------------
if not only or only == "sequences" then
  for n, v in ipairs(vec("sequences")) do
    local m = v.m
    local id = m.cls .. "/" .. m.role .. "/" .. m.seq .. "/" .. (m.leader and "leader" or m.unit) .. " #" .. n
    local plan = K.seqPlan(m)
    H.eq(#plan, #v.plan, id .. " band count")
    for i, b in ipairs(v.plan) do
      local p = plan[i] or {}
      H.eq(p.from, b.from, id .. " band " .. i .. " from")
      H.eq(p.to, b.to, id .. " band " .. i .. " to")
      H.deqMsg(p.list, b.list, id .. " band " .. i .. " list")
    end
  end
end

-- 5. custom keys and warnings ------------------------------------------------
if not only or only == "custom" then
  for n, v in ipairs(vec("custom")) do
    local m = v.m
    local id = m.cls .. " custom #" .. n .. " L" .. v.L
    H.deqMsg(K.seqOf(m, v.L), v.seq, id .. " seqOf")
    local has = K.seqHas(m, v.L)
    for i, ck in ipairs(m.customSeq) do
      local sp = {}
      for _, s in ipairs(ck.steps or {}) do local x = has(s); if x then sp[#sp + 1] = x end end
      local f = (ck.filler and ck.filler ~= "") and has(ck.filler) or nil
      H.deqMsg(E.customWarnings(ck.kind == "priority" and "priority" or "sequence", sp, f, ck.aim, m.cls), v.warn[i], id .. " warnings " .. i)
    end
  end
end

print(string.format("(%.1f s)", os.clock() - t0))
os.exit(H.report("parity") and 0 or 1)
