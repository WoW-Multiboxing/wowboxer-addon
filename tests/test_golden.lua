-- Golden: today's macro output per game must stay byte for byte the same (docs/multi-flavor-plan.md §0, rule 1).
-- Replaces tests/parity.lua: the addon is the source of truth now, so it is compared with its own snapshot instead of
-- the parked companion. A deliberate change to the macros regenerates the snapshot in the same commit:
--   lua tests/golden.lua --write    (with a one-line reason in the commit message)
local dir = (arg[0]:match("^(.*)/[^/]+$") or ".")
local H = dofile(dir .. "/harness.lua")
local Mock = dofile(dir .. "/wowmock.lua")
local G = dofile(dir .. "/golden.lua")

local function firstDiff(a, b)
  local line, i = 1, 1
  local n = math.min(#a, #b)
  while i <= n and a:byte(i) == b:byte(i) do
    if a:byte(i) == 10 then line = line + 1 end
    i = i + 1
  end
  local function around(s) local from = s:sub(1, i):match(".*\n()") or 1; return s:sub(from, (s:find("\n", i, true) or #s + 1) - 1) end
  return line, around(a), around(b)
end

-- only the running game's data loads (Game.lua + the guard line at the top of every data file)
for _, c in ipairs({ { toc = 16001, game = "forever", data = "forever" }, { toc = 11509, game = "era", data = "era" },
  { toc = 20506, game = "tbc", data = "tbc" }, { toc = 30405, game = "other", data = "forever" } }) do
  local W = Mock.new(H, { toc = c.toc })
  local ns = H.loadAddon({ env = W.env })
  H.eq(ns.game, c.game, "toc " .. c.toc .. ": game")
  H.eq(ns.dataGame, c.data, "toc " .. c.toc .. ": data")
  H.ok(ns.Data.spells and ns.Data.spells.priest and ns.Data.sequences and ns.Data.wowhead, "toc " .. c.toc .. ": data loaded")
  -- the other game's files alone leave ns.Data empty
  H.eq(ns.Data.game and ns.Data.game.key, c.data, "toc " .. c.toc .. ": the game's rules")
  for _, other in ipairs({ "Forever", "Era", "TBC" }) do
    if other:lower() ~= c.data then
      local files = { "Game.lua" }
      for _, f in ipairs(H.tocFiles()) do if f:find("^Data/" .. other .. "/") or f == "Games/" .. other .. ".lua" then files[#files + 1] = f end end
      local ns2 = H.loadAddon({ env = Mock.new(H, { toc = c.toc }).env, files = files })
      H.ok(#files > 10 and ns2.Data.spells == nil and ns2.Data.sequences == nil and ns2.Data.meta == nil and ns2.Data.game == nil,
        "toc " .. c.toc .. ": " .. other .. " data does not load")
    end
  end
end

local t0 = os.clock()
for _, game in ipairs({ "forever", "era", "tbc" }) do
  local want = H.readFile(G.path(H, game))
  if H.ok(want ~= nil, "missing tests/golden/" .. game .. ".json") then
    local got = G.build(H, Mock, game)
    if not H.ok(got == want, game .. ": output differs from tests/golden/" .. game .. ".json") then
      local line, g, w = firstDiff(got, want)
      print(string.format("  %s: first difference at line %d\n    got:      %s\n    expected: %s", game, line, g, w))
    end
  end
end
print(string.format("(%.1f s)", os.clock() - t0))
os.exit(H.report("golden") and 0 or 1)
