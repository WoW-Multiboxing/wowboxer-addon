-- Owner feedback 9 Nov 2026 (Warlock on Forever):
--   1. spells that need no target are plain spells: the spell itself on the bar, no macro slot;
--   2. no "Pet attack" squad macro; "Pet back" is opt-in; old WBX macros are offered for removal, never deleted silently;
--   3. the slot counter refreshes on UPDATE_MACROS; the banner names the macros without a slot; when character
--      slots run out the general (account) slots are used, named per character so two characters never collide.
-- Run: lua tests/test_plain.lua
local dir = (arg[0]:match("^(.*)/[^/]+$") or ".")
local H = dofile(dir .. "/harness.lua")
local Mock = dofile(dir .. "/wowmock.lua")

local function boot(opts)
  local W = Mock.new(H, opts)
  if opts.db then W.env.WoWBoxerDB = opts.db end
  local ns = H.loadAddon({ env = W.env, gameType = opts.gameType })
  W.fire("ADDON_LOADED", "WoWBoxer")
  W.fire("PLAYER_LOGIN")
  ns.Core.cdb.guide = "done"
  for _, s in ipairs(ns.Data.spells[(opts.class or "WARLOCK"):lower()]) do
    if s.level <= (opts.level or 10) and s.gate ~= "talent" then W.known[s.name] = true end
  end
  W.flush()
  return W, ns
end
local function spell(ns, cls, name) for _, s in ipairs(ns.Data.spells[cls]) do if s.name == name then return s end end end
local function item(ctx, name) for _, it in ipairs(ctx.macros.items) do if it.name == name then return it end end end
local function bar(ctx, name) for _, b in ipairs(ctx.bars.items) do if b.name == name then return b end end end
local function desiredBy(ctx, pred) for _, d in ipairs(ctx.desired) do if pred(d) then return d end end end
local function macro(W, name) for _, l in ipairs({ W.char, W.acc }) do for _, m in ipairs(l) do if m.name == name then return m end end end end

-- ------------------------------------------------------------------ 1. the rule, from the data, in every game
for _, g in ipairs({ { "forever", 16001, nil }, { "era", 11509, "vanilla" }, { "tbc", 20506, "tbc" } }) do
  local W = Mock.new(H, { toc = g[2] })
  local ns = H.loadAddon({ env = W.env, gameType = g[3] })
  local E, K = ns.Engine, ns.Kit
  for _, leader in ipairs({ true, false }) do
    local ctx = { leader = leader, unit = "party1", wand = true, assist = not leader }
    local tag = g[1] .. (leader and " leader: " or " follower: ")
    for _, n in ipairs({ "Summon Imp", "Summon Voidwalker", "Demon Skin", "Life Tap", "Create Healthstone" }) do
      local s = spell(ns, "warlock", n)
      if s then H.ok(E.isPlain(s, ctx), tag .. n .. " is a plain spell") end
    end
    for _, n in ipairs({ "Shadow Bolt", "Immolate", "Corruption", "Fear", "Health Funnel" }) do
      local s = spell(ns, "warlock", n)
      if s then H.ok(not E.isPlain(s, ctx), tag .. n .. " stays a macro (it has a target chain)") end
    end
    H.ok(not E.isPlain(K.wandOf({ cls = "warlock" }), ctx), tag .. "the wand's Shoot is never plain")
    if g[1] ~= "tbc" or K.engage() then H.ok(not E.isPlain(K.engage(), ctx), tag .. "Engage Target (/startattack) stays a macro") end
    for _, cls in ipairs(ns.Data.classOrder) do
      for _, s in ipairs(ns.Data.spells[cls]) do
        if E.isPlain(s, ctx) then
          H.ok(E.PLAIN_ACTIONS[s.action], tag .. cls .. " " .. s.name .. ": plain only for self, petself, ground")
          H.eq(E.makeMacro(s, ctx), "#showtooltip " .. s.name .. "\n/cast " .. s.name, tag .. cls .. " " .. s.name .. ": the macro would add nothing")
        end
      end
    end
  end
  -- per game: Games/<Game>.lua can change the set
  ns.Data.game.plainActions = { ground = true }
  H.ok(not ns.Engine.isPlain(spell(ns, "warlock", "Summon Imp"), { leader = true }), g[1] .. ": plainActions per game replaces the set")
  ns.Data.game.plainActions = nil
end

