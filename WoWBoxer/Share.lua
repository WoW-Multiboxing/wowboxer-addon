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
    -- an own build (a "u…" guide) travels as the member's build: order + name, no link text
    local build, buildName = m.build, m.buildName
    local own = (not build or #build == 0) and ns.Kit.guide(m.cls, m.guide or "") or nil
    if own and own.user then build, buildName = own.order, own.label end
    local custom = Json.array()
    for _, c in ipairs(m.customSeq or {}) do
      custom[#custom + 1] = { id = c.id, name = c.name, kind = c.kind, aim = c.aim, steps = Json.array(E_copy(c.steps)), filler = c.filler, fills = c.fills, reset = c.reset }
    end
    members[#members + 1] = { id = m.id, name = m.name, cls = m.cls, race = m.race, role = m.role, level = m.level, leader = m.leader, unit = m.unit,
      talented = m.talented, build = Json.array(E_copy(build)), buildName = buildName, guide = m.guide, seq = m.seq, seqTarget = m.seqTarget, customSeq = custom,
      pins = Json.array(E_copy(m.pins)), tags = Json.array(E_copy(m.tags)), seqTier = m.seqTier, realm = m.realm }
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

-- ------------------------------------------------------------------ one own key as text (copy / paste)
-- !WBXK:1!<base64 JSON>!<crc32>, JSON = {f="wowboxer-key/1", cls, key={name, kind, aim, steps, filler, fills, reset}}.
-- Like the squad string it carries spell NAMES only, never macro text: the client that pastes it builds the macro.
Sh.KEY_PREFIX = "!WBXK:1!"
Sh.KEY_FORMAT = "wowboxer-key/1"

function Sh.encodeKey(c, cls)
  local key = { name = c.name, kind = c.kind, aim = c.aim, steps = Json.array(E_copy(c.steps)), filler = c.filler or "", fills = c.fills, reset = c.reset }
  local json = Json.encode({ f = Sh.KEY_FORMAT, cls = cls, key = key }, KEY_ORDER)
  return Sh.KEY_PREFIX .. Json.b64encode(json) .. "!" .. Json.crc32hex(json)
end

--- A pasted key string -> clean key {name, kind, aim, steps, filler, fills, reset}, cls  or nil, error.
function Sh.decodeKey(str)
  str = (type(str) == "string" and str or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if #str > 4000 then return nil, "Too long for one macro." end
  local b64, crc = str:match("^!WBXK:1!([^!]+)!(%x%x%x%x%x%x%x%x)$")
  if not b64 then return nil, "Not a WoWBoxer macro." end
  local json, err = Json.b64decode(b64)
  if not json then return nil, "The macro is damaged: " .. err .. "." end
  if Json.crc32hex(json) ~= crc:lower() then return nil, "The macro is damaged (checksum). Copy it again." end
  local v = Json.decode(json, { maxDepth = 6, maxItems = 200, maxString = 200 })
  if type(v) ~= "table" or v.f ~= Sh.KEY_FORMAT or type(v.key) ~= "table" then return nil, "Unknown macro format." end
  local c = S.cleanCustom({ v.key })[1]
  if not c then return nil, "The macro is empty." end
  return c, (type(v.cls) == "string" and v.cls or nil)
end

--- Plain macro text (a /castsequence line, or /cast lines = a priority list) -> a key draft, or nil, error.
--- Only the spell names are taken over; WoWBoxer writes its own conditions and lines. Data only, never run.
function Sh.parseMacro(text)
  if type(text) ~= "string" or #text > 2000 then return nil, "Paste one macro (up to 255 characters)." end
  local function conds(rest)
    local c, i = "", 1
    while true do
      local a = rest:find("^%s*%[", i)
      if not a then break end
      local j = rest:find("]", i, true)
      if not j then break end
      c = c .. rest:sub(i, j); i = j + 1
    end
    return c, (rest:sub(i):gsub("^%s+", ""))
  end
  local function spell(n)
    n = (n or ""):gsub("^%s+", ""):gsub("%s+$", ""):gsub("^!", ""):gsub("%s*%(.-%)$", "")
    n = n:match("^([^;]*)") or n
    n = n:gsub("%s+$", "")
    if n == "" or #n > 40 or n:find("[%[%]/]") then return nil end
    return n
  end
  local seqLine, casts, help = nil, {}, false
  for line in (text:gsub("\r", "") .. "\n"):gmatch("([^\n]*)\n") do
    local rest = line:match("^%s*/castsequence%s+(.*)$")
    if rest then seqLine = seqLine or rest
    else
      local r2 = line:match("^%s*/cast%s+(.*)$")
      if r2 then casts[#casts + 1] = r2 end
    end
  end
  local out = { name = "Pasted macro", kind = "sequence", aim = "harm", steps = {}, filler = "", fills = 1, reset = "combat" }
  if seqLine then
    local c, tail = conds(seqLine)
    help = c:find("help", 1, true) ~= nil and not c:find("harm", 1, true)
    local reset, list = tail:match("^reset=(%S+)%s+(.*)$")
    if not reset then list = tail end
    if reset == "target" or reset == "target/combat" or reset == "combat/target" then out.reset = "target/combat"
    elseif reset and reset:find("%d") then out.reset = "combat/12" end
    local names = {}
    for item in (list .. ","):gmatch("([^,]*),") do local n = spell(item); if n then names[#names + 1] = n end end
    if #names == 0 then return nil, "No spells found after /castsequence." end
    -- the last spell repeated at the end is the filler
    local last, n = names[#names], 0
    for i = #names, 1, -1 do if names[i] == last then n = n + 1 else break end end
    if n >= 2 or #names == 1 then
      out.filler, out.fills = last, math.min(6, math.max(1, n))
      for i = 1, #names - n do out.steps[#out.steps + 1] = names[i] end
    else
      for _, x in ipairs(names) do out.steps[#out.steps + 1] = x end
    end
  elseif #casts > 0 then
    out.kind = "priority"
    for _, r in ipairs(casts) do
      local c, tail = conds(r)
      if c:find("help", 1, true) and not c:find("harm", 1, true) then help = true end
      local n = spell(tail)
      if n and #out.steps < 12 then
        local dup = false
        for _, x in ipairs(out.steps) do if x == n then dup = true end end
        if not dup then out.steps[#out.steps + 1] = n end
      end
    end
    if #out.steps == 0 then return nil, "No spells found after /cast." end
  else
    return nil, "Paste a WoWBoxer macro (!WBXK:1!…) or a macro with /castsequence or /cast lines."
  end
  out.aim = help and "help" or "harm"
  while #out.steps > 12 do table.remove(out.steps) end
  return out
end
