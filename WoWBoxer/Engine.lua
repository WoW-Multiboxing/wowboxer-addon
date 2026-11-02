--[[ WoWBoxer – engine.
  Lua port of the WoW Forever Multibox Companion engine (vendor/companion/engine.js, v8.4). Pure logic, no WoW API,
  so it runs in the tests exactly as in the game. Shared by every game; the per-game data (spells, talents, guides,
  sequence tables) is in Data/<Game>/ and Games/<Game>.lua. tests/test_golden.lua locks its output per game.

  Talent rules (Forever, build 1.60.1.70450/70532):
    - one talent point per level 10–60 (51 total; TBC: 10–70, 61 – per game, E.maxPoints()); Legacy perk "Talented" rank r moves the first point to level 10-r;
    - row N of a tree opens after (N-1)*5 points in that tree;
    - a talent at the end of an arrow needs the talent at the arrow's start at full rank.
  Macro rules (manual multiboxing, one key press = one action on one character):
    - the squad LEADER plays normally: hostile mouseover > own target; heals: friendly mouseover > friendly target > self;
    - FOLLOWERS assist the leader through a unit (party1-4 or focus): hostile mouseover > leader's target > own target;
      heals/buffs: friendly mouseover > leader > self;
    - melee abilities start auto attack with /startattack; pet classes send the pet with /petattack;
      crowd control never starts attacks or pets; every macro is at most 255 characters.
  Spell objects carry pre-computed seconds (castFirst, castLast, cdSec, durSec) from tools/build_data.js. ]]
local _, ns = ...
local E = {}
ns.Engine = E

local floor, ceil, max, min = math.floor, math.ceil, math.max, math.min
local tinsert, tconcat, tremove = table.insert, table.concat, table.remove
local sfind, ssub, sformat, smatch = string.find, string.sub, string.format, string.match

local MACRO_LIMIT = 255
E.MACRO_LIMIT = MACRO_LIMIT
--- Per game (ns.Data.game from Games/<Game>.lua): talent points at max level and the max level. Forever/Era 51 at 60.
local function MAXP() local g = ns.Data and ns.Data.game; return (g and g.maxPoints) or 51 end
function E.maxPoints() return MAXP() end
function E.maxLevel() local g = ns.Data and ns.Data.game; return (g and g.maxLevel) or 60 end

-- ------------------------------------------------------------------ small helpers (JS semantics)
local function jsround(x) return floor(x + 0.5) end
local function trunc(x) x = tonumber(x) or 0; if x ~= x then return 0 end; return x >= 0 and floor(x) or ceil(x) end
--- Number to string the way JavaScript prints it (15 -> "15", 1.5 -> "1.5").
local function numstr(x)
  if x == floor(x) and x > -1e15 and x < 1e15 then return sformat("%d", x) end
  local s = sformat("%.15g", x)
  if tonumber(s) ~= x then s = sformat("%.17g", x) end
  return s
