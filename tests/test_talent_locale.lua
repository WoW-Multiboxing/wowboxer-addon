-- Localized C_Traits names must still match the data's talent plan by stable node ID.
local dir = (arg[0]:match("^(.*)/[^/]+$") or ".")
local H = dofile(dir .. "/harness.lua")
local Mock = dofile(dir .. "/wowmock.lua")

for _, cls in ipairs({ "paladin", "priest" }) do
  local W = Mock.new(H, { name = "Deutsch", class = cls:upper(), race = "Human", level = 20 })
  W.env.GetLocale = function() return "deDE" end
  local ns = H.loadAddon({ env = W.env })
  W.fire("ADDON_LOADED", "WoWBoxer"); W.fire("PLAYER_LOGIN")
  ns.State.quickStart(ns.Core.db, ns.Core.cdb, ns.Core.playerInfo())
  local m = ns.Core.compute().member
  local node = ns.Data.talents[cls].nodes[1]
  H.ok(type(node.node) == "number", cls .. ": generated data retains the client talent node ID")
  local localName = cls == "paladin" and "Spiritueller Fokus" or "Kraft im Licht"
  local unknownID = 9999999
  W.env.C_ClassTalents = { GetActiveConfigID = function() return 77 end }
  W.env.C_Traits = {
    GetConfigInfo = function() return { treeIDs = { 5 } } end,
    GetTreeNodes = function() return { node.node, unknownID } end,
    GetNodeInfo = function(_, id) return { ranksPurchased = id == node.node and 2 or 1, entryIDs = { id } } end,
    GetEntryInfo = function(_, id) return { definitionID = id } end,
    GetDefinitionInfo = function(id) return { overrideName = id == node.node and localName or "Unbekanntes Talent" } end,
  }
  local ranks, source = ns.Compat.talentRanks()
  H.eq(source, "C_Traits", cls .. ": modern talent API used")
  H.eq(ranks[node.n], 2, cls .. ": localized talent maps to canonical data name")
  H.eq(ranks[localName], nil, cls .. ": localized talent is not counted twice")
  H.eq(ranks["Unbekanntes Talent"], 1, cls .. ": unknown node keeps its client name")
  local status = ns.Kit.talentStatus(m, ranks, 20)
  H.eq(status.spent, 2, cls .. ": spent points match the plan data on a German client")
  H.eq(#status.unknown, 1, cls .. ": only the actual unknown node is reported")
  H.eq(status.unknown[1], "Unbekanntes Talent", cls .. ": unknown talent remains visible")

  -- Node identity remains usable when the name has not loaded yet.
  W.env.C_Traits.GetDefinitionInfo = function() return {} end
  ranks = ns.Compat.talentRanks()
  H.eq(ranks[node.n], 2, cls .. ": uncached name does not lose a known node's points")
end

-- Every generated class uses node IDs from its own tree, without collisions.
do
  local ns = H.loadAddon({ env = Mock.new(H, {}).env })
  local seen, count = {}, 0
  for _, cls in ipairs(ns.Data.classOrder) do
    for _, n in ipairs(ns.Data.talents[cls].nodes) do
      H.ok(type(n.node) == "number" and not seen[n.node], cls .. ": unique numeric node ID for " .. n.n)
      if n.node then seen[n.node] = true end
      count = count + 1
    end
  end
  H.eq(count, 467, "all Forever talent nodes carry stable identities")
  local warhorse
  for _, s in ipairs(ns.Data.spells.paladin) do if s.name == "Summon Warhorse" then warhorse = s end end
  H.eq(warhorse and warhorse.ranks[1].id, 13819, "Summon Warhorse includes its established spell ID")
  H.eq(warhorse and warhorse.level, 40, "the mount keeps Forever's own unlock level")
end

os.exit(H.report("talent_locale") and 0 or 1)
