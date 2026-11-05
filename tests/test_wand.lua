-- Wands (owner, 5 Nov 2026): every wand class (mage, priest, warlock – every role, healers too) ends its damage spell keys
-- with "/cast <same target> !Shoot", so a press that cannot cast the spell shoots the wand; plus a Wand squad key.
-- Never on heals, buffs or crowd control, never for other classes; always within 255 characters.
local dir = (arg[0]:match("^(.*)/[^/]+$") or ".")
local H = dofile(dir .. "/harness.lua")
local Mock = dofile(dir .. "/wowmock.lua")

for _, game in ipairs({ { "forever", 16001, "camelot" }, { "era", 11509 }, { "tbc", 20506 } }) do
  local W = Mock.new(H, { toc = game[2] })
  local ns = H.loadAddon({ env = W.env, gameType = game[3] })
  local E, M = ns.Engine, ns.Macros
  local tag = game[1] .. ": "
  local function member(cls, role, leader, seq)
    return ns.State.newMember({ id = "w", name = "W", cls = cls, race = "human", role = role, level = 1, leader = leader, unit = "party1", seq = seq or "simple" })
  end
  local function byKey(list) local t = {}; for _, d in ipairs(list) do t[d.key] = d end return t end

  for _, c in ipairs({ { "priest", "healer" }, { "priest", "ranged" }, { "mage", "ranged" }, { "warlock", "ranged" } }) do
    for _, leader in ipairs({ true, false }) do
      local who = tag .. c[1] .. " " .. c[2] .. (leader and " leader" or " follower") .. ": "
      local m = member(c[1], c[2], leader)
      local d = byKey(M.desired(m, 20, {}))
      H.ok(d.Wand and d.Wand.body:find("!Shoot", 1, true), who .. "has the Wand key")
      H.ok(leader or d.Wand.body:find("@party1target", 1, true), who .. "the Wand key shoots the leader's target")
      local k1 = d.K1
      -- wand FIRST (owner: "put the wand shooting in the top"), then the spell; the tooltip still shows the spell
      H.ok(k1 and k1.body:find("^#showtooltip " .. k1.label .. "\n[^\n]*\n?/cast [^\n]* !Shoot\n/cast [^\n]* " .. k1.label .. "$") ~= nil,
        who .. "K1 (" .. (k1 and k1.label or "?") .. ") starts with the wand: " .. tostring(k1 and k1.body))
      for _, x in pairs(d) do
        if x.key ~= "Wand" and x.body:find("!Shoot", 1, true) then
          local firstCast = x.body:match("\n(/cast[^\n]*)")
          H.ok(firstCast and firstCast:find(" !Shoot$") ~= nil, who .. x.name .. ": the wand is the first cast line")
          H.ok(x.body:find("^#showtooltip [^\n]") ~= nil, who .. x.name .. ": the tooltip names the spell, not the wand: " .. x.body)
        end
      end
      for _, x in pairs(d) do
        H.ok(#x.body <= 255, who .. x.name .. " fits 255")
        if x.spell and x.body:find("!Shoot", 1, true) then
          H.ok(x.spell.category == "Damage" or x.spell.category == "Debuff", who .. x.name .. ": wand only after damage")
        end
        if x.spell and (x.spell.category == "Heal" or x.spell.category == "Control" or x.spell.category == "Buff") then
          H.ok(not x.body:find("Shoot", 1, true), who .. x.name .. " (" .. x.spell.category .. "): no wand")
        end
      end
      if d.S2 then H.ok(not d.S2.body:find("Shoot", 1, true), who .. "the heal sequence has no wand") end
    end
  end
  -- the healer's damage key
  local d = byKey(M.desired(member("priest", "healer", false), 20, {}))
  H.ok(d.K1.label == "Smite" and d.K1.body:find("!Shoot", 1, true), tag .. "healer priest: Smite falls back to the wand")
  -- crowd control never
  for _, s in ipairs(ns.Data.spells.mage) do
    if s.name == "Polymorph" then H.ok(not E.makeMacro(s, { leader = false, unit = "party1", wand = true }):find("Shoot", 1, true), tag .. "Polymorph: no wand") end
  end
  -- other classes never
  for _, cls in ipairs({ "hunter", "warrior", "rogue", "paladin", "shaman", "druid" }) do
    if ns.Data.classes[cls] then
      local role = ns.Data.classes[cls].roles[1]
      local all = M.desired(member(cls, role, false), 20, {})
      local any = false
      for _, x in ipairs(all) do if x.body:find("Shoot", 1, true) or x.key == "Wand" then any = true end end
      H.ok(not any, tag .. cls .. ": no wand")
    end
  end
  -- the squad key can be unticked
  local m = member("mage", "ranged", false)
  local off = byKey(M.desired(m, 20, { squadKeys = { Wand = false } }))
  H.ok(M.squadKeyOn(m, "Wand", nil) == true and M.squadKeyOn(m, "Wand", { Wand = false }) == false, tag .. "Wand is a squad key, on by default")
  local w = byKey(M.desired(m, 20, {})).Wand
  local ok, why = ns.Rules.validateMacro(w.name, w.body)
  H.ok(ok, tag .. "WBX Wand passes the macro rules: " .. tostring(why))
  local _ = off

  -- own macros: Shoot is a spell you can pick (owner: "shooting … has to be like a spell as well")
  local KE, K = ns.KeyEditor, ns.Kit
  local function choiceNames(m) local t = {}; for _, s in ipairs(KE.spellChoices(m, 20)) do t[s.name] = s end return t end
  for _, cls in ipairs({ "priest", "mage", "warlock" }) do
    for _, leader in ipairs({ true, false }) do
      local who = tag .. cls .. (leader and " leader" or " follower") .. " own macro: "
      local m = member(cls, "ranged", leader)
      local ch = choiceNames(m)
      H.ok(ch.Shoot ~= nil, who .. "Shoot is in the spell list")
      local nuke = ({ priest = "Smite", mage = "Fireball", warlock = "Shadow Bolt" })[cls]
      H.ok(ch[nuke] ~= nil, who .. nuke .. " is in the list")
      -- Priority: nuke, then Shoot -> one !Shoot line, no extra one
      local r, warn = KE.preview(m, { id = "x", name = "Nuke+wand", kind = "priority", aim = "harm", steps = { nuke, "Shoot" }, filler = "", fills = 1, reset = "combat" }, 20)
      local _, n = r.macro:gsub("!Shoot", "")
      H.eq(n, 1, who .. "priority with Shoot has one wand line: " .. r.macro)
      H.ok(r.macro:find("\n/cast [^\n]* !Shoot$") ~= nil, who .. "Shoot is the last line")
      H.ok(#r.macro <= 255, who .. "fits 255")
      H.eq(#warn, 0, who .. "no warnings: " .. table.concat(warn, " / "))
      -- Single: just the wand on the chosen target
      local s1 = KE.preview(m, { id = "y", name = "Wand", kind = "single", aim = "harm", steps = { "Shoot" }, filler = "", fills = 1, reset = "combat" }, 20)
      local _, n1 = s1.macro:gsub("Shoot", "")
      H.eq(n1, 1, who .. "single Shoot: " .. s1.macro)
      H.ok(leader or s1.macro:find("@party1target", 1, true), who .. "single Shoot aims at the leader's target")
      -- Shoot first in a priority: the lines below never run (warned)
      local _, w2 = KE.preview(m, { id = "z", name = "x", kind = "priority", aim = "harm", steps = { "Shoot", nuke }, filler = "", fills = 1, reset = "combat" }, 20)
      H.ok(#w2 > 0, who .. "Shoot first is warned about")
      -- Sequence with Shoot: warned, no extra wand line
      local q, w3 = KE.preview(m, { id = "q", name = "x", kind = "sequence", aim = "harm", steps = { nuke, "Shoot" }, filler = "", fills = 1, reset = "combat" }, 20)
      H.ok(not q.macro:find("!Shoot", 1, true), who .. "sequence: no extra wand line: " .. q.macro)
      H.ok(q.macro:find("Shoot", 1, true) ~= nil, who .. "sequence casts Shoot as a step")
      local hasW = false
      for _, w in ipairs(w3) do if w:find("Shoot in a sequence", 1, true) then hasW = true end end
      H.ok(hasW, who .. "sequence with Shoot is warned about")
      -- Friendly macro with Shoot: warned
      local _, w4 = KE.preview(m, { id = "f", name = "x", kind = "priority", aim = "help", steps = { "Shoot" }, filler = "", fills = 1, reset = "combat" }, 20)
      H.ok(#w4 > 0, who .. "Shoot in a Friendly macro is warned about")
      -- saved and built like every own macro
      m.customSeq = {}
      local idx = KE.save(m, { id = "s", name = "Wand nuke", kind = "priority", aim = "harm", steps = { nuke, "Shoot" }, filler = "", fills = 1, reset = "combat" })
      local found
      for _, x in ipairs(K.seqOf(m, 20)) do if x.custom then found = x end end
      H.ok(idx == 1 and found and found.macro:find("!Shoot", 1, true), who .. "saved own macro keeps Shoot")
    end
  end
  for _, cls in ipairs({ "warrior", "hunter", "rogue" }) do
    H.ok(choiceNames(member(cls, "melee", true)).Shoot == nil, tag .. cls .. ": no Shoot in the own-macro list")
  end
end

-- All spells shows Shoot; dragging it makes an own macro that shoots the wand (healers too)
for _, c in ipairs({ { "PRIEST", "healer" }, { "MAGE", "ranged" }, { "WARLOCK", "ranged" }, { "WARRIOR", "tank" } }) do
  local W = Mock.new(H, { name = "Rup", class = c[1], race = "Human", level = 12 })
  local ns = H.loadAddon({ env = W.env })
  W.fire("ADDON_LOADED", "WoWBoxer"); W.fire("PLAYER_LOGIN")
  local Core = ns.Core
  ns.State.quickStart(Core.db, Core.cdb, Core.playerInfo())
  local _, m = Core.me()
  m.role = c[2]
  local who = c[1] .. " " .. c[2] .. ": "
  local ctx = Core.compute()
  local shoot
  for _, sec in ipairs(ns.Book.spellSections(ctx, nil)) do
    for _, cell in ipairs(sec.cells) do if cell.label == "Shoot" then shoot = cell; H.ok(not sec.future, who .. "Shoot is a learned spell") end end
  end
  if c[1] == "WARRIOR" then H.ok(shoot == nil, who .. "no Shoot in All spells")
  else
    H.ok(shoot ~= nil, who .. "Shoot is in All spells")
    local found = 0
    for _, sec in ipairs(ns.Book.spellSections(ctx, "shoot")) do for _, cell in ipairs(sec.cells) do if cell.label == "Shoot" then found = found + 1 end end end
    H.eq(found, 1, who .. "search finds Shoot once")
    local i = Core.newSingle(shoot.spell)
    H.ok(i ~= nil, who .. "dragging Shoot makes an own macro")
    local body
    for _, d in ipairs(Core.compute().desired) do if d.name == "WBX C" .. tostring(i) then body = d.body end end
    H.ok(body and body:find("harm", 1, true) and body:find(" !Shoot$") and select(2, body:gsub("Shoot", "")) == 1, who .. "the own macro shoots: " .. tostring(body))
    -- the drag from All spells (Book: pickupSpell with the cell's spell id)
    local ok, why = Core.pickupSpell(shoot.spell.id)
    H.ok(ok, who .. "dragging Shoot from All spells gives a macro: " .. tostring(why))
    local x
    for _, d in ipairs(Core.compute().desired) do if d.key == "X:wand" then x = d end end
    H.ok(x and x.ok and x.body == "#showtooltip Shoot\n/cast " .. (m.leader and "[@mouseover,harm,nodead][harm,nodead]" or "") .. (m.leader and "" or x.body:match("/cast (%S+)")) .. " !Shoot",
      who .. "the dragged macro shoots: " .. tostring(x and x.body))
  end
end

H.report("wand")
