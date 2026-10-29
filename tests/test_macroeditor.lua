-- Edit macro… on every client (docs/feedback-2026-10-29-late.md §3, §5): in Advanced mode every macro and every spell
-- has it – on the LEADER's client (it failed on the owner's Paladin leader) and on followers via party1–4 and focus. A spell
-- without a macro becomes an own single-spell macro. New macro: Single spell with each preset, Sequence unchanged.
local dir = (arg[0]:match("^(.*)/[^/]+$") or ".")
local H = dofile(dir .. "/harness.lua")
local Mock = dofile(dir .. "/wowmock.lua")

local function client(me, cls, unit, party, partyInfo)
  local W = Mock.new(H, { name = me, class = cls, race = "Scourge", level = 30, party = party, partyInfo = partyInfo, focus = unit == "focus" and "Dorin" or nil })
  local ns = H.loadAddon({ env = W.env })
  W.fire("ADDON_LOADED", "WoWBoxer"); W.fire("PLAYER_LOGIN")
  for _, s in ipairs(ns.Data.spells[cls:lower()]) do if s.level <= 30 and s.gate ~= "talent" then W.known[s.name] = true end end
  local sq = ns.State.newSquad({ name = "Trio", members = {
    { name = "Dorin", cls = "paladin", race = "undead", role = "tank", leader = true },
    { name = "Anna", cls = "priest", race = "undead", role = "healer", unit = unit or "party1" },
    { name = "Bo", cls = "hunter", race = "orc", role = "ranged", unit = unit or "party1" } } })
  ns.Core.db.squads = { sq }; ns.Core.db.active = sq.id
  ns.Core.cdb.guide = "done"
  ns.Core.db.settings.advanced = true
  ns.UI.Open("keys")
  return W, ns
