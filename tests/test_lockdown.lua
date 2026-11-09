-- Addon message lockdown (bug sweep 9 Nov 2026: ~200 "send team on PARTY failed: AddOnMessageLockdown (11)" per account
-- on Forever, plus a few "GeneralError (9)"). Nothing is lost: refused messages wait in the outbox and go out in order
-- when the game allows; team status keeps only the newest of each kind; squad offers and automation keep every
-- message; one log line per lockdown period (with the state), not one per message; the team panel says "paused".
local dir = (arg[0]:match("^(.*)/[^/]+$") or ".")
local H = dofile(dir .. "/harness.lua")
local Mock = dofile(dir .. "/wowmock.lua")

local function boot(me)
  local W = Mock.new(H, { name = me, class = me == "Dorin" and "PALADIN" or "PRIEST", race = "Scourge", level = 20,
    party = me == "Dorin" and { party1 = "Anna", party2 = "Bo" } or { party1 = "Dorin", party2 = "Bo" },
    partyInfo = { party1 = { class = "PRIEST", race = "Scourge", level = 20 }, party2 = { class = "HUNTER", race = "Orc", level = 20 } } })
  local ns = H.loadAddon({ env = W.env })
  W.fire("ADDON_LOADED", "WoWBoxer"); W.fire("PLAYER_LOGIN")
  local sq = ns.State.newSquad({ name = "Trio", members = {
    { name = "Dorin", cls = "paladin", race = "undead", role = "tank", leader = true },
    { name = "Anna", cls = "priest", race = "undead", role = "healer", unit = "party1" },
    { name = "Bo", cls = "hunter", race = "orc", role = "ranged", unit = "party1" } } })
  ns.Core.db.squads = { sq }; ns.Core.db.active = sq.id
  return W, ns
end
local function logCount(ns, pat) local n = 0; for _, e in ipairs(ns.Core.db.log) do if tostring(e.m):find(pat, 1, true) then n = n + 1 end end return n end

