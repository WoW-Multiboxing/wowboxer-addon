--[[ WoWBoxer – Wowhead WoW Forever talent-calculator links (docs/talent-import.md), ported from
  docs/patches/wowhead_import.js.
  Link: https://www.wowhead.com/forever/talent-calc/<class>/<points>[/<order>]
    <points> = the hash version ("v2") + one digit per talent in Wowhead's order (row, then column), trees separated
               by "-", trailing zeros left out; then "_" options: t<0-5> Talented rank, l<level>, r<race>.
    <order>  = the click order: "0"/"1"/"2" switches tree, a lowercase token = +1 rank of that talent, an uppercase
               token = the rest of its ranks at once.
  Talents are matched to WoWBoxer's tree by NAME (Wowhead and WoWBoxer's data place a few talents differently).
  Hard rule 2: the link is data only – read with string functions; nothing in it is ever run. ]]
local _, ns = ...
local WH = {}
ns.Wowhead = WH

local E = ns.Engine
local sfind, ssub, smatch, slower = string.find, string.sub, string.match, string.lower
WH.MAX_LINK = 300

local function D() return ns.Data end
local function data() return D().wowhead end

--- name|tree -> WoWBoxer node, and Wowhead (tree, index) -> {w = Wowhead entry, n = WoWBoxer node or nil}
local function maps(cls)
  local byName = {}
  for _, n in ipairs(D().talents[cls].nodes) do byName[slower(n.n) .. "|" .. n.t] = n end
  local trees = data().trees[cls]
  local function node(tree, i) -- 0-based tree and index, like the JS
    local t = trees[tree + 1]
    local w = t and t[i + 1]
    if not w then return nil end
    return { w = w, n = byName[slower(w.n) .. "|" .. tree] }
  end
  return node
end

