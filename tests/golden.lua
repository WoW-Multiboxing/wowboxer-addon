--[[ Golden snapshot of the macro output per game (docs/multi-flavor-plan.md §0, rule 1).
  build(game) loads the addon the way that client does (its TOC files, its interface number) and renders, as canonical
  JSON (sorted keys, fixed layout):
    - members: every class × role × sequence tier × unit (leader, party1-4, focus), first race of the class, build = the
      role's default guide – the WBX macros of M.desired for
      levels 1-60, as level bands in which the output stays the same (name, key, group, body, icon, ok, why);
    - extras: per class × role the extra single-spell keys with their pending state per level band;
    - spells: E.makeMacro of every class spell, racial and Engage Target for the six unit contexts;
    - guides: the default talent guide per class × role and every guide's talent order.
  tests/test_golden.lua compares it byte for byte with tests/golden/<game>.json.
  Write the files (only for a deliberate change, with a one-line reason in the commit):
    lua tests/golden.lua --write            (or: python tools/lua.py tests/golden.lua --write) ]]
local G = {}
local dir = (arg and arg[0] and arg[0]:match("^(.*)/[^/]+$")) or "tests"

G.GAMES = {
  forever = { toc = 16001, gameType = "forever", maxLevel = 60 },
  era = { toc = 11509, gameType = "vanilla", maxLevel = 60 },
}

-- ------------------------------------------------------------------ canonical JSON
local function str(s)
  return '"' .. s:gsub('[%c"\\]', function(c)
    if c == '"' then return '\\"' elseif c == "\\" then return "\\\\" elseif c == "\n" then return "\\n"
    elseif c == "\r" then return "\\r" elseif c == "\t" then return "\\t" end
    return string.format("\\u%04x", c:byte())
  end) .. '"'
end
local function isArray(t)
  local n = 0
  for _ in pairs(t) do n = n + 1 end
  for i = 1, n do if t[i] == nil then return false end end
  return true, n
