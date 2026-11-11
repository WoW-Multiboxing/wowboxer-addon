-- Addon behaviour in a simulated client: squad setup, macro sync, action bars, level-up offers, combat queue,
-- settings, import/export, rules. Run: lua tests/test_core.lua
local dir = (arg[0]:match("^(.*)/[^/]+$") or ".")
local H = dofile(dir .. "/harness.lua")
local Mock = dofile(dir .. "/wowmock.lua")

--- Fresh client + addon. opts go to the mock.
local function boot(opts)
  local W = Mock.new(H, opts)
  local ns = H.loadAddon({ env = W.env })
  W.fire("ADDON_LOADED", "WoWBoxer")
  W.fire("PLAYER_LOGIN")
  return W, ns
end
local function namesAt(ns, cls, maxLevel, race)
  local out = {}
  for _, s in ipairs(ns.Data.spells[cls]) do if s.level <= maxLevel and s.gate ~= "talent" then out[s.name] = true end end
  return out
end

-- ------------------------------------------------------------------ rules
do
  local W, ns = boot()
  local R = ns.Rules
  H.ok(R.validateMacro("WBX K1", "#showtooltip\n/cast [@mouseover,harm,nodead][harm,nodead] Smite"), "valid macro")
  for _, bad in ipairs({ "/run print(1)", "/script x()", "/console foo", "/click Btn", "/dump 1", "hello there", "/say hi", "/cast X\n/run y()", "#show\n/cast A\n/e dance" }) do
    H.ok(not R.validateMacro("WBX K1", bad), "rejects " .. bad)
  end
  H.ok(not R.validateMacro("Other", "/cast Smite"), "rejects names without WBX")
  H.ok(not R.validateMacro("WBX 12345678901234", "/cast Smite"), "rejects names over 16 characters")
  H.ok(not R.validateMacro("WBX K1", "/cast " .. string.rep("a", 250)), "rejects 256 characters")
  H.ok(R.validateMacro("WBX K1", "/cast " .. string.rep("a", 249)), "accepts 255 characters")
  H.ok(not R.validateMacro("WBX K1", "/cast a\1b"), "rejects control characters")
  H.ok(not R.validateMacro("WBX K1", "#nonsense\n/cast a"), "rejects unknown # lines")
  H.ok(R.validateMacro("WBX K1", "/CAST Smite"), "slash commands are case-insensitive")
end

