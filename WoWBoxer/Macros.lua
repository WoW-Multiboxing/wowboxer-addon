--[[ WoWBoxer – macros.
  desired(m)  -> the WBX macros this character should have at its level (names are stable: WBX K1.., S1/S2, C1.., helpers)
  plan(list)  -> diff against the character's existing WBX macros: create / update / same / noslot / invalid
  apply(plan) -> CreateMacro / EditMacro, out of combat only (the caller queues it otherwise)
  Never touches a macro whose name does not start with WBX. ]]
local _, ns = ...
local M = {}
ns.Macros = M

local E, K, R, C = ns.Engine, ns.Kit, ns.Rules, ns.Compat

M.ICON = 134400 -- the "?" icon: #showtooltip then shows the spell
M.ORDER = { "K1", "K2", "K3", "K4", "K5", "K6", "K7", "K8", "S1", "S2", "C1", "C2", "C3", "C4", "C5", "C6", "C7", "C8",
  "Invite", "Invite2", "Follow", "FollowLead", "Assist", "Target", "Focus", "Pet", "PetBack" }
local SEQ_KEY = { dps = "S1", heal = "S2" }
--- Helper keys run no spell, so #showtooltip cannot pick an icon: each gets a picture that says what it does.
M.HELPER_ICON = { Follow = "Ability_Tracking", Assist = "Ability_Hunter_SniperShot", Focus = "Spell_Holy_MindVision",
  Pet = "Ability_GhoulFrenzy", PetBack = "Ability_Seal", Invite = "INV_Letter_01", Invite2 = "INV_Letter_01", Target = "Ability_TownWatch",
  FollowLead = "Ability_Rogue_Sprint" }

