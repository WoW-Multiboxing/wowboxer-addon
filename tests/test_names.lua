-- Character names (bug 5 Nov 2026, Forever live): Forever names are two-part ("Rip And", no realm) while old squads
-- hold the first name only ("Rip"). Every name match goes through Compat (baseName / nameKey / sameName / findByName):
-- party units, Sync offers, team status, automation senders, follow line, invite macros, finding "me", the squad page.
-- Also: SendAddonMessage result codes (Forever returns a code; pcall true is not success) and logged drops.
local dir = (arg[0]:match("^(.*)/[^/]+$") or ".")
local H = dofile(dir .. "/harness.lua")
local Mock = dofile(dir .. "/wowmock.lua")

-- ------------------------------------------------------------------ 1. the matcher itself
do
  local W = Mock.new(H, { name = "Rip And", class = "PALADIN" })
  local ns = H.loadAddon({ env = W.env })
  local C = ns.Compat
  H.eq(C.baseName("Rip And"), "Rip And", "baseName keeps the full Forever name")
  H.eq(C.baseName("  Rip   And-Realm "), "Rip And", "baseName: realm off, spaces trimmed and collapsed")
  H.eq(C.baseName("Dorin-Auberdine"), "Dorin", "baseName: Era realm off")
  H.eq(C.baseName(""), nil, "baseName: empty is nil")
  H.eq(C.baseName(nil), nil, "baseName: nil is nil")
  H.eq(C.nameKey("Rip And-93"), "rip and", "nameKey")
  H.eq(C.firstNameKey("Rip And"), "rip", "firstNameKey")
  H.ok(C.sameName("Rip", "Rip And"), "first name matches the full name")
  H.ok(C.sameName("Rip And", "rip"), "and the other way round, any case")
  H.ok(C.sameName("Rip And-Realm", "Rip And"), "realm ignored")
  H.ok(C.sameName("Rip-And", "Rip And"), "hyphen form (as the WTF folder shows it) still matches")
  H.ok(C.sameName("Dorin-Realm", "dorin"), "Era: Name-Realm vs Name")
  H.ok(not C.sameName("Rip And", "Rip Bob"), "two different full names never match")
  H.ok(not C.sameName("Rip", "Rup"), "two different first names never match")
  H.ok(not C.sameName("Rip", nil), "nil never matches")
  local list = { { name = "Rip" }, { name = "Rip And" } }
  H.eq(C.findByName(list, "Rip And"), list[2], "findByName: exact match wins over first name")
  H.eq(C.findByName(list, "Rip Bob"), list[1], "findByName: first name when no exact one")
  H.eq(C.findByName(list, "Rap And"), nil, "findByName: no match")
  -- the /invite line keeps the space
  H.eq(ns.Macros.inviteName({ name = "Rup  And " }), "Rup And", "inviteName: two-part name, single space")
  H.eq(ns.Macros.inviteName({ name = "Dorin", realm = "Auberdine" }), "Dorin-Auberdine", "inviteName: Era realm")
  local ok = ns.Rules.validateMacro("WBX Invite", "/invite Rup And\n/invite Rap And")
  H.ok(ok, "a /invite macro with two-part names is a valid macro")
end

