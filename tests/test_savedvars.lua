-- Saved data is untouched (docs/multi-flavor-plan.md §0, rule 3): SavedVariables written by v0.14.0 (squads, own macros,
-- talent plans, presets, builds, Advanced targeting, ticked squad macros, extras, settings, automation, bar and keybind
-- memory, CVar backup) load in today's code.
-- Forever: after a login + logout the data is exactly what v0.14.0 itself wrote after the same login
-- (tests/fixtures/savedvars-0.14.0/<game>-after.lua, logs and diagnose left out).
-- Classic Era got its own talent trees in 0.15 (before: Forever's). Everything else is exactly as v0.14.0 kept it; the
-- talent plans that Era's trees can't hold are cleaned for use, and their originals are kept unchanged in
-- WoWBoxerDB.legacy.
local dir = (arg[0]:match("^(.*)/[^/]+$") or ".")
local H = dofile(dir .. "/harness.lua")
local Mock = dofile(dir .. "/wowmock.lua")
local SV = dofile(dir .. "/savedvars.lua")

local VERSION = "0.14.0"
-- what the player made: never changed by a login
local DB_KEYS = { "squads", "active", "builds", "settings", "v" }
local CDB_KEYS = { "squadId", "memberId", "overrides", "squadKeys", "extras", "skip", "bindPrev", "cvarBackup", "placedOnce", "secondaryBar", "primaryBar" }
local function pick(t, keys) local o = {}; for _, k in ipairs(keys) do o[k] = t and t[k] end return o end
--- The data without talent plans (member guide/build, own builds) and without legacy: what must stay exact on Era.
local function withoutTalents(db)
  local c = SV.parse(SV.serialize(db, {}))
  c.builds, c.legacy = nil, nil
  for _, s in ipairs(c.squads or {}) do for _, m in ipairs(s.members or {}) do m.guide, m.build, m.race = nil, nil, nil end end
  return c
end

for _, game in ipairs({ "forever", "era" }) do
  local folder = SV.folder(H, VERSION)
  local beforeText = H.readFile(folder .. "/" .. game .. "-before.lua")
  local afterText = H.readFile(folder .. "/" .. game .. "-after.lua")
  if H.ok(beforeText and afterText, game .. ": fixtures in " .. folder) then
    local db, cdb = SV.parse(beforeText)
    H.ok(type(db) == "table" and type(cdb) == "table" and #db.squads == 1, game .. ": the v" .. VERSION .. " file has a squad")
    local db2, cdb2 = SV.relog(H, Mock, game, db, cdb)
    local got = SV.serialize(db2, cdb2, SV.VOLATILE_DB, SV.VOLATILE_CDB)
    do local a, ac = SV.parse(afterText); afterText = SV.serialize(a, ac, SV.VOLATILE_DB, SV.VOLATILE_CDB) end
    local b1, c1 = SV.parse(beforeText)
    local b2, c2 = SV.parse(got)
    if game == "forever" then
      if not H.ok(got == afterText, game .. ": saved data after a login equals what v" .. VERSION .. " wrote") then
        local i = 1
        while got:sub(i, i) == afterText:sub(i, i) do i = i + 1 end
        print("  first difference: " .. (got:sub(math.max(1, i - 80), i + 80):gsub("\n", " | ")))
      end
      H.eq(SV.serialize(pick(b2, DB_KEYS), pick(c2, CDB_KEYS)), SV.serialize(pick(b1, DB_KEYS), pick(c1, CDB_KEYS)),
        game .. ": squads, builds, settings, overrides, keybind and bar memory untouched")
      H.eq(b2.legacy, nil, game .. ": nothing moved to legacy")
    else
      local a1 = SV.parse(afterText)
      H.eq(SV.serialize(withoutTalents(b2), c2, nil, SV.VOLATILE_CDB), SV.serialize(withoutTalents(a1), select(2, SV.parse(afterText)), nil, SV.VOLATILE_CDB),
        game .. ": everything but the talent plans is exactly what v" .. VERSION .. " wrote")
      H.eq(SV.serialize(pick(withoutTalents(b2), DB_KEYS), pick(c2, CDB_KEYS)), SV.serialize(pick(withoutTalents(b1), DB_KEYS), pick(c1, CDB_KEYS)),
        game .. ": squads, settings, overrides, keybind and bar memory untouched")
      -- the originals of the talent plans are kept unchanged
      local L = b2.legacy
      if H.ok(type(L) == "table" and L.game == "era", game .. ": the old talent plans are kept in WoWBoxerDB.legacy") then
        local own = b1.builds.priest[1]
        local ownNow = b2.builds.priest and b2.builds.priest[1]
        if ownNow and SV.serialize(ownNow.order, {}) == SV.serialize(own.order, {}) then
          H.eq(L.builds[own.id], nil, game .. ": the own build '" .. own.label .. "' fits Era's trees: kept as it was")
        else
          H.eq(SV.serialize(L.builds[own.id], {}), SV.serialize(own, {}), game .. ": the own build '" .. own.label .. "' unchanged in legacy")
        end
        for _, m in ipairs(b1.squads[1].members) do
          local x = L.members[m.id]
          local mNow
          for _, y in ipairs(b2.squads[1].members) do if y.id == m.id then mNow = y end end
          local changed = mNow.guide ~= m.guide or mNow.race ~= m.race or SV.serialize(mNow.build or {}, {}) ~= SV.serialize(m.build or {}, {})
          if changed then
            H.ok(x and x.guide == m.guide and x.race == m.race and SV.serialize(x.build or {}, {}) == SV.serialize(m.build or {}, {}), game .. ": " .. m.name .. "'s guide, plan and race kept in legacy")
          end
        end
      end
      -- a second login keeps legacy as it is (written once)
      local db3, cdb3 = SV.relog(H, Mock, game, SV.parse(got))
      H.eq(SV.serialize(db3.legacy, {}), SV.serialize(b2.legacy, {}), game .. ": legacy is written once and kept")
    end
  end
end
os.exit(H.report("savedvars") and 0 or 1)
