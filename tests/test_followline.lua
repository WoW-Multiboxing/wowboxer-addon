-- Follow in a line (docs/follow-line.md): Follow (line) follows the member ahead through THIS client's party unit,
-- Follow leader is the old Follow; both on party units, never names; the slot is saved only after a click.
local dir = (arg[0]:match("^(.*)/[^/]+$") or ".")
local H = dofile(dir .. "/harness.lua")
local Mock = dofile(dir .. "/wowmock.lua")

--- A client of the squad Dorin (leader) → Anna → Bo → Cid, logged in as `me`, with its own party slots.
local function boot(me, cls, party, partyInfo)
  local W = Mock.new(H, { name = me, class = cls, race = "Scourge", level = 20, party = party, partyInfo = partyInfo })
  local ns = H.loadAddon({ env = W.env })
  W.fire("ADDON_LOADED", "WoWBoxer"); W.fire("PLAYER_LOGIN")
  for _, s in ipairs(ns.Data.spells[cls:lower()]) do if s.level <= 20 and s.gate ~= "talent" then W.known[s.name] = true end end
  local S = ns.State
  local s = S.newSquad({ name = "Line", members = {
    { name = "Dorin", cls = "paladin", race = "undead", role = "tank", leader = true },
    { name = "Anna", cls = "priest", race = "undead", role = "healer", unit = "party1" },
    { name = "Bo", cls = "warlock", race = "undead", role = "ranged", unit = "party1" },
    { name = "Cid", cls = "mage", race = "undead", role = "ranged", unit = "party1" } } })
  ns.Core.db.squads = { s }; ns.Core.db.active = s.id
  ns.Core.cdb.guide = "done"
  return W, ns, s
end
local function key(ns, name) for _, d in ipairs(ns.Core.compute().desired) do if d.name == name then return d end end end
local function errors(ns)
  local n = {}
  for _, e in ipairs(ns.Core.db.log) do if e.l == "error" then n[#n + 1] = e.m end end
  return table.concat(n, " | ")
end
local INFO = { class = "PRIEST", race = "Scourge", level = 20 }

-- the leader: no follow keys
do
  local _, ns = boot("Dorin", "PALADIN", {}, {})
  H.eq(key(ns, "WBX Follow"), nil, "leader: no Follow (line)")
  H.eq(key(ns, "WBX FollowLead"), nil, "leader: no Follow leader")
end

-- follower 1 (Anna): both keys follow the leader's unit
do
  local _, ns = boot("Anna", "PRIEST", { party1 = "Bo", party2 = "Dorin" }, { party1 = INFO, party2 = INFO })
  local _, me = ns.Core.me()
  me.unit = "party2"
  H.eq(key(ns, "WBX Follow").body, "/follow party2", "follower 1: Follow (line) follows the leader")
  H.eq(key(ns, "WBX FollowLead").body, "/follow party2", "follower 1: Follow leader too")
end

-- follower 2 (Bo): follows Anna through Bo's own party slot; saved after a click; reshuffle → hint + Fix
do
  local W, ns, s = boot("Bo", "WARLOCK", { party1 = "Dorin", party2 = "Cid", party3 = "Anna" }, { party1 = INFO, party2 = INFO, party3 = INFO })
  local Core = ns.Core
  local _, me = Core.me()
  H.eq(key(ns, "WBX Follow").body, "/follow party3", "follower 2: follows Anna as party3 on this client")
  H.eq(key(ns, "WBX FollowLead").body, "/follow party1", "Follow leader: the leader's unit (today's body)")
  for _, n in ipairs({ "WBX Follow", "WBX FollowLead" }) do H.ok(not key(ns, n).body:find("Anna", 1, true) and not key(ns, n).body:find("Dorin", 1, true), "no names in " .. n) end
  H.eq(me.lineUnit, nil, "nothing saved before a click")
  H.eq(ns.Squad.lineHint(), nil, "no hint before a slot was ever saved")
  Core.sync({})
  H.eq(me.lineUnit, "party3", "Place all saves the line slot")
  H.eq(W.slotMacroName(11), "WBX Follow", "placement: Follow (line) keeps primary slot 11")
  local slotL
  for slot = 1, 120 do if W.slotMacroName(slot) == "WBX FollowLead" then slotL = slot end end
  H.ok(slotL and slotL >= 61 and slotL <= 72, "placement: Follow leader on the secondary bar (" .. tostring(slotL) .. ")")
  -- the party reshuffles: Anna is party2 now
  W.party = { party1 = "Dorin", party2 = "Anna", party3 = "Cid" }
  local item
  for _, it in ipairs(Core.compute().macros.items) do if it.name == "WBX Follow" then item = it end end
  H.eq(item.status, "update", "reshuffle: Follow (line) shows as to update")
  local u, ahead = ns.Squad.lineHint()
  H.ok(u == "party2" and ahead.name == "Anna", "reshuffle: the hint names the new slot")
  local fix
  for _, it in ipairs(ns.Checklist.items()) do if it.fix and it.fix.label == "Use party2" then fix = it end end
  H.ok(fix ~= nil and fix.text:find("you follow Anna (party2)", 1, true), "checklist: Follow (line): you follow Anna (party2) + Fix Use party2")
  H.eq(ns.Book.nextStep(Core.compute(), "keys").button[1], "Use party2", "the book's top line offers the same Fix")
  local before = W.calls.EditMacro or 0
  fix.fix.fn()
  H.eq(me.lineUnit, "party2", "Fix saves WoWBoxer data")
  H.eq(W.calls.EditMacro or 0, before, "the Fix never writes the macro")
  H.eq(ns.Squad.lineHint(), nil, "no hint after the Fix")
  -- no party: the saved slot, then the leader
  W.party, W.env.IsInGroup = {}, function() return false end
  W.env.GetNumGroupMembers = function() return 0 end
  H.eq(key(ns, "WBX Follow").body, "/follow party2", "no party: the saved slot")
  local warn
  for _, it in ipairs(ns.Checklist.items()) do if it.text == "Anna is not in your party" then warn = it end end
  H.ok(warn and warn.hint:find("last known slot (party2)", 1, true), "checklist warns: Anna is not in your party")
  me.lineUnit = nil
  H.eq(key(ns, "WBX Follow").body, "/follow " .. me.unit, "nothing saved: follows the leader")
  -- reordering the squad changes the line: Bo first → follows the leader
  ns.UI.Open("squad")
  ns.SquadPages.editing = me.id; ns.UI.Refresh()
  local f = ns.UI.panels.squad.frames.main
  f.editor.up:Click()
  H.eq(s.members[2].name, "Bo", "Up moves Bo before Anna")
  H.eq(ns.State.aheadOf(s, me).name, "Dorin", "Bo now follows the leader in the line")
  H.ok(f.lineText:GetText():find("Dorin", 1, true) and select(2, f.lineText:GetText():gsub("→", "")) == 3, "Line: Dorin → Bo → Anna → Cid")
  -- untick: not created
  ns.Book.setSquadKey("FollowLead", false)
  H.eq(key(ns, "WBX FollowLead"), nil, "unticked Follow leader is not created")
  ns.Book.setSquadKey("Follow", false)
  H.eq(key(ns, "WBX Follow"), nil, "unticked Follow (line) is not created")
  -- per client: never in the share string
  me.lineUnit = "party3"
  local str = ns.Share.export(s, {})
  H.ok(not ns.Share.import(str).squad.members[2].lineUnit, "lineUnit never travels in the share string")
  H.eq(errors(ns), "", "no errors (follow line)")
end

os.exit(H.report("followline") and 0 or 1)
