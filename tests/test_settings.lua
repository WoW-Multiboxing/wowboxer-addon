-- The same settings on all characters (bug sweep 9 Nov 2026). WoWBoxerDB is per WoW account and each of the owner's
-- characters is on its own account, so "Advanced" on Rap was not on for Rip and Rup. A change offers "Use the same on
-- my other characters"; the others confirm with one click. Data only (rule 2): only known keys and values travel,
-- "Everyone" never does, and only squad members in the party can offer them.
local dir = (arg[0]:match("^(.*)/[^/]+$") or ".")
local H = dofile(dir .. "/harness.lua")
local Mock = dofile(dir .. "/wowmock.lua")

-- Forever names: UnitName "Rip" + realm "And"; addon senders "Rip And"
local NAMES = { "Rip", "Rup", "Rap" }
local function boot(me)
  local party, info, i = {}, {}, 0
  for _, n in ipairs(NAMES) do
    if n ~= me then i = i + 1; party["party" .. i] = n; info["party" .. i] = { class = "PRIEST", race = "Human", level = 20, realm = "And", leader = n == "Rip" } end
  end
  local W = Mock.new(H, { name = me, class = me == "Rip" and "PALADIN" or "PRIEST", race = "Human", faction = "Alliance", level = 20,
    party = party, partyInfo = info })
  local ns = H.loadAddon({ env = W.env })
  W.fire("ADDON_LOADED", "WoWBoxer"); W.fire("PLAYER_LOGIN")
  local sq = ns.State.newSquad({ name = "Trio", members = {
    { name = "Rip", cls = "paladin", race = "human", role = "tank", leader = true },
    { name = "Rup", cls = "priest", race = "human", role = "healer", unit = "party1" },
    { name = "Rap", cls = "priest", race = "human", role = "ranged", unit = "party1" } } })
  ns.Core.db.squads = { sq }; ns.Core.db.active = sq.id
  ns.Settings.Init()
  W.sent = {}
  return W, ns
end
local function deliver(from, toW, sender)
  local n = 0
  for _, m in ipairs(from.sent) do if m.prefix == "WBX1" then toW.fire("CHAT_MSG_ADDON", m.prefix, m.msg, "PARTY", sender); n = n + 1 end end
  return n
end
local function card(ns, kind) for _, q in ipairs(ns.Sync.queue) do if q.kind == kind then return q end end end

local Wrip, rip = boot("Rip")
local Wrup, rup = boot("Rup")
local Wrap, rap = boot("Rap")
local ST = rip.Settings

-- encode / decode: data only
do
  local t = ST.decode(ST.encode())
  H.ok(t and t.adv == "0" and t.team == "1" and t.from == "squad", "my settings as text and back: " .. ST.encode())
  H.eq(ST.decode("evil=1;adv=1").evil, nil, "unknown keys are dropped")
  H.eq(ST.decode("adv=1|x"), nil, "a text with | is not a settings message")
  H.eq(ST.decode(string.rep("a", 2000)), nil, "too long: not one")
  local d = rup.Settings.decode("adv=maybe;scale=5;from=everyone;auto=invite,evil;rew=nope")
  rup.Settings.apply(d, "test")
  H.ok(rup.Core.db.settings.advanced ~= true, "a bad value is not used (adv=maybe)")
  H.ok(rup.Core.db.settings.scale == nil, "a scale outside the list is not used")
  H.ok(rup.Core.db.settings.acceptFrom ~= "everyone", "Accept from Everyone is never taken from a message")
  H.ok(rup.Auto.on("invite") and not rup.Auto.BY_KEY.evil, "known automations are used, unknown ones dropped")
  rup.Auto.set("invite", false)
  rup.Settings.base = rup.Settings.encode()
  rip.Core.db.settings.acceptFrom = "everyone"
  H.eq(ST.decode(ST.encode()).from, nil, "Everyone never travels")
  rip.Core.db.settings.acceptFrom = nil
  ST.base = ST.encode()
end

