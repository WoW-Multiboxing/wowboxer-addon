--[[ SavedVariables from a released version (docs/multi-flavor-plan.md §0, rule 3: saved data is untouched).
  session(H, Mock, game) plays a typical session in the mock client: a squad of three with own macros, a talent plan,
  presets, a saved Wowhead build, Advanced targeting, ticked squad macros, extra spells, settings and automation, a
  sync (macros + action bars), a keybind and the recommended CVars – then logs out and returns WoWBoxerDB and
  WoWBoxerCharDB as the client writes them.
  relog(H, Mock, game, before) logs in again with that saved data (login, the delayed checks, logout) and returns it.
  Fixtures in tests/fixtures/savedvars-<version>/<game>-{before,after}.lua were written by the version named in the
  folder (`lua tests/savedvars.lua --write <version>` on that version's code); tests/test_savedvars.lua loads them in
  today's code and must reproduce <game>-after.lua. ]]
local SV = {}
local dir = (arg and arg[0] and arg[0]:match("^(.*)/[^/]+$")) or "tests"

SV.GAMES = { forever = 16001, era = 11509 }
--- Keys that change on every login (logs, diagnose, the bridge for the companion): not compared.
SV.VOLATILE_DB = { log = true, diag = true, bridge = true }
-- per character: the signature of the last level-up offer shown. It is made from the desired macros, so a deliberate
-- macro change (1.1.1: the Wand squad macro) changes it and the player is offered the new macro, by design.
SV.VOLATILE_CDB = { offerShown = true }

-- ------------------------------------------------------------------ serialise like the client (sorted, stable)
local function key(k)
  if type(k) == "number" then return "[" .. string.format("%d", k) .. "]" end
  return "[" .. string.format("%q", k) .. "]"
end
local function val(v, ind, out, skip)
  local t = type(v)
  if t == "string" then out[#out + 1] = string.format("%q", v):gsub("\\\n", "\\n")
  elseif t == "number" then out[#out + 1] = (v == math.floor(v) and math.abs(v) < 1e15) and string.format("%d", v) or string.format("%.10g", v)
  elseif t == "boolean" then out[#out + 1] = tostring(v)
  elseif t == "table" then
    local keys = {}
    for k in pairs(v) do if not (skip and skip[k]) then keys[#keys + 1] = k end end
    table.sort(keys, function(a, b)
      if type(a) ~= type(b) then return type(a) == "number" end
      return a < b
    end)
    out[#out + 1] = "{\n"
    for _, k in ipairs(keys) do
      local x = v[k]
      if type(x) ~= "function" and type(x) ~= "userdata" then
        out[#out + 1] = ind .. "\t" .. key(k) .. " = "
        val(x, ind .. "\t", out)
        out[#out + 1] = ",\n"
      end
    end
    out[#out + 1] = ind .. "}"
  else out[#out + 1] = "nil" end
end
--- "WoWBoxerDB = {...}\nWoWBoxerCharDB = {...}\n"; skipDb = keys of WoWBoxerDB to leave out.
function SV.serialize(db, cdb, skipDb, skipCdb)
  local out = { "WoWBoxerDB = " }
  val(db or {}, "", out, skipDb)
  out[#out + 1] = "\nWoWBoxerCharDB = "
  val(cdb or {}, "", out, skipCdb)
  out[#out + 1] = "\n"
  return table.concat(out)
end
--- Read a SavedVariables text as data (test side only; the addon never runs code from outside).
function SV.parse(text)
  local env = {}
  local f
  if setfenv then f = assert(loadstring(text)); setfenv(f, env) else f = assert(load(text, "savedvars", "t", env)) end
  f()
  return env.WoWBoxerDB, env.WoWBoxerCharDB
end

-- ------------------------------------------------------------------ the session
local function client(H, Mock, game)
  math.randomseed(7)
  return Mock.new(H, { toc = SV.GAMES[game], name = "Anna", class = "PRIEST", race = "Scourge", level = 20, faction = "Horde",
    party = { party1 = "Dorin", party2 = "Bo" },
    partyInfo = { party1 = { class = "PALADIN", race = "Scourge", level = 20, leader = true }, party2 = { class = "HUNTER", race = "Orc", level = 20 } } })
end
local function boot(H, W)
  local ns = H.loadAddon({ env = W.env })
  W.fire("ADDON_LOADED", "WoWBoxer"); W.fire("PLAYER_LOGIN")
  for _, s in ipairs(ns.Data.spells.priest) do if s.level <= 20 and s.gate ~= "talent" then W.known[s.name] = true end end
  return ns
end
local function finish(W)
  for _ = 1, 4 do W.flush() end
  W.fire("PLAYER_LOGOUT")
  return W.env.WoWBoxerDB, W.env.WoWBoxerCharDB
end

function SV.session(H, Mock, game)
  local W = client(H, Mock, game)
  local ns = boot(H, W)
  local Core, S = ns.Core, ns.State
  local guide = ns.Kit.defaultGuideFor("priest", "healer")
  local order = ns.Kit.guide("priest", guide).order
  local sq = S.newSquad({ id = "sTrio", name = "Trio", faction = "horde", linkLevels = true, notes = "Questing in the Barrens", members = {
    { id = "mDorin", name = "Dorin", cls = "paladin", race = "undead", role = "tank", leader = true, level = 20, seq = "medium", tags = { "tank" } },
    { id = "mAnna", name = "Anna", cls = "priest", race = "undead", role = "healer", unit = "party1", level = 20, seq = "advanced", seqTarget = true,
      guide = guide, build = { order[1], order[2], order[3], order[4], order[5] }, talented = 2, pins = { "priest-renew" }, buildName = "Holy start",
      customSeq = {
        { id = "qHeal", name = "Quick heal", kind = "priority", aim = "help", steps = { "Renew", "Lesser Heal" } },
        { id = "qDots", name = "Dots", kind = "sequence", aim = "harm", steps = { "Shadow Word: Pain", "Mind Blast" }, filler = "Smite", fills = 2, reset = "target/combat" } } },
    { id = "mBo", name = "Bo", cls = "hunter", race = "orc", role = "ranged", unit = "focus", level = 20, realm = "Testland", lineUnit = "party2" } } })
  sq.presets = S.cleanPresets(sq, { { id = "pBo", name = "Bo leads", leader = "mBo", roles = { mAnna = "ranged" } } })
  Core.db.squads = { sq }; Core.db.active = sq.id
  Core.cdb.squadId, Core.cdb.memberId = sq.id, "mAnna"
  Core.cdb.guide = "done"
  Core.db.builds = S.cleanBuilds({ priest = { { id = "uHoly", label = "My holy", kind = "exact-order", order = { order[1], order[2] }, talented = 1,
    link = "https://www.wowhead.com/forever/talent-calc/priest/abc", saved = "2026-11-01" } } })
  Core.db.settings.advanced = true
  Core.db.settings.scale = 0.9
  Core.db.settings.seqStrip = true
  Core.db.settings.minimapAngle = 200
  Core.db.settings.addons = { "Questie" }
  Core.db.settings.auto = { invite = false, restock = true }
  Core.cdb.overrides = ns.Override.cleanAll({
    ["WBX K2"] = { targets = { { who = "member", name = "Dorin" }, { who = "unit", unit = "party2", help = true } }, mod = "shift" },
    ["WBX K3"] = { text = "#showtooltip Flash Heal\n/cast [@party1,help,nodead][@player] Flash Heal" } })
  Core.cdb.squadKeys = { Target = true, FollowLead = false }
  Core.cdb.extras = { "priest-power-word-fortitude", "priest-psychic-scream" }
  Core.cdb.skip = { ["WBX Pet"] = true }
  Core.sync()
  for _ = 1, 3 do W.flush() end
  Core.bindKey("WBX K2", "H")
  Core.applyCVars()
  return finish(W)
end

function SV.relog(H, Mock, game, db, cdb)
  local W = client(H, Mock, game)
  W.env.WoWBoxerDB, W.env.WoWBoxerCharDB = db, cdb
  boot(H, W)
  return finish(W)
end

function SV.folder(H, version) return H.root .. "/tests/fixtures/savedvars-" .. version end

-- ------------------------------------------------------------------ CLI: --write <version>
if arg and arg[0] and (arg[0]:match("[/\\]savedvars%.lua$") or arg[0] == "savedvars.lua") and arg[1] == "--write" then
  local H = dofile(dir .. "/harness.lua")
  local Mock = dofile(dir .. "/wowmock.lua")
  local version = assert(arg[2], "usage: lua tests/savedvars.lua --write <version>")
  for game in pairs(SV.GAMES) do
    local db, cdb = SV.session(H, Mock, game)
    local before = SV.serialize(db, cdb)
    local db2, cdb2 = SV.parse(before)
    local db3, cdb3 = SV.relog(H, Mock, game, db2, cdb2)
    local after = SV.serialize(db3, cdb3, SV.VOLATILE_DB)
    for name, txt in pairs({ before = before, after = after }) do
      local p = SV.folder(H, version) .. "/" .. game .. "-" .. name .. ".lua"
      local fh = assert(io.open(p, "wb")); fh:write(txt); fh:close()
      print("wrote " .. p .. " (" .. #txt .. " bytes)")
    end
  end
end

return SV
