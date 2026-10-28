-- Three clients in one party (docs/squad-overhaul.md §3.3): team status with readiness + version, "Send squad to my
-- party" as an offer (Review / Ignore, import only after a click on that client), leader preset offers, the session
-- card, and that no message ever makes a client act by itself.
local dir = (arg[0]:match("^(.*)/[^/]+$") or ".")
local H = dofile(dir .. "/harness.lua")
local Mock = dofile(dir .. "/wowmock.lua")

local NAMES = { "Dorin", "Wowtwo", "Lock" }
local CLASS = { Dorin = "PALADIN", Wowtwo = "PRIEST", Lock = "WARLOCK" }
local clients = {}
for i, name in ipairs(NAMES) do
  local party, info = {}, {}
  local k = 0
  for _, other in ipairs(NAMES) do
    if other ~= name then
      k = k + 1
      party["party" .. k] = other
      info["party" .. k] = { class = CLASS[other], race = "Scourge", level = 20, leader = other == "Dorin" }
    end
  end
  local W = Mock.new(H, { name = name, class = CLASS[name], race = "Scourge", level = 20, party = party, partyInfo = info })
  W.player.leader = name == "Dorin"
  local ns = H.loadAddon({ env = W.env })
  W.fire("ADDON_LOADED", "WoWBoxer"); W.fire("PLAYER_LOGIN")
  ns.Core.cdb.guide = "done"
  for _, s in ipairs(ns.Data.spells[CLASS[name]:lower()]) do if s.level <= 20 and s.gate ~= "talent" then W.known[s.name] = true end end
  clients[i] = { W = W, ns = ns, name = name }
end
local A, B, C = clients[1], clients[2], clients[3]

--- Deliver everything each client sent to the others (as the party channel would), until nobody sends more.
local function deliver()
  for _ = 1, 50 do
    local any = false
    for _, from in ipairs(clients) do
      local list = from.W.sent
      from.W.sent = {}
      for _, m in ipairs(list) do
        any = true
        for _, to in ipairs(clients) do
          if to ~= from then to.W.fire("CHAT_MSG_ADDON", m.prefix, m.msg, m.chan, from.name .. "-Realm") end
        end
      end
    end
    for _, c in ipairs(clients) do c.W.flush() end
    if not any then
      local timers = 0
      for _, c in ipairs(clients) do timers = timers + #c.W.timers end
      if timers == 0 then return end
    end
  end
