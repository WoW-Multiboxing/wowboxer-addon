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
      H.ok(k1 and k1.body:find("\n/cast [^\n]* !Shoot$") ~= nil, who .. "K1 (" .. (k1 and k1.label or "?") .. ") ends with the wand")
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
end

H.report("wand")
