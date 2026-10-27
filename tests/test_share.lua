-- Share string: Lua must decode what share/wbx-string.js encodes, re-encode it byte-identically, give the same error
-- messages, and never execute or accept anything outside the whitelist. Fixtures: node share/test.js
local dir = (arg[0]:match("^(.*)/[^/]+$") or ".")
local H = dofile(dir .. "/harness.lua")
local Mock = dofile(dir .. "/wowmock.lua")

local W = Mock.new(H, { name = "Dorin", class = "PALADIN", race = "Scourge", level = 12 })
local ns = H.loadAddon({ env = W.env })
W.fire("ADDON_LOADED", "WoWBoxer"); W.fire("PLAYER_LOGIN")
local Sh, Json, Core = ns.Share, ns.Json, ns.Core

-- primitives
H.eq(Json.crc32hex("123456789"), "cbf43926", "crc32 check value")
H.eq(Json.b64encode("Man"), "TWFu", "base64 3 bytes")
H.eq(Json.b64encode("Ma"), "TWE=", "base64 2 bytes")
H.eq(Json.b64decode("TWE="), "Ma", "base64 decode padded")
H.eq(Json.b64decode("TWE"), "Ma", "base64 decode unpadded")
H.eq(Json.decode('"\\u00e6\\ud83d\\ude00"'), "\195\166\240\159\152\128", "unicode escapes")
H.eq(select(2, Json.decode('{"a":1}x')) ~= nil, true, "trailing garbage rejected")
H.eq(select(2, Json.decode(string.rep("[", 100) .. string.rep("]", 100), { maxDepth = 12 })) ~= nil, true, "depth limit")
H.eq(Json.encode({ b = 1, a = { 1, 2 }, c = Json.object() }), '{"a":[1,2],"b":1,"c":{}}', "canonical encode")

local fx = H.readFile(H.root .. "/tests/vectors/share.json")
if H.ok(fx ~= nil, "fixtures present (node share/test.js)") then
  local v = Json.decode(fx)
  for _, c in ipairs(v.cases) do
    local p, err = Sh.decode(c.str)
    H.ok(p ~= nil, c.name .. ": decodes " .. tostring(err))
    H.ok(H.deq(p, c.payload), c.name .. ": same payload as JS")
    H.eq(Sh.encode(c.payload), c.str, c.name .. ": Lua encodes byte-identically")
  end
  for _, b in ipairs(v.bad) do
    local p, err = Sh.decode(b.str)
    H.ok(p == nil, "rejected: " .. tostring(b.err or b.errPrefix))
    if b.err then H.eq(err, b.err, "same error text as JS") else H.ok(err and err:sub(1, #b.errPrefix) == b.errPrefix, "error prefix " .. tostring(err)) end
  end
  -- full import of the trio
  local res, err, warn = Core.importString(v.cases[1].str)
  H.ok(res ~= nil, "trio imports " .. tostring(err))
  H.eq(#res.squad.members, 3, "3 members")
  H.eq(res.cvars.autoLootDefault, "1", "allow-listed cvar kept")
  H.eq(res.addons[1], "Questie", "addon list kept")
  local m = Core.applyImport(res)
  H.eq(m and m.name, "Dorin", "this character recognised after import")
  H.eq(m and m.leader, true, "leader")
  H.eq(m and m.seq, "medium", "sequence tier imported")
  -- export of the imported squad round-trips through the JS-compatible format
  local out = Core.exportString()
  local back = Sh.import(out, "forever")
  H.ok(back ~= nil and #back.squad.members == 3, "export -> import")
  H.eq(back.squad.members[2].customSeq[1].name, "Shield + Renew", "custom keys survive")
end

-- hostile content
local function mk(payload) return Sh.encode(payload) end
local evil = mk({ f = "wowboxer/1", game = "forever", cvars = { scriptErrors = "1", autoLootDefault = "1; /run x", maxfpsbk = "30" },
  addons = { "Questie", "../../evil", string.rep("a", 200) },
  squad = { id = "x!y", name = "Evil\n/run", members = { { name = "/run DeleteMacro(1)", cls = "nope", race = "x", role = "god", level = 999, unit = "player",
    build = { "no-such" }, customSeq = { { name = "x", kind = "macro", steps = { "/run x()", "Smite" }, filler = "/script y", fills = 99, reset = "evil" } } } } } })
local res, err, warn = Sh.import(evil, "forever")
H.ok(res ~= nil, "hostile import is sanitised, not crashed: " .. tostring(err))
local m = res.squad.members[1]
H.eq(m.cls, "warrior", "unknown class -> warrior")
H.eq(m.level, 60, "level clamped")
H.eq(m.unit, "party1", "unit whitelisted")
H.eq(#m.build, 0, "unknown talents dropped")
H.eq(m.customSeq[1].kind, "sequence", "custom kind whitelisted")
H.eq(m.customSeq[1].fills, 6, "fills clamped")
H.eq(m.customSeq[1].reset, "combat", "reset whitelisted")
H.eq(res.cvars.scriptErrors, nil, "cvar outside the allow-list dropped")
H.eq(res.cvars.autoLootDefault, nil, "cvar value with junk dropped")
H.eq(res.cvars.maxfpsbk, "30", "valid cvar kept")
H.eq(#res.addons, 1, "only valid addon names")
H.ok(res.squad.id ~= "x!y", "unsafe id replaced")
H.eq(res.squad.name, "Evil/run", "control characters removed from names")
-- the macros built for that member never contain the injected text
local ctx = ns.Macros.desired(m, 60, {})
for _, d in ipairs(ctx) do
  H.ok(d.ok, "generated macro valid " .. d.name)
  H.ok(not d.body:find("/run") and not d.body:find("/script"), "no injected commands in " .. d.name)
end

os.exit(H.report("share") and 0 or 1)
