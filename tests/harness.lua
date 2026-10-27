--[[ Test harness: loads the addon's Lua files the way WoW does (each file gets ADDON_NAME and a shared namespace table)
  in a Lua 5.1-strict environment, so code that only works in Lua 5.2+ fails here too.
  Runs on Lua 5.1 / LuaJIT (CI) and on Lua 5.3/5.4 (e.g. texlua in the Cowork sandbox). ]]
local H = {}

H.root = (arg and arg[0] and arg[0]:match("^(.*)/tests/[^/]+$")) or "."
H.is51 = _VERSION == "Lua 5.1"

--- A copy of the globals without anything Lua 5.1 / WoW does not have.
function H.env51(extra)
  local env = {}
  for k, v in pairs(_G) do env[k] = v end
  local function copy(t) local c = {}; for k, v in pairs(t) do c[k] = v end; return c end
  env.table, env.string, env.math, env.os = copy(table), copy(string), copy(math), copy(os)
  env.unpack = rawget(_G, "unpack") or table.unpack
  env.table.unpack, env.table.pack, env.table.move = nil, nil, nil
  env.math.type, env.math.tointeger, env.math.ult = nil, nil, nil
  env.string.pack, env.string.unpack, env.string.packsize = nil, nil, nil
  env.utf8, env.bit32, env.coroutine = nil, nil, coroutine
  -- the addon must never compile or run code at runtime
  env.load, env.loadstring, env.dofile, env.loadfile, env.require = nil, nil, nil, nil, nil
  env.io, env.debug = nil, nil
  env.getfenv, env.setfenv = nil, nil
  env.math.pow = math.pow or function(a, b) return a ^ b end
  env.math.mod = math.fmod
  env.string.gfind = string.gmatch
  env._G = env
  for k, v in pairs(extra or {}) do env[k] = v end
  return env
end

local function loadIn(path, env)
  if H.is51 then
    local f, err = loadfile(path)
    if not f then error(err, 0) end
    setfenv(f, env)
    return f
  end
  local fh = assert(io.open(path, "rb"))
  local src = fh:read("*a"); fh:close()
  local f, err = load(src, "@" .. path, "t", env)
  if not f then error(err, 0) end
  return f
end
H.loadIn = loadIn

--- Files listed in the TOC (without [AllowLoad…] lines that exclude this game type), in order.
function H.tocFiles(gameType)
  local out = {}
  for line in io.lines(H.root .. "/WoWBoxer/WoWBoxer.toc") do
    line = line:gsub("\r", "")
    if not line:match("^%s*#") and line:match("%S") then
      local file, rest = line:match("^%s*(%S+)%s*(.*)$")
      local allowed = true
      local allow = rest:match("%[AllowLoadGameType ([^%]]+)%]")
      if allow and gameType then allowed = false; for g in allow:gmatch("[^,%s]+") do if g == gameType then allowed = true end end end
      if allowed then out[#out + 1] = file:gsub("\\", "/") end
    end
  end
  return out
end

--- Load the addon into a fresh env. opts: {files=list (default: TOC, Lua files only), env=table, gameType="camelot"|"classic"}
function H.loadAddon(opts)
  opts = opts or {}
  local env = opts.env or H.env51()
  local ns = {}
  local files = opts.files or H.tocFiles(opts.gameType)
  for _, f in ipairs(files) do
    if f:match("%.lua$") then
      local chunk = loadIn(H.root .. "/WoWBoxer/" .. f, env)
      chunk("WoWBoxer", ns)
    end
  end
  return ns, env
end

-- ------------------------------------------------------------------ tiny assertion lib
H.passed, H.failed, H.failures = 0, 0, {}
local function show(v, depth)
  depth = depth or 0
  if type(v) == "string" then return string.format("%q", v) end
  if type(v) ~= "table" or depth > 3 then return tostring(v) end
  local parts = {}
  for k, x in pairs(v) do parts[#parts + 1] = tostring(k) .. "=" .. show(x, depth + 1) end
  table.sort(parts)
  return "{" .. table.concat(parts, ", ") .. "}"
end
H.show = show
function H.ok(cond, msg)
  if cond then H.passed = H.passed + 1 else
    H.failed = H.failed + 1
    if #H.failures < 40 then H.failures[#H.failures + 1] = msg or "assertion failed" end
  end
  return cond
end
function H.eq(a, b, msg)
  return H.ok(a == b, (msg or "values differ") .. "\n    got:      " .. show(a) .. "\n    expected: " .. show(b))
end
--- Deep equality where nil and JSON null are the same and arrays/objects compare by content.
function H.deq(a, b)
  if a == b then return true end
  if type(a) ~= "table" or type(b) ~= "table" then
    if type(a) == "number" and type(b) == "number" then return math.abs(a - b) < 1e-9 end
    return false
  end
  for k, v in pairs(a) do if not H.deq(v, b[k]) then return false end end
  for k, v in pairs(b) do if a[k] == nil and v ~= nil then return false end end
  return true
end
function H.deqMsg(a, b, msg)
  return H.ok(H.deq(a, b), (msg or "tables differ") .. "\n    got:      " .. show(a) .. "\n    expected: " .. show(b))
end
function H.report(name)
  print(string.format("%s: %d passed, %d failed", name, H.passed, H.failed))
  for _, f in ipairs(H.failures) do print("  FAIL: " .. f) end
  return H.failed == 0
end
function H.readFile(path)
  local fh = io.open(path, "rb")
  if not fh then return nil end
  local s = fh:read("*a"); fh:close(); return s
end

return H
