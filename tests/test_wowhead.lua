-- Wowhead talent links (docs/talent-import.md §6), ported from docs/patches/wowhead_import.test.js: every guide is
-- written as a Wowhead link (with and without whole-talent tokens) and must read back to the same order; the example
-- link; bad links; a class mismatch; a link without order; a rank clamp; more than 51 points; a newer format.
-- WoW Forever's live trees (11 Nov 2026): links use Wowhead's current hash version; older "v2" links (before the live
-- trees) are read with Wowhead's older layouts and matched by name, gone talents and points that no longer fit are
-- left out with a warning (docs/talent-import.md §7).
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
H.eq(skip, 0, "no guide is skipped: Wowhead's calculator and the live trees have the same talents")
local HV = D.wowhead.hashVersion
H.ok(HV ~= "v2" and D.wowhead.layouts and D.wowhead.layouts.v2 and #D.wowhead.layouts.v2 >= 1, "current hash version " .. tostring(HV) .. ", older v2 layouts kept")

-- the example (the owner's druid link, made before the live trees: Wowhead's v2 layout)
local EX = "https://www.wowhead.com/forever/talent-calc/druid/v2410222-4_t0/0abaaaDEF1aaaa"
local EX_NOW = "https://www.wowhead.com/forever/talent-calc/druid/" .. HV .. "410222-4_t0/0abaaaDEF1aaaa"
local ex = WH.import(EX)
H.ok(#ex.warnings == 1 and ex.warnings[1]:find("Older Wowhead link (v2", 1, true), "example: read as an older link: " .. table.concat(ex.warnings, "; "))
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
local now = WH.import(EX_NOW)
H.ok(not now.error and #now.warnings == 0 and table.concat(now.order, ",") == table.concat(ex.order, ","), "the same build as a current link: same order, no warnings")

-- older links: a talent that is gone is left out with a warning; points that no longer fit are dropped with a warning
-- (Mage Arcane v2 layout: Wand Specialization, Arcane Focus, Improved Channeling, ...; Arcane Focus is gone)
local old = WH.import("https://www.wowhead.com/forever/talent-calc/mage/v2255")
local said = table.concat(old.warnings or { old.error or "" }, "; ")
H.ok(not old.error and old.points == 7 and said:find("Arcane Focus is not in WoW Forever's live talents", 1, true), "older link: Arcane Focus left out, the rest kept: " .. said)
-- Wand 2, Arcane Focus 5, Arcane Subtlety 2 (row 2): without Arcane Focus, Arcane Subtlety no longer reaches its row
local tm = WH.import("https://www.wowhead.com/forever/talent-calc/mage/v225002")
local tw = table.concat(tm.warnings or { tm.error or "" }, "; ")
H.ok(not tm.error and tm.points == 2 and tw:find("2 points no longer fit the live trees – left out: Arcane Subtlety", 1, true), "older link: points that no longer fit are left out: " .. tw)

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
local mage = WH.import("https://www.wowhead.com/forever/talent-calc/mage/" .. HV .. "2")
H.ok(mage.cls == "mage" and not mage.error, "another class's link: the build is for that class (" .. tostring(mage.cls) .. ")")

-- no order: points only → rows first, "order by WoWBoxer"
local nord = WH.import("https://www.wowhead.com/forever/talent-calc/druid/v2410222-4_t0")
H.eq(nord.kind, "final-derived", "no order: final-derived")
H.ok(not nord.hasOrder and nord.split == "11/4/0" and nord.points == 15, "no order: same points")
H.eq(E.validateOrder(T, nord.order), nil, "no order: a legal order")

-- rank clamp: a digit above the talent's max rank (Mage Fire: Incineration has 5 ranks, Flame Throwing 2)
local fireIdx
for i, w in ipairs(D.wowhead.trees.mage[2]) do if w.n == "Incineration" then fireIdx = i end end
local fireNode
for _, n in ipairs(D.talents.mage.nodes) do if n.n == "Incineration" then fireNode = n end end
H.ok(fireIdx and fireNode and fireNode.m == 5, "data: Incineration " .. tostring(fireNode and fireNode.m) .. " ranks (the live client and Wowhead agree)")
local wand = D.wowhead.trees.mage[1][1]
local clamp = WH.import("https://www.wowhead.com/forever/talent-calc/mage/" .. HV .. "5")
local warned = false
for _, w in ipairs(clamp.warnings or {}) do if w:find(wand.n .. ": 5 points on Wowhead, max " .. wand.m .. " here", 1, true) then warned = true end end
H.ok(warned, "rank clamp warned: " .. table.concat(clamp.warnings or { clamp.error or "" }, "; "))

-- more than 51 points: every talent at max rank in all three trees
local all = {}
for t = 1, 3 do
  local s = ""
  for _, w in ipairs(D.wowhead.trees.druid[t]) do s = s .. tostring(w.m) end
  all[t] = s
end
local big = WH.import("https://www.wowhead.com/forever/talent-calc/druid/" .. HV .. table.concat(all, "-"))
local cut = false
for _, w in ipairs(big.warnings or {}) do if w:find("More than 51 points", 1, true) then cut = true end end
H.ok(big.error or (cut and big.points == 51), "over 51 points: cut to 51 (or refused): " .. tostring(big.error or big.points))

-- Talented rank from the link
H.eq(WH.import("https://www.wowhead.com/forever/talent-calc/druid/v2410222-4_t3/0abaaaDEF1aaaa").talented, 3, "the t option = Talented rank")
-- the encoder writes the example in the current format
H.eq(WH.encode("druid", ex.order, 0, true), EX_NOW, "encode: the example as a current link")

-- the Talents tab: Import → preview → Save as → My builds → Use → its next point; Rename, Delete; share string
do
  local UI, Core = ns.UI, ns.Core
  Core.cdb.guide = "done"
  UI.Open("talents")
  local p = UI.panels.talents
  local tab
  for _, t in ipairs(UI.tabs) do if t.key == "talents" then tab = t end end
  p.importBtn:Click()
  local f = p.imp
  H.ok(f:IsShown(), "Import opens the window")
  H.ok(not f.save:IsEnabled(), "nothing to save before a link")
  f.link:SetText(EX); f.link._scripts.OnTextChanged(f.link)
  H.eq(f.info:GetText(), "Druid · 11/4/0 · 15 points · exact click order (levels 10–24)", "live preview")
  H.eq(f.name:GetText(), "Wowhead 11/4/0", "default name")
  H.ok(f.save:IsEnabled() and f.use:IsEnabled(), "Save as + Save and use for the right class")
  f.save:Click()
  local list = Core.db.builds.druid
  H.ok(list and #list == 1 and list[1].label == "Wowhead 11/4/0" and list[1].link == EX, "saved in WoWBoxerDB.builds.druid")
  H.ok(f.status:GetText():find("Saved", 1, true), "says so: " .. tostring(f.status:GetText()))
  local vals = p.guide.opts.values()
  H.eq(vals[1][2], "My build: Wowhead 11/4/0 (yours)", "first in the Guide list, marked (yours)")
  H.ok(vals[1][3]:find("Imported from Wowhead", 1, true) and vals[1][3]:find(EX, 1, true), "its tooltip: imported from Wowhead + the link")
  H.eq(ns.Kit.guidesOf("druid")[1].id, list[1].id, "Kit.guidesOf returns your builds first")
  f.close:Click()
  p.guide.select(vals[1][1])
  local _, m = Core.me()
  H.eq(m.guide, list[1].id, "picked for this character")
  H.eq(table.concat(ns.Kit.plan(m), ","), table.concat(ex.order, ","), "the plan is the build")
  H.ok(p.nextName:GetText() ~= nil and p.kind:GetText():find("Your build", 1, true), "the Talents tab shows it: " .. tostring(p.kind:GetText()))
  H.ok(p.renBtn:IsShown() and p.delBtn:IsShown(), "Rename / Delete on your own build")
  -- Wowhead link of the build
  H.eq(tab.copyLink(), EX_NOW, "Copy Wowhead link gives the build as a current link")
  -- rename
  p.renBtn:Click(); p.renBox:SetText("Boomkin 15"); p.renBox._scripts.OnEnterPressed(p.renBox)
  H.eq(list[1].label, "Boomkin 15", "renamed")
  -- the share string carries the build (order + name), not the link
  local s = Core.me()
  local str = ns.Share.export(s, {})
  local res = ns.Share.import(str)
  local rm = res.squad.members[1]
  H.eq(table.concat(rm.build, ","), table.concat(ex.order, ","), "share string: the member's build travels")
  H.eq(rm.buildName, "Boomkin 15", "with its name")
  H.ok(not str:find("wowhead", 1, true), "no link text in the share string")
  -- a druid link while this character is a druid is usable; a mage link only saves
  tab.openImport(p)
  f.link:SetText("https://www.wowhead.com/forever/talent-calc/mage/" .. HV .. "2"); f.link._scripts.OnTextChanged(f.link)
  H.ok(f.save:IsEnabled() and not f.use:IsEnabled(), "another class: Save as only")
  f.save:Click()
  H.ok(f.status:GetText():find("Saved for Mage – pick it on a Mage", 1, true), "Saved for Mage – pick it on a Mage")
  f.close:Click()
  -- survives a reload (SavedVariables) and m.guide still points at it
  local db2 = ns.State.initDB(Core.db, Core.cdb)
  H.eq(#db2.builds.druid, 1, "builds survive the SavedVariables clean-up")
  H.ok(ns.State.newSquad(Core.me()).members[1].guide == list[1].id, "a member keeps its build id")
  -- delete (asks first): back to the recommended guide
  p.delBtn:Click()
  local menu = W.env.WoWBoxerMenu
  local yes
  for _, b in ipairs(menu.rows) do if b:IsShown() and b.label:GetText() == "Yes, delete this build" then yes = b end end
  yes:Click()
  H.eq(Core.db.builds.druid, nil, "deleted")
  local _, m2 = Core.me()
  H.eq(m2.guide, ns.Kit.defaultGuideFor("druid", m2.role), "back to the recommended guide")
  H.eq(W.calls.LearnTalent, nil, "never touches the game's talents")
  H.eq(W.calls.CreateMacro, nil, "nothing written to the game")
end

os.exit(H.report("wowhead") and 0 or 1)