end
local function enc(v, ind, out)
  local tv = type(v)
  if v == nil then out[#out + 1] = "null"
  elseif tv == "boolean" then out[#out + 1] = v and "true" or "false"
  elseif tv == "number" then
    if v == math.floor(v) and math.abs(v) < 1e15 then out[#out + 1] = string.format("%d", v) else out[#out + 1] = string.format("%.6f", v) end
  elseif tv == "string" then out[#out + 1] = str(v)
  elseif tv == "table" then
    local arr, n = isArray(v)
    local inner = ind .. " "
    if arr then
      if n == 0 then out[#out + 1] = "[]" return end
      local flat = true
      for i = 1, n do if type(v[i]) == "table" then flat = false end end
      out[#out + 1] = "["
      for i = 1, n do
        if i > 1 then out[#out + 1] = "," end
        if not flat then out[#out + 1] = "\n" .. inner end
        enc(v[i], inner, out)
      end
      out[#out + 1] = flat and "]" or ("\n" .. ind .. "]")
    else
      local keys = {}
      for k in pairs(v) do keys[#keys + 1] = tostring(k) end
      table.sort(keys)
      out[#out + 1] = "{"
      for i, k in ipairs(keys) do
        if i > 1 then out[#out + 1] = "," end
        out[#out + 1] = "\n" .. inner .. str(k) .. ":"
        local x = v[k]; if x == nil then x = v[tonumber(k)] end
        enc(x, inner, out)
      end
      out[#out + 1] = "\n" .. ind .. "}"
    end
  else error("cannot encode " .. tv) end
end
function G.encode(v) local out = {}; enc(v, "", out); return table.concat(out) .. "\n" end

-- ------------------------------------------------------------------ build
local function firstRace(D, cls)
  for _, r in ipairs(D.races) do for _, c in ipairs(r.c) do if c == cls then return r.k end end end
end

--- The canonical JSON text of game `game` ("forever" | "era").
function G.build(H, Mock, game)
  local cfg = assert(G.GAMES[game], "unknown game " .. tostring(game))
  local W = Mock.new(H, { toc = cfg.toc })
  local ns = H.loadAddon({ env = W.env, gameType = cfg.gameType })
  local D, E, K, M = ns.Data, ns.Engine, ns.Kit, ns.Macros
  local maxL = cfg.maxLevel
  local UNITS = { "leader", "party1", "party2", "party3", "party4", "focus" }
  local function ctxOf(u) if u == "leader" then return { leader = true, unit = "party1" } end return { leader = false, unit = u } end

  -- a five-member squad so the leader's Invite key is part of the output
  local function squadFor(me)
    local s = { name = "Golden", members = { me } }
    for i = 1, 4 do s.members[#s.members + 1] = { name = "Member" .. i, cls = "warrior", role = "melee", leader = false, unit = "party" .. i } end
    return s
  end

  -- a member as the Squad page makes it (State.newMember), following its default guide's talent order, so
  -- talent spells enter the output at the level the guide takes them
  local function member(cls, race, role, leader, unit, tier)
    local guide = K.defaultGuideFor(cls, role)
    local g = K.guide(cls, guide)
    return ns.State.newMember({ id = "mgold", name = "Golden", cls = cls, race = race, role = role, level = 1, leader = leader, unit = unit,
      seq = tier, guide = guide, build = g and g.order or {} })
  end

  local out = { game = game, toc = cfg.toc, maxLevel = maxL, members = {}, extras = {}, spells = {}, guides = {} }
  for _, cls in ipairs(D.classOrder) do
    local race = firstRace(D, cls)
    local tiers = E.seqSupported(cls) and E.SEQ_TIERS or { "off" }
    for _, role in ipairs(D.classes[cls].roles) do
      for _, tier in ipairs(tiers) do
        for _, u in ipairs(UNITS) do
          local c = ctxOf(u)
          local m = member(cls, race, role, c.leader, c.unit, tier)
          local opts = { squad = squadFor(m) }
          local bands, prev = {}, nil
          for L = 1, maxL do
            m.level = L
            local list = {}
            for i, d in ipairs(M.desired(m, L, opts)) do
              list[i] = { name = d.name, key = d.key, group = d.group, body = d.body, icon = d.icon, ok = d.ok and true or false, why = d.why }
            end
            local sig = G.encode(list)
            if prev and prev.sig == sig then prev.band.to = L
            else
              prev = { sig = sig, band = { from = L, to = L, macros = list } }
              bands[#bands + 1] = prev.band
            end
          end
          out.members[#out.members + 1] = { cls = cls, role = role, race = race, tier = tier, unit = u, bands = bands }
        end
      end
      -- extra single-spell keys: every non-passive class spell and racial, party1 follower
      local m = member(cls, race, role, false, "party1", "off")
      local extras = {}
      for _, s in ipairs(K.spellsOf(m)) do if s.action ~= "passive" then extras[#extras + 1] = s.id end end
      local bands, prev = {}, nil
      for L = 1, maxL do
        m.level = L
        local list = {}
        for _, d in ipairs(M.desired(m, L, { extras = extras })) do
          if d.group == "extra" then list[#list + 1] = { name = d.name, id = d.spell.id, pending = d.pending, icon = d.icon } end
        end
        local sig = G.encode(list)
        if prev and prev.sig == sig then prev.band.to = L
        else prev = { sig = sig, band = { from = L, to = L, extras = list } }; bands[#bands + 1] = prev.band end
      end
      out.extras[#out.extras + 1] = { cls = cls, role = role, race = race, bands = bands }
    end
    -- every spell of the class (and the racials of every race that can be this class) for the six unit contexts
    local spells = {}
    local function addSpell(s)
      local bodies = {}
      for i, u in ipairs(UNITS) do bodies[i] = E.makeMacro(s, ctxOf(u)) end
      spells[#spells + 1] = { id = s.id, name = s.name, level = s.level, gate = s.gate, action = s.action, macros = bodies }
    end
    for _, s in ipairs(D.spells[cls]) do addSpell(s) end
    for _, r in ipairs(D.races) do
      for _, c in ipairs(r.c) do
        if c == cls then for _, s in ipairs(K.racialsOf({ cls = cls, race = r.k })) do addSpell(s) end end
      end
    end
    if cls == "paladin" then addSpell(K.engage()) end
    out.spells[cls] = spells
    -- talent guides
    local g = { default = K.defaultGuide(cls), byRole = {}, orders = {} }
    for _, role in ipairs(D.classes[cls].roles) do g.byRole[role] = K.defaultGuideFor(cls, role) end
    for _, x in ipairs(K.dataGuidesOf(cls)) do g.orders[#g.orders + 1] = { id = x.id, spec = x.spec, order = x.order } end
    out.guides[cls] = g
  end
  return G.encode(out)
end

function G.path(H, game) return H.root .. "/tests/golden/" .. game .. ".json" end

-- ------------------------------------------------------------------ CLI: --write
if arg and arg[0] and (arg[0]:match("[/\\]golden%.lua$") or arg[0] == "golden.lua") then
  local H = dofile(dir .. "/harness.lua")
  local Mock = dofile(dir .. "/wowmock.lua")
  local only = arg[2]
  if arg[1] == "--write" then
    for _, game in ipairs({ "forever", "era" }) do
      if not only or only == game then
        local txt = G.build(H, Mock, game)
        local fh = assert(io.open(G.path(H, game), "wb")); fh:write(txt); fh:close()
        print("wrote " .. G.path(H, game) .. " (" .. #txt .. " bytes)")
      end
    end
  else
    print("usage: lua tests/golden.lua --write [forever|era]")
  end
end

return G
