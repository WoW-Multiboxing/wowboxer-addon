--[[ WoWBoxer – JSON, base64 and CRC32 in plain Lua 5.1.
  Used for the import/export string. Imported text is only ever parsed as data: no loadstring, no RunScript.
  Json.decode(text, limits) never throws; it returns value or nil, errorText. JSON null becomes nil. ]]
local _, ns = ...
local Json = {}
ns.Json = Json

local byte, char, sub, find, format, gsub = string.byte, string.char, string.sub, string.find, string.format, string.gsub
local tconcat, floor = table.concat, math.floor

Json.ARRAY = { __jsontype = "array" }
Json.OBJECT = { __jsontype = "object" }
function Json.array(t) return setmetatable(t or {}, Json.ARRAY) end
function Json.object(t) return setmetatable(t or {}, Json.OBJECT) end

-- ------------------------------------------------------------------ decode
local escapes = { [34] = '"', [92] = "\\", [47] = "/", [98] = "\b", [102] = "\f", [110] = "\n", [114] = "\r", [116] = "\t" }

local function utf8char(cp)
  if cp < 0x80 then return char(cp) end
  if cp < 0x800 then return char(0xC0 + floor(cp / 0x40), 0x80 + cp % 0x40) end
  if cp < 0x10000 then return char(0xE0 + floor(cp / 0x1000), 0x80 + floor(cp / 0x40) % 0x40, 0x80 + cp % 0x40) end
  return char(0xF0 + floor(cp / 0x40000), 0x80 + floor(cp / 0x1000) % 0x40, 0x80 + floor(cp / 0x40) % 0x40, 0x80 + cp % 0x40)
end

