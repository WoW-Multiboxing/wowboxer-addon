--[[ WoWBoxer – kit.
  Lua port of the companion's per-character helpers in app.js (racialsOf, spellsOf, learned, coreList, kitLists, seqOf,
  seqPlan, defaultGuideFor). A "member" is the companion's member object:
    {id, name, cls, race, role, level, leader, unit, talented, build={talent keys}, guide, seq, seqTarget, customSeq, pins}
  Its output is locked per game by tests/test_golden.lua (tests/golden/). Addon-only additions (stable key slots, helper macros) are at the end. ]]
local _, ns = ...
local K = {}
ns.Kit = K
local E = ns.Engine

local tinsert, tsort, tconcat = table.insert, table.sort, table.concat
local contains, slice = E.contains, E.slice

local function D() return ns.Data end

-- ------------------------------------------------------------------ trees (cached)
local treeCache = {}
function K.tree(cls)
  if not treeCache[cls] and D().talents[cls] then treeCache[cls] = E.makeTree(D().talents[cls]) end
  return treeCache[cls]
end
function K.trees() for _, c in ipairs(D().classOrder) do K.tree(c) end return treeCache end

local raceIndex
function K.race(key)
  if not raceIndex then raceIndex = {}; for _, r in ipairs(D().races) do raceIndex[r.k] = r end end
  return raceIndex[key]
end

-- ------------------------------------------------------------------ spells
function K.engage()
  local g = D().engage
  if not K._engage then
    K._engage = { id = g.id, cls = "paladin", name = g.name, level = g.level, category = g.category, action = g.action, icon = g.icon, gate = g.gate, ranks = {},
      castFirst = g.castFirst, castLast = g.castLast, cdSec = g.cdSec, durSec = g.durSec }
  end
  return K._engage
end

local racialCache = {}
--- Racials of the member's race as spell objects (same fields as the companion's racialsOf).
function K.racialsOf(m)
  local r = D().racials[m.race]
  if not r then return {} end
  local key = m.race .. "|" .. tostring(m.cls)
  if racialCache[key] then return racialCache[key] end
  local out = {}
  for _, x in ipairs(r.racials) do
    if not x.only or contains(x.only, m.cls) then
      local desc = (x.note and (x.note .. " ") or "") .. (x.forever == "new" and "New in Forever." or "")
      out[#out + 1] = { id = x.id, cls = m.cls, name = x.name, level = 1, category = x.passive and "Passive" or "Racial", action = x.passive and "passive" or "self",
        icon = x.icon, gate = "racial", desc = desc, forever = x.forever, ranks = { { r = 1, id = x.spellId } },
        castFirst = x.castFirst, castLast = x.castLast, cdSec = x.cdSec, durSec = x.durSec }
    end
  end
  racialCache[key] = out
  return out
end

function K.raceOk(s, m)
  if not s.lock then return true end
  if s.lock.faction then local r = K.race(m.race); return r ~= nil and r.f == s.lock.faction end
  return contains(s.lock.races or {}, m.race)
end

