--[[ WoWBoxer – Wowhead WoW Forever talent-calculator links (docs/talent-import.md), ported from
  docs/patches/wowhead_import.js.
  Link: https://www.wowhead.com/forever/talent-calc/<class>/<points>[/<order>]
    <points> = the hash version (WoW Forever since its live trees: "vkndmh"; Era/TBC "v2") + one digit per talent in
               Wowhead's order (row, then column), trees separated by "-", trailing zeros left out; then "_" options:
               t<0-5> Talented rank, l<level>, r<race>.
    Older links (WoW Forever "v2", before the live trees): read with Wowhead's own older layouts (Data.wowhead.layouts,
    the first that reads legally wins, as Wowhead does), then matched by name; talents that are gone are left out with
    a warning, and points that no longer fit a row or prerequisite are dropped with a warning.
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
--- The game's part of a Wowhead link ("forever", "tbc") and its name for messages.
function WH.path() return (D().game and D().game.wowhead) or "forever" end
function WH.gameName() local g = D().game; return (g and (g.wowheadName or g.name)) or "WoW Forever" end

--- name -> WoWBoxer node, and Wowhead (tree, index) -> {w = Wowhead entry, n = WoWBoxer node or nil}.
--- trees = Wowhead's trees of the link's layout (default: the current one). Names are unique within a class.
local function maps(cls, trees)
  local byName = {}
  for _, n in ipairs(D().talents[cls].nodes) do byName[slower(n.n)] = n end
  trees = trees or data().trees[cls]
  local function node(tree, i) -- 0-based tree and index, like the JS
    local t = trees[tree + 1]
    local w = t and t[i + 1]
    if not w then return nil end
    return { w = w, n = byName[slower(w.n)] }
  end
  return node
end

--- An older layout's trees for this link's points, as Wowhead picks it: the first layout the digits fit that is
--- also legal (rows + prerequisites), else the first they fit. nil when none fits.
local function pickLayout(list, cls, pts)
  local parts = {}
  for digits in (pts .. "-"):gmatch("([^%-]*)%-") do parts[#parts + 1] = digits end
  local first
  for _, L in ipairs(list or {}) do
    local trees = L[cls]
    if trees then
      local fits, legal = #parts <= 3, true
      for t = 1, math.min(#parts, 3) do
        local tree, d = trees[t] or {}, parts[t]
        if #d > #tree or d:find("[^0-9]") then fits = false; break end
        local byRow = {}
        for i = 1, #d do
          local v = tonumber(ssub(d, i, i))
          if v > tree[i].m then fits = false; break end
          byRow[tree[i].r] = (byRow[tree[i].r] or 0) + v
        end
        if not fits then break end
        for i = 1, #d do
          local v, w = tonumber(ssub(d, i, i)), tree[i]
          if v > 0 then
            local below = 0
            for r, n in pairs(byRow) do if r < w.r then below = below + n end end
            if below < (w.p or 0) then legal = false end
            for _, q in ipairs(w.q or {}) do if (tonumber(ssub(d, q[1] + 1, q[1] + 1)) or 0) < q[2] then legal = false end end
          end
        end
      end
      if fits then
        first = first or trees
        if legal then return trees end
      end
    end
  end
  return first
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
  local path = WH.path()
  if not sfind(s, "/" .. path .. "/", 1, true) then return { error = "This is not a " .. WH.gameName() .. " link (look for /" .. path .. "/ in it)" } end
  local warn = {}
  local T = ns.Kit.tree(cls)
  local treeName = function(t) return D().talents[cls].trees[t + 1].n end
  -- points + options; the hash version picks the layout (the current trees, or one of Wowhead's older layouts)
  local hv = data().hashVersion
  local layoutTrees, old
  local function startsWith(v) return v and ssub(hash, 1, #v) == v and (#hash == #v or sfind(ssub(hash, #v + 1, #v + 1), "^[0-9_%-]") ~= nil) end
  if startsWith(hv) then hash = ssub(hash, #hv + 1)
  else
    for v in pairs(data().layouts or {}) do if startsWith(v) and (not old or #v > #old) then old = v end end
    if old then
      hash = ssub(hash, #old + 1)
      layoutTrees = pickLayout(data().layouts[old], cls, smatch(hash, "^([^_]*)") or "")
      if not layoutTrees then return { error = "This older Wowhead link (" .. old .. ") does not fit any of Wowhead's older " .. D().classes[cls].n .. " trees" } end
      warn[#warn + 1] = "Older Wowhead link (" .. old .. ", before " .. WH.gameName() .. "'s live talents): read with Wowhead's older trees and matched by name"
    elseif ssub(hash, 1, 1) == "v" then return { error = "This link uses a newer Wowhead format (" .. ssub(hash, 1, 3) .. "…) – WoWBoxer needs an update" } end
  end
  local node = maps(cls, layoutTrees)
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
        if not x.n then warn[#warn + 1] = x.w.n .. " is not in " .. (old and (WH.gameName() .. "'s live talents") or ("WoWBoxer's " .. treeName(tree) .. " tree")) .. " – left out"
        else
          local r2 = math.min(r, x.n.m)
          if r2 < r then warn[#warn + 1] = x.w.n .. ": " .. r .. " points on Wowhead, max " .. x.n.m .. " here" end
          counts[x.n.k] = (counts[x.n.k] or 0) + r2
          want[#want + 1] = { key = x.n.k, n = r2, t = x.n.t, r = x.n.r, i = #want }
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
        if old and x and not x.n then
          -- a talent that is gone, in an older link: its clicks are skipped (the warning above names it)
        elseif not (x and x.n) then warn[#warn + 1] = "Order: unknown talent \"" .. ch .. "\" – order ignored"; order = {}; break
        else
          local have = seen[x.n.k] or 0
          local to = all and x.n.m or have + 1
          for _ = have + 1, math.min(to, x.n.m) do order[#order + 1] = x.n.k end
          seen[x.n.k] = math.min(to, x.n.m)
        end
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
  local maxP = E.maxPoints()
  if #order > maxP then
    warn[#warn + 1] = "More than " .. maxP .. " points – cut to " .. maxP
    local cut = {}
    for i = 1, maxP do cut[i] = order[i] end
    order = cut
  end
  if #order == 0 then return { error = "The link has no talent points" } end
  local bad = E.validateOrder(T, order)
  if bad then
    local fixed = E.repairOrder(T, order)
    if not fixed and old then -- an older link: keep every point that still fits, in order, as Wowhead does
      local rest, c, out = {}, {}, {}
      for i, k in ipairs(order) do rest[i] = k end
      local moved = true
      while moved do
        moved = false
        for i, k in ipairs(rest) do
          if not E.addBlocker(T, c, k) then out[#out + 1] = k; c[k] = (c[k] or 0) + 1; table.remove(rest, i); moved = true; break end
        end
      end
      local gone, seenK = {}, {}
      for _, k in ipairs(rest) do if not seenK[k] then seenK[k] = true; gone[#gone + 1] = T.byKey[k].n end end
      warn[#warn + 1] = #rest .. " point" .. (#rest == 1 and "" or "s") .. " no longer fit the live trees – left out: " .. table.concat(gone, ", ")
      if #out == 0 then return { error = "Nothing in this older link fits the live talents" } end
      fixed = out
    end
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
  return "https://www.wowhead.com/" .. WH.path() .. "/talent-calc/" .. cls .. "/" .. data().hashVersion .. pts .. "_t" .. (talented or 0) .. "/" .. table.concat(ord)
end

return WH
