-- Fly where the leader flew (owner, 25 Nov 2026; option flyLeader, off by default): the leader's TakeTaxiNode sends
-- "FL|destination|start|time"; a follower who later opens a flight master flies there once. On / off, fresh / stale,
-- destination missing or unreachable, too expensive, combat, Shift, a stranger, used once, the same-window sync unchanged.
local dir = (arg[0]:match("^(.*)/[^/]+$") or ".")
local H = dofile(dir .. "/harness.lua")
local Mock = dofile(dir .. "/wowmock.lua")

local PAL = { class = "PALADIN", race = "Scourge", level = 20 }
local PRI = { class = "PRIEST", race = "Scourge", level = 20 }
local HUN = { class = "HUNTER", race = "Orc", level = 20 }
local function boot(me)
  local lead = me == "Dorin"
  local W = Mock.new(H, { name = me, class = lead and "PALADIN" or "PRIEST", race = "Scourge", level = 20,
    party = lead and { party1 = "Anna", party2 = "Bo" } or { party1 = "Dorin", party2 = "Bo" },
    partyInfo = lead and { party1 = PRI, party2 = HUN } or { party1 = PAL, party2 = HUN } })
  local ns = H.loadAddon({ env = W.env })
  W.fire("ADDON_LOADED", "WoWBoxer"); W.fire("PLAYER_LOGIN")
  local sq = ns.State.newSquad({ name = "Trio", members = {
    { name = "Dorin", cls = "paladin", race = "undead", role = "tank", leader = true },
    { name = "Anna", cls = "priest", race = "undead", role = "healer" },
    { name = "Bo", cls = "hunter", race = "orc", role = "ranged" } } })
  ns.Core.db.squads = { sq }; ns.Core.db.active = sq.id
  -- the flight master: Stormwind (here), Lakeshire (reachable), Darkshire (known, not reachable), Ironforge (expensive)
  W.nodes = { { "Stormwind", "CURRENT", 0 }, { "Lakeshire", "REACHABLE", 600 }, { "Darkshire", "DISTANT", 800 }, { "Ironforge", "REACHABLE", 50000 } }
  W.env.NumTaxiNodes = function() return #W.nodes end
  W.env.TaxiNodeName = function(i) return W.nodes[i] and W.nodes[i][1] end
  W.env.TaxiNodeGetType = function(i) return W.nodes[i] and W.nodes[i][2] end
  W.env.TaxiNodeCost = function(i) return W.nodes[i] and W.nodes[i][3] or 0 end
  W.took = {}
  W.env.TakeTaxiNode = function(i) W.took[#W.took + 1] = i; return true end
  W.env.GetServerTime = function() return 1795440000 end
  W.now = 1000
  return W, ns
end
local function msg(W, from, text) W.fire("CHAT_MSG_ADDON", "WBXA", text, "PARTY", from) end
local function chat(W, pat) for _, m in ipairs(W.chat) do if m:find(pat, 1, true) then return m end end return nil end
local function open(W) W.took = {}; W.fire("TAXIMAP_OPENED"); local t = W.took[1]; W.fire("TAXIMAP_CLOSED"); return t end

-- ------------------------------------------------------------------ the option
do
  local W, ns = boot("Anna")
  local AU = ns.Auto
  H.eq(AU.on("flyLeader"), false, "off by default")
  H.ok(AU.BY_KEY.flyLeader and AU.BY_KEY.flyLeader[3] == "Followers: when you open a flight master, fly where the leader just flew.", "its one line")
  AU.preset(); H.eq(AU.on("flyLeader"), false, "not in the Levelling squad preset")
  AU.defaults(); H.eq(AU.on("flyLeader"), false, "not in Default")
  AU.setAll(true); H.eq(AU.on("flyLeader"), true, "All on: on")
  AU.setAll(false)
  -- the Automation page: a tick
  ns.UI.Open("automation")
  local tick
  for _, c in ipairs(ns.UI.panels.automation.ticks) do if c.key == "flyLeader" then tick = c end end
  if H.ok(tick, "a tick on the Automation page") then tick:Click(); H.ok(AU.on("flyLeader"), "the tick turns it on") end
  -- share strings and the settings list
  local res = ns.Share.import(ns.Core.exportString())
  local has = false
  for _, k in ipairs(res.auto.on) do if k == "flyLeader" then has = true end end
  H.ok(has, "the share string carries it")
  AU.set("flyLeader", false); ns.Core.applyImport(res)
  H.ok(AU.on("flyLeader"), "importing it turns it on")
  local text = ns.Settings.encode()
  H.ok(text:find("flyLeader", 1, true), "the settings text carries it")
  AU.set("flyLeader", false)
  ns.Settings.BY_KEY.auto[4](text:match("auto=([^;]*)"))
  H.ok(AU.on("flyLeader"), "the settings text applies it")
end

-- ------------------------------------------------------------------ leader: the hook sends the destination
do
  local W, ns = boot("Dorin")
  W.sent = {}
  W.nodes[1][2], W.nodes[2][2] = "CURRENT", "REACHABLE"
  ns.Auto.leaderFlew(2)
  local m
  for _, x in ipairs(W.sent) do if x.msg:find("^FL|") then m = x.msg end end
  H.eq(m, "FL|Lakeshire|Stormwind|1795440000", "leader: destination, start and time (data only)")
  local W2, ns2 = boot("Anna")
  W2.sent = {}
  ns2.Auto.leaderFlew(2)
  H.eq(#W2.sent, 0, "a follower sends nothing")
end

-- ------------------------------------------------------------------ follower
do
  local W, ns = boot("Anna")
  local AU = ns.Auto
  -- off: remembered, not flown
  msg(W, "Dorin", "FL|Lakeshire|Stormwind|1795440000")
  H.eq(open(W), nil, "option off: no flight")
  AU.set("flyLeader", true)
  -- on, fresh: flies once
  msg(W, "Dorin", "FL|Lakeshire|Stormwind|1795440000")
  H.eq(open(W), 2, "on, fresh: flies to Lakeshire")
  H.ok(ns.Core.db.log[#ns.Core.db.log].m:find("Took the flight to Lakeshire like Dorin", 1, true), "one log line: Took the flight")
  H.eq(open(W), nil, "used up: not again at the next flight master")
  -- stale
  msg(W, "Dorin", "FL|Lakeshire|Stormwind|1795440000")
  W.now = W.now + 601
  H.eq(open(W), nil, "older than 10 minutes: no flight")
  H.eq(AU.lastFlight, nil, "and forgotten")
  -- missing / unreachable
  W.chat = {}
  msg(W, "Dorin", "FL|Booty Bay|Stormwind|1795440000")
  H.eq(open(W), nil, "a flight path you lack: no flight")
  H.ok(chat(W, "You don't know the flight path to Booty Bay."), "one line: You don't know the flight path to X")
  W.chat = {}
  msg(W, "Dorin", "FL|Darkshire|Stormwind|1795440000")
  H.eq(open(W), nil, "not reachable from here: no flight")
  H.ok(chat(W, "You don't know the flight path to Darkshire."), "the same line")
  -- too expensive
  msg(W, "Dorin", "FL|Ironforge|Stormwind|1795440000")
  H.eq(open(W), nil, "above the gold limit: no flight")
  H.ok(AU.flyLast:find("more than the limit", 1, true), "logged why")
  -- already there
  msg(W, "Dorin", "FL|Stormwind|Lakeshire|1795440000")
  H.eq(open(W), nil, "you are there already: no flight")
  -- combat and Shift: not flown, kept for the next flight master
  msg(W, "Dorin", "FL|Lakeshire|Stormwind|1795440000")
  W.combat = true
  H.eq(open(W), nil, "in combat: never")
  W.combat = false
  W.mods.shift = true
  H.eq(open(W), nil, "Shift held: skipped")
  W.mods.shift = false
  H.eq(open(W), 2, "afterwards: flies")
  -- a stranger, a squad member who is not the leader, a leader who left the party
  msg(W, "Stranger", "FL|Lakeshire|Stormwind|1795440000")
  H.eq(open(W), nil, "a stranger's flight: ignored")
  msg(W, "Bo", "FL|Lakeshire|Stormwind|1795440000")
  H.eq(open(W), nil, "not the leader: ignored")
  msg(W, "Dorin", "FL|Lakeshire|Stormwind|1795440000")
  W.party.party1 = nil
  H.eq(open(W), nil, "the leader left the party: no flight")
  W.party.party1 = "Dorin"
  -- the old same-window sync is unchanged (Follow dialogs)
  AU.set("dialog", true)
  W.took = {}
  W.fire("TAXIMAP_OPENED")
  msg(W, "Dorin", "D|taxi|t|2|Lakeshire")
  H.eq(W.took[1], 2, "same window open: the leader's flight is repeated at once")
  W.fire("TAXIMAP_CLOSED")
  W.took = {}
  msg(W, "Dorin", "D|taxi|t|2|Lakeshire")
  H.eq(W.took[1], nil, "no flight map open: nothing")
  -- a flight repeated through the window is not repeated again at the next flight master
  W.fire("TAXIMAP_OPENED")
  W.took = {}
  msg(W, "Dorin", "FL|Lakeshire|Stormwind|1795440000")
  msg(W, "Dorin", "D|taxi|t|2|Lakeshire")
  H.eq(W.took[1], 2, "the map was open when the leader flew: the same-window sync flies")
  W.fire("TAXIMAP_CLOSED")
  H.eq(open(W), nil, "flown through the same-window sync: used up")
  -- diagnose
  local d = ns.Core.selftest(true)
  H.ok(d.auto.flight and d.auto.flight.takeTaxi == true and d.auto.flight.last, "diagnose: TakeTaxiNode probe and the last decision")
end
-- the leader opening a flight master flies nowhere by itself
do
  local W, ns = boot("Dorin")
  ns.Auto.set("flyLeader", true)
  ns.Auto.lastFlight = { dest = "Lakeshire", at = W.now, from = "Bo" }
  H.eq(open(W), nil, "the leader: never")
end

os.exit(H.report("flight") and 0 or 1)
