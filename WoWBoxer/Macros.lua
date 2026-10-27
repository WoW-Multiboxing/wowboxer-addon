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
  "Follow", "Assist", "Focus", "Pet", "PetBack" }
local SEQ_KEY = { dps = "S1", heal = "S2" }

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

--- The macros member m should have at level L. opts: {live=fn|nil, extras={spellIds}}
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
  for _, h in ipairs(K.helpers(m)) do
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
  for _, id in ipairs(opts.extras or {}) do
    for _, s in ipairs(all) do
      if s.id == id and s.action ~= "passive" then
        local name = unique(shortName(s.name)) -- reserved even when not learned yet, so it never moves
        if name then
          taken[name] = true
          if K.learned(m, s, L) and (not live or live(s.name, s)) then
            out[#out + 1] = { key = "X:" .. s.id, name = name, group = "extra", label = s.name, body = E.makeMacro(s, ctx), spell = s }
          end
        end
      end
    end
  end
  local map = M.nameMap(m)
  for _, d in ipairs(out) do
    if map then d.body = M.localize(d.body, map) end
    d.icon = M.ICON; d.ok, d.why = R.validateMacro(d.name, d.body)
    if not d.ok and map and #d.body > R.MACRO_LIMIT then d.why = "too long with your client's spell names (" .. #d.body .. "/255)" end
  end
  return out
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
    local it = { name = d.name, key = d.key, label = d.label, body = d.body, icon = d.icon, group = d.group }
    local cur = byName[d.name]
    if skip[d.name] then it.status = "skipped"
    elseif not d.ok then it.status = "invalid"; it.why = d.why
    elseif cur and cur.body == d.body then it.status = "same"; it.index = cur.index
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