--- limits: {maxDepth=32, maxItems=100000, maxString=100000}
function Json.decode(text, limits)
  if type(text) ~= "string" then return nil, "not a string" end
  limits = limits or {}
  local maxDepth, maxItems, maxString = limits.maxDepth or 64, limits.maxItems or 10000000, limits.maxString or 10000000
  local pos, items = 1, 0
  local n = #text

  local function fail(msg) error({ json = msg .. " at character " .. pos }, 0) end
  local function skip()
    local _, e = find(text, "^[ \t\r\n]*", pos)
    pos = e + 1
  end
  local parseValue

  local function parseString()
    -- pos is at the opening quote
    local i = pos + 1
    local parts, np = {}, 0
    while true do
      local s, e = find(text, '["\\%c]', i)
      if not s then fail("unterminated string") end
      if s > i then np = np + 1; parts[np] = sub(text, i, s - 1) end
      local c = byte(text, s)
      if c == 34 then pos = e + 1; break end
      if c < 32 then fail("control character in string") end
      -- backslash
      local esc = byte(text, s + 1)
      if esc == 117 then
        local hex = sub(text, s + 2, s + 5)
        if not find(hex, "^%x%x%x%x$") then fail("bad \\u escape") end
        local cp = tonumber(hex, 16)
        local adv = 6
        if cp >= 0xD800 and cp <= 0xDBFF then
          local lo = sub(text, s + 6, s + 11)
          if find(lo, "^\\u[dD][c-fC-F]%x%x$") then
            cp = 0x10000 + (cp - 0xD800) * 0x400 + (tonumber(sub(lo, 3), 16) - 0xDC00); adv = 12
          else cp = 0xFFFD end
        elseif cp >= 0xDC00 and cp <= 0xDFFF then cp = 0xFFFD end
        np = np + 1; parts[np] = utf8char(cp)
        i = s + adv
      else
        local r = esc and escapes[esc]
        if not r then fail("bad escape") end
        np = np + 1; parts[np] = r
        i = s + 2
      end
    end
    local str = tconcat(parts)
    if #str > maxString then fail("string too long") end
    return str
  end

  local function parseNumber()
    local s, e = find(text, "^-?%d+%.?%d*[eE]?[-+]?%d*", pos)
    if not s then fail("bad number") end
    local num = tonumber(sub(text, s, e))
    if not num then fail("bad number") end
    pos = e + 1
    return num
  end

  function parseValue(depth)
    if depth > maxDepth then fail("too deeply nested") end
    items = items + 1
    if items > maxItems then fail("too many items") end
    skip()
    local c = byte(text, pos)
    if c == 123 then -- {
      local obj = setmetatable({}, Json.OBJECT)
      pos = pos + 1; skip()
      if byte(text, pos) == 125 then pos = pos + 1; return obj end
      while true do
        skip()
        if byte(text, pos) ~= 34 then fail("expected key") end
        local k = parseString()
        skip()
        if byte(text, pos) ~= 58 then fail("expected ':'") end
        pos = pos + 1
        local v = parseValue(depth + 1)
        obj[k] = v
        skip()
        local d = byte(text, pos)
        if d == 44 then pos = pos + 1
        elseif d == 125 then pos = pos + 1; return obj
        else fail("expected ',' or '}'") end
      end
    elseif c == 91 then -- [
      local arr, i = setmetatable({}, Json.ARRAY), 0
      pos = pos + 1; skip()
      if byte(text, pos) == 93 then pos = pos + 1; return arr end
      while true do
        i = i + 1
        arr[i] = parseValue(depth + 1)
        skip()
        local d = byte(text, pos)
        if d == 44 then pos = pos + 1
        elseif d == 93 then pos = pos + 1; return arr
        else fail("expected ',' or ']'") end
      end
    elseif c == 34 then return parseString()
    elseif c == 116 then if sub(text, pos, pos + 3) == "true" then pos = pos + 4; return true end fail("bad literal")
    elseif c == 102 then if sub(text, pos, pos + 4) == "false" then pos = pos + 5; return false end fail("bad literal")
    elseif c == 110 then if sub(text, pos, pos + 3) == "null" then pos = pos + 4; return nil end fail("bad literal")
    elseif c == 45 or (c and c >= 48 and c <= 57) then return parseNumber()
    end
    fail(c and "unexpected character" or "unexpected end")
  end

  local ok, res = pcall(function()
    local v = parseValue(1)
    skip()
    if pos <= n then fail("trailing characters") end
    return v
  end)
  if ok then return res end
  if type(res) == "table" and res.json then return nil, res.json end
  return nil, "invalid JSON"
end

-- ------------------------------------------------------------------ encode
local function numstr(x)
  if x ~= x or x == math.huge or x == -math.huge then return "null" end
  if x == floor(x) and x > -1e15 and x < 1e15 then return format("%d", x) end
  local s = format("%.15g", x)
  if tonumber(s) ~= x then s = format("%.17g", x) end
  return s
end
local function encStr(s)
  return '"' .. gsub(s, '[%c"\\]', function(c)
    local b = byte(c)
    if c == '"' then return '\\"' elseif c == "\\" then return "\\\\" elseif b == 10 then return "\\n" elseif b == 13 then return "\\r" elseif b == 9 then return "\\t" end
    return format("\\u%04x", b)
  end) .. '"'
end
local function isArray(t)
  local mt = getmetatable(t)
  if mt == Json.ARRAY then return true end
  if mt == Json.OBJECT then return false end
  local n = #t
  if n == 0 then return next(t) == nil end
  local count = 0
  for k in pairs(t) do
    if type(k) ~= "number" or k < 1 or k > n or k ~= floor(k) then return false end
    count = count + 1
  end
  return count == n
end
--- Deterministic: object keys are sorted (or follow keyOrder when given: {key1, key2, ...} applied at every level).
function Json.encode(v, keyOrder, depth)
  depth = depth or 0
  if depth > 64 then error("too deep") end
  local t = type(v)
  if v == nil then return "null" end
  if t == "boolean" then return v and "true" or "false" end
  if t == "number" then return numstr(v) end
  if t == "string" then return encStr(v) end
  if t ~= "table" then error("cannot encode " .. t) end
  if isArray(v) then
    local out = {}
    for i = 1, #v do out[i] = Json.encode(v[i], keyOrder, depth + 1) end
    return "[" .. tconcat(out, ",") .. "]"
  end
  local keys = {}
  for k in pairs(v) do if type(k) == "string" then keys[#keys + 1] = k end end
  local rank = {}
  if keyOrder then for i, k in ipairs(keyOrder) do rank[k] = i end end
  table.sort(keys, function(a, b)
    local ra, rb = rank[a] or 10000, rank[b] or 10000
    if ra ~= rb then return ra < rb end
    return a < b
  end)
  local out = {}
  for i, k in ipairs(keys) do out[i] = encStr(k) .. ":" .. Json.encode(v[k], keyOrder, depth + 1) end
  return "{" .. tconcat(out, ",") .. "}"
end

-- ------------------------------------------------------------------ base64 (RFC 4648, standard alphabet, padding optional on decode)
local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local b64dec = {}
for i = 1, 64 do b64dec[byte(B64, i)] = i - 1 end
b64dec[byte("-")] = 62; b64dec[byte("_")] = 63 -- also accept base64url

function Json.b64encode(s)
  local out, n = {}, 0
  for i = 1, #s, 3 do
    local a, b, c = byte(s, i, i + 2)
    local v = a * 65536 + (b or 0) * 256 + (c or 0)
    local c1, c2, c3, c4 = floor(v / 262144) % 64, floor(v / 4096) % 64, floor(v / 64) % 64, v % 64
    n = n + 1
    out[n] = sub(B64, c1 + 1, c1 + 1) .. sub(B64, c2 + 1, c2 + 1) .. (b and sub(B64, c3 + 1, c3 + 1) or "=") .. (c and sub(B64, c4 + 1, c4 + 1) or "=")
  end
  return tconcat(out)
end
--- Returns decoded string or nil, error. Whitespace is ignored.
function Json.b64decode(s)
  s = gsub(s, "[%s]", "")
  s = gsub(s, "=+$", "")
  if find(s, "[^%w%+/%-_]") then return nil, "invalid base64 character" end
  if #s % 4 == 1 then return nil, "invalid base64 length" end
  local out, n = {}, 0
  for i = 1, #s, 4 do
    local c1, c2, c3, c4 = byte(s, i, i + 3)
    local v = b64dec[c1] * 262144 + b64dec[c2] * 4096 + (c3 and b64dec[c3] or 0) * 64 + (c4 and b64dec[c4] or 0)
    n = n + 1
    if c4 then out[n] = char(floor(v / 65536) % 256, floor(v / 256) % 256, v % 256)
    elseif c3 then out[n] = char(floor(v / 65536) % 256, floor(v / 256) % 256)
    else out[n] = char(floor(v / 65536) % 256) end
  end
  return tconcat(out)
end

-- ------------------------------------------------------------------ CRC32 (IEEE, same as zlib) without bit ops
local crcTable
local function xor(a, b) -- 32-bit xor with arithmetic only (Lua 5.1 has no bit library outside WoW)
  local r, p = 0, 1
  for _ = 1, 32 do
    local x, y = a % 2, b % 2
    if x ~= y then r = r + p end
    a, b, p = (a - x) / 2, (b - y) / 2, p * 2
  end
  return r
end
local function xor8(a, b) -- xor of the low 8 bits
  local r, p = 0, 1
  for _ = 1, 8 do
    local x, y = a % 2, b % 2
    if x ~= y then r = r + p end
    a, b, p = (a - x) / 2, (b - y) / 2, p * 2
  end
  return r
end
local function buildTable()
  crcTable = {}
  for i = 0, 255 do
    local c = i
    for _ = 1, 8 do
      if c % 2 == 1 then c = xor(floor(c / 2), 0xEDB88320) else c = floor(c / 2) end
    end
    crcTable[i] = c
  end
end
function Json.crc32(s)
  if not crcTable then buildTable() end
  local crc = 0xFFFFFFFF
  for i = 1, #s do
    local idx = xor8(crc % 256, byte(s, i))
    crc = xor(floor(crc / 256), crcTable[idx])
  end
  return xor(crc, 0xFFFFFFFF)
end
function Json.crc32hex(s) return format("%08x", Json.crc32(s)) end