-- ------------------------------------------------------------------ 2. three Forever clients, old first-name squads
local NAMES = { "Rip And", "Rup And", "Rap And" }
local SHORT = { ["Rip And"] = "Rip", ["Rup And"] = "Rup", ["Rap And"] = "Rap" }
local CLASS = { ["Rip And"] = "PALADIN", ["Rup And"] = "PRIEST", ["Rap And"] = "MAGE" }
local function build(senderForm, toc)
  local clients = {}
  for i, name in ipairs(NAMES) do
    local party, info, k = {}, {}, 0
    for _, other in ipairs(NAMES) do
      if other ~= name then
        k = k + 1
        party["party" .. k] = other
        info["party" .. k] = { class = CLASS[other], race = "Human", level = 20, leader = other == "Rip And" }
      end
    end
    local W = Mock.new(H, { toc = toc, name = name, class = CLASS[name], race = "Human", faction = "Alliance", level = 20, party = party, partyInfo = info })
    W.player.leader = name == "Rip And"
    local ns = H.loadAddon({ env = W.env })
    W.fire("ADDON_LOADED", "WoWBoxer")
    -- the saved squad from before the fix: first names only, no link from this character to its member
    local members = {}
    for _, n in ipairs(NAMES) do members[#members + 1] = { name = SHORT[n], cls = CLASS[n]:lower(), level = 20, leader = n == "Rip And" } end
    local s = ns.State.newSquad({ name = "And trio", faction = "alliance", members = members })
    ns.Core.db.squads = { s }; ns.Core.db.active = s.id
    W.fire("PLAYER_LOGIN")
    ns.Core.cdb.guide = "done"
    for _, sp in ipairs(ns.Data.spells[CLASS[name]:lower()]) do if sp.level <= 20 and sp.gate ~= "talent" then W.known[sp.name] = true end end
    clients[i] = { W = W, ns = ns, name = name }
  end
  local function deliver()
    for _ = 1, 60 do
      local any = false
      for _, from in ipairs(clients) do
        local list = from.W.sent
        from.W.sent = {}
        for _, m in ipairs(list) do
          any = true
          for _, to in ipairs(clients) do
            if to ~= from then to.W.fire("CHAT_MSG_ADDON", m.prefix, m.msg, m.chan, senderForm(from.name)) end
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
  return clients, deliver
end
local function logHas(ns, pat) for _, e in ipairs(ns.Core.db.log) do if e.m:find(pat) then return true end end return false end
local function errors(ns)
  local n = {}
  for _, e in ipairs(ns.Core.db.log) do if e.l == "error" then n[#n + 1] = e.m end end
  return table.concat(n, " | ")
end

for _, form in ipairs({ { "no realm", function(n) return n end }, { "with realm", function(n) return n .. "-Realm" end } }) do
  local tag = "[" .. form[1] .. "] "
  local clients, deliver = build(form[2])
  local A, B, Cc = clients[1], clients[2], clients[3]

  -- finding "me" in an old squad by first name
  local sA, meA = A.ns.Core.me()
  H.ok(meA ~= nil, tag .. "Rip And finds its member in the old first-name squad")
  H.eq(meA and meA.leader, true, tag .. "and leads")
  local _, meB = B.ns.Core.me()
  H.eq(meB and meB.cls, "priest", tag .. "Rup And finds Rup")

  -- party units by first name
  H.eq(A.ns.Squad.unitOf("Rup"), "party1", tag .. "unitOf(first name) finds the two-part party unit")
  H.eq(A.ns.Squad.unitOf("Rap And"), "party2", tag .. "unitOf(full name)")
  H.eq(B.ns.Squad.unitOf("Rip"), "party1", tag .. "Rup: the leader is party1")
  H.eq(B.ns.Squad.myReady().unit, 1, tag .. "Rup: readiness says the leader unit is right")
  H.eq(B.ns.Checklist and #B.ns.Checklist.items() > 0, true, tag .. "checklist builds")

  -- follow line
  local u, ahead, how = Cc.ns.Squad.lineFor(Cc.ns.Core.me())
  H.ok(how == "leader" or how == "party", tag .. "follow line finds the one ahead by name (" .. tostring(how) .. ")")
  H.ok(u ~= nil and ahead ~= nil, tag .. "follow line has a unit")

  -- automation sender = a squad member in the party
  H.ok(B.ns.Auto.member(form[2]("Rip And"), true) ~= nil, tag .. "Auto.member: the leader's message counts as squad")
  H.ok(B.ns.Auto.member(form[2]("Stranger Guy"), true) == nil, tag .. "Auto.member: a stranger does not")
  H.ok(B.ns.Auto.allowed("invite", form[2]("Rip And"), false) ~= nil, tag .. "invite from the leader accepted (squad only)")

  -- team status: Rip's panel shows Rup and Rap with a signal
  for _, c in ipairs(clients) do c.ns.Team.send(true); c.ns.Team.sendReady(true) end
  deliver()
  local rows = A.ns.Team.rows()
  H.eq(#rows, 3, tag .. "team panel: three rows")
  for _, r in ipairs(rows) do
    if not r.me then H.ok(r.st ~= nil, tag .. "team panel: " .. r.name .. " has a signal") end
  end
  for _, r in ipairs(A.ns.Squad.readiness()) do
    if not r.me then H.ok(r.signal and r.inParty, tag .. "squad page: " .. r.m.name .. " in party with signal") end
  end

  -- Send to my other characters: Review appears on Rup and Rap
  for _, c in ipairs(clients) do c.ns.Sync.queue = {}; c.ns.Sync.show() end -- the login session cards
  H.ok(A.ns.Sync.sendSquad(sA), tag .. "Rip sends the squad")
  deliver()
  H.ok(B.ns.Sync.frame and B.ns.Sync.frame:IsShown(), tag .. "Rup: Review card shown")
  H.ok(Cc.ns.Sync.frame and Cc.ns.Sync.frame:IsShown(), tag .. "Rap: Review card shown")
  H.ok(B.ns.Sync.frame.text:GetText():find("Rip And", 1, true) ~= nil, tag .. "Rup: card names the sender")
  B.ns.Sync.accept()
  B.ns.UI.panels.share.importBtn:Click()
  local sB2, meB2 = B.ns.Core.me()
  H.ok(sB2 and meB2 and meB2.cls == "priest", tag .. "Rup: imported and found itself")

  -- a stranger's squad is dropped, and the drop is logged with its reason
  Cc.ns.Sync.dismiss()
  Cc.W.fire("CHAT_MSG_ADDON", "WBX1", "Q|abc|1|1|x", "PARTY", form[2]("Stranger Guy"))
  H.ok(not Cc.ns.Sync.frame:IsShown(), tag .. "stranger: no offer")
  H.ok(logHas(Cc.ns, "dropped sync from Stranger Guy: not in your party"), tag .. "stranger: drop logged with the reason")

  -- the old first names learn the full game names (roster update); /invite then uses them
  A.W.fire("GROUP_ROSTER_UPDATE")
  local names = {}
  for _, m in ipairs(sA.members) do names[#names + 1] = m.name end
  H.eq(table.concat(names, ","), "Rip And,Rup And,Rap And", tag .. "squad learned the full names")
  H.ok(logHas(A.ns, "Rup is Rup And in the game"), tag .. "name upgrade logged")
  local bodies = A.ns.Macros.inviteBodies(sA, select(2, A.ns.Core.me()))
  H.eq(bodies[1], "/invite Rup And\n/invite Rap And", tag .. "Invite squad: full two-part names")
  H.ok(A.ns.Rules.validateMacro("WBX Invite", bodies[1]), tag .. "Invite macro valid")
  H.eq(A.ns.Squad.unitOf("Rup And"), "party1", tag .. "still matched after the upgrade")
  local _, me2 = A.ns.Core.me()
  H.ok(me2 and me2.name == "Rip And", tag .. "me after the upgrade")

  for _, c in ipairs(clients) do H.eq(errors(c.ns), "", tag .. c.name .. ": no errors") end
end

-- ------------------------------------------------------------------ 3. Add from party stores the full name
do
  local W = Mock.new(H, { name = "Rip And", class = "PALADIN", race = "Human", faction = "Alliance", level = 20,
    party = { party1 = "Rup And" }, partyInfo = { party1 = { class = "PRIEST", race = "Human", level = 20 } } })
  W.player.leader = true
  local ns = H.loadAddon({ env = W.env })
  W.fire("ADDON_LOADED", "WoWBoxer"); W.fire("PLAYER_LOGIN")
  ns.Core.cdb.guide = "done"
  ns.UI.Open("squad")
  H.eq(ns.SquadPages.addParty(), 1, "Use my party: Rup And added next to this character")
  local s = ns.Core.me()
  H.eq(s.members[1].name .. "|" .. s.members[2].name, "Rip And|Rup And", "Use my party stores the full names")
  H.eq(ns.SquadPages.addParty(), 0, "nobody added twice")
  local m, err = ns.SquadPages.addByName("Rup", "priest")
  H.ok(m == nil and err:find("already", 1, true), "Add by first name: already in the squad")
end

-- ------------------------------------------------------------------ 4. Era still: Name-Realm senders, single names
do
  local clients = {}
  local NM = { "Dorin", "Wowtwo" }
  for i, name in ipairs(NM) do
    local other = NM[3 - i]
    local W = Mock.new(H, { toc = 11509, spellbookStyle = "classic", name = name, class = i == 1 and "PALADIN" or "PRIEST", race = "Human", faction = "Alliance",
      level = 20, party = { party1 = other }, partyInfo = { party1 = { class = i == 1 and "PRIEST" or "PALADIN", race = "Human", level = 20, leader = i == 2 } } })
    W.player.leader = i == 1
    local ns = H.loadAddon({ env = W.env })
    W.fire("ADDON_LOADED", "WoWBoxer"); W.fire("PLAYER_LOGIN")
    clients[i] = { W = W, ns = ns, name = name }
  end
  local A, B = clients[1], clients[2]
  A.ns.UI.Open("squad"); A.ns.SquadPages.addParty()
  H.eq(A.ns.Squad.unitOf("Wowtwo"), "party1", "Era: unitOf")
  H.ok(A.ns.Auto.member("Wowtwo-Auberdine", true) ~= nil, "Era: Name-Realm sender is the squad member")
  H.ok(not A.ns.Compat.sameName("Wowtwo", "Wowtwoo"), "Era: no prefix matching")
  A.W.fire("GROUP_ROSTER_UPDATE")
  H.eq(A.ns.Core.me().members[2].name, "Wowtwo", "Era: single names unchanged by the roster update")
  H.eq(errors(A.ns) .. errors(B.ns), "", "Era: no errors")
end

-- ------------------------------------------------------------------ 5. SendAddonMessage result codes
do
  local W = Mock.new(H, { name = "Rip And", class = "PALADIN", race = "Human", faction = "Alliance", level = 20,
    party = { party1 = "Rup And" }, partyInfo = { party1 = { class = "PRIEST", race = "Human", level = 20 } } })
  W.player.leader = true
  local ns = H.loadAddon({ env = W.env })
  W.fire("ADDON_LOADED", "WoWBoxer"); W.fire("PLAYER_LOGIN")
  ns.UI.Open("squad"); ns.SquadPages.addParty()
  local C = ns.Compat
  local code = 0
  W.env.C_ChatInfo.SendAddonMessage = function(prefix, msg, chan) W.sent[#W.sent + 1] = { prefix = prefix, msg = msg, chan = chan }; return code end
  H.ok(C.sendAddon("WBX1", "hi", "PARTY", "test"), "code 0 = success")
  code = 5
  local before = #W.chat
  local ok, reason = C.sendAddon("WBX1", "hi", "PARTY", "test", true)
  H.ok(not ok and reason:find("NotInGroup", 1, true), "code 5 = NotInGroup, not success (" .. tostring(reason) .. ")")
  H.ok(#W.chat > before and W.chat[#W.chat]:find("Could not send", 1, true), "the player is told in chat")
  H.ok(logHas(ns, "send test on PARTY failed: NotInGroup"), "the failure is logged with the code")
  W.env.C_ChatInfo.SendAddonMessage = function() return false end
  H.ok(not C.sendAddon("WBX1", "hi", "PARTY", "test"), "false = failure (older clients)")
  W.env.C_ChatInfo.SendAddonMessage = function() error("boom") end
  H.ok(not C.sendAddon("WBX1", "hi", "PARTY", "test"), "an error = failure")
  W.env.C_ChatInfo.SendAddonMessage = function() return nil end
  H.ok(C.sendAddon("WBX1", "hi", "PARTY", "test"), "nothing returned = sent (old API)")
  -- Send squad with a throttled channel: tried again, then reported
  W.chat = {}
  local n = 0
  W.env.C_ChatInfo.SendAddonMessage = function() n = n + 1; return 3 end
  ns.Sync.sendSquad(ns.Core.me())
  for _ = 1, 40 do W.flush() end
  H.ok(n > 1 and n % (ns.Sync.RETRIES + 1) == 0, "throttled chunks are retried (" .. n .. " tries)")
  local told = false
  for _, l in ipairs(W.chat) do if l:find("AddonMessageThrottle", 1, true) then told = true end end
  H.ok(told, "player told the send was throttled")
  local lines = ns.Core.namesReport()
  H.ok(table.concat(lines, "\n"):find("party1: \"Rup And\"", 1, true) ~= nil, "/wbx names shows the game's names")
  H.ok(table.concat(lines, "\n"):find("failed", 1, true) ~= nil, "/wbx names shows the send results")
end


-- ------------------------------------------------------------------ 6. Forever as seen live (5 Nov 08:17 logs)
-- UnitName gives "Rip" with realm "And"; CHAT_MSG_ADDON senders arrive as "Rip And" (name, space, realm). Every
-- automation must treat both forms (and "Rip-And") as the squad member Rip.
for _, sender in ipairs({ "Rip And", "Rip-And", "Rip" }) do
  local tag = "[live, sender \"" .. sender .. "\"] "
  local W = Mock.new(H, { name = "Rup", class = "PRIEST", race = "Human", faction = "Alliance", level = 20,
    party = { party1 = "Rip", party2 = "Rap" },
    partyInfo = { party1 = { class = "PALADIN", race = "Human", level = 20, leader = true, realm = "And" }, party2 = { class = "MAGE", race = "Human", level = 20, realm = "And" } } })
  local ns = H.loadAddon({ env = W.env })
  W.fire("ADDON_LOADED", "WoWBoxer")
  local sq = ns.State.newSquad({ name = "Gronspaetterne", faction = "alliance", members = {
    { name = "Rip", cls = "paladin", race = "human", role = "tank", leader = true, realm = "And" },
    { name = "Rup", cls = "priest", race = "human", role = "healer", unit = "party1", realm = "And" },
    { name = "Rap", cls = "mage", race = "human", role = "ranged", unit = "party1", realm = "And" } } })
  ns.Core.db.squads = { sq }; ns.Core.db.active = sq.id
  W.fire("PLAYER_LOGIN")
  W.did = {}
  for _, fn in ipairs({ "AcceptGroup", "AcceptQuest", "ConfirmAcceptQuest", "AcceptResurrect", "ConfirmSummon", "CompleteLFGRoleCheck",
    "SelectGossipOption", "TakeTaxiNode", "StaticPopup_Hide", "GetQuestReward", "InviteUnit" }) do
    W.env[fn] = function(...) local t = {}; for i = 1, select("#", ...) do t[i] = tostring(select(i, ...)) end; W.did[#W.did + 1] = fn .. "(" .. table.concat(t, ",") .. ")"; return true end
  end
  W.env.C_PartyInfo, W.env.C_GossipInfo, W.env.C_SummonInfo = nil, nil, nil
  local function did(name) for _, c in ipairs(W.did) do if c:find("^" .. name .. "%(") then return c end end return nil end
  local AU = ns.Auto
  for _, o in ipairs(AU.OPTIONS) do AU.set(o[1], true) end
  AU.set("questAny", false)
  H.ok(AU.member(sender, true) ~= nil, tag .. "the sender is the squad member Rip, in the party")
  H.eq(ns.Squad.unitOf(sender), "party1", tag .. "unitOf")
  -- invite
  W.did = {}; W.fire("PARTY_INVITE_REQUEST", sender)
  H.ok(did("AcceptGroup"), tag .. "invite accepted")
  -- escort / shared quest start
  W.did = {}; W.fire("QUEST_ACCEPT_CONFIRM", sender)
  H.ok(did("ConfirmAcceptQuest"), tag .. "escort / shared quest accepted")
  -- quest share: the leader's quest list (message), then the shared quest window
  W.fire("CHAT_MSG_ADDON", AU.PREFIX, "QL|501", "PARTY", sender)
  W.env.GetQuestID = function() return 501 end
  W.did = {}; W.fire("QUEST_DETAIL")
  H.ok(did("AcceptQuest"), tag .. "quest the leader has: accepted")
  -- the leader's reward pick
  W.env.GetQuestID = function() return 77 end
  W.env.GetNumQuestChoices = function() return 3 end
  ns.Core.db.settings.autoReward = "leader"
  W.did = {}; W.fire("QUEST_COMPLETE")
  W.fire("CHAT_MSG_ADDON", AU.PREFIX, "QR|77|2", "PARTY", sender)
  H.eq(did("GetQuestReward"), "GetQuestReward(2)", tag .. "the leader's reward pick")
  W.fire("QUEST_FINISHED")
  -- the quest window opens before the leader has the quest: not yet (logged why), then accepted when the leader takes it
  W.env.GetQuestID = function() return 602 end
  W.did = {}; W.fire("QUEST_DETAIL")
  H.eq(did("AcceptQuest"), nil, tag .. "quest the leader does not have yet: waits")
  H.ok(logHas(ns, "not accepted yet %– the leader does not have it"), tag .. "the reason is logged")
  W.fire("CHAT_MSG_ADDON", AU.PREFIX, "QL|501,602", "PARTY", sender)
  H.ok(did("AcceptQuest"), tag .. "accepted as soon as the leader takes it")
  W.fire("QUEST_FINISHED")
  W.did = {}; W.fire("CHAT_MSG_ADDON", AU.PREFIX, "QL|501,602,603", "PARTY", sender)
  H.eq(did("AcceptQuest"), nil, tag .. "window closed: a later quest list accepts nothing")
  -- our own message echoed back is not a "dropped" message
  W.fire("CHAT_MSG_ADDON", AU.PREFIX, "QL|1", "PARTY", "Rup And")
  H.ok(not logHas(ns, "dropped WBXA from Rup And"), tag .. "own echo: no drop logged")
  -- resurrection + summon
  W.did = {}; W.fire("RESURRECT_REQUEST", sender)
  H.ok(did("AcceptResurrect"), tag .. "resurrection accepted")
  W.env.GetSummonConfirmSummoner = function() return sender end
  W.did = {}; W.fire("CONFIRM_SUMMON")
  H.ok(did("ConfirmSummon"), tag .. "summon accepted")
  -- role check (the group leader is in the squad)
  W.env.UnitIsGroupLeader = function(u) return u == "party1" end
  W.did = {}; W.fire("LFG_ROLE_CHECK_SHOW")
  H.ok(did("CompleteLFGRoleCheck"), tag .. "role check")
  -- dialog + flight sync from the leader
  W.env.UnitName = (function(orig) return function(u) if u == "npc" then return "Innkeeper" end return orig(u) end end)(W.env.UnitName)
  W.env.GetGossipOptions = function() return "Make this inn your home.", "binder" end
  W.fire("GOSSIP_SHOW")
  W.did = {}; W.fire("CHAT_MSG_ADDON", AU.PREFIX, "D|Innkeeper|g|1|Make this inn your home.", "PARTY", sender)
  H.eq(did("SelectGossipOption"), "SelectGossipOption(1)", tag .. "dialog sync")
  W.fire("GOSSIP_CLOSED")
  W.env.NumTaxiNodes = function() return 1 end
  W.env.TaxiNodeName = function() return "Goldshire" end
  W.env.TaxiNodeCost = function() return 10 end
  W.fire("TAXIMAP_OPENED")
  W.did = {}; W.fire("CHAT_MSG_ADDON", AU.PREFIX, "D|taxi|t|1|Goldshire", "PARTY", sender)
  H.eq(did("TakeTaxiNode"), "TakeTaxiNode(1)", tag .. "flight sync")
  -- a stranger with the same realm never counts
  W.did = {}; W.fire("PARTY_INVITE_REQUEST", "Stranger And")
  W.fire("RESURRECT_REQUEST", "Stranger And")
  H.eq(#W.did, 0, tag .. "a stranger: nothing accepted")
  -- team status: the leader's message gives Rip a signal; our own message does not make a peer
  ns.Team.receive(ns.Team.PREFIX, ns.Team.encode({ level = 20, mana = 50, follow = 0, combat = 0, target = "-" }), "PARTY", sender)
  ns.Team.receive(ns.Team.PREFIX, ns.Team.encode({ level = 20, mana = 50, follow = 0, combat = 0, target = "-" }), "PARTY", "Rup And")
  local sig = {}
  for _, r in ipairs(ns.Team.rows()) do sig[r.name] = r.st ~= nil end
  H.ok(sig.Rip and sig.Rup, tag .. "team panel: Rip has a signal")
  H.ok(not sig.Rap, tag .. "team panel: Rap (silent) has no signal")
  H.eq(ns.Team.peers["rup and"], nil, tag .. "our own message is not a peer")
  H.ok(logHas(ns, "first " .. AU.PREFIX .. " message from \"" .. sender:gsub("%-", "%%-") .. "\""), tag .. "arrival logged with the raw sender")
  -- invite macro: Name-Realm
  local bodies = ns.Macros.inviteBodies(sq, select(2, ns.Core.me()))
  H.eq(bodies[1], "/invite Rip-And\n/invite Rap-And", tag .. "invite macro uses Name-Realm")
  -- learnNames never turns "Rip" + realm into a two-part name
  W.fire("GROUP_ROSTER_UPDATE")
  H.eq(sq.members[1].name, "Rip", tag .. "names unchanged by the roster update")
  ns.Core.selftest(true)
  H.ok(logHas(ns, "team sees: Rip=party/signal, Rap=party/no signal"), tag .. "selftest logs who is seen")
  H.eq(errors(ns), "", tag .. "no errors")
end

os.exit(H.report("names") and 0 or 1)