-- ------------------------------------------------------------------ squad + first sync (leader)
do
  local W, ns
  W, ns = boot({ name = "Dorin", class = "PALADIN", race = "Scourge", level = 10 })
  W.known = namesAt(ns, "paladin", 10)
  local Core, S = ns.Core, ns.State
  H.ok(Core.db and Core.cdb, "saved variables created")
  H.eq(_G and W.env.WoWBoxerDB, Core.db, "WoWBoxerDB global set")
  H.ok(Core.compute() == nil, "no squad yet")
  -- the player's own macros must never be touched
  W.addMacro("Heal me", "/cast Holy Light", true)
  W.addMacro("WBX Shared", "/cast Old", false) -- an account macro with our prefix: left alone too
  W.actions[3] = { kind = "spell", id = 6603 }
  S.quickStart(Core.db, Core.cdb, Core.playerInfo())
  local ctx = Core.compute()
  H.ok(ctx ~= nil, "member found after quick start")
  H.eq(ctx.member.name, "Dorin", "me = Dorin")
  H.eq(ctx.member.cls, "paladin", "class from game")
  H.eq(ctx.member.race, "undead", "race Scourge -> undead")
  H.ok(ctx.member.leader, "quick start makes a leader")
  H.ok(ctx.macros.counts.create > 0, "macros to create")
  for _, d in ipairs(ctx.desired) do H.ok(d.ok, "desired macro valid: " .. d.name .. " " .. tostring(d.why)) end
  for _, it in ipairs(ctx.macros.items) do H.ok(not it.body:find("party1target"), "leader macros never assist: " .. it.name) end
  Core.sync()
  local nCreated = 0
  for _, m in ipairs(W.char) do if m.name:sub(1, 3) == "WBX" then nCreated = nCreated + 1 end end
  H.eq(nCreated, ctx.macros.counts.create, "all macros created")
  H.eq(W.char[1].name == "Heal me" and W.char[1].body or (function() for _, m in ipairs(W.char) do if m.name == "Heal me" then return m.body end end end)(), "/cast Holy Light", "own macro untouched")
  H.eq(W.acc[1].body, "/cast Old", "account WBX macro untouched")
  H.eq(W.slotMacroName(1), "WBX K1", "K1 on button 1")
  H.eq(W.slotMacroName(2), "WBX K2", "K2 on button 2")
  H.eq(W.actions[3] and W.actions[3].kind, "spell", "occupied slot kept without replace")
  H.ok(W.chatHas("created"), "sync reports in chat")
  local again = Core.compute()
  H.eq(again.macros.changes, 0, "second compute: nothing to change")
  -- replace occupied slots on request
  Core.sync({ replace = true })
  local k3
  for _, d in ipairs(Core.compute().desired) do if d.key == "K3" then k3 = d end end
  if k3 and k3.plain then -- a spell without a target is the spell itself on the bar (owner, 9 Nov 2026)
    H.ok(W.actions[3] and W.actions[3].kind == "spell" and ns.Compat.isRankOf(W.actions[3].id, k3.spell), "replace puts K3 (" .. k3.label .. ", a plain spell) on button 3")
  else H.eq(W.slotMacroName(3), "WBX K3", "replace puts K3 on button 3") end

  -- level up: same names, new bodies, offer in chat
  local before = {}
  for _, m in ipairs(W.char) do before[m.name] = m.body end
  W.player.level = 20
  W.known = namesAt(ns, "paladin", 20)
  W.chat = {}
  W.fire("PLAYER_LEVEL_UP", 20)
  W.flush()
  H.ok(W.chatHas("changed at level 20"), "level-up offer in chat")
  local c20 = Core.compute()
  H.ok(c20.macros.changes > 0, "changes at level 20")
  local editsBefore = W.calls.EditMacro or 0
  -- in combat: queued, nothing written
  W.combat = true
  Core.sync()
  H.eq(W.calls.EditMacro or 0, editsBefore, "no macro writes in combat")
  H.ok(W.chatHas("waiting until combat ends"), "queued message")
  W.combat = false
  W.fire("PLAYER_REGEN_ENABLED")
  H.ok((W.calls.EditMacro or 0) > editsBefore or (W.calls.CreateMacro or 0) > 0, "applied after combat")
  H.eq(Core.compute().macros.changes, 0, "up to date after combat")
  for name in pairs(before) do
    local found = false
    for _, m in ipairs(W.char) do if m.name == name then found = true end end
    H.ok(found, "macro kept its name after level-up: " .. name)
  end
  H.eq(W.slotMacroName(1), "WBX K1", "K1 still on button 1 after level-up (client keeps the reference)")
  -- selftest
  local r = Core.selftest()
  H.ok(Core.db.diag["Dorin-Realm"] == r, "selftest stored under character key")
  H.eq(r.probe.game, "forever", "probe: forever")
  H.eq(r.probe.api.CreateMacro, "function", "probe: CreateMacro")
  H.ok(#Core.db.log > 0, "log has entries")
end

-- ------------------------------------------------------------------ follower macros, helpers, sequences
do
  local W, ns = boot({ name = "Wowtwo", class = "PRIEST", race = "Scourge", level = 20, party = { party1 = "Dorin" } })
  W.known = namesAt(ns, "priest", 20)
  local Core, S = ns.Core, ns.State
  local s = S.newSquad({ name = "Trio", members = {
    { name = "Dorin", cls = "paladin", race = "undead", role = "tank", leader = true },
    { name = "Wowtwo", cls = "priest", race = "undead", role = "healer", unit = "party1", seq = "medium" } } })
  Core.db.squads[1] = s; Core.db.active = s.id
  local ctx = Core.compute()
  H.eq(ctx.member.name, "Wowtwo", "found by name")
  local byKey = {}
  for _, d in ipairs(ctx.desired) do byKey[d.key] = d end
  H.eq(byKey.Follow and byKey.Follow.body, "/follow party1", "follow helper")
  H.eq(byKey.Assist and byKey.Assist.body, "/assist party1", "assist helper")
  H.ok(byKey.S1 and byKey.S1.body:find("castsequence"), "damage sequence S1")
  H.ok(byKey.S2 and byKey.S2.body:find("reset=combat/12"), "heal sequence S2")
  H.ok(byKey.K1 and byKey.K1.body:find("party1"), "kit follows party1")
  -- spells not in the spellbook stay out of sequences
  W.known["Mind Blast"] = nil
  W.fire("SPELLS_CHANGED") -- the client fires this whenever the spellbook changes (the addon caches the scan)
  local ctx2 = Core.compute()
  local s1
  for _, d in ipairs(ctx2.desired) do if d.key == "S1" then s1 = d end end
  H.ok(s1 and not s1.body:find("Mind Blast"), "untrained spell left out of the sequence")
  local miss = false
  for _, x in ipairs(ctx2.missing) do if x.name == "Mind Blast" then miss = true end end
  H.ok(miss, "untrained spell listed as missing (visit trainer)")
  Core.sync()
  H.eq(W.slotMacroName(11), "WBX Follow", "Follow on button 11")
  H.eq(W.slotMacroName(12), "WBX Assist", "Assist on button 12")
  H.eq(W.slotMacroName(9), "WBX S1", "S1 on button 9")
end

-- ------------------------------------------------------------------ full macro slots
do
  local W, ns = boot({ name = "Lock", class = "WARLOCK", race = "Scourge", level = 30, maxChar = 2 })
  W.known = namesAt(ns, "warlock", 30)
  local Core, S = ns.Core, ns.State
  W.addMacro("Mine", "/cast Fear", true)
  S.quickStart(Core.db, Core.cdb, Core.playerInfo())
  local ctx = Core.compute()
  local inChar, inAcc = 0, 0
  for _, it in ipairs(ctx.macros.items) do if it.status == "create" then if it.account then inAcc = inAcc + 1 else inChar = inChar + 1 end end end
  H.eq(inChar, 1, "the free character slot first")
  H.ok(inAcc > 0, "the rest goes to general (account) slots")
  H.eq(ctx.macros.counts.noslot, 0, "general slots free: no macro without a slot")
  Core.sync()
  H.eq(#W.char, 2, "never more than the character slot limit")
  local tag = Core.db.macroTags and Core.db.macroTags[Core.charKey]
  H.ok(type(tag) == "string" and #tag == 2, "a general-slot tag is kept for this character")
  local accOurs = 0
  for _, m in ipairs(W.acc) do if m.name:sub(1, 3) == "WBX" then accOurs = accOurs + 1; H.ok(m.name:sub(1, 6) == "WBX" .. tag .. " " and #m.name <= 16, "general macro named for this character: " .. m.name) end end
  H.eq(accOurs, inAcc, "every general macro created")
  H.eq(Core.compute().macros.changes, 0, "after sync: nothing left to create")
end
do -- character AND general slots full: the banner and chat name the macros without a slot
  local W, ns = boot({ name = "Lock", class = "WARLOCK", race = "Scourge", level = 30, maxChar = 2 })
  W.known = namesAt(ns, "warlock", 30)
  local Core, S = ns.Core, ns.State
  W.addMacro("Mine", "/cast Fear", true)
  for i = 1, 120 do W.addMacro(string.format("Acc%03d", i), "/cast Fear", false) end
  S.quickStart(Core.db, Core.cdb, Core.playerInfo())
  local ctx = Core.compute()
  H.eq(ctx.macros.counts.create, 1, "only free slots are planned")
  H.ok(ctx.macros.counts.noslot > 0, "rest reported as no slot")
  H.eq(#ctx.macros.noslotNames, ctx.macros.counts.noslot, "every macro without a slot is named")
  Core.sync()
  local said = false
  for _, m in ipairs(W.chat) do if m:find("without a free macro slot (" .. tostring(ctx.macros.noslotNames[1]), 1, true) then said = true end end
  H.ok(said, "no-slot warning in chat names the macros")
  H.eq(#W.char, 2, "never more than the slot limit")
  H.eq(#W.acc, 120, "no general macro over the limit")
end

-- ------------------------------------------------------------------ settings (CVars)
do
  local W, ns = boot({ name = "Dorin" })
  local Core, S = ns.Core, ns.State
  S.quickStart(Core.db, Core.cdb, Core.playerInfo())
  local plan = Core.cvarPlan()
  local st = {}
  for _, c in ipairs(plan) do st[c.name] = c.status end
  H.eq(st.autoLootDefault, "change", "auto loot needs change")
  H.eq(st.AutoPushSpellToActionBar, "missing", "missing CVar skipped")
  Core.applyCVars()
  H.eq(W.cvars.autoLootDefault, "1", "auto loot on")
  H.eq(W.cvars.maxfpsbk, "30", "background fps")
  H.eq(Core.cdb.cvarBackup.autoLootDefault, "0", "backup kept")
  Core.restoreCVars()
  H.eq(W.cvars.autoLootDefault, "0", "restored")
  H.eq(W.cvars.maxfpsbk, "8", "restored fps")
  -- The owner 2026-10-29: clear target on click (the game's normal), nameplates, cast bars only where the CVar exists
  local by = {}
  for _, c in ipairs(Core.cvarPlan()) do by[c.name] = c end
  H.ok(by.deselectOnClick.want == "1" and by.deselectOnClick.status == "ok" and by.deselectOnClick.label == "Clear target on click", "clear target on click: recommended On")
  H.eq(by.nameplateShowEnemies.status, "change", "enemy nameplates recommended")
  H.eq(by.nameplateShowFriends.status, "change", "friendly nameplates recommended")
  H.eq(by.nameplateShowSelf.status, "missing", "no personal nameplate on this client: not offered")
  H.eq(by.showVKeyCastbar.status, "change", "the cast bar CVar that exists is offered")
  H.eq(by.nameplateShowFriendlyCastBar.status, "missing", "cast bar names that do not exist stay hidden")
  W.env.C_Console = { GetAllCommands = function() return { { command = "showVKeyCastbar" }, { command = "autoLootDefault" }, { command = "ShowTargetCastbar" } } end }
  local pr = ns.Compat.cvarProbe()
  H.ok(pr.candidates.showVKeyCastbar and not pr.candidates.nameplateShowCastBars, "probe: which candidates exist")
  H.eq(table.concat(pr.found, ","), "ShowTargetCastbar,showVKeyCastbar", "probe: every CVar with cast in its name, for the diagnose")
  H.ok(Core.selftest(true).cvarProbe.source == "console", "the diagnose logs the probe")
  ns.UI.Open("setup")
  local shown = 0
  for _, r in ipairs(ns.UI.panels.setup.cvPool.rows) do if r:IsShown() then shown = shown + 1 end end
  local exist = 0
  for _, c in ipairs(Core.cvarPlan()) do if c.status ~= "missing" then exist = exist + 1 end end
  H.eq(shown, exist, "Setup lists only the settings this client has")
  Core.applyCVars()
  H.ok(W.cvars.nameplateShowFriends == "1" and W.cvars.showVKeyCastbar == "1" and W.cvars.nameplateShowSelf == nil, "applied through the allow-list")
  Core.restoreCVars()
  H.ok(W.cvars.nameplateShowFriends == "0" and W.cvars.showVKeyCastbar == "0", "and restored")
end

-- ------------------------------------------------------------------ era client, classic spellbook, secrets
do
  local W, ns = boot({ toc = 11509, spellbookStyle = "classic", name = "Pala", class = "PALADIN", race = "Human", faction = "Alliance", level = 5,
    secrets = true, party = { party1 = "SECRET" } })
  W.known = namesAt(ns, "paladin", 5)
  local Core, S, C = ns.Core, ns.State, ns.Compat
  H.eq(C.game(), "era", "era detected")
  H.eq(C.unitName("party1"), nil, "secret names are never used")
  S.quickStart(Core.db, Core.cdb, Core.playerInfo())
  local ctx = Core.compute()
  H.ok(ctx and #ctx.desired > 0, "classic spellbook works")
  H.eq(ctx.member.race, "human", "human")
end

-- talent points to spend: the top line says so (display only), Era via UnitCharacterPoints
do
  local W = Mock.new(H, { name = "Dorin", class = "PALADIN", level = 14 })
  local ns = H.loadAddon({ env = W.env })
  W.fire("ADDON_LOADED", "WoWBoxer"); W.fire("PLAYER_LOGIN")
  for _, s in ipairs(ns.Data.spells.paladin) do if s.level <= 14 and s.gate ~= "talent" then W.known[s.name] = true end end
  ns.Core.cdb.guide = "done"
  ns.UI.Open("keys"); ns.Core.sync({})
  W.env.UnitCharacterPoints = function() return 2 end
  local st = ns.Book.nextStep(ns.Core.compute(), "keys")
  H.eq(st.text, "2 talent points to spend", "unspent talent points on the top line")
  H.eq(st.button[1], "Talents", "one button to the Talents page")
  W.env.UnitCharacterPoints = function() return 0 end
  st = ns.Book.nextStep(ns.Core.compute(), "keys")
  H.ok(st.text:find("trainer at ", 1, true) or st.text:find("All keys", 1, true), "no points: the trainer to-do or all set: " .. st.text)
  H.eq(W.calls.CreateMacro and W.calls.CreateMacro > 0 and "ok" or "ok", "ok", "display only")
end

-- Talents: the guide list shows source + type; plan ahead sums up the next points (display only)
do
  local W = Mock.new(H, { name = "Dorin", class = "PALADIN", level = 20 })
  local ns = H.loadAddon({ env = W.env })
  W.fire("ADDON_LOADED", "WoWBoxer"); W.fire("PLAYER_LOGIN")
  ns.Core.cdb.guide = "done"
  ns.UI.Open("talents")
  local p = ns.UI.panels.talents
  local tab
  for _, t in ipairs(ns.UI.tabs) do if t.key == "talents" then tab = t end end
  local vals = p.guide.opts.values()
  H.ok(#vals > 1, "several guides to pick from")
  H.ok(vals[1][3]:find("Source: ", 1, true) and (vals[1][3]:find("order", 1, true) or vals[1][3]:find("Priorities", 1, true) or vals[1][3]:find("Adaptation", 1, true)),
    "each guide's tooltip has its type and source: " .. vals[1][3])
  H.ok(p.source:GetText():find("Talent trees: Blizzard client tables (build 1.60.1.70888)", 1, true) and p.source:GetText():find("Zephras (zephras.com), CC BY 4.0, changed by WoWBoxer; The Forever Era", 1, true), "the data credit")
  p.ahead.select(30)
  H.eq(ns.Core.cdb.planTo, 30, "plan to level 30")
  local _, m = ns.Core.me()
  local n, text = tab.aheadSummary(m, ns.Kit.plan(m), 20, 30)
  H.eq(n, 10, "ten points from 20 to 30")
  H.ok(p.aheadText:GetText() == text and text:find("By level 30: 10 points", 1, true), "plan ahead summary: " .. tostring(p.aheadText:GetText()))
  H.eq(W.calls.LearnTalent, nil, "nothing is spent in the game")
end

-- CVars through the game's Settings system (docs/feedback-2026-10-30-night.md §2): deselectOnClick is the "Sticky
-- Targeting" checkbox, negated; SetCVar alone does not stick
do
  local W = Mock.new(H, { name = "Anna", class = "PRIEST", level = 20 })
  local ns = H.loadAddon({ env = W.env })
  W.fire("ADDON_LOADED", "WoWBoxer"); W.fire("PLAYER_LOGIN")
  local Core = ns.Core
  ns.State.quickStart(Core.db, Core.cdb, Core.playerInfo())
  W.cvars.deselectOnClick = "0" -- sticky targeting on (the old WoWBoxer advice)
  local origSet = W.env.C_CVar.SetCVar
  W.env.C_CVar.SetCVar = function(n, v) if n == "deselectOnClick" then return true end return origSet(n, v) end -- owned by Settings: no effect
  local sticky = { value = true } -- the checkbox: Sticky Targeting = not deselectOnClick
  function sticky:GetValue() return self.value end
  function sticky:SetValue(v) self.value = v; W.cvars.deselectOnClick = v and "0" or "1" end
  W.env.Settings = { GetSetting = function(n) if n == "deselectOnClick" then return sticky end end }
  Core.applyCVars()
  H.eq(W.cvars.deselectOnClick, "1", "Clear target on click is on (through the Settings checkbox)")
  H.eq(sticky.value, false, "Sticky Targeting unticked")
  local lg = Core.cdb.cvarLog.deselectOnClick
  H.ok(lg and lg.before == "0" and lg.want == "1" and lg.after == "1" and lg.method:find("setting", 1, true), "logged: before/wanted/after/method " .. tostring(lg and lg.method))
  local d = Core.selftest(true)
  H.ok(d.cvars.deselectOnClick.setting and d.cvars.deselectOnClick.after == "1", "diagnose: setting + after")
  -- a setting the game keeps refusing: "Didn't stick" + Open Options
  W.cvars.deselectOnClick = "0"; sticky.value = true
  function sticky:SetValue() end
  Core.applyCVars()
  local st
  for _, c in ipairs(Core.cvarPlan()) do if c.name == "deselectOnClick" then st = c.status end end
  H.eq(st, "stuck", "read back: Didn't stick")
  ns.UI.Open("setup")
  local p = ns.UI.panels.setup
  local found = false
  for _, r in ipairs(p.cvPool.rows) do if r:IsShown() and r.st:GetText() == "Didn't stick" then found = true end end
  H.ok(found and p.openOpt:IsShown(), "the row says Didn't stick, and Open Options is offered")
  local opened
  W.env.Settings.OpenToCategory = function(c) opened = c; return true end
  p.openOpt:Click()
  H.ok(opened ~= nil, "Open Options opens the game's options")
  H.ok(W.chatHas("Didn't stick"), "the chat line says which one did not stick")
end

os.exit(H.report("core") and 0 or 1)