end
local function calls(c) local t = {}; for k, v in pairs(c.W.calls) do t[k] = v end return t end
local function same(a, b) for k, v in pairs(a) do if b[k] ~= v then return false end end for k, v in pairs(b) do if a[k] ~= v then return false end end return true end
local function errors(ns)
  local n = {}
  for _, e in ipairs(ns.Core.db.log) do if e.l == "error" then n[#n + 1] = e.m end end
  return table.concat(n, " | ")
end
local function logHas(ns, pat) for _, e in ipairs(ns.Core.db.log) do if e.m:find(pat) then return true end end return false end

-- ------------------------------------------------------------------ A builds the squad from the party
A.ns.UI.Open("squad")
H.eq(A.ns.SquadPages.addParty(), 2, "A: Add my party")
local sA = A.ns.Core.me()
H.eq(#sA.members, 3, "A: squad of three")
H.eq(A.ns.State.leaderOf(sA).name, "Dorin", "A: Dorin leads (party leader)")
for _, m in ipairs(sA.members) do if m.name == "Wowtwo" then m.role = "healer" end end
A.ns.State.savePreset(sA, "Questing")
for _, m in ipairs(sA.members) do m.leader = m.name == "Wowtwo" end
A.ns.State.savePreset(sA, "Wowtwo leads")
A.ns.State.applyPreset(sA, sA.presets[1].id)
A.ns.Core.changed()

-- B and C have only their solo squads
B.ns.UI.Open("keys"); C.ns.UI.Open("keys")
local bSquads, cSquads = #B.ns.Core.db.squads, #C.ns.Core.db.squads
local before = { calls(A), calls(B), calls(C) }

-- ------------------------------------------------------------------ Send squad to my party = an offer
A.ns.UI.Select("squad")
local home = A.ns.UI.panels.squad.frames.home
H.ok(home.send:IsEnabled(), "A: Send squad to my party enabled when grouped")
home.send:Click()
H.ok(#A.W.timers > 0 or #A.W.sent > 0, "A: chunks queued")
deliver()
local chunks = 0
H.ok(B.ns.Sync.frame and B.ns.Sync.frame:IsShown(), "B: offer card shown")
H.ok(C.ns.Sync.frame and C.ns.Sync.frame:IsShown(), "C: offer card shown")
H.ok(B.ns.Sync.frame.text:GetText():find("Dorin", 1, true) and B.ns.Sync.frame.text:GetText():find("(3)", 1, true), "B: who shares what")
H.eq(#B.ns.Core.db.squads, bSquads, "B: nothing imported before a click")
H.ok(logHas(A.ns, "offered squad") and logHas(B.ns, "squad offer from Dorin"), "logged on both sides")
-- B reviews and imports
B.ns.Sync.accept()
local share = B.ns.UI.panels.share
H.ok(share:IsVisible(), "B: Review opens the Share preview")
H.ok(share.result:GetText():find("Valid", 1, true) ~= nil, "B: preview says valid")
H.eq(#B.ns.Core.db.squads, bSquads, "B: still nothing imported after Review")
share.importBtn:Click()
local sB, meB = B.ns.Core.me()
H.eq(sB.id, sA.id, "B: imported after the Import click")
H.eq(meB.name, "Wowtwo", "B: picked itself by name")
H.eq(#sB.presets, 2, "B: presets came along")
-- C ignores
C.ns.Sync.dismiss()
H.ok(not C.ns.Sync.frame:IsShown(), "C: Ignore closes the card")
H.eq(#C.ns.Core.db.squads, cSquads, "C: nothing changed")
H.ok(logHas(C.ns, "ignored squad offer"), "C: ignore logged")

-- ------------------------------------------------------------------ a damaged or foreign message is no offer
C.W.fire("CHAT_MSG_ADDON", "WBX1", "Q|abc|1|1|!WBX:1!garbage!00000000", "PARTY", "Dorin-Realm")
H.ok(not C.ns.Sync.frame:IsShown(), "C: damaged squad: no offer")
C.W.fire("CHAT_MSG_ADDON", "WBX1", "Q|abc|1|1|" .. A.ns.Core.exportString(), "PARTY", "Stranger-Realm")
H.ok(not C.ns.Sync.frame:IsShown(), "C: not from my party: no offer")
C.W.fire("CHAT_MSG_ADDON", "WBX1", "Q|abc|5|999|x", "PARTY", "Dorin-Realm")
H.ok(not C.ns.Sync.frame:IsShown(), "C: too many chunks: ignored")

-- ------------------------------------------------------------------ leader preset switch = an offer
local p2 = sA.presets[2]
A.ns.SquadPages.choosePreset(p2.id)
H.eq(A.ns.State.leaderOf(sA).name, "Wowtwo", "A: Wowtwo leads after the switch")
deliver()
H.ok(B.ns.Sync.frame:IsShown() and B.ns.Sync.frame.text:GetText():find("Wowtwo leads", 1, true), "B: preset offer")
H.eq(B.ns.State.leaderOf(sB).name, "Dorin", "B: leader unchanged before the click")
H.ok(not C.ns.Sync.frame:IsShown(), "C: no offer (does not have that squad)")
B.ns.Sync.accept()
H.eq(B.ns.State.leaderOf(sB).name, "Wowtwo", "B: Apply switches the leader")
H.ok(select(2, B.ns.Core.me()).leader, "B: this character leads now")
H.ok(B.ns.Core.compute().macros.changes > 0, "B: keys wait for Update keys (not changed by the message)")

-- ------------------------------------------------------------------ team status: readiness + version, session card
B.ns.Core.VERSION = "0.0.9"
for _, c in ipairs(clients) do c.ns.Team.send(true); c.ns.Team.sendReady(true) end
deliver()
local rows = A.ns.Squad.readiness()
local rowB
for _, r in ipairs(rows) do if r.m.name == "Wowtwo" then rowB = r end end
H.ok(rowB.signal, "A: Wowtwo reports")
H.ok(rowB.ready and rowB.ready.keys > 0, "A: sees Wowtwo's keys to update")
H.eq(rowB.version, "0.0.9", "A: sees Wowtwo's version")
A.ns.SquadPages.select(A.ns.UI.panels.squad, "ready")
local note = A.ns.UI.panels.squad.frames.ready.note:GetText()
H.ok(note:find("Wowtwo runs WoWBoxer 0.0.9", 1, true) ~= nil, "A: version check on Readiness")
A.ns.SquadPages.select(A.ns.UI.panels.squad, "home")
H.ok(home.hints:GetText():find("Wowtwo runs WoWBoxer 0.0.9", 1, true) ~= nil, "A: version check on Home")
local text = A.ns.Sync.sessionText()
H.ok(text and text:find("2/3 online", 1, true) ~= nil, "A: session card counts who reports (C has no squad): " .. tostring(text))
H.ok(text:find("Wowtwo", 1, true) ~= nil and text:find("Update keys", 1, true) ~= nil, "A: session card names who needs an update: " .. text)
H.ok(A.ns.Sync.sessionCard(), "A: session card shown")
H.ok(A.ns.Sync.frame:IsShown(), "A: card visible")
A.ns.Sync.accept()
H.ok(A.ns.UI.panels.squad:IsVisible(), "A: Open squad from the card")

-- ------------------------------------------------------------------ hard rules
H.ok(same(before[1], calls(A)), "A: no protected calls from sync")
H.ok(same(before[3], calls(C)), "C: no protected calls from messages")
local bc = calls(B)
H.ok(bc.CreateMacro == nil and bc.EditMacro == nil and bc.PlaceAction == nil and bc.SetBinding == nil, "B: imports and presets write nothing to the game")
for _, c in ipairs(clients) do H.eq(errors(c.ns), "", c.name .. ": no errors") end

os.exit(H.report("sync") and 0 or 1)