-- ------------------------------------------------------------------ 1. the result code 11 (no lockdown API)
do
  local W, ns = boot("Dorin")
  local C, TM, AU = ns.Compat, ns.Team, ns.Auto
  local code, got, tries = 11, {}, 0
  W.env.C_ChatInfo.SendAddonMessage = function(prefix, msg) tries = tries + 1; if code == 0 then got[#got + 1] = prefix .. " " .. msg end; return code end
  W.now = 100
  W.inCombatUnit = true
  W.env.InCombatLockdown = function() return true end
  W.env.IsInInstance = function() return true, "party" end
  W.fire("ENCOUNTER_START", 1, "Rhahk'Zor")
  -- a fight: many team status changes, a quest list and two automation messages
  for i = 1, 30 do W.mana = 1000 - i * 30; W.now = W.now + 2; TM.send(true); TM.sendReady(true); TM.sendExtra(true) end
  AU.send("D", "Innkeeper", "g", 1, "first")
  AU.send("D", "Innkeeper", "g", 2, "second")
  H.ok(C.messagesPaused(), "the lockdown is noticed")
  H.eq(logCount(ns, "send team on PARTY failed"), 0, "no warn line per refused message any more")
  H.eq(logCount(ns, "addon messages paused by the game"), 1, "one log line for the lockdown period")
  local line
  for _, e in ipairs(ns.Core.db.log) do if tostring(e.m):find("paused by the game", 1, true) then line = e.m end end
  H.ok(line and line:find("combat yes", 1, true) and line:find("instance party", 1, true) and line:find("encounter Rhahk'Zor", 1, true)
    and line:find("lockdown API missing", 1, true), "the state is logged: " .. tostring(line))
  local kinds = {}
  for _, it in ipairs(C.outbox) do kinds[it.latest or it.msg] = (kinds[it.latest or it.msg] or 0) + 1 end
  H.eq(kinds["team S"], 1, "team status: only the newest S waits")
  H.eq(kinds["team R"], 1, "team status: only the newest R waits")
  H.eq(kinds["team X"], 1, "team status: only the newest X waits")
  H.eq(#C.outbox, 5, "3 team messages + 2 automation messages wait")
  -- no chat spam while it lasts
  local spam = 0
  for _, l in ipairs(W.chat) do if l:find("Could not send", 1, true) then spam = spam + 1 end end
  H.eq(spam, 0, "no 'Could not send' chat lines for a lockdown")
  -- still locked: a flush tries one message only, sends nothing
  local before = tries
  C.flush()
  H.eq(tries - before, 1, "while locked a flush probes with one message")
  -- the fight ends: everything goes out, in order, automation unchanged
  code = 0
  W.inCombatUnit = false
  W.env.InCombatLockdown = function() return false end
  W.fire("ENCOUNTER_END", 1)
  W.fire("PLAYER_REGEN_ENABLED")
  for _ = 1, 5 do C.flush() end
  H.eq(#C.outbox, 0, "after the lockdown nothing waits")
  H.ok(not C.messagesPaused(), "the lockdown is over")
  local autos = {}
  for _, g in ipairs(got) do if g:find("^WBXA D|") then autos[#autos + 1] = g end end
  H.eq(#autos, 2, "both automation messages arrived")
  H.ok(autos[1] and autos[1]:find("first", 1, true) and autos[2]:find("second", 1, true), "automation messages kept their order")
  local lastS
  for _, g in ipairs(got) do if g:find("^WBX1 S|") then lastS = g end end
  H.ok(lastS ~= nil, "the newest team status was sent: " .. tostring(lastS))
  H.eq(logCount(ns, "addon messages flow again after"), 1, "one log line when it ends")
  local d = ns.Core.db.diag[ns.Core.charKey]
  H.ok(d and d.lockdowns and #d.lockdowns == 1 and d.lockdowns[1].secs >= 50 and d.lockdowns[1].sent == 5, "diagnose keeps the period: "
    .. tostring(d and d.lockdowns and d.lockdowns[1] and d.lockdowns[1].secs))
  -- after a lockdown everything sends straight away again
  got = {}
  W.now = W.now + 5
  H.ok(TM.send(true) and #got == 1, "team status sends directly after the lockdown")
  H.ok(AU.send("D", "x", "g", 1, "y") and #got == 2, "automation sends directly after the lockdown")
  -- a second lockdown is a second period (one more line, not one per message)
  code = 11
  for _ = 1, 10 do W.now = W.now + 2; TM.send(true) end
  H.eq(logCount(ns, "addon messages paused by the game"), 2, "a new lockdown: one new line")
  code = 0; C.flush()
  -- leaving the party drops what waits
  code = 11
  AU.send("D", "x", "g", 1, "z")
  W.party = {}
  W.env.IsInGroup = function() return false end
  W.env.GetNumGroupMembers = function() return 0 end
  C.flush()
  H.eq(#C.outbox, 0, "left the party: the waiting messages are dropped")
  H.ok(not C.messagesPaused(), "and the period ends")
end

-- ------------------------------------------------------------------ 2. the lockdown API: nothing is even tried while it says locked
do
  local W, ns = boot("Dorin")
  local C, TM = ns.Compat, ns.Team
  local locked, tries = true, 0
  W.env.C_ChatInfo.InChatMessagingLockdown = function() return locked, 2 end
  W.env.Enum = W.env.Enum or {}
  W.env.Enum.ChatMessagingLockdownReason = { Encounter = 2 }
  W.env.C_ChatInfo.SendAddonMessage = function() tries = tries + 1; return 0 end
  TM.send(true); TM.sendReady(true)
  H.eq(tries, 0, "the API says locked: no send is tried")
  H.eq(#C.outbox, 2, "both wait")
  local line
  for _, e in ipairs(ns.Core.db.log) do if tostring(e.m):find("paused by the game", 1, true) then line = e.m end end
  H.ok(line and line:find("lockdown Encounter", 1, true) and line:find("lockdown API yes (Encounter)", 1, true), "the API's reason is logged: " .. tostring(line))
  H.ok(ns.Compat.probe().chatLockdownApi == true, "the diagnose says the API exists")
  locked = false
  C.flush()
  H.eq(tries, 2, "the lockdown ended: both sent")
  H.eq(#C.outbox, 0, "nothing waits")
end

-- ------------------------------------------------------------------ 3. GeneralError (9) while zoning waits the same way
do
  local W, ns = boot("Dorin")
  local C, TM = ns.Compat, ns.Team
  local code, got = 9, 0
  W.env.C_ChatInfo.SendAddonMessage = function() if code == 0 then got = got + 1 end; return code end
  W.fire("LOADING_SCREEN_ENABLED")
  TM.heartbeat()
  local line
  for _, e in ipairs(ns.Core.db.log) do if tostring(e.m):find("paused by the game", 1, true) then line = e.m end end
  H.ok(line and line:find("general (9)", 1, true) and line:find("zoning", 1, true), "GeneralError is logged once with 'zoning': " .. tostring(line))
  H.eq(logCount(ns, "failed: GeneralError"), 0, "no warn line per message")
  code = 0
  W.fire("LOADING_SCREEN_DISABLED")
  H.ok(got >= 1 and #C.outbox == 0, "after the loading screen the heartbeat went out (" .. got .. ")")
end

-- ------------------------------------------------------------------ 4. the team panel says "paused", and is back after the fight
do
  local W, ns = boot("Dorin")
  local C, TM = ns.Compat, ns.Team
  local code = 11
  W.env.C_ChatInfo.SendAddonMessage = function() return code end
  TM.send(true)
  local function flagOf(name)
    for _, r in ipairs(TM.rows()) do if r.name == name then return r.flags[1] and r.flags[1][1] end end
  end
  H.eq(flagOf("Anna"), "paused", "while locked: Anna shows 'paused', not 'no signal'")
  code = 0; C.flush()
  H.eq(flagOf("Anna"), "no signal", "after it: 'no signal' until Anna's message arrives")
  W.now = (W.now or 0) + 1
  W.fire("CHAT_MSG_ADDON", "WBX1", "S|20|80|1|0|-", "PARTY", "Anna")
  W.fire("CHAT_MSG_ADDON", "WBX1", "S|20|80|1|0|-", "PARTY", "Bo And")
  H.ok(flagOf("Anna") ~= "no signal" and flagOf("Anna") ~= "paused" and flagOf("Bo") ~= "no signal", "after the fight all three show again")
end

-- ------------------------------------------------------------------ 5. a squad offer during a lockdown arrives complete
do
  local W, ns = boot("Dorin")
  local C = ns.Compat
  local code, got = 11, {}
  W.env.C_ChatInfo.SendAddonMessage = function(_, msg) if code == 0 then got[#got + 1] = msg end; return code end
  W.chat = {}
  ns.Sync.sendSquad(ns.Core.me())
  for _ = 1, 10 do W.flush() end
  local told = false
  for _, l in ipairs(W.chat) do if l:find("holds addon messages back", 1, true) then told = true end end
  H.ok(told, "the player who pressed Send is told it waits")
  code = 0
  for _ = 1, 20 do C.flush() end
  H.ok(#got > 0 and #C.outbox == 0, "every chunk went out after the lockdown (" .. #got .. ")")
  -- the receiver builds the squad from them
  local W2, ns2 = boot("Anna")
  for _, m in ipairs(got) do W2.fire("CHAT_MSG_ADDON", "WBX1", m, "PARTY", "Dorin") end
  H.ok(ns2.Sync.queue[1] and ns2.Sync.queue[1].kind == "squad", "the squad offer arrived on the other client")
end

-- ------------------------------------------------------------------ 6. C: Place all while the cursor holds something
do
  local W = Mock.new(H, { name = "Dorin", class = "PALADIN", race = "Scourge", level = 20 })
  local ns = H.loadAddon({ env = W.env })
  W.fire("ADDON_LOADED", "WoWBoxer"); W.fire("PLAYER_LOGIN")
  for _, sp in ipairs(ns.Data.spells.paladin) do if sp.level <= 20 then W.known[sp.name] = true end end
  ns.State.quickStart(ns.Core.db, ns.Core.cdb, ns.Core.playerInfo())
  W.cursor = { kind = "macro" }
  W.chat = {}
  ns.Core.sync({})
  local told = false
  for _, l in ipairs(W.chat) do if l:find("cursor is holding a macro", 1, true) and l:find("press Escape", 1, true) then told = true end end
  H.ok(told, "the player is told in plain words")
  local err = 0
  for _, e in ipairs(ns.Core.db.log) do if e.l == "error" then err = err + 1 end end
  H.eq(err, 0, "no error in the log")
  local placedBefore = 0
  for _, v in pairs(ns.Core.cdb.slots or {}) do if v then placedBefore = placedBefore + 1 end end
  H.eq(placedBefore, 0, "nothing placed while the cursor is busy")
  for _ = 1, 3 do W.flush() end
  H.ok(ns.Core.cursorWait ~= nil, "still waiting while it holds the macro")
  W.cursor = nil
  W.fire("CURSOR_CHANGED")
  local placed = 0
  for _ in pairs(ns.Core.cdb.slots or {}) do placed = placed + 1 end
  H.ok(placed > 0 and ns.Core.cursorWait == nil, "the cursor is free: the macros are placed (" .. placed .. ")")
end

H.report("lockdown")