--- Read a link. Returns {cls, order, talented, level, hasOrder, kind, split, points, warnings} or {error = text}.
function WH.import(link)
  local s = type(link) == "string" and smatch(link, "^%s*(.-)%s*$") or ""
  if #s > WH.MAX_LINK then return { error = "That link is too long (over " .. WH.MAX_LINK .. " characters)" } end
  s = s:gsub("[%?#].*$", ""):gsub("/+$", "")
  local cls, rest = smatch(s, "talent%-calc/([a-z%-]+)/(.*)$")
  if not cls then return { error = "Not a Wowhead talent calculator link" } end
  local hash, ord = smatch(rest, "^([^/]*)/([^/]*)$")
  if not hash then
    if sfind(rest, "/", 1, true) then return { error = "Not a Wowhead talent calculator link" } end
    hash = rest
  end
  if not (D().talents[cls] and data().trees[cls]) then return { error = "Unknown class \"" .. cls .. "\"" } end
  if not sfind(s, "/forever/", 1, true) then return { error = "This is not a WoW Forever link (look for /forever/ in it)" } end
  local warn = {}
  local T = ns.Kit.tree(cls)
  local node = maps(cls)
  local treeName = function(t) return D().talents[cls].trees[t + 1].n end
  -- points + options
  local hv = data().hashVersion
  if hv and ssub(hash, 1, #hv) == hv then hash = ssub(hash, #hv + 1)
  elseif ssub(hash, 1, 1) == "v" then return { error = "This link uses a newer Wowhead format (" .. ssub(hash, 1, 3) .. "…) – WoWBoxer needs an update" } end
  local parts = {}
  for p in (hash .. "_"):gmatch("([^_]*)_") do parts[#parts + 1] = p end
  local pts = parts[1] or ""
  local talented, level = 0, nil
  for i = 2, #parts do
    local t = smatch(parts[i], "^t([0-5])$")
    local l = smatch(parts[i], "^l(%d%d?)$")
    if t then talented = tonumber(t) elseif l then level = tonumber(l) end
  end
  local counts, want = {}, {}
  local tree = 0
  for digits in (pts .. "-"):gmatch("([^%-]*)%-") do
    for i = 1, #digits do
      local r = tonumber(ssub(digits, i, i)) or 0
      if r > 0 then
        local x = node(tree, i - 1)
        if not x then warn[#warn + 1] = "Point " .. r .. " at position " .. i .. " in tree " .. (tree + 1) .. " is not a known talent"; break end
        if not x.n then warn[#warn + 1] = x.w.n .. " is not in WoWBoxer's " .. treeName(tree) .. " tree – left out"
        else
          local r2 = math.min(r, x.n.m)
          if r2 < r then warn[#warn + 1] = x.w.n .. ": " .. r .. " points on Wowhead, max " .. x.n.m .. " here" end
          counts[x.n.k] = (counts[x.n.k] or 0) + r2
          want[#want + 1] = { key = x.n.k, n = r2, t = tree, r = x.n.r, i = #want }
        end
      end
    end
    tree = tree + 1
  end
  -- click order, when the link has one
  local order, hasOrder = {}, false
  if ord and ord ~= "" then
    local one, max = data().tokens.one, data().tokens.max
    local seen = {}
    tree = 0
    for j = 1, #ord do
      local ch = ssub(ord, j, j)
      if ch == "0" or ch == "1" or ch == "2" then tree = tonumber(ch)
      else
        local i, all = sfind(one, ch, 1, true), false
        if not i then i = sfind(max, ch, 1, true); all = true end
        local x = i and node(tree, i - 1) or nil
        if not (x and x.n) then warn[#warn + 1] = "Order: unknown talent \"" .. ch .. "\" – order ignored"; order = {}; break end
        local have = seen[x.n.k] or 0
        local to = all and x.n.m or have + 1
        for _ = have + 1, math.min(to, x.n.m) do order[#order + 1] = x.n.k end
        seen[x.n.k] = math.min(to, x.n.m)
      end
    end
    hasOrder = #order > 0
    if hasOrder then -- the order must give the same points as the points part
      local c, same, nc, nk = E.countsOf(order), true, 0, 0
      for k, v in pairs(c) do nc = nc + 1; if counts[k] ~= v then same = false end end
      for _ in pairs(counts) do nk = nk + 1 end
      if not same or nc ~= nk then
        warn[#warn + 1] = "The click order and the points in the link do not match – used the points, order by WoWBoxer"
        hasOrder = false
      end
    end
  end
  if not hasOrder then -- no order: rows first, then tree, as the companion does for "final-derived" guides
    table.sort(want, function(a, b) if a.r ~= b.r then return a.r < b.r end if a.t ~= b.t then return a.t < b.t end return a.i < b.i end)
    order = {}
    for _, w in ipairs(want) do for _ = 1, w.n do order[#order + 1] = w.key end end
  end
  if #order > 51 then
    warn[#warn + 1] = "More than 51 points – cut to 51"
    local cut = {}
    for i = 1, 51 do cut[i] = order[i] end
    order = cut
  end
  if #order == 0 then return { error = "The link has no talent points" } end
  local bad = E.validateOrder(T, order)
  if bad then
    local fixed = E.repairOrder(T, order)
    if not fixed then return { error = "The build breaks the talent rules at point " .. (bad.index + 1) .. ": " .. bad.reason } end
    warn[#warn + 1] = (hasOrder and "The click order" or "The order") .. " broke a talent rule at point " .. (bad.index + 1) .. " (" .. bad.reason .. ") – reordered"
    order = fixed
  end
  local tp = E.treePoints(T, E.countsOf(order))
  return { cls = cls, order = order, talented = talented, level = level, hasOrder = hasOrder, kind = hasOrder and "exact-order" or "final-derived",
    split = tp[1] .. "/" .. tp[2] .. "/" .. tp[3], points = #order, warnings = warn }
end

--- Write a talent order as a Wowhead link (points + click order; compress = whole-talent tokens where possible).
--- nil when the order holds a talent Wowhead's tree does not have (e.g. Mage Arcane Focus).
function WH.encode(cls, order, talented, compress)
  local trees = data().trees[cls]
  if not (trees and D().talents[cls]) then return nil end
  local idx = {}
  for t, tree in ipairs(trees) do
    for i, w in ipairs(tree) do
      for _, n in ipairs(D().talents[cls].nodes) do
        if n.t == t - 1 and slower(n.n) == slower(w.n) then idx[n.k] = { t = t - 1, i = i, m = n.m } end
      end
    end
  end
  for _, k in ipairs(order) do if not idx[k] then return nil end end
  local c = E.countsOf(order)
  local digits = { {}, {}, {} }
  local len = { 0, 0, 0 }
  for k, v in pairs(c) do local x = idx[k]; digits[x.t + 1][x.i] = v; if x.i > len[x.t + 1] then len[x.t + 1] = x.i end end
  local pt = {}
  for t = 1, 3 do
    local s = ""
    for i = 1, len[t] do s = s .. tostring(digits[t][i] or 0) end
    pt[t] = s
  end
  local pts = table.concat(pt, "-"):gsub("%-+$", "")
  local one, max = data().tokens.one, data().tokens.max
  local ord, tree, seen = {}, -1, {}
  local j = 1
  while j <= #order do
    local k = order[j]
    local x = idx[k]
    if x.t ~= tree then ord[#ord + 1] = tostring(x.t); tree = x.t end
    local run = 1
    while order[j + run] == k do run = run + 1 end
    if compress and not seen[k] and run == x.m then
      ord[#ord + 1] = ssub(max, x.i, x.i); seen[k] = true; j = j + run
    else
      ord[#ord + 1] = ssub(one, x.i, x.i); seen[k] = true; j = j + 1
    end
  end
  return "https://www.wowhead.com/forever/talent-calc/" .. cls .. "/" .. data().hashVersion .. pts .. "_t" .. (talented or 0) .. "/" .. table.concat(ord)
end

return WH
