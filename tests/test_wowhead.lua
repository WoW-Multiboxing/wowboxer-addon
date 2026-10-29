-- Wowhead talent links (docs/talent-import.md §6), ported from docs/patches/wowhead_import.test.js: every guide is
-- written as a Wowhead link (with and without whole-talent tokens) and must read back to the same order; the example
-- link; bad links; a class mismatch; a link without order; a rank clamp; more than 51 points; a newer format.
local dir = (arg[0]:match("^(.*)/[^/]+$") or ".")
local H = dofile(dir .. "/harness.lua")
local Mock = dofile(dir .. "/wowmock.lua")

local W = Mock.new(H, { name = "Dorin", class = "DRUID", race = "Tauren", level = 24 })
local ns = H.loadAddon({ env = W.env })
W.fire("ADDON_LOADED", "WoWBoxer"); W.fire("PLAYER_LOGIN")
local WH, D, E, K = ns.Wowhead, ns.Data, ns.Engine, ns.Kit

-- round trip over every guide
local pass, fail, skip = 0, 0, 0
for _, cls in ipairs(D.classOrder) do
  for _, g in ipairs(D.guides[cls]) do
    if g.order and #g.order > 0 then
      for _, compress in ipairs({ false, true }) do
        local link = WH.encode(cls, g.order, 0, compress)
        if not link then skip = skip + 1
        else
          local r = WH.import(link)
          if not r.error and r.hasOrder and table.concat(r.order, ",") == table.concat(g.order, ",") and #r.warnings == 0 then pass = pass + 1
          else fail = fail + 1; print("  FAIL " .. g.id .. " " .. tostring(compress) .. " " .. tostring(r.error or table.concat(r.warnings or {}, "; "))) end
        end
      end
    end
  end
end
H.eq(fail, 0, "round trip: every guide reads back to the same order (" .. pass .. " links, " .. skip .. " skipped: talent only in WoWBoxer's data)")
H.ok(pass >= 100, "round trip covers the guides (" .. pass .. ")")
H.ok(skip > 0 and skip <= 12, "only the Mage guides with Arcane Focus are skipped (" .. skip .. ")")

-- the example (the owner's druid link)
local EX = "https://www.wowhead.com/forever/talent-calc/druid/v2410222-4_t0/0abaaaDEF1aaaa"
local ex = WH.import(EX)
H.eq(ex.cls, "druid", "example: druid")
H.eq(ex.split, "11/4/0", "example: 11/4/0")
H.eq(ex.points, 15, "example: 15 points")
H.ok(ex.hasOrder and ex.kind == "exact-order", "example: exact click order")
local T = K.tree("druid")
local names = {}
for i = 1, 5 do names[i] = T.byKey[ex.order[i]].n end
H.eq(table.concat(names, ","), "Improved Wrath,Genesis,Improved Wrath,Improved Wrath,Improved Wrath", "example: levels 10–14")
H.eq(T.byKey[ex.order[15]].n, "Ferocity", "example: level 24 Ferocity")
H.eq(E.levelForPoint(14, ex.talented), 24, "example: the 15th point at level 24")

-- bad links
for _, b in ipairs({
  { "https://www.wowhead.com/classic/talent-calc/druid/0abaa", "not a WoW Forever link" },
  { "https://example.com/x", "Not a Wowhead" },
  { "https://www.wowhead.com/forever/talent-calc/deathknight/v2", "Unknown class" },
  { "https://www.wowhead.com/forever/talent-calc/druid/v3123", "newer Wowhead format" },
  { "https://www.wowhead.com/forever/talent-calc/druid/v2", "no talent points" },
  { "https://www.wowhead.com/forever/talent-calc/druid/v2" .. string.rep("1", 300), "too long" },
  { nil, "Not a Wowhead" },
}) do
  local r = WH.import(b[1])
  H.ok(r.error and r.error:find(b[2], 1, true), "bad link → " .. b[2] .. ": " .. tostring(r.error))
end

-- a class mismatch: a druid link read on a mage is still a druid build
ns.Core.ensureMe()
local _, m = ns.Core.me()
H.eq(m.cls, "druid", "this character is a druid")
local mage = WH.import("https://www.wowhead.com/forever/talent-calc/mage/v2" .. "5")
H.ok(mage.cls == "mage" and not mage.error, "another class's link: the build is for that class (" .. tostring(mage.cls) .. ")")

-- no order: points only → rows first, "order by WoWBoxer"
local nord = WH.import("https://www.wowhead.com/forever/talent-calc/druid/v2410222-4_t0")
H.eq(nord.kind, "final-derived", "no order: final-derived")
H.ok(not nord.hasOrder and nord.split == "11/4/0" and nord.points == 15, "no order: same points")
H.eq(E.validateOrder(T, nord.order), nil, "no order: a legal order")

-- rank clamp: Incineration has 5 ranks on Wowhead and 3 here (Mage Fire, docs §5)
local fireIdx
for i, w in ipairs(D.wowhead.trees.mage[2]) do if w.n == "Incineration" then fireIdx = i end end
local fireNode
for _, n in ipairs(D.talents.mage.nodes) do if n.n == "Incineration" then fireNode = n end end
H.ok(fireIdx and fireNode and fireNode.m < 5, "data: Incineration " .. tostring(fireNode and fireNode.m) .. " ranks here")
local digits = string.rep("0", fireIdx - 1) .. "5"
local clamp = WH.import("https://www.wowhead.com/forever/talent-calc/mage/v2-" .. digits)
local warned = false
for _, w in ipairs(clamp.warnings or {}) do if w:find("Incineration: 5 points on Wowhead, max " .. fireNode.m .. " here", 1, true) then warned = true end end
H.ok(warned, "rank clamp warned: " .. table.concat(clamp.warnings or { clamp.error or "" }, "; "))

-- more than 51 points: every talent at max rank in all three trees
local all = {}
for t = 1, 3 do
  local s = ""
  for _, w in ipairs(D.wowhead.trees.druid[t]) do s = s .. tostring(w.m) end
  all[t] = s
end
local big = WH.import("https://www.wowhead.com/forever/talent-calc/druid/v2" .. table.concat(all, "-"))
local cut = false
for _, w in ipairs(big.warnings or {}) do if w:find("More than 51 points", 1, true) then cut = true end end
H.ok(big.error or (cut and big.points == 51), "over 51 points: cut to 51 (or refused): " .. tostring(big.error or big.points))

-- Talented rank from the link
H.eq(WH.import("https://www.wowhead.com/forever/talent-calc/druid/v2410222-4_t3/0abaaaDEF1aaaa").talented, 3, "the t option = Talented rank")
-- the encoder writes the example back
H.eq(WH.encode("druid", ex.order, 0, true), "https://www.wowhead.com/forever/talent-calc/druid/v2410222-4_t0/0abaaaDEF1aaaa", "encode: the example link again")

os.exit(H.report("wowhead") and 0 or 1)
