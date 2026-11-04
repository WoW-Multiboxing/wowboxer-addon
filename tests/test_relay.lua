-- Team relay (WoWBoxer/Relay.lua) and the team panel extras (Team.lua X messages, away): whispers forwarded to the
-- leader, GM tag + sound, follow-broke warning with its exceptions, the shared sell list, gold / bags / away.
-- Display and settings only: nothing here may cast, target, move, follow or accept.
local dir = (arg[0]:match("^(.*)/[^/]+$") or ".")
local H = dofile(dir .. "/harness.lua")
local Mock = dofile(dir .. "/wowmock.lua")

local PAL = { class = "PALADIN", race = "Scourge", level = 20 }
local PRI = { class = "PRIEST", race = "Scourge", level = 20 }
local HUN = { class = "HUNTER", race = "Orc", level = 20 }
local function boot(me)
  local party = me == "Dorin" and { party1 = "Anna", party2 = "Bo" } or { party1 = "Dorin", party2 = "Bo" }
  local info = me == "Dorin" and { party1 = PRI, party2 = HUN } or { party1 = PAL, party2 = HUN }
  local W = Mock.new(H, { name = me, class = me == "Dorin" and "PALADIN" or "PRIEST", race = "Scourge", level = 20, party = party, partyInfo = info })
  local ns = H.loadAddon({ env = W.env })
  W.fire("ADDON_LOADED", "WoWBoxer"); W.fire("PLAYER_LOGIN")
  local sq = ns.State.newSquad({ name = "Trio", members = {
    { name = "Dorin", cls = "paladin", race = "undead", role = "tank", leader = true },
    { name = "Anna", cls = "priest", race = "undead", role = "healer" },
    { name = "Bo", cls = "hunter", race = "orc", role = "ranged" } } })
  ns.Core.db.squads = { sq }; ns.Core.db.active = sq.id
  W.sounds, W.warnings = {}, {}
  W.env.PlaySound = function(k) W.sounds[#W.sounds + 1] = k end
  W.env.RaidWarningFrame = {}
  W.env.RaidNotice_AddMessage = function(_, text) W.warnings[#W.warnings + 1] = text end
  W.env.SOUNDKIT = { RAID_WARNING = 8959 }
  W.env.ChatTypeInfo = { RAID_WARNING = { r = 1, g = 0.3, b = 0.1 } }
  W.env.UnitIsDeadOrGhost = function() return W.dead end
  W.env.UnitOnTaxi = function() return W.taxi end
  W.env.UnitIsAFK = function(u) return W.afk and W.afk[u] end
  W.env.UnitIsDND = function() return false end
  W.env.GetServerTime = function() return W.server or 1000 end
  W.env.GetMoney = function() return W.money or 0 end
  W.env.GetContainerNumSlots = function(bag) return bag <= 1 and 16 or 0 end
  W.env.GetContainerNumFreeSlots = function(bag) return bag <= 1 and (W.free or 8) or 0, 0 end
  W.env.C_Container = nil
  -- nothing in the relay may act: any of these being called is a failure
  W.acted = {}
  for _, fn in ipairs({ "CastSpellByName", "TargetUnit", "FollowUnit", "AcceptGroup", "AcceptQuest", "UseContainerItem", "InteractUnit" }) do
    W.env[fn] = function() W.acted[#W.acted + 1] = fn end
  end
  return W, ns
end
local function relayed(W, kind)
  for _, m in ipairs(W.sent) do if m.prefix == "WBXR" and m.msg:sub(1, #kind) == kind then return m.msg end end
  return nil
end
local function deliver(W, from, text) W.fire("CHAT_MSG_ADDON", "WBXR", text, "PARTY", from) end

-- ------------------------------------------------------------------ whispers
do
  local A = boot("Anna")
  H.ok(A.prefixes.WBXR, "the relay prefix is registered")
  local W2, nsA = boot("Anna")
  local AU = nsA.Auto
  H.ok(AU.on("whispers") and AU.on("followWarn") and not AU.on("shareSell"), "defaults: whispers and follow warning on, sell sharing off")
  H.ok(not AU.anyOn(), "display options do not count as automation on (nudge, OFF badge)")
  W2.fire("CHAT_MSG_WHISPER", "hi |cff1eff00|Hitem:2589::::::::20:::::::|h[Linen Cloth]|h|r there", "Stranger-Realm", "", "", "", "")
  H.eq(relayed(W2, "W|"), "W|0|Stranger|hi [Linen Cloth] there", "a follower forwards a stranger's whisper as plain text")
  W2.sent = {}
  W2.fire("CHAT_MSG_WHISPER", "inc", "Dorin", "", "", "", "")
  H.eq(relayed(W2, "W|"), nil, "whispers between squad members are not forwarded")
  W2.env.issecretvalue = function(v) return v == "SECRET" end
  W2.fire("CHAT_MSG_WHISPER", "SECRET", "Stranger", "", "", "", "")
  H.eq(relayed(W2, "W|"), nil, "a secret (chat lockdown) text is never forwarded")
  W2.fire("CHAT_MSG_WHISPER", "Hello, this is a Game Master", "Blizz", "", "", "", "GM")
  H.eq(relayed(W2, "W|1|"), "W|1|Blizz|Hello, this is a Game Master", "GM flag travels")
  AU.set("whispers", false); W2.sent = {}
  W2.fire("CHAT_MSG_WHISPER", "hi", "Stranger", "", "", "", "")
  H.eq(relayed(W2, "W|"), nil, "option off: nothing is forwarded")
  local long = string.rep("x", 400)
  AU.set("whispers", true)
  W2.fire("CHAT_MSG_WHISPER", long, "Stranger", "", "", "", "")
  H.ok(#relayed(W2, "W|") <= 255, "a long whisper fits one addon message")
  H.eq(#W2.acted, 0, "follower: nothing acted")
end
do
  local W, ns = boot("Dorin")
  deliver(W, "Anna", "W|0|Stranger|wts linen")
  H.ok(W.chatHas("%[Anna%] Stranger whispers: wts linen"), "the leader shows a forwarded whisper")
  H.eq(#W.sounds, 0, "no sound for a normal whisper")
  deliver(W, "Anna", "W|1|Blizz|Hello")
  H.ok(W.chatHas("<GM>") and #W.sounds == 1 and #W.warnings == 1, "a GM whisper is tagged, with a sound and a warning")
  W.chat = {}
  deliver(W, "Mallory", "W|0|Stranger|fake")
  H.ok(not W.chatHas("fake"), "a non-squad sender is ignored")
  deliver(W, "Anna", "W|x|broken")
  H.ok(not W.chatHas("broken"), "a malformed message is ignored")
  -- the leader's own whispers are not sent anywhere
  W.sent = {}
  W.fire("CHAT_MSG_WHISPER", "hi", "Stranger", "", "", "", "")
  H.eq(relayed(W, "W|"), nil, "the leader does not forward")
  H.eq(#W.acted, 0, "leader: nothing acted")
  local _ = ns
end

-- ------------------------------------------------------------------ follow warning
do
  local W, ns = boot("Anna")
  local RL = ns.Relay
  RL.zonedAt = -1e9
  W.fire("AUTOFOLLOW_BEGIN", "Dorin"); W.fire("AUTOFOLLOW_END"); W.flush()
  H.eq(relayed(W, "F|"), "F|1", "follow broke out of combat: the follower tells the leader")
  W.sent = {}
  W.fire("AUTOFOLLOW_BEGIN", "Dorin"); W.fire("AUTOFOLLOW_END"); W.fire("AUTOFOLLOW_BEGIN", "Dorin"); W.flush()
  H.eq(relayed(W, "F|"), nil, "follow resumed within a second: no warning")
  W.fire("AUTOFOLLOW_END")
  W.inCombatUnit = true; W.flush(); W.inCombatUnit = false
  H.eq(relayed(W, "F|"), nil, "in combat: no warning")
  W.dead = true; W.fire("AUTOFOLLOW_END"); W.flush(); W.dead = false
  H.eq(relayed(W, "F|"), nil, "dead: no warning")
  W.taxi = true; W.fire("AUTOFOLLOW_END"); W.flush(); W.taxi = false
  H.eq(relayed(W, "F|"), nil, "on a flight: no warning")
  W.fire("PLAYER_ENTERING_WORLD"); W.fire("AUTOFOLLOW_END"); W.flush()
  H.eq(relayed(W, "F|"), nil, "loading screen: no warning")
  RL.zonedAt = -1e9
  ns.Auto.set("followWarn", false); W.fire("AUTOFOLLOW_END"); W.flush()
  H.eq(relayed(W, "F|"), nil, "option off: no warning")
end
do
  local W, ns = boot("Dorin")
  ns.Relay.zonedAt = -1e9
  deliver(W, "Anna", "F|1")
  H.ok(#W.warnings == 1 and W.warnings[1]:find("Anna stopped following") and #W.sounds == 1, "the leader gets a warning and a sound")
  deliver(W, "Anna", "F|1")
  H.eq(#W.warnings, 1, "not again within a few seconds")
  W.now = (W.now or 0) + 100
  W.taxi = true; deliver(W, "Bo", "F|1"); W.taxi = false
  H.eq(#W.warnings, 1, "the leader is on a flight: no warning")
  W.inCombatUnit = true; deliver(W, "Bo", "F|1"); W.inCombatUnit = false
  H.eq(#W.warnings, 1, "the leader is in combat: no warning")
  deliver(W, "Mallory", "F|1")
  H.eq(#W.warnings, 1, "a stranger cannot raise it")
  H.eq(#W.acted, 0, "the warning never acts (no follow, no target)")
end

-- ------------------------------------------------------------------ shared sell list
do
  local W, ns = boot("Anna")
  local RL, AU = ns.Relay, ns.Auto
  RL.slash("add |cffffffff|Hitem:2589::::::::20:::::::|h[Linen Cloth]|h|r")
  H.eq(RL.sellList()[1], "Linen Cloth", "/wbx sell add takes an item link")
  H.eq(relayed(W, "L|"), nil, "sharing off: the list is not sent")
  AU.set("shareSell", true)
  W.server = 2000
  RL.slash("add Light Leather")
  local m = relayed(W, "L|")
  H.eq(m, "L|2000|1|1|Linen Cloth;Light Leather", "sharing on: the list is sent with its time")
  RL.slash("add linen cloth")
  H.eq(#RL.sellList(), 2, "no duplicates (any case)")
  RL.slash("remove Light Leather")
  H.eq(table.concat(RL.sellList(), ","), "Linen Cloth", "/wbx sell remove")
  -- a newer list from the squad replaces ours; an older one does not
  deliver(W, "Dorin", "L|1500|1|1|Old Thing")
  H.eq(RL.sellList()[1], "Linen Cloth", "an older list is ignored")
  deliver(W, "Dorin", "L|9000|1|2|Wool Cloth;Sil")
  H.eq(RL.sellList()[1], "Linen Cloth", "half a list changes nothing")
  deliver(W, "Dorin", "L|9000|2|2|k Cloth")
  H.eq(table.concat(RL.sellList(), ","), "Wool Cloth,Silk Cloth", "both parts: the newer list replaces ours")
  deliver(W, "Mallory", "L|99999|1|1|Hearthstone")
  H.eq(table.concat(RL.sellList(), ","), "Wool Cloth,Silk Cloth", "a stranger's list is ignored")
  AU.set("shareSell", false)
  deliver(W, "Dorin", "L|99999|1|1|Something")
  H.eq(table.concat(RL.sellList(), ","), "Wool Cloth,Silk Cloth", "sharing off: lists from the squad are ignored")
  H.eq(#W.acted, 0, "receiving a list never sells (only a merchant this window opens does)")
end

-- ------------------------------------------------------------------ team panel: gold, bags, away
do
  local W, ns = boot("Dorin")
  local TM = ns.Team
  W.money, W.free = 1234567, 1
  local x = TM.collectExtra()
  H.ok(x.gold == 123 and x.free == 2 and x.slots == 32, "gold in whole gold, free slots over normal bags")
  H.eq(TM.encodeExtra(x), "X|123|2|32", "X message")
  H.eq(TM.decodeExtra("X|5|abc|1"), nil, "malformed X is ignored")
  W.fire("CHAT_MSG_ADDON", "WBX1", "X|45|0|64", "PARTY", "Anna")
  W.afk = { party2 = true }
  local rows = TM.rows()
  local by = {}
  for _, r in ipairs(rows) do by[r.name] = r end
  H.ok(by.Anna.extra and by.Anna.extra.gold == 45, "Anna's gold from her X message")
  local function has(r, word) for _, f in ipairs(r.flags) do if f[1] == word then return true end end return false end
  H.ok(has(by.Anna, "bags full"), "0 free slots: bags full")
  H.ok(has(by.Dorin, "bags full"), "my own 2 free slots: bags full")
  H.ok(has(by.Bo, "away"), "AFK from the party unit: away")
  H.ok(not has(by.Anna, "away"), "not AFK: no away")
  H.eq(ns.TeamFrame.bagsText(by.Anna.extra), "|cffffd10045g|r · 0", "panel text: gold and free slots")
  H.eq(ns.TeamFrame.bagsText(nil), "", "unknown: empty")
end

os.exit(H.report("relay") and 0 or 1)
