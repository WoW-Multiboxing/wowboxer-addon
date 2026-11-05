--[[ WoWBoxer – action bar placement.
  Fixed layout so muscle memory survives level-ups: on the primary bar K1–K8 sit on buttons 1–8, S1/S2 on 9–10 and
  Follow/Assist on 11–12; on the secondary bar C1–C8 sit on 1–8, Focus/Pet/PetBack on 9–11 and Invite on 12 (Wand on 10, or
  the first of 9/12/11 its character does not use), extras fill what is
  left. A slot that holds something that is not a WoWBoxer macro is only replaced when the player ticks "replace". ]]
local _, ns = ...
local B = {}
ns.Bars = B

local R, C, M = ns.Rules, ns.Compat, ns.Macros
local G = _G

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
local SECONDARY = { C1 = 0, C2 = 1, C3 = 2, C4 = 3, C5 = 4, C6 = 5, C7 = 6, C8 = 7, Focus = 8, Pet = 9, PetBack = 10, Invite = 11 }
local SHARED = { Wand = { 9, 8, 11, 10 } }

--- The action slots that have a button on screen (the five bars), in bar order.
function B.buttonSlots()
  local out = {}
  for _, b in ipairs(B.BARS) do for i = 0, 11 do out[#out + 1] = b.first + i end end
  return out
end
--- Target slot for every desired macro, in this order (owner, 5 Nov 2026):
---   1. where the player has that WBX macro now (cdb.slots, kept by Core.scanBars) – updates never move it;
---   2. the button that already holds the macro's spell (Smite on button 5 -> WBX K1 goes on button 5);
---   3. the fixed layout below; extras go to an empty button first.
--- info(slot) -> C.actionInfo-like table (optional; without it steps 2 and "empty first" are skipped).
function B.layout(desired, cdb, info)
  local p, s = cdb.primaryBar or 1, cdb.secondaryBar or 61
  local taken, out = {}, {}
  local function take(slot) taken[slot] = true; return slot end
  for _, d in ipairs(desired) do
    local slot = cdb.slots[d.name]
    if slot and not taken[slot] then out[d.name] = take(slot) end
  end
  local held = {}
  if info then
    local bySpell = {}
    for _, slot in ipairs(B.buttonSlots()) do
      local a = info(slot)
      held[slot] = a ~= nil
      if a and a.kind == "spell" and type(a.name) == "string" and not taken[slot] and not bySpell[a.name] then bySpell[a.name] = slot end
    end
    for _, d in ipairs(desired) do
      local sp = d.spell and d.spell.name
      local slot = sp and bySpell[sp]
      if not out[d.name] and slot and not taken[slot] then out[d.name] = take(slot) end
    end
  end
  for _, d in ipairs(desired) do
    if not out[d.name] then
      local slot
      if PRIMARY[d.key] then slot = p + PRIMARY[d.key] elseif SECONDARY[d.key] then slot = s + SECONDARY[d.key] end
      if slot and not taken[slot] then out[d.name] = take(slot) end
    end
  end
  -- keys that share a fixed button (Wand: the Pet button for mages and priests; a warlock's next free fixed button)
  local reserved = {}
  for _, d in ipairs(desired) do if SECONDARY[d.key] then reserved[s + SECONDARY[d.key]] = true end end
  for _, d in ipairs(desired) do
    if not out[d.name] and SHARED[d.key] then
      for _, i in ipairs(SHARED[d.key]) do
        local slot = s + i
        if not taken[slot] and not reserved[slot] then out[d.name] = take(slot); break end
      end
    end
  end
  -- extras: the first empty button on the secondary bar, then the primary bar; then the first one not planned
  for _, d in ipairs(desired) do
    if not out[d.name] then
      for _, emptyOnly in ipairs({ true, false }) do
        for _, base in ipairs({ s, p }) do
          for i = 0, 11 do
            local slot = base + i
            if not taken[slot] and not (emptyOnly and held[slot]) then out[d.name] = take(slot); break end
          end
          if out[d.name] then break end
        end
        if out[d.name] then break end
      end
    end
  end
  return out
end

--- Placement plan: {items={{name, slot, status, current}}, counts}. status: placed | empty | ours | occupied | missing | off
function B.plan(desired, cdb, skip)
  skip = skip or {}
  local layout = B.layout(desired, cdb, C.actionInfo)
  local items, counts = {}, { placed = 0, empty = 0, ours = 0, occupied = 0, missing = 0, off = 0 }
  for _, d in ipairs(desired) do
    local slot = layout[d.name]
    if slot and not skip[d.name] then
      local cur = C.actionInfo(slot)
      local it = { name = d.name, label = d.label, slot = slot, current = cur }
      if cur and cur.kind == "macro" and cur.name == d.name then it.status = "placed"
      elseif d.keepOff then it.status = "off" -- "Keep off my bars": never placed by Place all, never counted
      elseif not M.findIndex(d.name) then it.status = "missing"
      elseif not cur then it.status = "empty"
      elseif cur.kind == "macro" and R.isOurs(cur.name) then it.status = "ours"
      else it.status = "occupied" end
      counts[it.status] = counts[it.status] + 1
      items[#items + 1] = it
    end
  end
  return { items = items, counts = counts, changes = counts.empty + counts.ours }
end

-- ------------------------------------------------------------------ the ONLY writes to action slots and the cursor
-- Every PickupMacro / PlaceAction / PickupAction / ClearCursor of the addon is here (lint51 checks it), with a log line
-- naming who asked (source=). Before WoWBoxer first changes a slot, what was there goes into cdb.barOriginal[slot]
-- (never overwritten), so Reset to default can put the bars back as they were.
local function charDB() return ns.Core and ns.Core.cdb end
local function log(msg) if ns.Core then ns.Core.log("info", msg) end end
--- What a slot holds, as data: {kind = "empty"} | {kind = "spell"/"item"/"macro", id, name}.
function B.content(slot)
  local a = C.actionInfo(slot)
  if not a then return { kind = "empty" } end
  return { kind = a.kind, id = a.id, name = a.name }
end
--- Remember what slot held before WoWBoxer's first change (once; a WBX macro there is never "the original").
function B.snapshot(slot, before)
  local c = charDB()
  if not (c and slot) then return end
  c.barOriginal = c.barOriginal or {}
  if c.barOriginal[slot] ~= nil then return end
  before = before or B.content(slot)
  if before.kind == "macro" and R.isOurs(before.name) then return end
  c.barOriginal[slot] = before
end
--- Watch the bars (scanBars): a slot that now holds a WBX macro but was something else last time (the player dragged
--- it there) gets that something else as its original.
function B.watch()
  local c = charDB()
  if not c then return end
  c.barSeen = c.barSeen or {}
  for slot = 1, 120 do
    local now = B.content(slot)
    local ours = now.kind == "macro" and R.isOurs(now.name)
    if ours then
      if c.barSeen[slot] then B.snapshot(slot, c.barSeen[slot]) end
    else c.barSeen[slot] = now end
  end
end
function B.clearCursor(source)
  if C.cursorBusy() then pcall(ClearCursor); log("cursor cleared (source=" .. tostring(source) .. ")") end
end
--- Put macro #idx on the cursor (a drag starts; the player drops it).
function B.pickupMacro(idx, source)
  B.clearCursor(source)
  local ok = pcall(PickupMacro, idx)
  log("pickup macro #" .. tostring(idx) .. " (source=" .. tostring(source) .. ")")
  return ok
end
--- Put macro #idx on slot (snapshot first). Returns true or false, err.
function B.placeMacro(idx, slot, source)
  B.snapshot(slot)
  local ok, err = pcall(function() PickupMacro(idx); PlaceAction(slot); ClearCursor() end)
  if not ok then pcall(ClearCursor) end
  log("bar " .. slot .. " <- macro #" .. tostring(idx) .. (ok and "" or (" failed: " .. tostring(err))) .. " (source=" .. tostring(source) .. ")")
  return ok, err
end
--- Put the original content back on slot (Reset to default). Returns true or false, why.
function B.restoreSlot(slot, orig, source)
  local ok, err
  if orig.kind == "empty" then
    ok, err = pcall(function() PickupAction(slot); ClearCursor() end)
  elseif orig.kind == "spell" and orig.id and G.PickupSpell then ok, err = pcall(function() G.PickupSpell(orig.id); PlaceAction(slot); ClearCursor() end)
  elseif orig.kind == "item" and orig.id and G.PickupItem then ok, err = pcall(function() G.PickupItem(orig.id); PlaceAction(slot); ClearCursor() end)
  elseif orig.kind == "macro" and orig.name and not R.isOurs(orig.name) then
    local idx = G.GetMacroIndexByName and G.GetMacroIndexByName(orig.name)
    if idx and idx > 0 then ok, err = pcall(function() PickupMacro(idx); PlaceAction(slot); ClearCursor() end) else ok, err = false, "macro " .. orig.name .. " is gone" end
  else ok, err = false, "cannot put back a " .. tostring(orig.kind) end
  if not ok then pcall(ClearCursor) end
  log("bar " .. slot .. " restored to " .. tostring(orig.kind) .. " " .. tostring(orig.name or orig.id or "") .. (ok and "" or (" failed: " .. tostring(err))) .. " (source=" .. tostring(source) .. ")")
  return ok, err
end

--- Place the macros on empty buttons. replace=true (only after the player said yes to "Replace?") also replaces
--- buttons that hold something else – a spell, an item or another WBX macro. Out of combat only.
function B.apply(plan, cdb, replace)
  local res = { placed = 0, skipped = 0, failed = {}, list = {} }
  if C.inCombat() then res.failed[1] = { name = "*", err = "in combat" }; return res end
  if C.cursorBusy() then res.failed[1] = { name = "*", err = "your cursor is holding something; drop it first" }; return res end
  for _, it in ipairs(plan.items) do
    if it.status == "empty" or ((it.status == "occupied" or it.status == "ours") and replace) then
      local idx = M.findIndex(it.name)
      if idx then
        local ok, err = B.placeMacro(idx, it.slot, "place all")
        if ok then res.placed = res.placed + 1; cdb.slots[it.name] = it.slot; if cdb.placedOnce then cdb.placedOnce[it.name] = true end; res.list[#res.list + 1] = it.name
        else res.failed[#res.failed + 1] = { name = it.name, err = tostring(err) } end
      end
    elseif it.status == "placed" then cdb.slots[it.name] = it.slot
    else res.skipped = res.skipped + 1 end
  end
  return res
end
