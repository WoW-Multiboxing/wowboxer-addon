--[[ WoWBoxer – which game is running (loaded first, before any data).
  One package for several games (docs/multi-flavor-plan.md): the engine is shared, the data is per game. Every data
  file (Data/<Game>/*.lua, Games/<Game>.lua) loads on every client and returns at once unless ns.dataGame is its game,
  so only the running game's data fills ns.Data. The interface number decides (a capability probe, never a project ID).
  [AFKLAR: TOC AllowLoadGameType names on the Forever launch client – until verified the runtime check above is the
  only switch, so an unknown game type can never leave the addon without data.] ]]
local _, ns = ...

--- "forever" | "era" | "tbc" | "other" for an interface number.
function ns.gameOf(toc)
  toc = tonumber(toc) or 0
  if toc >= 16000 and toc < 20000 then return "forever" end
  if toc >= 11000 and toc < 12000 then return "era" end
  if toc >= 20000 and toc < 30000 then return "tbc" end
  return "other"
end

local _, _, _, toc = GetBuildInfo()
ns.game = ns.gameOf(toc)
--- Whose data loads: Classic Era its own; every other client the Forever data (today's behaviour).
ns.dataGame = ns.game == "era" and "era" or "forever"
ns.Data = ns.Data or {}
