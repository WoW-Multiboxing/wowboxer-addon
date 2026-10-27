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
  for _, id in ipairs(opts.extras or {}) do
    for _, s in ipairs(all) do
      if s.id == id and K.learned(m, s, L) and (not live or live(s.name, s)) and s.action ~= "passive" then
        out[#out + 1] = { key = "X:" .. s.id, name = shortName(s.name), group = "extra", label = s.name, body = E.makeMacro(s, ctx), spell = s }
      end
    end
  end
  for _, d in ipairs(out) do d.icon = M.ICON; d.ok, d.why = R.validateMacro(d.name, d.body) end
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
  local res = { created = 0, updated = 0, failed = {} }
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
          if okc then res.updated = res.updated + 1 else res.failed[#res.failed + 1] = { name = it.name, err = tostring(err) } end
        else
          local okc, err = pcall(CreateMacro, it.name, it.icon, it.body, true)
          if okc and err then res.created = res.created + 1 else res.failed[#res.failed + 1] = { name = it.name, err = tostring(err or "no free macro slot") } end
        end
      else
        local idx = M.findIndex(it.name)
        if not idx then res.failed[#res.failed + 1] = { name = it.name, err = "macro disappeared" }
        else
          local okc, err = pcall(EditMacro, idx, it.name, it.icon, it.body)
          if okc then res.updated = res.updated + 1 else res.failed[#res.failed + 1] = { name = it.name, err = tostring(err) } end
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
