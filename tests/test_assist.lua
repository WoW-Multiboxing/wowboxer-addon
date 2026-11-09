-- "Take the leader's target" (owner bug 9 Nov 2026: the wand filler shoots once and stops on followers). Auto-repeat
-- (Shoot, Auto Shot) only keeps going on your OWN target and combo points sit on your own target, so a follower's damage
-- keys start with /assist <the leader's unit>. On by default for followers, never for the leader; off = today's macros.
-- The wand line stays last; to fit 255 the wand line goes first, then /assist. Every game, every class.
local dir = (arg[0]:match("^(.*)/[^/]+$") or ".")
local H = dofile(dir .. "/harness.lua")
local Mock = dofile(dir .. "/wowmock.lua")

for _, game in ipairs({ { "forever", 16001, "camelot" }, { "era", 11509 }, { "tbc", 20506 } }) do
  local W = Mock.new(H, { toc = game[2] })
  local ns = H.loadAddon({ env = W.env, gameType = game[3] })
  local E, M, K, S = ns.Engine, ns.Macros, ns.Kit, ns.State
  local tag = game[1] .. ": "
  local function member(o)
    local m = { id = "a", name = "A", race = "human", level = 1, unit = "party1", seq = "advanced" }
    for k, v in pairs(o) do m[k] = v end
    return S.newMember(m)
  end
  local function byKey(list) local t = {}; for _, d in ipairs(list) do t[d.key] = d end return t end
  local function bodies(m, L) local t = {}; for _, d in ipairs(M.desired(m, L, {})) do t[d.key] = d.body end return t end

  -- defaults
  H.eq(K.takesTarget(member({ cls = "mage", role = "ranged", leader = false })), true, tag .. "on by default for a follower")
  H.eq(K.takesTarget(member({ cls = "mage", role = "ranged", leader = true })), false, tag .. "never for the leader")
  H.eq(K.takesTarget(member({ cls = "mage", role = "ranged", leader = true, assist = true })), false, tag .. "not even when the leader's member says so")
  H.eq(K.takesTarget(member({ cls = "mage", role = "ranged", assist = false })), false, tag .. "switched off")
  H.eq(member({ cls = "mage", role = "ranged", assist = true }).assist, nil, tag .. "stored as the default (nil), not as true")

  for _, cls in ipairs({ "warrior", "rogue", "druid", "mage", "priest", "warlock", "hunter", "paladin", "shaman" }) do
    local roles = ns.Data.classes[cls] and ns.Data.classes[cls].roles
    for _, role in ipairs(roles or {}) do
      for _, unit in ipairs({ "party1", "party2", "party3", "party4", "focus" }) do
        for _, L in ipairs({ 1, 10, 20, 40, E.maxLevel() }) do
          local who = tag .. cls .. " " .. role .. " " .. unit .. " L" .. L .. ": "
          local on = member({ cls = cls, role = role, unit = unit, level = L })
          local off = member({ cls = cls, role = role, unit = unit, level = L, assist = false })
          local lead = member({ cls = cls, role = role, unit = unit, level = L, leader = true })
          local A, B = bodies(on, L), bodies(off, L)
          for key, body in pairs(A) do
            H.ok(#body <= 255, who .. key .. " fits 255 (" .. #body .. ")")
            local assist = body:match("\n/assist ([^\n]+)")
            if assist then
              H.eq(assist, unit, who .. key .. ": /assist the leader's unit")
              H.ok(body:find("^#showtooltip[^\n]*\n/assist ") ~= nil, who .. key .. ": /assist right after #showtooltip")
              -- with the line taken out, the rest is today's key – or, for the wand, the same with the own-target aim
              local without = body:gsub("\n/assist [^\n]+", "", 1)
              local today = B[key]
              if today and without ~= today and key ~= "Wand" then
                local wandOwn = without:gsub("\n/cast %[harm,nodead%] !Shoot$", "")
                local todayNoWand = today:gsub("\n/cast [^\n]* !Shoot$", "")
                H.ok(wandOwn == todayNoWand or #today > 200, who .. key .. ": only /assist (and the wand's aim) differ\n" .. body .. "\n--- off:\n" .. today)
              end
            end
            if body:find("!Shoot", 1, true) and key ~= "Wand" then
              H.ok(body:find(" !Shoot$") ~= nil, who .. key .. ": the wand line is last")
              if assist then H.ok(body:find("\n/cast %[harm,nodead%] !Shoot$") ~= nil, who .. key .. ": the wand shoots the own target (= the leader's after /assist)") end
            end
          end
          -- off = today's output; the leader never assists
          for key, body in pairs(B) do H.ok(not body:find("/assist", 1, true) or key == "Assist", who .. key .. ": off = no /assist") end
          for key, body in pairs(bodies(lead, L)) do H.ok(not body:find("/assist", 1, true), who .. key .. ": the leader never assists") end
          -- crowd control and friendly keys never assist
          for _, d in ipairs(M.desired(on, L, {})) do
            if d.spell and (d.spell.category == "Control" or d.spell.category == "Heal" or d.spell.category == "Buff") then
              H.ok(not d.body:find("/assist", 1, true), who .. d.key .. " (" .. d.spell.category .. "): no /assist")
            end
            if d.spell and E.assistsFirst(d.spell, K.memberCtx(on)) and d.body ~= "" then
              H.ok(d.body:find("\n/assist " .. unit, 1, true) ~= nil or #B[d.key] > 230, who .. d.key .. " (" .. d.label .. "): damage key assists")
            end
          end
        end
      end
    end
  end

  -- the owner's case: a priest follower's Smite takes the target, then falls back to a wand that keeps shooting
  local d = byKey(M.desired(member({ cls = "priest", role = "healer", level = 20 }), 20, {}))
  H.eq(d.K1.body, "#showtooltip Smite\n/assist party1\n/cast [@mouseover,harm,nodead][@party1target,harm,nodead][harm,nodead] Smite\n/cast [harm,nodead] !Shoot",
    tag .. "priest follower Smite")
  H.eq(d.Wand.body, "#showtooltip Shoot\n/assist party1\n/cast [harm,nodead] !Shoot", tag .. "the Wand key takes the target first")
  -- Rogue: combo builders and finishers on the own target
  local r = byKey(M.desired(member({ cls = "rogue", role = "melee", level = 20 }), 20, {}))
  local any = false
  for _, x in pairs(r) do if x.body:find("Sinister Strike", 1, true) then any = true; H.ok(x.body:find("\n/assist party1\n", 1, true) ~= nil, tag .. "rogue " .. x.key .. " assists") end end
  H.ok(any, tag .. "rogue has Sinister Strike keys")
  -- Follow (line): the macros take the LEADER's target (the unit the damage keys aim through), not the one ahead
  local lm = member({ cls = "mage", role = "ranged", level = 20, unit = "party2", lineUnit = "party3" })
  local lb = bodies(lm, 20)
  H.ok(lb.Follow and lb.Follow:find("/follow party3", 1, true), tag .. "line: Follow follows the one ahead")
  for key, body in pairs(lb) do
    local a = body:match("\n/assist ([^\n]+)")
    if a then H.eq(a, "party2", tag .. "line: " .. key .. " assists the leader (party2)") end
  end

  -- 255: a key that does not fit with /assist is today's key (the wand line went first)
  local fake = { name = string.rep("X", 160), action = "ranged", category = "Damage" }
  local ctx = { leader = false, unit = "party4", wand = true, assist = true }
  local long = E.makeMacro(fake, ctx)
  H.ok(#long <= 255, tag .. "a long spell still fits")
  local plain = E.makeMacro(fake, { leader = false, unit = "party4", wand = true })
  H.ok(not long:find("/assist", 1, true), tag .. "too long with /assist: no /assist"); H.eq(long, plain, tag .. "too long with /assist: today's key")
  local mid = { name = string.rep("Y", 140), action = "ranged", category = "Damage" }
  local m1 = E.makeMacro(mid, ctx)
  H.ok(m1:find("/assist party4", 1, true) and not m1:find("Shoot", 1, true), tag .. "the wand line goes before /assist: " .. #m1)

  -- share string: the switch travels only when off
  local sq = S.newSquad({ name = "T", members = { { name = "L", cls = "mage", leader = true }, { name = "F", cls = "rogue", assist = false }, { name = "G", cls = "priest" } } })
  local str = ns.Share.export(sq)
  local back = ns.Share.import(str)
  local ms = back and (back.squad or back).members
  if ms then
    H.eq(ms[2].assist, false, tag .. "share: off stays off")
    H.eq(ms[3].assist, nil, tag .. "share: default stays default")
  else
    H.ok(false, tag .. "share import: " .. tostring(back))
  end
end

H.report("assist")