function K.spellsOf(m)
  local out = {}
  for _, s in ipairs(D().spells[m.cls] or {}) do if K.raceOk(s, m) then out[#out + 1] = s end end
  for _, s in ipairs(K.racialsOf(m)) do out[#out + 1] = s end
  return out
end

function K.rankAt(s, level)
  local r
  for _, x in ipairs(s.ranks or {}) do if x.l == nil or x.l <= level then r = x end end
  return r
end
function K.nextRank(s, level)
  for _, x in ipairs(s.ranks or {}) do if x.l ~= nil and x.l > level then return x end end
  return nil
end

-- counts per (build, points) are cached: learned() is called for every spell and level
local countCache = setmetatable({}, { __mode = "k" })
function K.buildHas(m, talentKey, level)
  if not talentKey then return false end
  local pts = E.pointsAt(level, m.talented)
  local per = countCache[m.build]
  if not per then per = {}; countCache[m.build] = per end
  local c = per[pts]
  if not c then c = E.countsOf(m.build or {}, pts); per[pts] = c end
  return (c[talentKey] or 0) > 0
end
function K.learned(m, s, level) return s.level <= level and (s.gate ~= "talent" or K.buildHas(m, s.talent, level)) end
--- Can member m use spell s at level L? In game (live = the spellbook check): on a game whose data says liveSpells
--- (TBC: plan step 2) the spellbook alone decides; elsewhere the data must say learned AND the spellbook must have it.
function K.usable(m, s, L, live)
  if live and D().game and D().game.liveSpells then return live(s.name, s) and true or false end
  return K.learned(m, s, L) and (not live or live(s.name, s)) and true or false
end

-- ------------------------------------------------------------------ everyday kit
--- The companion's "primary keys" for class + role at level L (highest learned alternative wins).
function K.coreList(m, L)
  local have = {}
  for _, s in ipairs(K.spellsOf(m)) do if K.learned(m, s, L) then have[#have + 1] = s end end
  local items = (D().core[m.cls] or {})[m.role] or {}
  local out = {}
  for _, it in ipairs(items) do
    local names = type(it) == "table" and it or { it }
    local pick
    for _, n in ipairs(names) do for _, x in ipairs(have) do if x.name == n then pick = x break end end end
    if pick and not contains(out, pick) then out[#out + 1] = pick end
  end
  if m.cls == "paladin" and L < 4 and (m.role == "tank" or m.role == "melee") then tinsert(out, 1, K.engage()) end
  return slice(out, 1, math.min(8, #out))
end

local CAT_ORDER = { "Damage", "Heal", "Debuff", "Control", "Defense", "Buff", "Totem", "Pet", "Utility", "Mount", "Racial" }
K.CAT_ORDER = CAT_ORDER
local function catOrder(s) for i, c in ipairs(CAT_ORDER) do if c == s.category then return i - 1 end end return 99 end
K.catOrder = catOrder

-- String.prototype.localeCompare (ICU root collation) for ASCII: punctuation < digits < letters, case-insensitive
-- first; lower case before upper case only as a tie-break.
local PUNCT = " _-,;:!?.'\"()[]{}@*/\\&#%`^+<=>|~$"
local weight = {}
for i = 1, #PUNCT do weight[PUNCT:byte(i)] = i end
for b = 48, 57 do weight[b] = 100 + b end
for b = 97, 122 do weight[b] = 200 + b; weight[b - 32] = 200 + b end
function K.localeCompare(a, b)
  local la, lb = #a, #b
  for i = 1, math.min(la, lb) do
    local wa, wb = weight[a:byte(i)] or 1000 + a:byte(i), weight[b:byte(i)] or 1000 + b:byte(i)
    if wa ~= wb then return wa < wb and -1 or 1 end
  end
  if la ~= lb then return la < lb and -1 or 1 end
  for i = 1, la do -- tertiary: lower case first
    local ca, cb = a:byte(i), b:byte(i)
    if ca ~= cb then local ua, ub = ca >= 65 and ca <= 90, cb >= 65 and cb <= 90; if ua ~= ub then return ua and 1 or -1 end return ca < cb and -1 or 1 end
  end
  return 0
end

--- {primary, others}: pinned + core keys, then every other learned non-passive spell sorted like the companion.
function K.kitLists(m)
  local L, all = m.level, K.spellsOf(m)
  local pinned = {}
  for _, id in ipairs(m.pins or {}) do
    for _, x in ipairs(all) do
      if x.id == id then if K.learned(m, x, L) and x.action ~= "passive" then pinned[#pinned + 1] = x end break end
    end
  end
  local primary = slice(pinned)
  for _, x in ipairs(K.coreList(m, L)) do if not contains(pinned, x) then primary[#primary + 1] = x end end
  local others = {}
  for i, s in ipairs(K.spellsOf(m)) do
    if K.learned(m, s, L) and not contains(primary, s) and s.action ~= "passive" then
      others[#others + 1] = { s = s, i = i }
    end
  end
  tsort(others, function(x, y)
    local a, b = x.s, y.s
    local ca, cb = catOrder(a), catOrder(b)
    if ca ~= cb then return ca < cb end
    if a.level ~= b.level then return a.level < b.level end
    local lc = K.localeCompare(a.name, b.name)
    if lc ~= 0 then return lc < 0 end
    return x.i < y.i
  end)
  for i, x in ipairs(others) do
    local s = x.s
    if s.gate == "talent" then local c = {}; for k, v in pairs(s) do c[k] = v end; c.fromTalent = true; s = c end
    others[i] = s
  end
  return { primary = primary, others = others }
end

-- ------------------------------------------------------------------ sequences
local MELEE_CLS = { "warrior", "rogue", "paladin" }
function K.isMelee(m)
  return contains(MELEE_CLS, m.cls) or (m.cls == "druid" and (m.role == "tank" or m.role == "melee")) or (m.cls == "shaman" and m.role == "melee")
end
function K.memberCtx(m) return { leader = not not m.leader, unit = m.unit, wand = E.WAND_CLASSES[m.cls] or false } end

--- has(name) for level L: the learned spell object with that name or nil. live(name) (optional, in game) must also say yes.
function K.seqHas(m, L, live)
  local all = K.spellsOf(m)
  return function(name)
    for _, s in ipairs(all) do
      if s.name == name and K.usable(m, s, L, live) then return s end
    end
    return nil
  end
end

function K.seqOf(m, L, live)
  local has = K.seqHas(m, L == nil and m.level or L, live)
  local gen = E.buildSequences(m.cls, m.role, m.seq or "off", K.memberCtx(m), has, { targetReset = not not m.seqTarget })
  for _, c in ipairs(m.customSeq or {}) do
    local r = E.buildCustom(m.cls, c, K.memberCtx(m), has, { melee = K.isMelee(m) })
    if r.kind ~= "empty" then gen[#gen + 1] = r end
  end
  return gen
end
function K.seqOn(m) return m ~= nil and ((m.seq and m.seq ~= "off" and E.seqSupported(m.cls)) or #(m.customSeq or {}) > 0) end

--- Level bands in which the sequence macros stay the same: {{from, to, list}}
function K.seqPlan(m)
  local out, prev = {}, nil
  for L = 1, E.maxLevel() do
    local list = K.seqOf(m, L)
    local parts = {}
    for i, x in ipairs(list) do parts[i] = x.macro end
    local sig = tconcat(parts, "\n§\n")
    if not prev or sig ~= prev.sig then prev = { from = L, to = L, list = list, sig = sig }; out[#out + 1] = prev else prev.to = L end
  end
  return out
end

-- ------------------------------------------------------------------ guides
--- The player's own builds (WoWBoxerDB.builds, set by State.initDB): {[cls] = {{id = "u…", label, kind, order, …}}}.
K.userBuilds = nil
function K.setBuilds(b) K.userBuilds = b end
--- The data guides only (defaults and parity never pick a player's build).
function K.dataGuidesOf(cls) return D().guides[cls] or {} end
--- The player's builds first ("My builds"), then the data guides. A build works everywhere a guide id works.
function K.guidesOf(cls)
  local mine = K.userBuilds and K.userBuilds[cls]
  if not (mine and #mine > 0) then return K.dataGuidesOf(cls) end
  local out = {}
  for _, b in ipairs(mine) do out[#out + 1] = b end
  for _, g in ipairs(K.dataGuidesOf(cls)) do out[#out + 1] = g end
  return out
end
function K.guide(cls, id) for _, g in ipairs(K.guidesOf(cls)) do if g.id == id then return g end end return nil end
function K.defaultGuide(cls)
  local first
  for _, g in ipairs(K.dataGuidesOf(cls)) do first = first or g; if g.default then return g.id end end
  return first and first.id or nil
end
--- Best guide for a class + role: the class default if it matches the role's spec, else the longest exact/derived guide of that spec.
function K.defaultGuideFor(cls, role)
  local spec, def = (D().roleSpec[cls] or {})[role], K.defaultGuide(cls)
  if not spec or (K.guide(cls, def) or {}).spec == spec then return def end
  local c, idx = {}, {}
  for i, g in ipairs(K.dataGuidesOf(cls)) do if g.spec == spec and #g.order > 0 then c[#c + 1] = g; idx[g] = i end end
  tsort(c, function(a, b)
    local ea, eb = a.kind ~= "exact-order" and 1 or 0, b.kind ~= "exact-order" and 1 or 0
    if ea ~= eb then return ea < eb end
    if #a.order ~= #b.order then return #a.order > #b.order end
    return idx[a] < idx[b]
  end)
  return c[1] and c[1].id or def
end

--- The member's talent plan: own build if any, else the selected guide's order.
function K.plan(m)
  if m.build and #m.build > 0 then return m.build, "build" end
  local g = K.guide(m.cls, m.guide or "") or K.guide(m.cls, K.defaultGuideFor(m.cls, m.role))
  return g and g.order or {}, g and "guide" or "none"
end

-- ================================================================== addon-only additions
--- Stable key slots for the everyday kit: slot i = item i of the companion's kit list for class + role,
--- so a level-up changes the body of WBX K<i> but never moves it. Paladin tank/melee levels 1–3: "Engage Target"
--- takes the Judgement slot (from level 4 Judgement does this job, same key).
function K.kitSlots(m, L, live)
  local have = {}
  for _, s in ipairs(K.spellsOf(m)) do
    if K.usable(m, s, L, live) then have[#have + 1] = s end
  end
  local items = (D().core[m.cls] or {})[m.role] or {}
  local out, used = {}, {}
  for i, it in ipairs(items) do
    if i > 8 then break end
    local names = type(it) == "table" and it or { it }
    local pick
    for _, n in ipairs(names) do for _, x in ipairs(have) do if x.name == n then pick = x break end end end
    if pick and not used[pick] then used[pick] = true; out[#out + 1] = { slot = i, spell = pick, item = names[1] }
    elseif m.cls == "paladin" and L < 4 and (m.role == "tank" or m.role == "melee") and names[1] == "Judgement" then
      out[#out + 1] = { slot = i, spell = K.engage(), item = names[1] }
    end
  end
  return out
end

--- Helper macros for the member (followers: follow/assist/focus; pet classes: pet attack/recall). Only whitelisted commands.
function K.helpers(m)
  local u = E.units(m.unit)
  local out = {}
  if not m.leader then
    out[#out + 1] = { key = "Follow", label = "Follow the leader", body = "/follow " .. u.main }
    out[#out + 1] = { key = "Assist", label = "Take the leader's target", body = "/assist " .. u.main }
    if m.unit == "focus" then
      out[#out + 1] = { key = "Focus", label = "Set your target (the leader) as focus", body = "/focus [@target,help,nodead]" }
    end
  end
  if m.cls == "warlock" or m.cls == "hunter" then
    local chain = m.leader and "[@mouseover,harm,nodead][harm,nodead]" or ("[@mouseover,harm,nodead][@" .. u.mainTarget .. ",harm,nodead][harm,nodead]")
    out[#out + 1] = { key = "Pet", label = "Send pet to the same target", body = "#showtooltip\n/petattack " .. chain }
    out[#out + 1] = { key = "PetBack", label = "Pet passive + follow", body = "/petpassive\n/petfollow" }
  end
  if E.WAND_CLASSES[m.cls] then
    local chain = m.leader and "[@mouseover,harm,nodead][harm,nodead]" or ("[@mouseover,harm,nodead][@" .. u.mainTarget .. ",harm,nodead][harm,nodead]")
    out[#out + 1] = { key = "Wand", label = "Shoot your wand at " .. (m.leader and "your target" or "the leader's target"),
      body = "#showtooltip Shoot\n/cast " .. chain .. " !Shoot" }
  end
  return out
end

--- Talents spent in game (ranks by name, from Compat.talentRanks) compared with the plan at this level.
--- {spent, available, matched, off = {{key, name, have, plan}}, next = {key, name, rank, level}|nil, unknown = {names}}
function K.talentStatus(m, ranks, level)
  local T = K.tree(m.cls)
  local byName = {}
  for _, n in ipairs(T.nodes) do byName[n.n:lower()] = n end
  local counts, spent, unknown = {}, 0, {}
  for name, r in pairs(ranks or {}) do
    local n = type(name) == "string" and byName[name:lower()]
    if n then
      local c = math.min(tonumber(r) or 0, n.m)
      counts[n.k] = c; spent = spent + c
    else unknown[#unknown + 1] = tostring(name) end
  end
  table.sort(unknown)
  local plan = K.plan(m)
  local have = E.pointsAt(level, m.talented)
  local want = E.countsOf(plan, have)
  local off = {}
  for k, c in pairs(counts) do
    local w = want[k] or 0
    if c > w then off[#off + 1] = { key = k, name = T.byKey[k].n, have = c, plan = w } end
  end
  table.sort(off, function(a, b) return a.name < b.name end)
  local order = {}
  for _, n in ipairs(T.nodes) do for _ = 1, counts[n.k] or 0 do order[#order + 1] = n.k end end
  local nxt
  if #plan > 0 then
    local g = E.guideNext(T, plan, order)
    if g and T.byKey[g.key] then nxt = { key = g.key, name = T.byKey[g.key].n, rank = g.rank, level = E.levelForPoint(g.index, m.talented) } end
  end
  return { spent = spent, available = have, off = off, next = nxt, unknown = unknown }
end

return K
