-- Advanced mode, own targeting per key (docs/advanced-mode.md §6): every target kind, pet units, the modifier line,
-- the 255 error, member-unit remapping after a regroup, a member not in the party, frozen text keys on level-up,
-- Back to WoWBoxer's version, and the whitelist / conditionals checks for text overrides.
local dir = (arg[0]:match("^(.*)/[^/]+$") or ".")
local H = dofile(dir .. "/harness.lua")
local Mock = dofile(dir .. "/wowmock.lua")

local INFO = { class = "PALADIN", race = "Scourge", level = 20 }
local W = Mock.new(H, { name = "Anna", class = "PRIEST", race = "Scourge", level = 20, party = { party1 = "Bo", party2 = "Dorin" },
  partyInfo = { party1 = { class = "HUNTER", race = "Orc", level = 20 }, party2 = INFO } })
local ns = H.loadAddon({ env = W.env })
W.fire("ADDON_LOADED", "WoWBoxer"); W.fire("PLAYER_LOGIN")
for _, s in ipairs(ns.Data.spells.priest) do if s.level <= 20 and s.gate ~= "talent" then W.known[s.name] = true end end
local Core, O, S = ns.Core, ns.Override, ns.State
local sq = S.newSquad({ name = "Trio", members = {
  { name = "Dorin", cls = "paladin", race = "undead", role = "tank", leader = true },
  { name = "Anna", cls = "priest", race = "undead", role = "healer", unit = "party2" },
  { name = "Bo", cls = "hunter", race = "orc", role = "ranged", unit = "party2" } } })
Core.db.squads = { sq }; Core.db.active = sq.id
Core.cdb.guide = "done"
local s, me = Core.me()
local ctx = { squad = s, me = me }

local function desired(name) for _, d in ipairs(Core.compute().desired) do if d.name == name then return d end end end
local heal
for _, d in ipairs(Core.compute().desired) do if not heal and d.group == "kit" and d.body:find("help", 1, true) then heal = d end end
H.ok(heal ~= nil, "a heal key: " .. tostring(heal and heal.name))
local NAME, ENGINE = heal.name, heal.body