end
E.numstr = numstr
local function contains(list, v) for i = 1, #list do if list[i] == v then return true end end return false end
local function slice(list, a, b) local out = {}; for i = a or 1, b or #list do out[#out + 1] = list[i] end return out end
local function replaceFirst(s, find, repl)
  local i = sfind(s, find, 1, true)
  if not i then return s end
  return ssub(s, 1, i - 1) .. repl .. ssub(s, i + #find)
end
E.contains, E.slice = contains, slice

-- ------------------------------------------------------------------ talents
function E.firstPointLevel(talented) return 10 - max(0, min(5, trunc(talented))) end
function E.pointsAt(level, talented)
  local n = level - E.firstPointLevel(talented) + 1
  return max(0, min(MAXP(), n))
end
function E.levelForPoint(index, talented) return E.firstPointLevel(talented) + index end -- index 0-based
function E.levelForPoints(n, talented) if n <= 0 then return 1 end return E.firstPointLevel(talented) + n - 1 end

--- classData = {trees={{n=...}}, nodes={{k,n,t,r,c,m,...}}, arrows={{a,b}}}; node.t is 0-based like the companion.
function E.makeTree(classData)
  local byKey, prereq, dependents = {}, {}, {}
  for i, n in ipairs(classData.nodes) do byKey[n.k] = n; n.idx = i - 1 end
  for _, a in ipairs(classData.arrows) do
    prereq[a[2]] = a[1]
    dependents[a[1]] = dependents[a[1]] or {}
    tinsert(dependents[a[1]], a[2])
  end
  return { nodes = classData.nodes, byKey = byKey, prereq = prereq, dependents = dependents, trees = classData.trees, arrows = classData.arrows }
end

-- counts keep the order in which talents were first taken (JavaScript objects iterate in insertion order)
local ORDER = setmetatable({}, { __mode = "k" })
local function newCounts() local c = {}; ORDER[c] = {}; return c end
local function bump(c, k)
  if c[k] == nil then local o = ORDER[c]; if o then o[#o + 1] = k end; c[k] = 0 end
  c[k] = c[k] + 1
end
local function countKeys(c)
  local o = ORDER[c]
  if o then return o end
  local ks = {}; for k in pairs(c) do ks[#ks + 1] = k end; table.sort(ks); return ks
end
E.newCounts, E.bump, E.countKeys = newCounts, bump, countKeys

function E.countsOf(order, limit)
  local c = newCounts()
  local n = limit == nil and #order or min(limit, #order)
  for i = 1, n do bump(c, order[i]) end
  return c
end
function E.treePoints(T, counts)
  local t = { 0, 0, 0 }
  for k, v in pairs(counts) do local n = T.byKey[k]; if n then t[n.t + 1] = t[n.t + 1] + v end end
  return t
end
function E.total(counts) local s = 0; for _, v in pairs(counts) do s = s + v end return s end

--- Why a point can't be added (nil = allowed).
function E.addBlocker(T, counts, key, cap)
  local n = T.byKey[key]
  if not n then return { code = "unknown", text = "Unknown talent" } end
  local have = counts[key] or 0
  if have >= n.m then return { code = "max", text = n.n .. " is already at max rank" } end
  local lim = cap == nil and MAXP() or cap
  if E.total(counts) >= lim then return { code = "points", text = "No talent points left" } end
  local need, spent = (n.r - 1) * 5, E.treePoints(T, counts)[n.t + 1]
  if spent < need then
    return { code = "row", text = "Requires " .. need .. " points in " .. T.trees[n.t + 1].n .. " (you have " .. spent .. ")", need = need, spent = spent }
  end
  local p = T.prereq[key]
  if p and (counts[p] or 0) < T.byKey[p].m then
    local pm = T.byKey[p].m
    return { code = "prereq", text = "Requires " .. pm .. " point" .. (pm > 1 and "s" or "") .. " in " .. T.byKey[p].n, prereq = p }
  end
  return nil
end

--- Is a final allocation legal (independent of order)? Returns nil or a reason.
function E.stateBlocker(T, counts)
  if E.total(counts) > MAXP() then return "More than " .. MAXP() .. " points" end
  for _, k in ipairs(countKeys(counts)) do
    local v = counts[k]
    if v and v ~= 0 then
      local n = T.byKey[k]
      if not n then return "Unknown talent " .. k end
      if v > n.m then return n.n .. " above max rank" end
      local below = 0
      for kk, vv in pairs(counts) do local m = T.byKey[kk]; if m and m.t == n.t and m.r < n.r then below = below + vv end end
      if below < (n.r - 1) * 5 then return n.n .. " (row " .. n.r .. ") needs " .. (n.r - 1) * 5 .. " points in the rows above" end
      local p = T.prereq[k]
      if p and (counts[p] or 0) < T.byKey[p].m then return n.n .. " needs " .. T.byKey[p].n .. " at full rank" end
    end
  end
  return nil
end

function E.validateOrder(T, order)
  local c = newCounts()
  for i = 1, #order do
    local b = E.addBlocker(T, c, order[i])
    if b then return { index = i - 1, key = order[i], reason = b.text } end
    bump(c, order[i])
  end
  return nil
end

--- Re-sequence an order so every point is legal when taken, keeping the original order where the rules allow.
function E.repairOrder(T, order)
  local rest, out, c = slice(order), {}, newCounts()
  while #rest > 0 do
    local i = 1
    while i <= #rest do if not E.addBlocker(T, c, rest[i]) then break end i = i + 1 end
    if i > #rest then return nil end
    local k = tremove(rest, i)
    out[#out + 1] = k; bump(c, k)
  end
  return out
end

function E.addPoint(T, order, key, cap)
  local b = E.addBlocker(T, E.countsOf(order), key, cap)
  if b then return { error = b.text, code = b.code } end
  local o = slice(order); o[#o + 1] = key
  return { order = o }
end

function E.removePoint(T, order, key)
  local idx
  for i = #order, 1, -1 do if order[i] == key then idx = i break end end
  if not idx then return { error = "No points in " .. (T.byKey[key] and T.byKey[key].n or tostring(key)) } end
  local nxt = {}
  for i = 1, #order do if i ~= idx then nxt[#nxt + 1] = order[i] end end
  local c = E.countsOf(nxt)
  for _, d in ipairs(T.dependents[key] or {}) do
    if (c[d] or 0) > 0 and (c[key] or 0) < T.byKey[key].m then return { error = T.byKey[d].n .. " requires " .. T.byKey[key].n .. " at full rank" } end
  end
  local sb = E.stateBlocker(T, c)
  if sb then return { error = "Can't remove: " .. sb } end
  local fixed = E.repairOrder(T, nxt)
  if not fixed then return { error = "Can't remove: the remaining build would be invalid" } end
  return { order = fixed }
end

--- First guide point not yet covered by the build (by talent counts): {index (0-based), key, rank} or nil.
function E.guideNext(T, guideOrder, order)
  local mine, need = E.countsOf(order), {}
  for i = 1, #guideOrder do
    local k = guideOrder[i]
    need[k] = (need[k] or 0) + 1
    if need[k] > (mine[k] or 0) then return { index = i - 1, key = k, rank = need[k] } end
  end
  return nil
end
function E.offGuide(guideOrder, order)
  local g, mine, out = E.countsOf(guideOrder), E.countsOf(order), {}
  for k, v in pairs(mine) do if v > (g[k] or 0) then out[k] = v - (g[k] or 0) end end
  return out
end

local ALPHA = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
function E.encodeBuild(T, cls, order)
  local out = {}
  for i = 1, #order do local ix = T.byKey[order[i]].idx; out[i] = ssub(ALPHA, ix + 1, ix + 1) end
  return "WF8." .. cls .. "." .. tconcat(out)
end
--- trees: {cls = tree}. Returns {cls, order} or {error}.
function E.decodeBuild(trees, code)
  local s = smatch(tostring(code or ""), "^%s*(.-)%s*$")
  local cls, body = smatch(s, "^WF[78]%.([a-z]+)%.([A-Za-z0-9_%-]*)$")
  if cls and #body > 51 then cls = nil end
  if cls and not trees[cls] then return { error = "Unknown class in code" } end
  if not cls then return { error = "Not a valid WF7 build code" } end
  local T, order = trees[cls], {}
  for i = 1, #body do
    local ch = ssub(body, i, i)
    local ix = sfind(ALPHA, ch, 1, true)
    if not ix or not T.nodes[ix] then return { error = "Unknown talent in code" } end
    order[#order + 1] = T.nodes[ix].k
  end
  local v = E.validateOrder(T, order)
  if v then return { error = "Build code breaks talent rules at point " .. (v.index + 1) .. ": " .. v.reason } end
  return { cls = cls, order = order }
end

-- ------------------------------------------------------------------ macros
local UNITS = { "party1", "party2", "party3", "party4", "focus" }
E.UNITS = UNITS
function E.units(mode)
  local u = contains(UNITS, mode) and mode or "party1"
  return { main = u, mainTarget = u .. "target" }
end
local function ctxOf(ctx)
  if type(ctx) == "string" or ctx == nil then return { leader = false, unit = ctx or "party1" } end
  return { leader = not not ctx.leader, unit = contains(UNITS, ctx.unit) and ctx.unit or "party1" }
end
E.ctxOf = ctxOf

local function buildMacro(s, ctxIn)
  local ctx, name = ctxOf(ctxIn), s.name
  local u = E.units(ctx.unit)
  local title = "#showtooltip " .. name
  local harm = ctx.leader and "[@mouseover,harm,nodead][harm,nodead]" or ("[@mouseover,harm,nodead][@" .. u.mainTarget .. ",harm,nodead][harm,nodead]")
  local help = ctx.leader and "[@mouseover,help,nodead][help,nodead][@player]" or ("[@mouseover,help,nodead][@" .. u.main .. ",help,nodead][@player]")
  local meleeStart = ctx.leader and "/startattack [harm,nodead]" or ("/startattack " .. harm)
  local meleeCast = ctx.leader and "[harm,nodead]" or harm
  local a = s.action
  if a == "engage" then return "#showtooltip Attack\n" .. meleeStart
  elseif a == "melee" then return title .. "\n" .. meleeStart .. "\n/cast " .. meleeCast .. " " .. name
  elseif a == "melee-pet" then return title .. "\n" .. meleeStart .. "\n/petattack " .. harm .. "\n/cast " .. meleeCast .. " " .. name
  elseif a == "melee-cc" then return title .. "\n" .. meleeStart .. "\n/cast " .. harm .. " " .. name
  elseif a == "opener" then return title .. "\n/cast " .. meleeCast .. " " .. name .. "\n" .. meleeStart
  elseif a == "aoe-melee" then return title .. "\n" .. meleeStart .. "\n/cast " .. name
  elseif a == "dual" then
    return title .. "\n" .. meleeStart .. "\n/cast [@mouseover,harm,nodead][@mouseover,help,nodead]" .. (ctx.leader and "" or ("[@" .. u.mainTarget .. ",harm,nodead]")) .. "[harm,nodead][help,nodead][@player] " .. name
  elseif a == "ranged" then return title .. "\n/cast " .. harm .. " " .. name
  elseif a == "autoshot" then return title .. "\n/petattack " .. harm .. "\n/cast " .. harm .. " !" .. name
  elseif a == "petattack" then return title .. "\n/petattack " .. harm .. "\n/cast " .. harm .. " " .. name
  elseif a == "friendlymain" then return title .. "\n/cast " .. help .. " " .. name
  elseif a == "friendlyself" then return title .. "\n/cast [@mouseover,help,nodead][help,nodead][@player] " .. name
  elseif a == "friendlytarget" then return title .. "\n/cast [@mouseover,help,nodead][help,nodead] " .. name
  elseif a == "petheal" then return title .. "\n/cast [@pet,exists,nodead] " .. name
  elseif a == "resurrection" then return title .. "\n/cast [@mouseover,help,dead][help,dead] " .. name
  elseif a == "hostile" then return title .. "\n/cast [@mouseover,harm,nodead][harm,nodead] " .. name
  elseif a == "passive" then return ""
  end
  return title .. "\n/cast " .. name
end
function E.makeMacro(s, ctxIn)
  local out = buildMacro(s, ctxIn)
  if #out > MACRO_LIMIT then return replaceFirst(out, "#showtooltip " .. s.name .. "\n", "#showtooltip\n") end
  return out
end
E.OFFENSIVE_MELEE = { "melee", "melee-pet", "melee-cc", "aoe-melee", "dual", "engage", "opener" }
E.OFFENSIVE_PAL = E.OFFENSIVE_MELEE

-- ------------------------------------------------------------------ sequences (opt-in)
local SEQ_TIERS = { "off", "simple", "medium", "advanced" }
local SEQ_MAX_FILL = 4
E.SEQ_TIERS = SEQ_TIERS
-- The sequence tables are per game data: ns.Data.sequences from Games/<Game>.lua (only the running game's file loads).
-- step: string = spell name, list = first learned of the alternatives; k: 'dot' | 'cd' | 'hot' | 'nuke' (default)
local function SEQ() return (ns.Data and ns.Data.sequences) or {} end
--- The running game's sequence table {[cls] = {[role or "_all"] = {defs}}}.
function E.seqTable() return SEQ() end
function E.seqSupported(cls) return SEQ()[cls] ~= nil end
local function pickSpell(alts, has)
  if type(alts) ~= "table" then alts = { alts } end
  for _, n in ipairs(alts) do local s = has(n); if s then return s end end
  return nil
end
local function seqDefs(cls, role) local c = SEQ()[cls]; if not c then return {} end return c[role] or c._all or {} end
local function castSec(s, which) return which == "first" and (s.castFirst or 1.5) or (s.castLast or 1.5) end
local function cdSec(s) return s.cdSec or 0 end
local function durSec(s) return s.durSec or 0 end
E.castSec, E.cdSec, E.durSec = castSec, cdSec, durSec

--- Targeting for a sequence line. lvl 0 = full, 1 = without the own-target fallback, 2 = leader's target only (followers).
local function aimFor(def, ctx, lvl)
  local u = E.units(ctx.unit)
  if def.aim == "help" then
    if ctx.leader then return lvl == 0 and "[@mouseover,help,nodead][help,nodead][@player]" or "[help,nodead][@player]" end
    return lvl < 2 and ("[@mouseover,help,nodead][@" .. u.main .. ",help,nodead][@player]") or ("[@" .. u.main .. ",help,nodead][@player]")
  end
  if ctx.leader then return lvl < 2 and "[@mouseover,harm,nodead][harm,nodead]" or "[harm,nodead]" end
  local opts = { "[@mouseover,harm,nodead][@" .. u.mainTarget .. ",harm,nodead][harm,nodead]", "[@mouseover,harm,nodead][@" .. u.mainTarget .. ",harm,nodead]", "[@" .. u.mainTarget .. ",harm,nodead]" }
  return opts[lvl + 1]
end
E.aimFor = aimFor

local function buildCastSequence(def, t, ctx, has, o)
  local steps = {}
  for _, st in ipairs(t.steps) do
    local s = pickSpell(st.s, has)
    if s then
      local dup = false
      if not def.allowDup then for _, x in ipairs(steps) do if x.s == s then dup = true break end end end
      if not dup then steps[#steps + 1] = { s = s, k = st.k or "nuke", consumes = st.consumes } end
    end
  end
  local filler = pickSpell(t.filler, has)
  if not filler and #steps == 0 then return nil end
  local names = {}
  for i, x in ipairs(steps) do names[i] = x.s.name end
  local pre, preFast = 0, 0
  for _, x in ipairs(steps) do pre = pre + castSec(x.s, "last"); preFast = preFast + castSec(x.s, "first") end
  local n, why, need = 0, "", 1
  if filler then
    local consumed = {}
    for _, x in ipairs(steps) do if x.consumes then consumed[#consumed + 1] = x.consumes end end
    local dots, cds = {}, {}
    for _, x in ipairs(steps) do
      if (x.k == "dot" or x.k == "hot") and not contains(consumed, x.s.name) then local d = durSec(x.s); if d ~= 0 then dots[#dots + 1] = d end end
      if x.k == "cd" then local c = cdSec(x.s); if c ~= 0 then cds[#cds + 1] = c end end
    end
    local fc, fcFast = castSec(filler, "last"), castSec(filler, "first")
    if #steps == 0 then n = 1
    elseif def.fixedFill then n = def.fixedFill
    else
      if #dots > 0 then local d = min(unpack(dots)); n = max(1, jsround((d - pre) / fc)); why = "about every " .. numstr(d) .. " s" end
      if #cds > 0 then
        local c = max(unpack(cds))
        need = max(1, ceil((c - preFast) / fcFast))
        if need > n then n = need; why = need <= SEQ_MAX_FILL and "cooldown-safe" or "" end
      end
    end
    n = max(1, min(def.fixedFill and 6 or SEQ_MAX_FILL, n)); need = min(need, n)
  end
  -- reset=target only helps a character whose own target changes: the leader. Followers cast on the leader's target.
  local reset = def.reset or ((o.targetReset and ctx.leader) and "target/combat" or "combat")
  local function make(lvl, nFill)
    local aim = aimFor(def, ctx, lvl)
    local list = slice(names)
    if filler then for _ = 1, nFill do list[#list + 1] = filler.name end end
    local txt = "#showtooltip\n"
    if def.startattack then txt = txt .. "/startattack " .. aim .. "\n" end
    if def.pet then txt = txt .. "/petattack " .. aim .. "\n" end
    if #list == 1 then return txt .. "/cast " .. aim .. " " .. list[1] end
    return txt .. "/castsequence " .. aim .. " reset=" .. reset .. " " .. tconcat(list, ", ")
  end
  -- fit 255 characters: (1) drop the own-target fallback, (2) the leader's target only, then (3) fewer fillers,
  -- but never fewer than a cooldown in the loop needs
  local level, fill = 0, n
  local macro = make(0, fill)
  for _, lv in ipairs({ 1, 2 }) do
    if #macro > MACRO_LIMIT and aimFor(def, ctx, lv) ~= aimFor(def, ctx, level) then level = lv; macro = make(lv, fill) end
  end
  while #macro > MACRO_LIMIT and fill > need do fill = fill - 1; macro = make(level, fill) end
  local single = #names + (filler and fill or 0) == 1
  local loopSec = jsround((pre + (filler and fill * castSec(filler, "last") or 0)) * 10) / 10
  if fill < n and ssub(why, 1, 5) == "about" then why = "" end
  local spells = slice(names)
  if filler then spells[#spells + 1] = filler.name end
  return { id = def.id, label = def.label, base = "sequence", fixedReset = not not def.reset, kind = single and "single" or "sequence",
    spells = spells, filler = filler and filler.name or nil, fills = filler and fill or 0,
    reset = reset, loopSec = loopSec, why = why, macro = macro, compact = level > 0 or fill < n, tooLong = #macro > MACRO_LIMIT }
end
E.buildCastSequence = buildCastSequence

local function buildPriority(def, t, ctx, has)
  local spells, self = {}, {}
  for _, n in ipairs(t.steps) do
    local o = (type(n) == "table" and n.s ~= nil) and n or { s = n }
    local s = pickSpell(o.s, has)
    if s and not contains(spells, s) then spells[#spells + 1] = s; if o.self then self[s] = true end end
  end
  local u = E.units(ctx.unit)
  local tipName
  for _, s in ipairs(spells) do if s.name == def.tip then tipName = def.tip break end end
  tipName = tipName or (spells[1] and spells[1].name or "Attack")
  -- v8.5: /startattack only for melee keys, /petattack for pet keys, a final !Auto Shot for hunters; a ranged leader
  -- aims at the mouseover first
  local function make(lvl, list)
    local aim
    if ctx.leader then aim = def.aim == "melee" and "" or "[@mouseover,harm,nodead][harm,nodead] "
    else aim = lvl == 0 and ("[@" .. u.mainTarget .. ",harm,nodead][harm,nodead] ") or ("[@" .. u.mainTarget .. ",harm,nodead] ") end
    local cond = smatch(aim, "^%s*(.-)%s*$")
    if cond == "" then cond = "[harm,nodead]" end
    local parts = { "#showtooltip " .. tipName }
    if def.aim == "melee" then parts[#parts + 1] = "\n/startattack " .. cond end
    if def.pet then parts[#parts + 1] = "\n/petattack " .. cond end
    for _, s in ipairs(list) do parts[#parts + 1] = "\n/cast " .. (self[s] and "[combat] " or aim) .. s.name end
    if def.autoshot then parts[#parts + 1] = "\n/cast " .. aim .. "!Auto Shot" end
    return tconcat(parts)
  end
  if #spells == 0 then
    local c0 = ctx.leader and "[harm,nodead]" or ("[@" .. u.mainTarget .. ",harm,nodead][harm,nodead]")
    if def.autoshot then
      return { id = def.id, label = def.label, base = "priority", kind = "engage", spells = {},
        macro = "#showtooltip Auto Shot\n/petattack " .. c0 .. "\n/cast " .. c0 .. " !Auto Shot", compact = false, tooLong = false }
    end
    if def.aim ~= "melee" then return nil end
    return { id = def.id, label = def.label, base = "priority", kind = "engage", spells = {},
      macro = "#showtooltip Attack\n/startattack " .. c0, compact = false, tooLong = false }
  end
  local list, level = slice(spells), 0
  local macro = make(0, list)
  if #macro > MACRO_LIMIT and not ctx.leader then level = 1; macro = make(1, list) end
  while #macro > MACRO_LIMIT and #list > 1 do list = slice(list, 1, #list - 1); macro = make(level, list) end
  local names = {}
  for i, s in ipairs(list) do names[i] = s.name end
  return { id = def.id, label = def.label, base = "priority", kind = #list == 1 and "single" or "priority", spells = names, macro = macro,
    compact = level > 0 or #list < #spells, tooLong = #macro > MACRO_LIMIT }
end

--- Build the sequence keys for one character. has(name) -> learned spell object or nil. opts: {targetReset}
function E.buildSequences(cls, role, tier, ctxIn, has, opts)
  if not contains(SEQ_TIERS, tier) or tier == "off" or not E.seqSupported(cls) then return {} end
  local ctx, o = ctxOf(ctxIn), opts or {}
  local out = {}
  for _, def in ipairs(seqDefs(cls, role)) do
    local r = (def.kind == "priority" and buildPriority or buildCastSequence)(def, def.tiers[tier], ctx, has, o)
    if r then out[#out + 1] = r end
  end
  return out
end

-- ------------------------------------------------------------------ custom keys (v8.4)
local CUSTOM_KINDS, CUSTOM_AIMS, CUSTOM_RESETS = { "sequence", "priority" }, { "harm", "help" }, { "combat", "target/combat", "combat/12" }
local PET_CLASSES, MELEE_CLASSES = { "warlock", "hunter" }, { "warrior", "rogue", "paladin" }
local CHANNELS = { "Mind Flay", "Drain Life", "Drain Soul", "Drain Mana", "Health Funnel", "Arcane Missiles", "Evocation", "Hurricane", "Tranquility", "Blizzard", "Rain of Fire", "Volley", "Hellfire", "Wrack" }
local STALLERS = { ["Conflagrate"] = "needs your Immolate on the target; without it the sequence waits here", ["Power Word: Shield"] = "Weakened Soul blocks it for 15 s on the same target, so the sequence waits here" }
local NO_TARGET = { "self", "aoe-melee", "ground", "petself" }
E.CUSTOM_KINDS, E.CUSTOM_AIMS, E.CUSTOM_RESETS, E.PET_CLASSES, E.MELEE_CLASSES = CUSTOM_KINDS, CUSTOM_AIMS, CUSTOM_RESETS, PET_CLASSES, MELEE_CLASSES

--- opts.melee: the character fights in melee (adds /startattack to enemy keys).
function E.buildCustom(cls, c, ctxIn, has, opts)
  local ctx, id = ctxOf(ctxIn), "c" .. tostring(c.id)
  local aim = contains(CUSTOM_AIMS, c.aim) and c.aim or "harm"
  local pet = contains(PET_CLASSES, cls) and aim == "harm"
  local meleeOpt = (opts and opts.melee) or contains(MELEE_CLASSES, cls)
  if c.kind == "priority" then
    local spells = {}
    for _, n in ipairs(c.steps or {}) do local s = has(n); if s and not contains(spells, s) then spells[#spells + 1] = s end end
    if #spells == 0 then return { id = id, label = c.name, custom = true, base = "priority", kind = "empty", spells = {}, macro = "", compact = false, tooLong = false } end
    local melee = meleeOpt and aim == "harm"
    local def = { aim = aim }
    local function make(lvl, list)
      local a = aimFor(def, ctx, lvl)
      local txt = "#showtooltip\n"
      if melee then txt = txt .. "/startattack " .. a .. "\n" end
      if pet then txt = txt .. "/petattack " .. a .. "\n" end
      local lines = {}
      for i, s in ipairs(list) do lines[i] = "/cast " .. (contains(NO_TARGET, s.action) and "[combat] " or (a .. " ")) .. s.name end
      return txt .. tconcat(lines, "\n")
    end
    local level, list = 0, slice(spells)
    local macro = make(0, list)
    for _, lv in ipairs({ 1, 2 }) do
      if #macro > MACRO_LIMIT and aimFor(def, ctx, lv) ~= aimFor(def, ctx, level) then level = lv; macro = make(lv, list) end
    end
    while #macro > MACRO_LIMIT and #list > 1 do list = slice(list, 1, #list - 1); macro = make(level, list) end
    local names = {}
    for i, s in ipairs(list) do names[i] = s.name end
    return { id = id, label = c.name, custom = true, base = "priority", kind = #list == 1 and "single" or "priority", spells = names, macro = macro,
      compact = level > 0 or #list < #spells, tooLong = #macro > MACRO_LIMIT }
  end
  local f = trunc(c.fills)
  if f == 0 then f = 1 end
  local fills = max(1, min(6, f))
  local def = { id = id, label = c.name, kind = "sequence", aim = aim, pet = pet, startattack = meleeOpt and aim == "harm",
    reset = contains(CUSTOM_RESETS, c.reset) and c.reset or "combat", fixedFill = fills, allowDup = true }
  local steps = {}
  for _, n in ipairs(c.steps or {}) do if has(n) then steps[#steps + 1] = n end end
  local function run()
    local st = {}
    for i, n in ipairs(steps) do st[i] = { s = n } end
    local filler = (c.filler and c.filler ~= "") and { c.filler } or {}
    return buildCastSequence(def, { steps = st, filler = filler }, ctx, has, {})
  end
  local r = run()
  while r and r.tooLong and #steps > 1 do
    steps = slice(steps, 1, #steps - 1)
    r = run()
    if r then r.compact = true end
  end
  if not r then return { id = id, label = c.name, custom = true, base = "sequence", kind = "empty", spells = {}, macro = "", compact = false, tooLong = false } end
  r.custom = true; r.why = ""
  return r
end

local FRIENDLY_ACTIONS = { "friendlymain", "friendlyself", "friendlytarget", "resurrection", "petheal" }
local HOSTILE_ACTIONS = { "hostile", "ranged", "melee", "melee-pet", "melee-cc", "opener", "petattack", "autoshot", "aoe-melee" }
--- Plain-language warnings for a custom key. spells: learned spell objects in key order (filler last for sequences).
function E.customWarnings(kind, spells, filler, aim, cls)
  local out, all = {}, slice(spells)
  if filler then all[#all + 1] = filler end
  for _, s in ipairs(spells) do
    if STALLERS[s.name] then out[#out + 1] = s.name .. " " .. STALLERS[s.name] .. "."
    elseif kind == "sequence" and cdSec(s) > 12 then out[#out + 1] = s.name .. " has a " .. numstr(cdSec(s)) .. " s cooldown: the sequence waits until it is ready. Better on its own key." end
    if contains(CHANNELS, s.name) then out[#out + 1] = s.name .. " is channelled: pressing the key again cuts it short." end
    if s.action == "ground" then out[#out + 1] = s.name .. " needs a click on the ground after the key press." end
  end
  local wrong, seen = {}, {}
  for _, s in ipairs(all) do
    if (aim == "harm" and contains(FRIENDLY_ACTIONS, s.action)) or (aim == "help" and contains(HOSTILE_ACTIONS, s.action)) then
      if not seen[s.name] then seen[s.name] = true; wrong[#wrong + 1] = s.name end
    end
  end
  if #wrong > 0 then
    out[#out + 1] = tconcat(wrong, ", ") .. (aim == "harm" and " is a friendly spell in an Enemy key" or " is an enemy spell in a Friendly key") ..
      ": it would be cast on the wrong target and fail" .. (kind == "sequence" and ", and the sequence waits there." or ".")
  end
  if aim == "harm" and contains(PET_CLASSES, cls) then
    local cc = {}
    for _, s in ipairs(all) do if s.category == "Control" then cc[#cc + 1] = s.name end end
    if #cc > 0 then out[#out + 1] = "This key also sends your pet, even for crowd control (" .. tconcat(cc, ", ") .. "). Keep crowd control on its own key." end
  end
  if kind == "sequence" and filler and cdSec(filler) > 0 then
    out[#out + 1] = "The filler " .. filler.name .. " has a cooldown, so the sequence will wait on it. Pick a spell without a cooldown as filler."
  end
  if kind == "priority" then
    local blockers = {}
    for i = 1, #spells - 1 do
      local s = spells[i]
      local exempt = false
      for _, w in ipairs({ "Hammer of Wrath", "Exorcism", "Execute", "Overpower", "Revenge" }) do if sfind(s.name, w, 1, true) then exempt = true break end end
      if cdSec(s) == 0 and not exempt then blockers[#blockers + 1] = s.name end
    end
    if #blockers > 0 then
      out[#out + 1] = tconcat(blockers, ", ") .. " ha" .. (#blockers > 1 and "ve" or "s") .. " no cooldown, so the lines below " .. (#blockers > 1 and "them" or "it") ..
        " never run. Put spells with cooldowns first and the spammable spell last."
    end
  end
  return out
end
