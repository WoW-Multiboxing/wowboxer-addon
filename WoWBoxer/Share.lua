--[[ WoWBoxer – import/export string, shared with the WoWBoxer website and the web companion.
    !WBX:1!<base64(UTF-8 JSON)>!<crc32 of the JSON, 8 hex digits>
  JSON = {f="wowboxer/1", game="forever"|"era"|"any", squad={companion squad}, cvars={name=value}, addons={names}}
  The string is data only: it is parsed with our own JSON reader, every field is whitelisted and sanitised, and it
  never contains macro text (the addon builds macros itself). Reference implementation: share/wbx-string.js. ]]
local _, ns = ...
local Sh = {}
ns.Share = Sh

local Json, S, R = ns.Json, ns.State, ns.Rules

Sh.PREFIX = "!WBX:1!"
Sh.FORMAT = "wowboxer/1"
Sh.MAX_LEN = 16384
Sh.GAMES = { forever = true, era = true, tbc = true, any = true }

local function E_copy(t) local o = {}; for i, v in ipairs(t or {}) do o[i] = v end return o end
local KEY_ORDER = nil -- sorted keys (canonical JSON, same as share/wbx-string.js)

--- payload table -> string
function Sh.encode(payload)
  local json = Json.encode(payload, KEY_ORDER)
  return Sh.PREFIX .. Json.b64encode(json) .. "!" .. Json.crc32hex(json)
end

--- string -> raw payload table or nil, error
function Sh.decode(str)
  if type(str) ~= "string" then return nil, "Nothing to import." end
  str = str:gsub("^%s+", ""):gsub("%s+$", "")
  if #str > Sh.MAX_LEN then return nil, "The string is too long (" .. #str .. " characters, max " .. Sh.MAX_LEN .. ")." end
  if str:sub(1, 5) == "!WBX:" and str:sub(1, #Sh.PREFIX) ~= Sh.PREFIX then return nil, "This string was made by a newer WoWBoxer. Update the addon." end
  if str:sub(1, #Sh.PREFIX) ~= Sh.PREFIX then return nil, "Not a WoWBoxer string (it should start with " .. Sh.PREFIX .. ")." end
  local body = str:sub(#Sh.PREFIX + 1)
  local b64, crc = body:match("^([^!]+)!(%x%x%x%x%x%x%x%x)$")
  if not b64 then return nil, "The string is incomplete (copy all of it)." end
  local json, err = Json.b64decode(b64)
  if not json then return nil, "The string is damaged: " .. err .. "." end
  if Json.crc32hex(json) ~= crc:lower() then return nil, "The string is damaged (checksum mismatch). Copy it again." end
  local v, jerr = Json.decode(json, { maxDepth = 12, maxItems = 5000, maxString = 2000 })
  if v == nil then return nil, "The string is damaged: " .. tostring(jerr) .. "." end
  if type(v) ~= "table" or v.f ~= Sh.FORMAT then return nil, "Unknown format." end
  return v
end

--- Raw payload -> clean import {squad, cvars, addons, game}, warnings
function Sh.validate(v, game)
  local warn = {}
  if type(v.squad) ~= "table" then return nil, { "The string has no squad." } end
  local s = S.newSquad(v.squad)
  if #s.members == 0 then return nil, { "The squad has no characters." } end
  local nIn = type(v.squad.members) == "table" and #v.squad.members or 0
  if nIn > #s.members then warn[#warn + 1] = (nIn - #s.members) .. " character(s) over the limit of " .. S.MAX_MEMBERS .. " were left out." end
  local g = Sh.GAMES[v.game] and v.game or "any"
  if g ~= "any" and game and g ~= game then warn[#warn + 1] = "This setup was made for " .. g .. "; you are playing " .. game .. "." end
  local cvars = {}
  if type(v.cvars) == "table" then
    for k, val in pairs(v.cvars) do
      if R.CVAR_BY_NAME[k] and R.cleanCVarValue(val) then cvars[k] = R.cleanCVarValue(val)
      else warn[#warn + 1] = "Setting " .. tostring(k) .. " is not on WoWBoxer's list and was ignored." end
    end
  end
  local addons = {}
  if type(v.addons) == "table" then
    for _, a in ipairs(v.addons) do local n = R.cleanAddonName(a); if n and #addons < 30 then addons[#addons + 1] = n end end
  end
  return { squad = s, cvars = cvars, addons = addons, game = g }, warn
end

--- Full import: string -> clean import or nil, error; warnings
function Sh.import(str, game)
  local v, err = Sh.decode(str)
  if not v then return nil, err, {} end
  local res, warn = Sh.validate(v, game)
  if not res then return nil, warn[1], {} end
  return res, nil, warn
end

--- Squad -> export string (plain companion fields only).
function Sh.export(squad, extra)
  extra = extra or {}
  local members = Json.array()
  for _, m in ipairs(squad.members) do
    local custom = Json.array()
    for _, c in ipairs(m.customSeq or {}) do
      custom[#custom + 1] = { id = c.id, name = c.name, kind = c.kind, aim = c.aim, steps = Json.array(E_copy(c.steps)), filler = c.filler, fills = c.fills, reset = c.reset }
    end
    members[#members + 1] = { id = m.id, name = m.name, cls = m.cls, race = m.race, role = m.role, level = m.level, leader = m.leader, unit = m.unit,
      talented = m.talented, build = Json.array(E_copy(m.build)), guide = m.guide, seq = m.seq, seqTarget = m.seqTarget, customSeq = custom,
      pins = Json.array(E_copy(m.pins)), tags = Json.array(E_copy(m.tags)), seqTier = m.seqTier }
  end
  local payload = { f = Sh.FORMAT, game = extra.game or "any",
    squad = { id = squad.id, name = squad.name, faction = squad.faction, linkLevels = squad.linkLevels, members = members } }
  local presets = Json.array()
  for _, p in ipairs(squad.presets or {}) do presets[#presets + 1] = { id = p.id, name = p.name, leader = p.leader, roles = Json.object(p.roles) } end
  if #presets > 0 then payload.squad.presets = presets; payload.squad.activePreset = squad.activePreset end
  if squad.notes and squad.notes ~= "" then payload.squad.notes = squad.notes end
  if extra.cvars and next(extra.cvars) then payload.cvars = Json.object(extra.cvars) end
  if extra.addons and #extra.addons > 0 then payload.addons = Json.array(E_copy(extra.addons)) end
  return Sh.encode(payload)
end

