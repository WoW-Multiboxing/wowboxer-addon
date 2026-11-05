--[[ WoWBoxer – Advanced mode: your own targeting per key (docs/advanced-mode.md §2–§4).
  The engine builds every key exactly as the companion does (parity unchanged); this module then rewrites the key:
  - targets: the conditional chain of its /cast, /castsequence (and, on enemy keys, /startattack and /petattack) lines
    is replaced by the player's chain. Targets are stored by MEANING ("Bo's pet", "the leader"), never by unit, and
    turned into this client's party units each time the keys are built – so a regroup only needs the usual Update.
  - options: reset=, /startattack on/off, /petattack on/off, a modifier line (Shift = myself …).
  - text: the player's own macro text (the last resort); such a key is frozen: level-ups do not change it.
  Every result still goes through Rules.validateMacro (255, whitelist, WBX names). Nothing here is ever run as code,
  and share strings never carry any of it as macro text (hard rule 3). ]]
local _, ns = ...
local O = {}
ns.Override = O

local sfind, smatch, sgsub, slower = string.find, string.match, string.gsub, string.lower
local tconcat = table.concat
local function S() return ns.State end

O.MAX_TARGETS = 8
O.KINDS = { "mouseover", "target", "leader", "leadertarget", "member", "mypet", "unit", "focus", "targettarget", "player" }
-- raw units: party1–4 and their pets (a party is you + party1–4: there is no party5), then raid1–40 and their pets.
-- A macro with a raid unit still works in a party: [@raidN] simply does not exist there and the macro goes on.
O.PARTY_UNITS = { "party1", "party2", "party3", "party4", "party1pet", "party2pet", "party3pet", "party4pet" }
O.RAID_UNITS = {}
for i = 1, 40 do O.RAID_UNITS[#O.RAID_UNITS + 1] = "raid" .. i end
for i = 1, 40 do O.RAID_UNITS[#O.RAID_UNITS + 1] = "raid" .. i .. "pet" end
O.RAW_UNITS = {}
for _, u in ipairs(O.PARTY_UNITS) do O.RAW_UNITS[#O.RAW_UNITS + 1] = u end
for _, u in ipairs(O.RAID_UNITS) do O.RAW_UNITS[#O.RAW_UNITS + 1] = u end
O.MODS = { "shift", "ctrl", "alt" }
O.RESETS = { "combat", "target", "combat/target", "12", "combat/12" }
local function contains(t, v) for _, x in ipairs(t) do if x == v then return true end end return false end

-- ------------------------------------------------------------------ cleaning (SavedVariables are data)
local function cleanTarget(t)
  if type(t) ~= "table" or not contains(O.KINDS, t.who) then return nil end
  local x = { who = t.who, nodead = t.nodead ~= false }
  if t.help == true or t.help == false then x.help = t.help end -- true = friendly, false = enemy, nil = either
  if t.who == "member" then
    x.name = ns.Rules.cleanText(t.name, 24)
    if not x.name or x.name == "" then return nil end
    x.pet = t.pet == true or nil
  elseif t.who == "unit" then
    if not contains(O.RAW_UNITS, t.unit) then return nil end
    x.unit = t.unit
  end
  return x
end
O.cleanTarget = cleanTarget
--- One override {targets = {…}, mod, reset, startattack, petattack} or {text = "…"}; nil when empty or broken.
function O.clean(ov)
  if type(ov) ~= "table" then return nil end
  if type(ov.text) == "string" then
    local t = sgsub(ov.text, "\r", "")
    if t == "" or #t > 400 then return nil end
    return { text = t }
  end
  local x = { targets = {} }
  for _, t in ipairs(type(ov.targets) == "table" and ov.targets or {}) do
    local c = cleanTarget(t)
    if c and #x.targets < O.MAX_TARGETS then x.targets[#x.targets + 1] = c end
  end
  if contains(O.MODS, ov.mod) then x.mod = ov.mod end
  if contains(O.RESETS, ov.reset) then x.reset = ov.reset end
  if ov.startattack == true or ov.startattack == false then x.startattack = ov.startattack end
  if ov.petattack == true or ov.petattack == false then x.petattack = ov.petattack end
  if #x.targets == 0 and not x.mod and not x.reset and x.startattack == nil and x.petattack == nil then return nil end
  return x
end
function O.cleanAll(t)
  local out = {}
  if type(t) ~= "table" then return out end
  for name, ov in pairs(t) do
    if ns.Rules.isOurs(name) and #name <= ns.Rules.NAME_LIMIT then out[name] = O.clean(ov) end
  end
  return out
end

-- ------------------------------------------------------------------ meaning -> this client's unit
--- ctx = {squad, me}. Returns unit (or "" for "your target") or nil when it can't be found here (member not in party).
function O.unitFor(t, ctx)
  local me, s = ctx.me, ctx.squad
  local w = t.who
  if w == "mouseover" or w == "focus" or w == "player" or w == "targettarget" then return w end
  if w == "target" then return "target" end
  if w == "mypet" then return "pet" end
  if w == "unit" then return t.unit end
  local L = S().leaderOf(s)
  local function memberUnit(m)
    if not m then return nil end
    if m == me then return "player" end
    local u = ns.Squad.unitOf(m.name)
    if not u and m == L and me and not me.leader then u = me.unit end -- the leader: the unit set under Plays as
    return u
  end
  if w == "leader" then return (me and me.leader) and "player" or memberUnit(L) end
  if w == "leadertarget" then
    if me and me.leader then return "target" end
    local u = memberUnit(L)
    return u and (u .. "target") or nil
  end
  if w == "member" then
    local m = ns.Compat.findByName(s and s.members or {}, t.name) -- full or first name (Compat names)
    local u = memberUnit(m)
    if not u then return nil end
    if t.pet then return u == "player" and "pet" or (u .. "pet") end
    return u
  end
  return nil
end

--- A plain name for a target: "Bo's pet", "the leader's target", "Mouseover".
function O.label(t, ctx)
  local w = t.who
  local L = S().leaderOf(ctx and ctx.squad)
  if w == "mouseover" then return "Mouseover" end
  if w == "target" then return "Your target" end
  if w == "leader" then return (L and L.name or "The leader") .. " (leader)" end
  if w == "leadertarget" then return (L and L.name or "The leader") .. "'s target" end
  if w == "member" then return t.name .. (t.pet and "'s pet" or "") end
  if w == "mypet" then return "My pet" end
  if w == "unit" then return t.unit end
  if w == "focus" then return "Focus" end
  if w == "targettarget" then return "Target of target" end
  if w == "player" then return "Myself" end
  return w
end

--- The conditional for one target on this client: "[@party2pet,help,nodead]" (nil when not found here).
function O.cond(t, ctx)
  local u = O.unitFor(t, ctx)
  if not u then return nil end
  local parts = { "@" .. u }
  if t.help == true then parts[#parts + 1] = "help" elseif t.help == false then parts[#parts + 1] = "harm" end
  if t.nodead then parts[#parts + 1] = "nodead" end
  return "[" .. tconcat(parts, ",") .. "]", u
end
--- What a row means in plain words: "Casts on Bo's pet when it exists, is friendly and alive".
function O.meaning(t, ctx)
  local bits = { "exists" }
  if t.help == true then bits[#bits + 1] = "is friendly" elseif t.help == false then bits[#bits + 1] = "is an enemy" end
  if t.nodead then bits[#bits + 1] = "is alive" end
  local last = table.remove(bits)
  local list = #bits > 0 and (tconcat(bits, ", ") .. " and " .. last) or last
  return "Casts on " .. O.label(t, ctx) .. " when it " .. list
end

--- The whole chain for an override: "[mod:shift,@player][@mouseover,help,nodead]…", plus the names left out here.
function O.chain(ov, ctx, help)
  local parts, missing = {}, {}
  if ov.mod then parts[#parts + 1] = "[mod:" .. ov.mod .. ",@player]" end -- hold the modifier = cast on myself
  for _, t in ipairs(ov.targets or {}) do
    local c = O.cond(t, ctx)
    if c then parts[#parts + 1] = c else missing[#missing + 1] = O.label(t, ctx) end
  end
  return tconcat(parts), missing
end

-- ------------------------------------------------------------------ apply to a body
local TARGET_CMDS = { ["/cast"] = true, ["/castsequence"] = true, ["/use"] = true }
local ATTACK_CMDS = { ["/startattack"] = true, ["/petattack"] = true }
--- Leading [..][..] groups of a line's argument: conds, rest.
local function splitConds(arg)
  local conds, i = "", 1
  while arg:sub(i, i) == "[" do
    local j = arg:find("]", i, true)
    if not j then break end
    conds = conds .. arg:sub(i, j); i = j + 1
  end
  return conds, (arg:sub(i):gsub("^%s+", ""))
end
--- Does a conditional run pick a unit / friend-or-foe (so it is targeting, not [combat])?
local function isTargeting(conds) return conds == "" or sfind(conds, "@", 1, true) or sfind(conds, "harm", 1, true) or sfind(conds, "help", 1, true) end

--- Rewrite a body with override ov (targets/options). Returns body, {missing names}.
function O.apply(body, ov, ctx)
  local lines = {}
  for line in (body .. "\n"):gmatch("([^\n]*)\n") do lines[#lines + 1] = line end
  -- an enemy key or a friendly key? (from the first targeting line)
  local help
  for _, l in ipairs(lines) do
    local cmd, arg = smatch(l, "^(/%S+)%s*(.*)$")
    if cmd and TARGET_CMDS[cmd] then local c = splitConds(arg); if sfind(c, "help", 1, true) then help = true; break elseif sfind(c, "harm", 1, true) then help = false; break end end
  end
  local chain, missing = "", {}
  local hasTargets = ov.targets and #ov.targets > 0
  if hasTargets or ov.mod then chain, missing = O.chain(ov, ctx, help) end
  local out, hadStart, hadPet = {}, false, false
  for _, l in ipairs(lines) do
    local cmd, arg = smatch(l, "^(/%S+)%s*(.*)$")
    local keep = true
    if cmd == "/startattack" then hadStart = true; if ov.startattack == false then keep = false end end
    if cmd == "/petattack" then hadPet = true; if ov.petattack == false then keep = false end end
    if keep and cmd and (hasTargets or ov.mod) and (TARGET_CMDS[cmd] or (ATTACK_CMDS[cmd] and help ~= true)) then
      local conds, rest = splitConds(arg)
      if isTargeting(conds) then l = cmd .. " " .. chain .. (rest ~= "" and (" " .. rest) or "") end
    end
    if keep and cmd == "/castsequence" and ov.reset then
      l = l:gsub(" reset=%S+ ", " reset=" .. ov.reset .. " ", 1)
      if not sfind(l, " reset=", 1, true) then
        local c, rest = splitConds((smatch(l, "^/castsequence%s*(.*)$")))
        l = "/castsequence " .. (c ~= "" and (c .. " ") or "") .. "reset=" .. ov.reset .. " " .. rest
      end
    end
    if keep then out[#out + 1] = l end
  end
  -- add /startattack or /petattack right after #showtooltip (enemy keys only)
  local function addAfterTip(line)
    local at = (out[1] and sfind(out[1], "^#show")) and 2 or 1
    table.insert(out, at, line)
  end
  local harmChain = (hasTargets and help ~= true and chain ~= "") and chain or "[harm,nodead]"
  if ov.petattack == true and not hadPet then addAfterTip("/petattack " .. harmChain) end
  if ov.startattack == true and not hadStart then addAfterTip("/startattack " .. harmChain) end
  return tconcat(out, "\n"), missing
end

--- "mouseover > leader > Bo's pet > me" for the book's tooltip.
function O.summary(ov, ctx)
  if ov.text then return "your own macro text" end
  local parts = {}
  if ov.mod then parts[#parts + 1] = ov.mod .. " = me" end
  for _, t in ipairs(ov.targets or {}) do parts[#parts + 1] = O.label(t, ctx) end
  return tconcat(parts, " > ")
end

-- ------------------------------------------------------------------ text overrides: live checks
-- Only WoW's own macro conditionals (no addon or script syntax).
local COND_WORDS = { help = 1, harm = 1, dead = 1, nodead = 1, exists = 1, noexists = 1, combat = 1, nocombat = 1, mod = 1, nomod = 1,
  stealth = 1, nostealth = 1, channeling = 1, nochanneling = 1, pet = 1, nopet = 1, group = 1, nogroup = 1, flying = 1, noflying = 1,
  mounted = 1, nomounted = 1, indoors = 1, outdoors = 1, swimming = 1, noswimming = 1, party = 1, raid = 1, actionbar = 1, bar = 1,
  bonusbar = 1, button = 1, btn = 1, equipped = 1, worn = 1, form = 1, stance = 1, noform = 1, nostance = 1, known = 1, noknown = 1,
  spec = 1, talent = 1, flyable = 1, noflyable = 1, resting = 1, noresting = 1, modifier = 1, nomodifier = 1, target = 1 }
--- Problems with the conditionals of a body: list of plain sentences (empty = fine).
function O.checkConditionals(body)
  local out = {}
  for group in body:gmatch("%[([^%]]*)%]") do
    for part in (group .. ","):gmatch("%s*([^,]*),") do
      if part ~= "" then
        local word = smatch(part, "^@") and "@" or smatch(part, "^([%a]+)")
        if word == "@" then
          if not smatch(part, "^@[%w]+$") then out[#out + 1] = "\"" .. part .. "\" is not a unit" end
        elseif not (word and COND_WORDS[slower(word)]) then
          out[#out + 1] = "\"" .. part .. "\" is not a WoW macro condition"
        end
      end
    end
  end
  if sfind(body, "[", 1, true) and select(2, body:gsub("%[", "")) ~= select(2, body:gsub("%]", "")) then out[#out + 1] = "A [ has no matching ]" end
  return out
end
--- All checks for a text override: ok, {problems}. The same Rules as every key, plus the conditionals.
function O.checkText(name, body)
  local probs = {}
  local ok, why = ns.Rules.validateMacro(name, body)
  if not ok then probs[#probs + 1] = why end
  for _, p in ipairs(O.checkConditionals(body)) do probs[#probs + 1] = p end
  return #probs == 0, probs
end

-- ------------------------------------------------------------------ hook for Macros.desired
--- Apply cdb.overrides to the desired list (in place). ctx = {squad, me}. Marks d.override, d.frozen, d.ovMissing.
function O.applyAll(desired, overrides, ctx)
  if not overrides then return end
  for _, d in ipairs(desired) do
    local ov = overrides[d.name]
    if ov then
      d.override = ov
      d.engineBody = d.body
      if ov.text then
        d.body, d.frozen = ov.text, true -- frozen: level-ups no longer change it
      else
        d.body, d.ovMissing = O.apply(d.body, ov, ctx)
        if #d.ovMissing == 0 then d.ovMissing = nil end
      end
    end
  end
end

--- Context for this character (the squad and its member).
function O.ctx()
  local s, m = ns.Core.me()
  return { squad = s, me = m }
end

--- The targets the engine's body uses, read back as meanings (prefill for the Targeting window).
function O.fromBody(body, ctx)
  local me = ctx.me
  local first
  for line in (body .. "\n"):gmatch("([^\n]*)\n") do
    local cmd, arg = smatch(line, "^(/%S+)%s*(.*)$")
    if cmd and TARGET_CMDS[cmd] then local c = splitConds(arg); if isTargeting(c) then first = c; break end end
  end
  local out = {}
  if not first then return out end
  if first == "" then return { { who = "target", nodead = false } } end
  local leaderUnit = me and not me.leader and me.unit or nil
  for g in first:gmatch("%[([^%]]*)%]") do
    local unit = smatch(g, "@([%w]+)")
    local t = { help = sfind(g, "help", 1, true) and true or (sfind(g, "harm", 1, true) and false or nil), nodead = sfind(g, "nodead", 1, true) ~= nil }
    if not unit then t.who = "target"
    elseif unit == "mouseover" or unit == "focus" or unit == "player" or unit == "targettarget" then t.who = unit
    elseif unit == "pet" then t.who = "mypet"
    elseif leaderUnit and unit == leaderUnit then t.who = "leader"
    elseif leaderUnit and unit == leaderUnit .. "target" then t.who = "leadertarget"
    elseif contains(O.RAW_UNITS, unit) then t.who, t.unit = "unit", unit
    else t = nil end
    if t then out[#out + 1] = t end
  end
  return out
end

--- What a target is, in a few words (the tile's tooltip): "Mouseover – whoever your mouse is over".
O.ABOUT = { mouseover = "whoever your mouse is over", target = "what you have targeted", leader = "the squad's leader",
  leadertarget = "what the leader has targeted", focus = "the unit you set as focus", targettarget = "your target's target",
  player = "you", mypet = "your own pet" }
function O.about(t, ctx)
  if t.who == "member" then return t.pet and ("the pet of " .. t.name) or ("your squad member " .. t.name) end
  if t.who == "unit" then
    local n, pet = smatch(t.unit, "^%a+(%d+)(p?e?t?)$")
    local kind = smatch(t.unit, "^raid") and "raid member " or "party member "
    return (pet == "pet" and ("the pet of " .. kind) or kind) .. (n or "")
  end
  return O.ABOUT[t.who] or ""
end

--- Add-target choices for this client, grouped (docs: Macro editor → Targeting):
--- {{key, title, tip, folded, items = {{label, target}}}} – Common, Squad, Party, Raid (folded).
function O.groups(ctx, help)
  local function item(t)
    t.help = help; t.nodead = true
    local u, label = O.unitFor(t, ctx), O.label(t, ctx)
    local text = label
    if not u then text = label .. " (not in party)"
    elseif slower(u) ~= slower(label) and u ~= "" then
      text = label .. (sfind(label, "(", 1, true) and (" · " .. u) or (" (" .. u .. ")")) -- "Dorin (leader) · player"
    end
    return { text, t }
  end
  local common = {}
  for _, w in ipairs({ "mouseover", "target", "leader", "leadertarget", "focus", "targettarget", "player", "mypet" }) do
    common[#common + 1] = item({ who = w })
  end
  local squad = {}
  for _, m in ipairs(ctx.squad and ctx.squad.members or {}) do
    if m ~= ctx.me then
      squad[#squad + 1] = item({ who = "member", name = m.name })
      if m.cls == "hunter" or m.cls == "warlock" then squad[#squad + 1] = item({ who = "member", name = m.name, pet = true }) end
    end
  end
  local party, raid = {}, {}
  for _, u in ipairs(O.PARTY_UNITS) do party[#party + 1] = item({ who = "unit", unit = u }) end
  for _, u in ipairs(O.RAID_UNITS) do raid[#raid + 1] = item({ who = "unit", unit = u }) end
  local out = {
    { key = "common", title = "Common", tip = "Who your macro aims at, wherever you play.", items = common },
    { key = "squad", title = "Squad", tip = "Your squad members (and their pets) with their unit on this client.", items = squad },
    { key = "party", title = "Party", tip = "A party is you + party1–4 (there is no party5: you are \"player\").", items = party },
    { key = "raid", title = "Raid", tip = "raid1–40 and their pets, for squads of 6 or more. In a party a raid unit is simply skipped.", items = raid, folded = true },
  }
  if #squad == 0 then table.remove(out, 2) end
  return out
end
--- The same choices as one flat list {{label, target}} (the order of the groups).
function O.choices(ctx, help)
  local v = {}
  for _, g in ipairs(O.groups(ctx, help)) do for _, it in ipairs(g.items) do v[#v + 1] = it end end
  return v
end

--- Pets in the squad other than mine: {{name, label}} – for "Also heal Bo's pet".
function O.squadPets(ctx)
  local out = {}
  for _, m in ipairs(ctx.squad and ctx.squad.members or {}) do
    if m ~= ctx.me and (m.cls == "hunter" or m.cls == "warlock") then out[#out + 1] = m end
  end
  return out
end

return O