end
local function labels(items) local t = {}; for _, it in ipairs(items) do t[#t + 1] = it[1] end return table.concat(t, "|") end
local function has(items, l) for _, it in ipairs(items) do if it[1] == l and not it[4] then return it end end end

local HUN = { class = "HUNTER", race = "Orc", level = 30 }
local PAL = { class = "PALADIN", race = "Scourge", level = 30 }
local PRI = { class = "PRIEST", race = "Scourge", level = 30 }
for _, sc in ipairs({
  { "Dorin", "PALADIN", nil, { party1 = "Anna", party2 = "Bo" }, { party1 = PRI, party2 = HUN }, "leader" },
  { "Anna", "PRIEST", "party1", { party1 = "Dorin", party2 = "Bo" }, { party1 = PAL, party2 = HUN }, "follower party1" },
  { "Anna", "PRIEST", "party3", { party3 = "Dorin", party4 = "Bo" }, { party3 = PAL, party4 = HUN }, "follower party3" },
  { "Anna", "PRIEST", "focus", { party2 = "Dorin", party1 = "Bo" }, { party2 = PAL, party1 = HUN }, "follower focus" },
}) do
  local W, ns = client(sc[1], sc[2], sc[3], sc[4], sc[5])
  local tag = sc[6] .. ": "
  local Core, Book, UI, A = ns.Core, ns.Book, ns.UI, ns.Advanced
  local s, me = Core.me()
  if sc[3] then me.leader = false; me.unit = sc[3]; for _, m in ipairs(s.members) do m.leader = m.name == "Dorin" end end
  Core.sync({})
  UI.Refresh()
  local p = UI.panels.keys
  -- every recommended macro and squad macro on My macros
  local n, ok = 0, 0
  for _, b in ipairs(p.cells) do
    if b:IsShown() and b.cell and b.cell.name then n = n + 1; if has(Book.menuFor(p, b.cell), "Edit macro…") then ok = ok + 1 end end
  end
  H.ok(n > 0 and ok == n, tag .. "Edit macro… on every macro (" .. ok .. "/" .. n .. ")")
  -- a heal spell on All spells, with and without a macro (Holy Light on the Paladin leader – the owner's case)
  UI.Select("spells")
  local sp = UI.panels.spells
  local heal, plain
  for _, b in ipairs(sp.cells) do
    if b:IsShown() and b.cell and b.cell.spell then
      if not heal and (b.cell.label == "Holy Light" or b.cell.label == "Lesser Heal" or b.cell.label == "Heal") then heal = b.cell end
      if not plain and not b.cell.name and not b.cell.pending then plain = b.cell end
    end
  end
  H.ok(heal and has(Book.menuFor(sp, heal), "Edit macro…"), tag .. "Edit macro… on " .. tostring(heal and heal.label) .. " in All spells: " .. labels(heal and Book.menuFor(sp, heal) or {}))
  H.ok(plain and has(Book.menuFor(sp, plain), "Edit macro…"), tag .. "Edit macro… on a spell without a macro (" .. tostring(plain and plain.label) .. ")")
  local before = #(me.customSeq or {})
  has(Book.menuFor(sp, plain), "Edit macro…")[2]()
  H.eq(#me.customSeq, before + 1, tag .. "that spell became an own single-spell macro")
  local c = me.customSeq[#me.customSeq]
  H.ok(c.kind == "priority" and #c.steps == 1 and c.steps[1] == plain.label, tag .. "single spell = priority with one step")
  H.ok(A.ef:IsShown() and A.ef.name == "WBX C" .. #me.customSeq, tag .. "and the Macro editor opened on it")
  -- the targets this client offers: every member and pet; a follower also the leader and the leader's target
  local whos = {}
  for _, t in ipairs(A.ef.tiles) do if t:IsShown() then whos[#whos + 1] = t.full end end
  local all = table.concat(whos, " | ")
  H.ok(all:find("Bo's pet (", 1, true) and (sc[1] == "Dorin" and all:find("Anna (", 1, true) or all:find("Dorin (", 1, true)), tag .. "members and pets: " .. all)
  if sc[3] then H.ok(all:find("(leader)", 1, true) and all:find("Dorin's target", 1, true), tag .. "a follower also gets the leader and the leader's target") end
  A.ef:Hide()
  -- Standard: greyed with a tip, on every client
  Core.db.settings.advanced = nil
  local it
  for _, x in ipairs(Book.menuFor(sp, heal)) do if x[1] == "Edit macro… (Advanced mode)" then it = x end end
  H.ok(it and it[4] == true, tag .. "Standard: greyed Edit macro… (Advanced mode)")
  H.eq(W.calls.LearnTalent, nil, tag .. "nothing else written")
end

-- New macro: Single spell or Sequence first; presets; single + Advanced targeting; ≤ 255
do
  local W, ns = client("Anna", "PRIEST", "party1", { party1 = "Dorin", party2 = "Bo" }, { party1 = PAL, party2 = HUN })
  local Core, UI, KE = ns.Core, ns.UI, ns.KeyEditor
  local s, me = Core.me()
  me.leader = false; me.unit = "party1"; for _, m in ipairs(s.members) do m.leader = m.name == "Dorin" end
  Core.db.settings.advanced = nil
  UI.Select("custom")
  local p = UI.panels.custom
  local newCell
  for _, b in ipairs(p.cells) do if b:IsShown() and b.cell and b.cell.kind == "new" then newCell = b end end
  newCell:Click("LeftButton")
  local f = KE.frame
  H.ok(f.choice:IsShown() and f.choice.single:IsShown() and f.choice.seq:IsShown(), "New macro: Single spell or Sequence first")
  f.choice.single:Click()
  H.eq(f.draft.kind, "single", "Single spell chosen")
  local vals = KE.presetValues()
  local pv = {}
  for _, v in ipairs(vals) do pv[#pv + 1] = v[2] end
  H.eq(table.concat(pv, ","), "Enemy,Friendly,Myself,Friendly: Bo's pet", "Standard presets")
  local function body(name) for _, d in ipairs(Core.compute().desired) do if d.name == name then return d.body, d end end end
  local results = {}
  for _, preset in ipairs({ "enemy", "friendly", "self", "pet:Bo" }) do
    KE.Open(p, nil); f.choice.single:Click()
    KE.addStep(preset == "enemy" and "Smite" or "Lesser Heal")
    KE.addStep(preset == "enemy" and "Smite" or "Lesser Heal") -- single: a second pick replaces, never adds
    H.eq(#f.draft.steps, 1, preset .. ": one spell only")
    f.preset.select(preset)
    f.save:Click()
    local i = #me.customSeq
    local b, d = body("WBX C" .. i)
    results[preset] = b
    H.ok(b and d.ok and #b <= 255, preset .. ": a valid macro ≤ 255 (" .. tostring(b and #b) .. ")")
  end
  H.ok(results.enemy:find("[@mouseover,harm,nodead]", 1, true) and results.enemy:find("[@party1target,harm,nodead]", 1, true), "Enemy: mouseover > leader's target > my target: " .. results.enemy)
  H.ok(results.friendly:find("[@mouseover,help,nodead]", 1, true) and results.friendly:find("[@party1,help,nodead]", 1, true), "Friendly: mouseover > leader > me")
  H.ok(results.self:find("/cast [@player,help", 1, true) and not results.self:find("mouseover", 1, true), "Myself: " .. results.self)
  H.ok(results["pet:Bo"]:find("[@party2pet,help,nodead]", 1, true), "a squad pet: Bo's pet = party2pet here")
  -- reopening shows Single spell and the preset again
  KE.Open(p, 3)
  H.ok(f.draft.kind == "single" and f.draft.preset == "self" and not f.choice:IsShown(), "reopened: Single spell, Myself")
  KE.Close()
  -- Sequence is today's editor (engine unchanged)
  KE.Open(p, nil); f.choice.seq:Click()
  KE.addStep("Shadow Word: Pain"); KE.addStep("Mind Blast")
  H.eq(#f.draft.steps, 2, "Sequence: steps add up")
  f.save:Click()
  H.eq(me.customSeq[#me.customSeq].kind, "sequence", "saved as a sequence")
  -- single + Advanced targeting through the Macro editor
  Core.db.settings.advanced = true
  KE.Open(p, 1)
  f.targeting:Click()
  local ef = ns.Advanced.ef
  H.ok(ef:IsShown() and ef.name == "WBX C1", "Advanced: Edit macro… in the own-macro editor opens the Macro editor")
  for _, t in ipairs(ef.tiles) do if t:IsShown() and t.target.who == "focus" then t:Click() end end
  ef.save:Click()
  local b = body("WBX C1")
  H.ok(b:find("[@focus", 1, true) and #b <= 255, "single spell + Advanced targeting: " .. b)
end

os.exit(H.report("macroeditor") and 0 or 1)
