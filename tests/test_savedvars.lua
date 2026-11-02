-- Saved data is untouched (docs/multi-flavor-plan.md §0, rule 3): SavedVariables written by v0.14.0 (squads, own macros,
-- talent plans, presets, builds, Advanced targeting, ticked squad macros, extras, settings, automation, bar and keybind
-- memory, CVar backup) load in today's code, and after a login + logout the data is exactly what v0.14.0 itself
-- wrote after the same login (tests/fixtures/savedvars-0.14.0/<game>-after.lua, logs and diagnose left out).
local dir = (arg[0]:match("^(.*)/[^/]+$") or ".")
local H = dofile(dir .. "/harness.lua")
local Mock = dofile(dir .. "/wowmock.lua")
local SV = dofile(dir .. "/savedvars.lua")

local VERSION = "0.14.0"
-- what the player made: never changed by a login
local DB_KEYS = { "squads", "active", "builds", "settings", "v" }
local CDB_KEYS = { "squadId", "memberId", "overrides", "squadKeys", "extras", "skip", "bindPrev", "cvarBackup", "placedOnce", "secondaryBar", "primaryBar" }
local function pick(t, keys) local o = {}; for _, k in ipairs(keys) do o[k] = t and t[k] end return o end

for _, game in ipairs({ "forever", "era" }) do
  local folder = SV.folder(H, VERSION)
  local beforeText = H.readFile(folder .. "/" .. game .. "-before.lua")
  local afterText = H.readFile(folder .. "/" .. game .. "-after.lua")
  if H.ok(beforeText and afterText, game .. ": fixtures in " .. folder) then
    local db, cdb = SV.parse(beforeText)
    H.ok(type(db) == "table" and type(cdb) == "table" and #db.squads == 1, game .. ": the v" .. VERSION .. " file has a squad")
    local db2, cdb2 = SV.relog(H, Mock, game, db, cdb)
    local got = SV.serialize(db2, cdb2, SV.VOLATILE_DB)
    if not H.ok(got == afterText, game .. ": saved data after a login equals what v" .. VERSION .. " wrote") then
      local i = 1
      while got:sub(i, i) == afterText:sub(i, i) do i = i + 1 end
      print("  first difference: " .. (got:sub(math.max(1, i - 80), i + 80):gsub("\n", " | ")))
    end
    -- the player's own data is the same before and after
    local b1, c1 = SV.parse(beforeText)
    local b2, c2 = SV.parse(got)
    H.eq(SV.serialize(pick(b2, DB_KEYS), pick(c2, CDB_KEYS)), SV.serialize(pick(b1, DB_KEYS), pick(c1, CDB_KEYS)),
      game .. ": squads, builds, settings, overrides, keybind and bar memory untouched")
  end
end
os.exit(H.report("savedvars") and 0 or 1)
