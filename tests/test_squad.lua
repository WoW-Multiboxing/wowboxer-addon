-- The squad (docs/squad-overhaul.md §3): data model (order, tags, presets, notes), Add my party,
-- unit hint, readiness, key map, levelling plan and the share string carrying it all.
local dir = (arg[0]:match("^(.*)/[^/]+$") or ".")
local H = dofile(dir .. "/harness.lua")
local Mock = dofile(dir .. "/wowmock.lua")

local function boot(opts)
  local W = Mock.new(H, opts)
  local ns = H.loadAddon({ env = W.env })
  W.fire("ADDON_LOADED", "WoWBoxer"); W.fire("PLAYER_LOGIN")
  ns.Core.cdb.guide = "done"
  for _, s in ipairs(ns.Data.spells[(opts.class or "PALADIN"):lower()]) do if s.level <= (opts.level or 10) and s.gate ~= "talent" then W.known[s.name] = true end end
  return W, ns
end
local function errors(ns)
  local n = {}
  for _, e in ipairs(ns.Core.db.log) do if e.l == "error" then n[#n + 1] = e.m end end
  return table.concat(n, " | ")
end

-- ------------------------------------------------------------------ data model
do
  local _, ns = boot({})
  local S = ns.State
  local s = S.newSquad({ name = "Trio", members = {
    { id = "a", name = "Dorin", cls = "paladin", race = "undead", role = "tank", leader = true, tags = { "tank", "bogus", "tank" } },
    { id = "b", name = "Wowtwo", cls = "priest", race = "undead", role = "healer" },
    { id = "c", name = "Lock", cls = "warlock", race = "undead", role = "ranged" } },
    presets = { { id = "p1", name = "Questing", leader = "a", roles = { a = "tank", b = "healer", c = "nonsense" } },
      { id = "p2", name = "Ghost", leader = "zzz" } }, activePreset = "p1", notes = "Our trio\n" })
  H.eq(table.concat(s.members[1].tags, ","), "tank", "tags: whitelist, no duplicates")
  H.eq(#s.presets, 1, "a preset with an unknown leader is dropped")
  H.eq(s.presets[1].roles.c, nil, "a role the class cannot have is dropped")
  H.eq(s.activePreset, "p1", "active preset kept")
  H.eq(s.notes, "Our trio", "notes cleaned")
  -- order
  H.ok(S.moveMember(s, 3, 1), "move")
  H.eq(s.members[1].name, "Lock", "slot 1 is now Lock")
  H.eq(S.slotOf(s, s.members[2]), 2, "slot of a member")
  H.ok(not S.moveMember(s, 9, 1), "bad index ignored")
  -- presets
  s.members[2].leader = false; s.members[1].leader = true; s.members[3].role = "melee"
  local p = S.savePreset(s, "Lock leads")
  H.eq(p.leader, s.members[1].id, "preset remembers the leader")
  H.eq(s.activePreset, p.id, "saved preset is active")
  H.ok(S.applyPreset(s, "p1"), "switch back to Questing")
  H.ok(S.member(s, "a").leader and not s.members[1].leader, "Dorin leads again")
  H.eq(S.member(s, "b").role, "healer", "roles from the preset")
  local again = S.savePreset(s, "lock LEADS")
  H.eq(again.id, p.id, "same name (any case) overwrites")
  -- composition
  local hints = table.concat(S.composition(S.newSquad({ members = { { cls = "warrior", role = "tank" }, { cls = "warrior", role = "tank" }, { cls = "mage" } } })), " ")
  H.ok(hints:find("No healer") and hints:find("2 tanks"), "composition hints: " .. hints)
  -- tags from class + role
  H.eq(table.concat(S.tagsOf(S.newMember({ cls = "warlock", role = "ranged" })), ","), "caster,pet", "auto tags")
  -- setClass resets class-bound data
  local m = S.newMember({ cls = "priest", role = "healer", race = "undead", build = {}, customSeq = { { name = "x", steps = { "Smite" } } } })
  S.setClass(s, m, "warrior")
  H.ok(m.cls == "warrior" and m.role == "tank" and #m.customSeq == 0, "class change resets role and own keys")
  -- share string carries presets, notes and tags
  local str = ns.Share.export(s, {})
  local res = ns.Share.import(str)
  H.ok(res ~= nil, "export imports")
  H.eq(#res.squad.presets, #s.presets, "presets travel")
  H.eq(res.squad.notes, "Our trio", "notes travel")
  H.eq(table.concat(res.squad.members[2].tags, ","), "tank", "tags travel")
end

-- ------------------------------------------------------------------ the live party: Add my party, unit hint
do
  local W, ns = boot({ name = "Wowtwo", class = "PRIEST", race = "Scourge", level = 20,
    party = { party1 = "Lock", party2 = "Dorin" },
    partyInfo = { party1 = { class = "WARLOCK", race = "Scourge", level = 19 }, party2 = { class = "PALADIN", race = "Scourge", level = 21, leader = true } } })
  local Core, UI, SQ = ns.Core, ns.UI, ns.Squad
  local info = SQ.partyInfo()
  H.eq(#info, 3, "me + two party members")
  H.eq(info[1].name, "Wowtwo", "this character first")
  H.eq(info[3].cls, "paladin", "class from the game")
  H.eq(info[3].race, "undead", "race from the game")
  H.ok(info[3].leader and not info[1].leader, "group leader from the game")
  H.eq(SQ.unitOf("Dorin"), "party2", "Dorin is party2 here")
  UI.Open("squad")
  ns.SquadPages.select(UI.panels.squad, "edit")
  local n = ns.SquadPages.addParty()
  H.eq(n, 2, "Add my party adds the two others")
  local s, me = Core.me()
  H.eq(#s.members, 3, "squad of three")
  H.ok(ns.State.leaderOf(s).name == "Dorin", "the party leader leads")
  H.eq(ns.SquadPages.addParty(), 0, "nobody twice")
  -- I follow via party1 by default, but Dorin is party2 here
  H.ok(not me.leader and me.unit == "party1", "this character follows via party1")
  local hu = SQ.unitHint()
  H.eq(hu, "party2", "unit hint: use party2")
  UI.Select("keys")
  local step = ns.Book.nextStep(Core.compute(), "keys")
  H.ok(step.text:find("Dorin is party2 here", 1, true) ~= nil, "the book's next step offers the unit: " .. step.text)
  H.eq(step.button[1], "Use party2", "one button")
  step.button[3]()
  H.eq(me.unit, "party2", "one click fixes it")
  H.eq(SQ.unitHint(), nil, "no hint any more")
  -- readiness of this character
  local r = SQ.myReady()
  H.eq(r.unit, 1, "unit OK now")
  H.ok(r.keys > 0, "keys to create before Place all")
  Core.sync({})
  H.eq(SQ.myReady().keys, 0, "keys OK after Place all")
  -- readiness rows + the pages render
  local rows = SQ.readiness()
  H.eq(#rows, 3, "one row per member")
  H.ok(rows[1].me, "this character's row (slot 1)")
  H.ok(not rows[2].signal, "no signal from the others yet")
  for _, def in ipairs(ns.SquadPages.pages) do ns.SquadPages.select(UI.panels.squad, def.key) end
  -- key map + cheat sheet
  local map = SQ.keyMap(s)
  H.eq(#map.rows, 3, "key map: one row per member")
  H.ok(map.rows[1].cells.K1 ~= nil, "key 1 of the paladin")
  H.ok(map.rows[2].cells.Follow, "followers have Follow")
  H.ok(not map.rows[3].cells.Follow, "the leader has no Follow key")
  local sheet = SQ.cheatSheet(s)
  H.ok(sheet:find("Key 1 – ", 1, true) ~= nil and sheet:find("Dorin: ", 1, true) ~= nil, "cheat sheet text")
  -- plan
  local tl, names = SQ.nextTrainer({ cls = "priest", race = "undead", role = "healer", level = 20, guide = me.guide, build = {}, talented = 0 })
  H.ok(tl and tl > 20 and #names > 0, "next trainer visit after level 20")
  local nt = SQ.nextTalent(me)
  H.ok(nt and nt.level >= 10 and nt.name, "next talent from the guide")
  H.eq(errors(ns), "", "no errors (party)")
end

os.exit(H.report("squad") and 0 or 1)
