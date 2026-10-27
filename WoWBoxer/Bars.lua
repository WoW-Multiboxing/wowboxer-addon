--[[ WoWBoxer – action bar placement.
  Fixed layout so muscle memory survives level-ups: on the primary bar K1–K8 sit on buttons 1–8, S1/S2 on 9–10 and
  Follow/Assist on 11–12; on the secondary bar C1–C8 sit on 1–8 and Focus/Pet/PetBack on 9–11, extras fill what is
  left. A slot that holds something that is not a WoWBoxer macro is only replaced when the player ticks "replace". ]]
local _, ns = ...
local B = {}
ns.Bars = B

local R, C, M = ns.Rules, ns.Compat, ns.Macros

B.BARS = {
  { first = 1, label = "Action Bar 1", short = "Bar 1" },
  { first = 61, label = "Bottom Left Bar", short = "BL" },
  { first = 49, label = "Bottom Right Bar", short = "BR" },
  { first = 25, label = "Right Bar", short = "R1" },
  { first = 37, label = "Right Bar 2", short = "R2" },
}
--- "Bar1 3", "BL 12" … for an action slot
function B.slotLabel(slot)
  local first = slot - (slot - 1) % 12
  for _, b in ipairs(B.BARS) do if b.first == first then return b.short .. " · " .. ((slot - 1) % 12 + 1) end end
  return "#" .. slot
end
function B.barLabel(first) for _, b in ipairs(B.BARS) do if b.first == first then return b.label end end return "Bar " .. tostring(first) end
local PRIMARY = { K1 = 0, K2 = 1, K3 = 2, K4 = 3, K5 = 4, K6 = 5, K7 = 6, K8 = 7, S1 = 8, S2 = 9, Follow = 10, Assist = 11 }
local SECONDARY = { C1 = 0, C2 = 1, C3 = 2, C4 = 3, C5 = 4, C6 = 5, C7 = 6, C8 = 7, Focus = 8, Pet = 9, PetBack = 10 }

--- Target slot for every desired macro. cdb.slots remembers manual/earlier placements.
function B.layout(desired, cdb)
  local p, s = cdb.primaryBar or 1, cdb.secondaryBar or 61
  local taken, out = {}, {}
  local function take(slot) taken[slot] = true; return slot end
  for _, d in ipairs(desired) do
    local slot = cdb.slots[d.name]
    if not slot then
      if PRIMARY[d.key] then slot = p + PRIMARY[d.key] elseif SECONDARY[d.key] then slot = s + SECONDARY[d.key] end
    end
    if slot and not taken[slot] then out[d.name] = take(slot) end
  end
  -- extras: first free button on the secondary bar, then the primary bar
  for _, d in ipairs(desired) do
    if not out[d.name] then
      for _, base in ipairs({ s, p }) do
        for i = 0, 11 do if not taken[base + i] then out[d.name] = take(base + i); break end end
        if out[d.name] then break end
      end
    end
  end
  return out
end

--- Placement plan: {items={{name, slot, status, current}}, counts}. status: placed | empty | ours | occupied | missing
function B.plan(desired, cdb, skip)
  skip = skip or {}
  local layout = B.layout(desired, cdb)
  local items, counts = {}, { placed = 0, empty = 0, ours = 0, occupied = 0, missing = 0 }
  for _, d in ipairs(desired) do
    local slot = layout[d.name]
    if slot and not skip[d.name] then
      local cur = C.actionInfo(slot)
      local it = { name = d.name, label = d.label, slot = slot, current = cur }
      if not M.findIndex(d.name) then it.status = "missing"
      elseif not cur then it.status = "empty"
      elseif cur.kind == "macro" and cur.name == d.name then it.status = "placed"
      elseif cur.kind == "macro" and R.isOurs(cur.name) then it.status = "ours"
      else it.status = "occupied" end
      counts[it.status] = counts[it.status] + 1
      items[#items + 1] = it
    end
  end
  return { items = items, counts = counts, changes = counts.empty + counts.ours }
end

--- Place the macros. replace=true also replaces slots that hold other things. Out of combat only.
function B.apply(plan, cdb, replace)
  local res = { placed = 0, skipped = 0, failed = {}, list = {} }
  if C.inCombat() then res.failed[1] = { name = "*", err = "in combat" }; return res end
  if C.cursorBusy() then res.failed[1] = { name = "*", err = "your cursor is holding something; drop it first" }; return res end
  for _, it in ipairs(plan.items) do
    if it.status == "empty" or it.status == "ours" or (it.status == "occupied" and replace) then
      local idx = M.findIndex(it.name)
      if idx then
        local ok, err = pcall(function() PickupMacro(idx); PlaceAction(it.slot); ClearCursor() end)
        if ok then res.placed = res.placed + 1; cdb.slots[it.name] = it.slot; res.list[#res.list + 1] = it.name
        else res.failed[#res.failed + 1] = { name = it.name, err = tostring(err) }; pcall(ClearCursor) end
      end
    elseif it.status == "placed" then cdb.slots[it.name] = it.slot
    else res.skipped = res.skipped + 1 end
  end
  return res
end