-- Rip turns Advanced on: a card offers to copy it (after the changes settle)
rip.Core.db.settings.advanced = true
rip.Core.changed()
Wrip.flush()
local push = card(rip, "push")
H.ok(push ~= nil, "after a change: 'Use the same on your other characters?'")
rip.Core.changed(); Wrip.flush()
local pushes = 0
for _, q in ipairs(rip.Sync.queue) do if q.kind == "push" then pushes = pushes + 1 end end
H.eq(pushes, 1, "one card, not one per change")
-- Not now: nothing is sent
Wrip.sent = {}
while rip.Sync.queue[1] and rip.Sync.queue[1].kind ~= "push" do rip.Sync.dismiss() end
rip.Sync.accept()   -- Send
for _ = 1, 5 do Wrip.flush() end
H.ok(#Wrip.sent > 0, "Send: the settings go to the party (" .. #Wrip.sent .. " message(s))")
for _, m in ipairs(Wrip.sent) do H.ok(#m.msg <= 255, "each message fits 255") end
-- Rup and Rap get an offer card and use it with one click (Forever sender "Rip And")
for _, c in ipairs({ { Wrup, rup, "Rup" }, { Wrap, rap, "Rap" } }) do
  local W, ns, who = c[1], c[2], c[3]
  deliver(Wrip, W, "Rip And")
  local x = card(ns, "settings")
  H.ok(x and x.from == "Rip" and x.text:find("Advanced mode Advanced", 1, true), who .. ": the card says what changes: " .. tostring(x and x.text))
  H.ok(ns.Core.db.settings.advanced ~= true, who .. ": nothing changes before the click")
  while ns.Sync.queue[1] and ns.Sync.queue[1].kind ~= "settings" do ns.Sync.dismiss() end
  ns.Sync.accept()
  H.ok(ns.Core.db.settings.advanced == true and ns.Core.advanced(), who .. ": Use them → Advanced is on")
  -- the SavedVariable keeps it (after /reload)
  H.ok(W.env.WoWBoxerDB.settings.advanced == true, who .. ": saved in WoWBoxerDB.settings")
  -- what was just taken is not offered back
  ns.Core.changed(); W.flush()
  H.eq(card(ns, "push"), nil, who .. ": taking settings does not ask to send them back")
end

-- only squad members in the party
do
  local W, ns = boot("Rup")
  W.sent = {}
  Wrip.sent = {}
  rip.Settings.send(true)
  for _ = 1, 5 do Wrip.flush() end
  deliver(Wrip, W, "Stranger")
  H.eq(card(ns, "settings"), nil, "a stranger's settings are ignored")
  ns.Core.db.settings.advanced = true
  deliver(Wrip, W, "Rip And")
  H.eq(card(ns, "settings"), nil, "the same settings already: no card")
end

-- Send to my other characters also offers the settings
do
  local W, ns = boot("Rup")
  rip.Core.db.settings.animations = false
  Wrip.sent = {}
  rip.Sync.sendSquad(rip.Core.me())
  for _ = 1, 20 do Wrip.flush() end
  deliver(Wrip, W, "Rip And")
  H.ok(card(ns, "squad") and card(ns, "settings"), "Send to my other characters: a squad card and a settings card")
end

-- solo: no question (nobody to send to), and the Setup button says join a party
do
  local W = Mock.new(H, { name = "Solo", class = "MAGE", race = "Human", level = 10 })
  local ns = H.loadAddon({ env = W.env })
  W.fire("ADDON_LOADED", "WoWBoxer"); W.fire("PLAYER_LOGIN")
  ns.State.quickStart(ns.Core.db, ns.Core.cdb, ns.Core.playerInfo())
  ns.Settings.Init()
  ns.Core.db.settings.advanced = true
  ns.Core.changed(); W.flush()
  H.eq(card(ns, "push"), nil, "solo: no question")
  W.chat = {}
  ns.Settings.send()
  H.ok(W.chat[#W.chat] and W.chat[#W.chat]:find("Join a party", 1, true), "solo Send: told to join a party")
end

H.report("settings")