-- ------------------------------------------------------------------ squad keys (docs/squad-v2-simple.md §3)
-- The player ticks which ones this character gets (cdb.squadKeys, per character); unticked ones are not created.
-- Only Invite uses names; Follow, Assist, Target and Focus use the leader's party unit, exactly like the spell keys.
local function follower(m) return not m.leader end
local function petClass(m) return m.cls == "warlock" or m.cls == "hunter" end
M.SQUAD_KEYS = {
  { key = "Invite", label = "Invite squad", applies = function(m, s) return s ~= nil and #s.members > 1 end, default = function(m) return m.leader end },
  { key = "Follow", label = "Follow (line)", applies = follower, default = function() return true end },
  { key = "FollowLead", label = "Follow leader", applies = follower, default = function() return true end },
  { key = "Assist", label = "Assist", applies = follower, default = function() return true end },
  { key = "Target", label = "Target leader", applies = follower, default = function() return false end },
  { key = "Focus", label = "Focus leader", applies = function(m) return follower(m) and m.unit == "focus" end, default = function() return true end },
  { key = "Pet", label = "Pet attack", applies = petClass, default = function() return true end },
  { key = "PetBack", label = "Pet back", applies = petClass, default = function() return true end },
}
--- Is squad key `key` ticked for member m? choices = cdb.squadKeys ({[key] = true/false}); nil = the default.
function M.squadKeyOn(m, key, choices)
  local v = choices and choices[key]
  if v ~= nil then return v and true or false end
  for _, d in ipairs(M.SQUAD_KEYS) do if d.key == key then return d.default(m) end end
  return true
end
--- The squad keys this member can have: {{key, label, on}} (in the order of M.SQUAD_KEYS).
function M.squadKeyList(m, choices, s)
  local out = {}
  for _, d in ipairs(M.SQUAD_KEYS) do
    if d.applies(m, s) then out[#out + 1] = { key = d.key, label = d.label, on = M.squadKeyOn(m, d.key, choices) } end
  end
  return out
end
--- "Name" or "Name-Realm" for /invite.
function M.inviteName(m) return m.realm and (m.name .. "-" .. m.realm) or m.name end
--- /invite lines for every other member, split into bodies of at most 255 characters.
function M.inviteBodies(s, me)
  local bodies, cur = {}, ""
  for _, x in ipairs(s and s.members or {}) do
    if x ~= me then
      local line = "/invite " .. M.inviteName(x)
      if cur ~= "" and #cur + 1 + #line > R.MACRO_LIMIT then bodies[#bodies + 1] = cur; cur = "" end
      cur = cur == "" and line or (cur .. "\n" .. line)
    end
  end
  if cur ~= "" then bodies[#bodies + 1] = cur end
  return bodies
end
--- The squad keys member m gets: {{key, label, body}} – K.helpers filtered by the ticks, plus Target and Invite.
--- Follow (line) follows the member ahead (opts.lineUnit on this client, else m.lineUnit, else the leader's unit);
--- Follow leader is the old Follow. Both use party units, never names (docs/follow-line.md).
function M.squadKeys(m, opts)
  local choices, s = opts.squadKeys, opts.squad
  local out = {}
  if s and M.squadKeyOn(m, "Invite", choices) then
    for i, body in ipairs(M.inviteBodies(s, m)) do
      if i <= 2 then out[#out + 1] = { key = i == 1 and "Invite" or "Invite2", label = i == 1 and "Invite squad" or "Invite squad 2", body = body } end
    end
  end
  local u = E.units(m.unit)
  for _, h in ipairs(K.helpers(m)) do
    if h.key == "Follow" then
      if M.squadKeyOn(m, "Follow", choices) then
        out[#out + 1] = { key = "Follow", label = "Follow the one ahead in the line", body = "/follow " .. (opts.lineUnit or m.lineUnit or u.main) }
      end
      if M.squadKeyOn(m, "FollowLead", choices) then out[#out + 1] = { key = "FollowLead", label = "Follow the leader", body = h.body } end
    elseif M.squadKeyOn(m, h.key, choices) then out[#out + 1] = h end
    if h.key == "Assist" and M.squadKeyOn(m, "Target", choices) then
      out[#out + 1] = { key = "Target", label = "Target the leader", body = "/target " .. u.main }
    end
  end
  return out
end
--- The icon argument for CreateMacro/EditMacro: the file ID when the client can look it up, else the icon name.
function M.namedIcon(slug)
  local f = _G.GetFileIDFromPath
  if f then
    local ok, id = pcall(f, "Interface\\Icons\\" .. slug)
    if ok and type(id) == "number" and id > 0 then return id end
  end
  return slug
end

--- live(name, spell) from the spellbook: true if the character really knows the spell. nil when no spellbook API.
function M.liveCheck()
  local names = C.knownSpellNames()
  if not names then return nil end
  return function(name, spell) return names[name] == true or C.knowsAnyRank(spell) end
end

local function shortName(name) local s = R.PREFIX .. " " .. name; if #s > R.NAME_LIMIT then s = s:sub(1, R.NAME_LIMIT) end return s end
M.shortName = shortName

-- ------------------------------------------------------------------ non-English clients
-- The data (and so every macro) uses English spell names. On other locales /cast needs the client's own names: they come
-- from the spell IDs in the data (C_Spell.GetSpellName / GetSpellInfo). Only whole tokens are replaced – the name after
-- #showtooltip, after the conditions of /cast (optionally "!"), and each entry of a /castsequence – never substrings,
-- so "Heal" inside "Greater Heal" stays intact. English clients skip all of this.
local nameMaps = {}
function M.nameMap(m)
  if not C.needsLocalNames() then return nil end
  local key = m.cls .. ":" .. tostring(m.race)
  if nameMaps[key] ~= nil then return nameMaps[key] or nil end
  local map, n = {}, 0
  for _, s in ipairs(K.spellsOf(m)) do
    local id = s.ranks and s.ranks[1] and s.ranks[1].id
    local loc = id and C.spellName(id)
    if loc and loc ~= s.name then map[s.name] = loc; n = n + 1 end
  end
  nameMaps[key] = n > 0 and map or false
  return n > 0 and map or nil
end
local function locName(map, name)
  local bang, base = name:match("^(!?)(.*)$")
  return bang .. (map[base] or base)
end
--- Translate the spell names in a macro body with `map` (English -> client name). Pure function.
function M.localize(body, map)
  if not map then return body end
  local out = {}
  for line in (body .. "\n"):gmatch("([^\n]*)\n") do
    local tip = line:match("^#showtooltip (.+)$")
    if tip then line = "#showtooltip " .. locName(map, tip)
    else
      local cmd, rest = line:match("^(/castsequence )(.*)$")
      if not cmd then cmd, rest = line:match("^(/cast )(.*)$") end
      if cmd then
        local conds, i = "", 1
        while rest:sub(i, i) == "[" do
          local j = rest:find("]", i, true)
          if not j then break end
          conds = conds .. rest:sub(i, j); i = j + 1
        end
        local tail = rest:sub(i):gsub("^%s+", "")
        local reset, list = tail:match("^(reset=%S+ )(.*)$")
        if not reset then reset, list = "", tail end
        local parts = {}
        for item in (list .. ", "):gmatch("(.-), ") do parts[#parts + 1] = locName(map, item) end
        line = cmd .. conds .. ((conds ~= "" and #parts > 0) and " " or "") .. reset .. table.concat(parts, ", ")
      end
    end
    out[#out + 1] = line
  end
  return table.concat(out, "\n")
end

M.CAP = 60 -- the highest level any spell in the data unlocks at

--- Whether spell s is usable by member m at level L: nil = known now, "trainer" = learnable now but not in the
--- spellbook, a number = the level it unlocks at, false = never (a talent outside the plan, or past the cap).
function M.pendingOf(m, s, L, live)
  local known = live and live(s.name, s)
  if known then return nil end
  if K.learned(m, s, L) then return live and "trainer" or nil end
  if s.gate ~= "talent" then return s.level <= M.CAP and s.level or false end
  for lv = math.max(L + 1, s.level), M.CAP do if K.learned(m, s, lv) then return lv end end -- when the plan takes the talent
  return false
end

--- The macros member m should have at level L. opts: {live=fn|nil, extras={spellIds}, squad=s, squadKeys=ticks}
--- Each item: {name, key, group, label, body, spell?, icon}
function M.desired(m, L, opts)
  opts = opts or {}
  L = L or m.level
  local live = opts.live
  local ctx = K.memberCtx(m)
  local out = {}
  for _, x in ipairs(K.kitSlots(m, L, live)) do
    local body = E.makeMacro(x.spell, ctx)
    if body ~= "" then
      out[#out + 1] = { key = "K" .. x.slot, name = R.PREFIX .. " K" .. x.slot, group = "kit", label = x.spell.name, item = x.item, body = body, spell = x.spell }
    end
  end
  local customIndex = {}
  for i, c in ipairs(m.customSeq or {}) do customIndex["c" .. c.id] = i end
  for _, x in ipairs(K.seqOf(m, L, live)) do
    local key = x.custom and customIndex[x.id] and ("C" .. customIndex[x.id]) or SEQ_KEY[x.id]
    if key and x.macro ~= "" then
      out[#out + 1] = { key = key, name = R.PREFIX .. " " .. key, group = x.custom and "custom" or "sequence", label = x.label, body = x.macro, seq = x }
    end
  end
  for _, h in ipairs(M.squadKeys(m, opts)) do
    out[#out + 1] = { key = h.key, name = R.PREFIX .. " " .. h.key, group = "helper", label = h.label, body = h.body }
  end
  -- extra single-spell keys the player added from the spell list
  local all = K.spellsOf(m)
  -- names are cut to 16 characters, so two spells can share one ("Shadow Word: Pain"/"Death"): the later one gets a
  -- digit instead of its last character. Taken in the order of the extras list, so a name never changes by level.
  local taken = {}
  for _, d in ipairs(out) do taken[d.name] = true end
  local function unique(name)
    if not taken[name] then return name end
    for i = 2, 9 do
      local n = name:sub(1, R.NAME_LIMIT - 1) .. i
      if not taken[n] then return n end
    end
    return nil
  end
  -- A spell not learned yet (trainer, or a later level) still gets its macro: /cast does nothing until the spell is
  -- learned, then the same macro just works. pending = "trainer" or the unlock level.
  for _, id in ipairs(opts.extras or {}) do
    for _, s in ipairs(all) do
      if s.id == id and s.action ~= "passive" then
        local name = unique(shortName(s.name)) -- reserved even when not learned yet, so it never moves
        if name then
          taken[name] = true
          local pending = M.pendingOf(m, s, L, live)
          if pending ~= false then
            out[#out + 1] = { key = "X:" .. s.id, name = name, group = "extra", label = s.name, body = E.makeMacro(s, ctx), spell = s,
              pending = pending }
          end
        end
      end
    end
  end
  local map = M.nameMap(m)
  local byName = {}
  for _, s in ipairs(all) do byName[s.name] = s end
  for _, d in ipairs(out) do
    if map then d.body = M.localize(d.body, map) end
    d.icon = M.ICON
    -- a "?" macro of an unknown spell stays a "?" on the bar: give it the spell's own picture
    if d.pending and d.spell.icon then d.icon = M.namedIcon(d.spell.icon) end
    if d.seq then M.seqIcon(d, byName) end
    if d.group == "helper" and M.HELPER_ICON[d.key] then d.iconName = M.HELPER_ICON[d.key]; d.icon = M.namedIcon(d.iconName) end
    d.ok, d.why = R.validateMacro(d.name, d.body)
    if not d.ok and map and #d.body > R.MACRO_LIMIT then d.why = "too long with your client's spell names (" .. #d.body .. "/255)" end
  end
  -- Advanced mode: the player's own targeting / text (Override.lua), checked by the same rules as every key
  if opts.overrides and ns.Override then
    ns.Override.applyAll(out, opts.overrides, opts.ovCtx or {})
    for _, d in ipairs(out) do
      if d.override then
        d.ok, d.why = R.validateMacro(d.name, d.body)
        if not d.ok and #d.body > R.MACRO_LIMIT then d.why = "Too long with your targeting (" .. #d.body .. "/255): remove a target or untick Skip if dead" end
      end
    end
  end
  return out
end

--- Sequence and priority keys: their steps as spell objects and a real icon. A bare #showtooltip shows "?" whenever no
--- line's conditions match (no hostile target, docs/squad-overhaul.md §1), so these macros get the main spell's icon:
--- the filler of a castsequence, the first line of a priority key. d.steps = spells in cast order, d.main = that spell.
function M.seqIcon(d, byName)
  local x = d.seq
  local steps = {}
  for _, n in ipairs(x.spells or {}) do if byName[n] then steps[#steps + 1] = byName[n] end end
  if x.base == "sequence" and x.filler and byName[x.filler] then
    -- cast order: the steps, then the filler (fills) times
    steps = {}
    for _, n in ipairs(x.spells) do if n ~= x.filler and byName[n] then steps[#steps + 1] = byName[n] end end
    for _ = 1, math.max(1, x.fills or 1) do steps[#steps + 1] = byName[x.filler] end
  end
  d.steps = steps
  d.main = (x.base == "sequence" and x.filler and byName[x.filler]) or steps[1]
  d.icon = C.spellTexture(d.main) or M.ICON
end

--- Spells the character should know at level L (data) but the spellbook does not have: visit the trainer.
function M.missingFromBook(m, L, live)
  if not live then return {} end
  local out = {}
  for _, s in ipairs(K.spellsOf(m)) do
    if K.learned(m, s, L) and s.gate ~= "racial" and s.action ~= "passive" and not live(s.name, s) then out[#out + 1] = s end
  end
  return out
end

--- True when an existing macro needs a new icon: it still has the "?" while we want a real one, or another real one.
function M.iconChanged(have, want)
  if want == nil or want == M.ICON then return false end
  if type(have) == "string" and not tonumber(have) then return have:lower():find("questionmark", 1, true) ~= nil end
  -- an icon given by name: the client stores some file ID for it, so only the "?" counts as a change
  if type(want) == "string" then return have == nil or tonumber(have) == M.ICON end
  have = tonumber(have)
  return have == nil or have == M.ICON or have ~= want
end

--- Diff desired against existing character macros. skip = {[name]=true} to leave out.
function M.plan(desired, skip)
  skip = skip or {}
  local existing = C.characterMacros()
  local byName = {}
  for _, x in ipairs(existing) do if R.isOurs(x.name) and not byName[x.name] then byName[x.name] = x end end
  local accMax, charMax = C.macroLimits()
  local free = charMax - #existing
  local items, wanted = {}, {}
  local counts = { create = 0, update = 0, same = 0, noslot = 0, invalid = 0, skipped = 0 }
  for _, d in ipairs(desired) do
    wanted[d.name] = true
    local it = { name = d.name, key = d.key, label = d.label, body = d.body, icon = d.icon, group = d.group, seq = d.seq ~= nil }
    local cur = byName[d.name]
    if skip[d.name] then it.status = "skipped"
    elseif not d.ok then it.status = "invalid"; it.why = d.why
    elseif cur and cur.body == d.body and not M.iconChanged(cur.icon, d.icon) then it.status = "same"; it.index = cur.index
    elseif cur then it.status = "update"; it.index = cur.index; it.old = cur.body
    elseif free > 0 then it.status = "create"; free = free - 1
    else it.status = "noslot" end
    counts[it.status] = counts[it.status] + 1
    items[#items + 1] = it
  end
  local unused = {}
  for _, x in ipairs(existing) do if R.isOurs(x.name) and not wanted[x.name] then unused[#unused + 1] = x.name end end
  local accountOurs = {}
  for _, x in ipairs(C.accountMacros()) do if R.isOurs(x.name) then accountOurs[#accountOurs + 1] = x.name end end
  return { items = items, counts = counts, unused = unused, accountOurs = accountOurs, free = free, charMax = charMax, accMax = accMax,
    changes = counts.create + counts.update }
end

--- Index of our character macro with this name (re-read every time: indices move when macros are sorted).
function M.findIndex(name)
  for _, x in ipairs(C.characterMacros()) do if x.name == name then return x.index end end
  return nil
end

--- Apply create/update items. Must be called out of combat. Returns {done, failed={{name, err}}}
function M.apply(plan)
  local res = { created = 0, updated = 0, failed = {}, changed = {} }
  if C.inCombat() then res.failed[1] = { name = "*", err = "in combat" }; return res end
  for _, it in ipairs(plan.items) do
    if it.status == "create" or it.status == "update" then
      local ok, why = R.validateMacro(it.name, it.body)
      if not ok then
        res.failed[#res.failed + 1] = { name = it.name, err = why }
      elseif it.status == "create" then
        if M.findIndex(it.name) then -- created meanwhile: edit instead
          local idx = M.findIndex(it.name)
          local okc, err = pcall(EditMacro, idx, it.name, it.icon, it.body)
          if okc then res.updated = res.updated + 1; res.changed[#res.changed + 1] = it.name else res.failed[#res.failed + 1] = { name = it.name, err = tostring(err) } end
        else
          local okc, err = pcall(CreateMacro, it.name, it.icon, it.body, true)
          if okc and err then res.created = res.created + 1; res.changed[#res.changed + 1] = it.name else res.failed[#res.failed + 1] = { name = it.name, err = tostring(err or "no free macro slot") } end
        end
      else
        local idx = M.findIndex(it.name)
        if not idx then res.failed[#res.failed + 1] = { name = it.name, err = "macro disappeared" }
        else
          local okc, err = pcall(EditMacro, idx, it.name, it.icon, it.body)
          if okc then res.updated = res.updated + 1; res.changed[#res.changed + 1] = it.name else res.failed[#res.failed + 1] = { name = it.name, err = tostring(err) } end
        end
      end
    end
  end
  return res
end

--- Delete unused WBX character macros (only on an explicit click).
function M.deleteUnused(names)
  local n = 0
  if C.inCombat() then return 0 end
  for _, name in ipairs(names) do
    if R.isOurs(name) then
      local idx = M.findIndex(name)
      if idx and pcall(DeleteMacro, idx) then n = n + 1 end
    end
  end
  return n
end