-- the engine's targets read back as meanings
local base = O.fromBody(ENGINE, ctx)
local kinds = {}
for _, t in ipairs(base) do kinds[#kinds + 1] = t.who end
H.ok(table.concat(kinds, ","):find("leader", 1, true), "prefill: the engine's chain read back (" .. table.concat(kinds, ",") .. ")")

-- every target kind on this client
local function cond(t) return (O.cond(t, ctx)) end
H.eq(cond({ who = "mouseover", help = true, nodead = true }), "[@mouseover,help,nodead]", "mouseover")
H.eq(cond({ who = "target", help = false, nodead = true }), "[@target,harm,nodead]", "your target")
H.eq(cond({ who = "leader", help = true, nodead = true }), "[@party2,help,nodead]", "the leader: Dorin is party2 here")
H.eq(cond({ who = "leadertarget", help = false, nodead = true }), "[@party2target,harm,nodead]", "the leader's target")
H.eq(cond({ who = "member", name = "Bo", help = true, nodead = true }), "[@party1,help,nodead]", "a member by name: Bo is party1")
H.eq(cond({ who = "member", name = "Bo", pet = true, help = true, nodead = true }), "[@party1pet,help,nodead]", "Bo's pet: party1pet")
H.eq(cond({ who = "member", name = "Anna", help = true }), "[@player,help]", "myself by name: player, Skip if dead off")
H.eq(cond({ who = "mypet", help = true, nodead = true }), "[@pet,help,nodead]", "my pet")
H.eq(cond({ who = "unit", unit = "party3pet", help = true, nodead = true }), "[@party3pet,help,nodead]", "a raw unit")
H.eq(cond({ who = "focus", help = true, nodead = true }), "[@focus,help,nodead]", "focus")
H.eq(cond({ who = "targettarget", nodead = true }), "[@targettarget,nodead]", "target of target")
H.eq(cond({ who = "player", help = true }), "[@player,help]", "myself")
H.eq(O.meaning({ who = "member", name = "Bo", pet = true, help = true, nodead = true }, ctx), "Casts on Bo's pet when it exists, is friendly and is alive", "hover meaning")
H.eq(O.clean({ targets = { { who = "member", name = "" }, { who = "evil" }, { who = "unit", unit = "raid41" }, { who = "unit", unit = "boss1" } } }), nil, "bad targets are dropped")
-- raid units: raid1–40 and their pets are allowed (a macro with them still works in a party: the unit is skipped)
H.eq(#O.RAW_UNITS, 8 + 80, "8 party units + 80 raid units")
H.eq(O.clean({ targets = { { who = "unit", unit = "raid40pet" } } }).targets[1].unit, "raid40pet", "raid40pet is kept")
H.eq(cond({ who = "unit", unit = "raid12", help = true, nodead = true }), "[@raid12,help,nodead]", "raid unit conditional")
H.eq(#O.checkConditionals("/cast [@raid40pet,help,nodead][@party4pet,help][@player] Heal"), 0, "raid and party pets pass the conditional check")

-- Also heal Bo's pet: after the leader, one click
H.ok(Core.alsoHeal(NAME, "Bo"), "Also heal Bo's pet")
local d = desired(NAME)
local a, b = d.body:find("[@party2,help,nodead]", 1, true), d.body:find("[@party1pet,help,nodead]", 1, true)
H.ok(a and b and b > a, "Bo's pet comes after the leader: " .. d.body)
H.ok(d.ok and #d.body <= 255, "still a valid macro (" .. #d.body .. ")")
H.ok(d.override and Core.cdb.overrides[NAME].targets, "stored per character")
local stored = Core.cdb.overrides[NAME].targets
local petRow
for _, t in ipairs(stored) do if t.pet then petRow = t end end
H.ok(petRow and petRow.who == "member" and petRow.name == "Bo" and petRow.unit == nil, "stored by meaning (Bo's pet), not as party1pet")
H.eq(Core.alsoHeal(NAME, "Bo"), false, "not twice")
H.eq(O.summary(Core.cdb.overrides[NAME], ctx):find("Bo's pet", 1, true) ~= nil, true, "tooltip summary: " .. O.summary(Core.cdb.overrides[NAME], ctx))
-- regroup: Bo is party3 now → the key follows after the usual Update (status "update")
Core.sync({})
W.party = { party2 = "Dorin", party3 = "Bo" }
W.partyInfo = { party2 = INFO, party3 = { class = "HUNTER", race = "Orc", level = 20 } }
d = desired(NAME)
H.ok(d.body:find("[@party3pet,help,nodead]", 1, true), "regroup: remapped to party3pet")
local st
for _, it in ipairs(Core.compute().macros.items) do if it.name == NAME then st = it.status end end
H.eq(st, "update", "regroup: the key shows as to update")
-- Bo not in the party: that row is left out, with a warning
W.party = { party2 = "Dorin" }
d = desired(NAME)
H.ok(not d.body:find("pet", 1, true) and d.ovMissing and d.ovMissing[1] == "Bo's pet", "member not in the party: left out + warned")
W.party = { party1 = "Bo", party2 = "Dorin" }
W.partyInfo = { party1 = { class = "HUNTER", race = "Orc", level = 20 }, party2 = INFO }

-- modifier line + options
Core.setOverride(NAME, { targets = stored, mod = "shift" })
d = desired(NAME)
H.ok(d.body:find("[mod:shift,@player][", 1, true), "modifier: [mod:shift,@player] first")
-- too long: the 255 error in plain words
local many = {}
for i = 1, 8 do many[i] = { who = "unit", unit = O.RAW_UNITS[i], help = true, nodead = true } end
Core.setOverride(NAME, { targets = many, mod = "shift" })
d = desired(NAME)
if #d.body > 255 then
  H.ok(not d.ok and d.why:find("remove a target or untick Skip if dead", 1, true), "too long: " .. tostring(d.why))
else H.ok(d.ok, "eight targets still fit (" .. #d.body .. ")") end
-- an enemy key: startattack / petattack / reset options
local dps
for _, x in ipairs(Core.compute().desired) do if not dps and x.group == "kit" and x.body:find("harm", 1, true) then dps = x end end
Core.setOverride(dps.name, { targets = { { who = "leadertarget", help = false, nodead = true } }, startattack = true })
local dd = desired(dps.name)
H.ok(dd.body:find("\n/startattack [@party2target,harm,nodead]", 1, true), "startattack on, on the same chain: " .. dd.body)
Core.setOverride(dps.name, nil)
H.eq(desired(dps.name).body, dps.body, "Back to WoWBoxer's version")

-- text overrides: whitelist + conditionals, frozen on level-up
for _, bad in ipairs({ "/run DoEmote('dance')", "/script print(1)", "/console foo 1", "/click Button" }) do
  H.ok(not O.checkText(NAME, bad), "refused: " .. bad)
end
local okc, probs = O.checkText(NAME, "/cast [@party9,help][bogus] Heal")
H.ok(not okc and table.concat(probs, " "):find("bogus", 1, true), "unknown conditional refused: " .. table.concat(probs, "; "))
H.ok(O.checkText(NAME, "#showtooltip\n/cast [@mouseover,help,nodead][@party1pet,help,nodead][@player] Heal"), "a plain macro passes")
Core.setOverride(NAME, { text = "#showtooltip\n/cast [@mouseover,help,nodead][@player] Lesser Heal" })
Core.sync({})
d = desired(NAME)
H.ok(d.frozen and d.body:find("Lesser Heal", 1, true), "text override used, frozen")
W.player.level = 30
for _, sp in ipairs(ns.Data.spells.priest) do if sp.level <= 30 and sp.gate ~= "talent" then W.known[sp.name] = true end end
W.fire("PLAYER_LEVEL_UP", 30); W.flush()
for _, it in ipairs(Core.compute().macros.items) do if it.name == NAME then st = it.status end end
H.eq(st, "same", "frozen text key: not updated on level-up")
local pending = select(3, Core.pending(Core.compute()))
for _, it in ipairs(pending) do H.ok(it.name ~= NAME, "frozen key not in the level-up reminder") end
Core.setOverride(NAME, nil)
for _, it in ipairs(Core.compute().macros.items) do if it.name == NAME then st = it.status end end
H.eq(st, "update", "Back to WoWBoxer's version unfreezes it (the new level's macro)")

-- the engine is untouched; share strings carry no overrides
Core.alsoHeal(NAME, "Bo")
local str = ns.Share.export(s, {})
H.ok(not str:find("party1pet", 1, true) and not str:find("override", 1, true), "the share string carries no override macro text")
H.eq(W.calls.CreateMacro ~= nil, true, "macros only written by the Update clicks above")
os.exit(H.report("override") and 0 or 1)
