--[[ WoWBoxer – TBC Anniversary (interface 20506): the hand-written macro data of this game (the addon is the source of
  truth, docs/multi-flavor-plan.md §0). Loads on every client but only fills ns.Data on TBC Anniversary.
  "Basic TBC" (plan step 2): the macros come from the live spellbook (liveSpells), the talent trees from the client's
  own tables (Data/TBC/, tools/fetch_tbc.py). Built-in sequence keys and default talent guides come in step 4, so the
  sequence table is empty and the pages say "coming". Protected by tests/golden/tbc.json. ]]
local _, ns = ...
if ns.dataGame ~= "tbc" then return end
local D = ns.Data

D.game = { key = "tbc", name = "TBC Anniversary", maxLevel = 70, maxPoints = 61, wowhead = "tbc", liveSpells = true }

D.sequences = {}