-- ------------------------------------------------------------------ 1. drag and Place spells: the spell itself
do
  local W, ns = boot({ name = "Lock", class = "WARLOCK", race = "Scourge", level = 20 })
  local Core, UI = ns.Core, ns.UI
  UI.Open("keys")
  local ctx = Core.compute()
  local plain = desiredBy(ctx, function(d) return d.plain and d.group == "kit" end)
  H.ok(plain ~= nil, "warlock 20 has a plain kit key (" .. tostring(plain and plain.label) .. ")")
  local it = item(ctx, plain.name)
  H.eq(it.status, "spell", "a plain spell has no macro plan")
  local made = W.calls.CreateMacro or 0
  H.ok(Core.pickup(plain.name), "drag a plain key")
  H.ok(W.cursor and W.cursor.kind == "spell" and ns.Compat.isRankOf(W.cursor.id, plain.spell), "the cursor holds the spell itself")
  H.eq(W.calls.CreateMacro or 0, made, "no macro made by the drag")
  W.cursor = nil
  -- All spells: Summon Imp
  local imp = spell(ns, "warlock", "Summon Imp")
  local nExtras = #Core.cdb.extras
  H.ok(Core.pickupSpell(imp.id), "drag Summon Imp from All spells")
  H.ok(W.cursor and W.cursor.kind == "spell" and ns.Compat.isRankOf(W.cursor.id, imp), "Summon Imp: the spell on the cursor")
  H.eq(#Core.cdb.extras, nExtras, "Summon Imp does not become an extra macro")
  W.cursor = nil
  -- a spell with a target still makes a macro
  local sb = spell(ns, "warlock", "Corruption")
  H.ok(Core.pickupSpell(sb.id), "drag Corruption")
  H.ok(W.cursor and W.cursor.kind == "macro", "Corruption: a macro (target chain) on the cursor")
  W.cursor = nil
  -- Place spells: plain keys on their fixed buttons as spells
  Core.sync({ page = "spells" })
  W.flush()
  local slot = Core.cdb.slots[plain.name]
  H.ok(slot and W.actions[slot] and W.actions[slot].kind == "spell" and ns.Compat.isRankOf(W.actions[slot].id, plain.spell), "Place spells puts the spell itself on its button")
  for _, m in ipairs(W.char) do H.ok(m.name ~= plain.name, "no macro " .. plain.name) end
  local after = Core.compute()
  H.eq(bar(after, plain.name).status, "placed", "the plain spell counts as on its bar")
  Core.scanBars()
  H.eq(Core.cdb.slots[plain.name], slot, "bar memory keeps the plain spell's button")
  H.eq(Core.compute().bars.changes, 0, "nothing left to place")
  -- the tooltip says which slot type
  H.ok(ns.Book.slotText(item(after, plain.name)):find("no macro slot", 1, true), "tooltip: a plain spell uses no macro slot")
  H.ok(ns.Book.slotText(item(after, "WBX K1")):find("character macro slot", 1, true), "tooltip: K1 uses a character macro slot")
  -- Advanced: own targeting on a plain key makes it a macro again
  Core.cdb.overrides[plain.name] = ns.Override.clean({ targets = { { who = "player", help = true } } })
  local ov = desiredBy(Core.compute(), function(d) return d.name == plain.name end)
  H.ok(not ov.plain and ov.body:find("/cast", 1, true), "own targeting on a plain key: a macro again")
  Core.cdb.overrides[plain.name] = nil
end

-- ------------------------------------------------------------------ 1. an old WBX macro of a plain spell
do
  local W, ns = boot({ name = "Lock", class = "WARLOCK", race = "Scourge", level = 20 })
  local Core = ns.Core
  ns.State.quickStart(Core.db, Core.cdb, Core.playerInfo())
  local ctx = Core.compute()
  local plain = desiredBy(ctx, function(d) return d.plain and d.group == "kit" end)
  W.addMacro(plain.name, "#showtooltip " .. plain.label .. "\n/cast " .. plain.label, true) -- what 1.2 made
  W.addMacro("Mine", "/cast Fear", true)
  local slot = 1 + (tonumber(plain.key:sub(2)) - 1)
  W.env.PickupMacro(W.indexOf(macro(W, plain.name))); W.env.PlaceAction(slot); W.cursor = nil
  Core.scanBars()
  ctx = Core.compute()
  H.eq(bar(ctx, plain.name).status, "convert", "its button holds the old macro: becomes the spell on Place")
  local unused = table.concat(ctx.macros.unused, ",")
  H.ok(unused:find(plain.name, 1, true), "the old macro is offered for removal: " .. unused)
  H.ok(not unused:find("Mine", 1, true), "the player's own macro is never offered")
  local step = ns.Book.nextStep(ctx, "keys")
  H.ok(step.button and step.button[1]:find("Remove", 1, true) and step.tip:find(plain.name, 1, true), "banner offers Remove and names it: " .. step.text)
  Core.sync({})
  W.flush()
  H.ok(W.actions[slot] and W.actions[slot].kind == "spell", "Place: the button now holds the spell")
  H.ok(macro(W, plain.name) ~= nil, "sync never deletes the old macro by itself")
  Core.removeUnused()
  H.ok(macro(W, plain.name) == nil, "Remove: the old WBX macro is gone")
  H.ok(macro(W, "Mine") ~= nil, "Remove: the player's own macro stays")
  H.ok(W.actions[slot] and W.actions[slot].kind == "spell", "Remove: the spell stays on its button")
end

-- ------------------------------------------------------------------ 1. a higher rank goes on the bar
do
  local W, ns = boot({ name = "Lock", class = "WARLOCK", race = "Scourge", level = 20, gameType = "vanilla", toc = 11509 })
  local Core = ns.Core
  ns.State.quickStart(Core.db, Core.cdb, Core.playerInfo())
  local ctx = Core.compute()
  local d = desiredBy(ctx, function(x) return x.plain and #x.spell.ranks >= 2 end)
  if d then
    local r1, r2 = d.spell.ranks[1].id, d.spell.ranks[2].id
    W.knownIds[r1], W.knownIds[r2] = true, true
    local slot = bar(ctx, d.name).slot
    W.actions[slot] = { kind = "spell", id = r1 }
    Core.cdb.slots[d.name] = slot; Core.cdb.spellSlots = { [d.name] = true }
    H.eq(bar(Core.compute(), d.name).status, "rank", d.label .. ": rank 1 on the bar, rank 2 known")
    Core.sync({ page = "spells" })
    H.eq(W.actions[slot].id, r2, d.label .. ": Place spells puts the highest known rank there")
  else H.ok(false, "era warlock 20: a plain spell with ranks") end
end

-- ------------------------------------------------------------------ 2. squad macros: no Pet attack, Pet back opt-in
do
  local W, ns = boot({ name = "Lock", class = "WARLOCK", race = "Scourge", level = 20 })
  local Core, M = ns.Core, ns.Macros
  ns.State.quickStart(Core.db, Core.cdb, Core.playerInfo())
  Core.setPlaysAs("party1")
  W.addMacro("WBX Pet", "#showtooltip\n/petattack [@mouseover,harm,nodead][@party1target,harm,nodead][harm,nodead]", true)
  W.addMacro("WBX PetBack", "/petpassive\n/petfollow", true)
  local ctx = Core.compute()
  H.ok(desiredBy(ctx, function(d) return d.key == "Pet" end) == nil, "no Pet attack squad macro")
  H.ok(desiredBy(ctx, function(d) return d.key == "PetBack" end) == nil, "Pet back is off by default")
  local list = M.squadKeyList(ctx.member, Core.cdb.squadKeys, ctx.squad)
  local pb
  for _, k in ipairs(list) do H.ok(k.key ~= "Pet", "no Pet tick"); if k.key == "PetBack" then pb = k end end
  H.ok(pb and not pb.on, "Squad page: a Pet back tick, unticked")
  local dmg = desiredBy(ctx, function(d) return d.group == "kit" and not d.plain end)
  H.ok(dmg.body:find("/petattack", 1, true), "damage macros still send the pet: " .. dmg.name)
  local unused = table.concat(ctx.macros.unused, ",")
  H.ok(unused:find("WBX Pet", 1, true) and unused:find("WBX PetBack", 1, true), "old pet macros offered for removal: " .. unused)
  Core.sync({})
  H.ok(macro(W, "WBX Pet") and macro(W, "WBX PetBack"), "never deleted without the click")
  ns.Book.setSquadKey("PetBack", true)
  ctx = Core.compute()
  H.ok(desiredBy(ctx, function(d) return d.key == "PetBack" end) ~= nil, "ticked: Pet back is a squad macro again")
  H.ok(not table.concat(ctx.macros.unused, ","):find("PetBack", 1, true), "ticked: WBX PetBack is no longer unused")
  Core.removeUnused()
  H.ok(macro(W, "WBX Pet") == nil and macro(W, "WBX PetBack") ~= nil, "Remove deletes WBX Pet, keeps the ticked Pet back")
end

-- ------------------------------------------------------------------ 3. slot counter, banner, UPDATE_MACROS
do
  local W, ns = boot({ name = "Lock", class = "WARLOCK", race = "Scourge", level = 20, maxChar = 3 })
  local Core, UI = ns.Core, ns.UI
  for i = 1, 3 do W.addMacro("Mine" .. i, "/cast Fear", true) end
  for i = 1, 120 do W.addMacro(string.format("Acc%03d", i), "/cast Fear", false) end
  ns.State.quickStart(Core.db, Core.cdb, Core.playerInfo())
  UI.Open("keys")
  local ctx = Core.compute()
  H.ok(ctx.macros.counts.noslot > 0, "all slots full: macros without a slot")
  local step = ns.Book.nextStep(ctx, "keys")
  H.ok(step.tip:find(ctx.macros.noslotNames[1], 1, true), "banner names the macros: " .. step.tip)
  H.ok(UI.meter.text:GetText():find("3 of 3", 1, true), "meter: 3 of 3")
  -- the player deletes a macro in /macro: UPDATE_MACROS refreshes everything
  local changed = 0
  local orig = Core.changed
  Core.changed = function() changed = changed + 1; orig() end
  W.env.DeleteMacro(121)
  W.fire("UPDATE_MACROS"); W.fire("UPDATE_MACROS"); W.fire("UPDATE_MACROS")
  W.flush()
  Core.changed = orig
  H.eq(changed, 1, "UPDATE_MACROS: one refresh for a burst of events")
  H.ok(UI.meter.text:GetText():find("2 of 3", 1, true), "meter after the delete: " .. UI.meter.text:GetText())
  local after = Core.compute()
  H.eq(after.macros.counts.create, 1, "the freed slot is planned at once")
  H.eq(after.macros.counts.noslot, ctx.macros.counts.noslot - 1, "one macro fewer without a slot")
  local _, used = ns.Compat.numMacros()
  H.eq(after.macros.charUsed, used, "the plan counts what /macro shows")
end

-- ------------------------------------------------------------------ 3. general slots, named per character
do
  local W1, ns1 = boot({ name = "Ripper", class = "WARLOCK", race = "Scourge", level = 20, maxChar = 1 })
  local C1 = ns1.Core
  W1.addMacro("Mine", "/cast Fear", true)
  ns1.State.quickStart(C1.db, C1.cdb, C1.playerInfo())
  C1.setPlaysAs("party1")
  C1.sync({})
  local tag1 = C1.db.macroTags[C1.charKey]
  local mine1 = {}
  for _, m in ipairs(W1.acc) do if m.name:sub(1, 3) == "WBX" then mine1[#mine1 + 1] = m.name end end
  H.ok(#mine1 > 0, "character slots full: macros in general slots (" .. table.concat(mine1, ", ") .. ")")
  H.eq(tag1, "Ri", "tag from the name")
  for _, n in ipairs(mine1) do H.ok(#n <= 16 and n:sub(1, 6) == "WBXRi ", "general macro name: " .. n) end
  local ctx1 = C1.compute()
  H.eq(ctx1.macros.changes, 0, "after sync nothing to change")
  local acc = desiredBy(ctx1, function(d) return item(ctx1, d.name).account end)
  H.ok(ns1.Book.slotText(item(ctx1, acc.name)):find("general macro slot", 1, true), "tooltip: general macro slot, named " .. item(ctx1, acc.name).gameName)
  H.eq(bar(ctx1, acc.name).status, "placed", "a general macro counts as on its bar")
  -- a second character of the same WoW account: same SavedVariables, same general macros
  local W2, ns2 = boot({ name = "Ripley", class = "WARLOCK", race = "Scourge", level = 20, maxChar = 1, db = C1.db })
  W2.acc = W1.acc
  local C2 = ns2.Core
  W2.addMacro("Mine", "/cast Fear", true)
  ns2.State.quickStart(C2.db, C2.cdb, C2.playerInfo())
  C2.setPlaysAs("party1")
  C2.sync({})
  local tag2 = C2.db.macroTags[C2.charKey]
  H.ok(tag2 and tag2 ~= tag1, "the second character gets its own tag: " .. tostring(tag2))
  for _, n in ipairs(mine1) do
    local m = macro(W1, n)
    H.ok(m ~= nil, "the first character's general macro is still there: " .. n)
  end
  local ctx2 = C2.compute()
  for _, it in ipairs(ctx2.macros.items) do if it.account then H.ok(it.gameName:sub(1, 6) == "WBX" .. tag2 .. " ", "second character's names: " .. it.gameName) end end
  for _, n in ipairs(ctx2.macros.unused) do H.ok(n:sub(1, 6) ~= "WBXRi ", "the other character's macros are never unused here: " .. n) end
  H.eq(ns2.Macros.deleteUnused(mine1), 0, "deleteUnused never removes another character's general macro")
  -- the first character again: everything still the same
  ns1.Macros.setTag(tag1)
  H.eq(C1.compute().macros.changes, 0, "the first character sees no change after the second one's sync")
end

os.exit(H.report("plain") and 0 or 1)
