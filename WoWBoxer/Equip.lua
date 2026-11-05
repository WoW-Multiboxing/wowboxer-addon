--[[ WoWBoxer – Auto-equip (owner, 5 Nov 2026): an automation option, OFF by default (not in any preset or Default).
  When a new item lands in your bags (loot, quest reward, mail, vendor):
  - strictly better than what you wear (every stat that counts for your class and role is the same or higher, at
    least one is higher, nothing it wears now is lost) → equipped, one log/chat line;
  - bind on equip (not bound yet) → always asked first (equipping binds it to you);
  - in doubt (some stats up, some down; trinkets; weapon layout changes; effects WoWBoxer can't compare; no stats
    on this client) → asked: Equip / Keep in bag – but only when it could be an upgrade: a trade-off must come out
    ahead in a weighted score for your class and role (E.score), a lower-quality item (white next to green) clearly
    ahead (25 %), and trinkets / unreadable items must not be a lower quality or item level;
  - worse, or not for you (red text in its tooltip: armour type, level, class) → nothing. Too high a level: looked
    at again after a level-up.
  Only this character's own bags and gear through WoW's normal API (EquipItemByName); never in combat (waits until
  it ends); Shift held skips once. Items you had before login, items you take off and items you said no to are
  never asked about again. Reads item data from the client only (data only, hard rule 2). ]]
local _, ns = ...
local E = {}
ns.Equip = E

local G = _G
local function Core() return ns.Core end
local function C() return ns.Compat end
local function AU() return ns.Auto end

-- ------------------------------------------------------------------ slots
--- equipLoc → inventory slots it can go to (first = the usual one). Shirts, tabards, bags and ammo are left out.
E.SLOTS = {
  INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 },
  INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 }, INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 },
  INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 }, INVTYPE_CLOAK = { 15 },
  INVTYPE_WEAPON = { 16 }, INVTYPE_2HWEAPON = { 16 }, INVTYPE_WEAPONMAINHAND = { 16 },
  INVTYPE_WEAPONOFFHAND = { 17 }, INVTYPE_SHIELD = { 17 }, INVTYPE_HOLDABLE = { 17 },
  INVTYPE_RANGED = { 18 }, INVTYPE_RANGEDRIGHT = { 18 }, INVTYPE_THROWN = { 18 }, INVTYPE_RELIC = { 18 },
}

-- ------------------------------------------------------------------ which stats count
local STR, AGI, STA, INT, SPI = "ITEM_MOD_STRENGTH_SHORT", "ITEM_MOD_AGILITY_SHORT", "ITEM_MOD_STAMINA_SHORT", "ITEM_MOD_INTELLECT_SHORT", "ITEM_MOD_SPIRIT_SHORT"
local ARMOR, DPS = "RESISTANCE0_NAME", "ITEM_MOD_DAMAGE_PER_SECOND_SHORT"
local PHYS = { STR, AGI, STA, ARMOR, DPS, "ITEM_MOD_ATTACK_POWER_SHORT", "ITEM_MOD_CRIT_RATING_SHORT", "ITEM_MOD_HIT_RATING_SHORT",
  "ITEM_MOD_CRIT_MELEE_RATING_SHORT", "ITEM_MOD_HIT_MELEE_RATING_SHORT", "ITEM_MOD_HASTE_RATING_SHORT", "ITEM_MOD_EXPERTISE_RATING_SHORT",
  "ITEM_MOD_ARMOR_PENETRATION_RATING_SHORT", "ITEM_MOD_MELEE_ATTACK_POWER_SHORT" }
local TANK = { "ITEM_MOD_DEFENSE_SKILL_RATING_SHORT", "ITEM_MOD_DODGE_RATING_SHORT", "ITEM_MOD_PARRY_RATING_SHORT",
  "ITEM_MOD_BLOCK_RATING_SHORT", "ITEM_MOD_BLOCK_VALUE_SHORT", "ITEM_MOD_EXTRA_ARMOR_SHORT" }
local CASTER = { INT, SPI, STA, ARMOR, "ITEM_MOD_SPELL_POWER_SHORT", "ITEM_MOD_SPELL_DAMAGE_DONE_SHORT", "ITEM_MOD_CRIT_SPELL_RATING_SHORT",
  "ITEM_MOD_HIT_SPELL_RATING_SHORT", "ITEM_MOD_HASTE_SPELL_RATING_SHORT", "ITEM_MOD_SPELL_PENETRATION_SHORT", "ITEM_MOD_MANA_REGENERATION_SHORT",
  "ITEM_MOD_POWER_REGEN0_SHORT", "ITEM_MOD_CRIT_RATING_SHORT", "ITEM_MOD_HIT_RATING_SHORT", "ITEM_MOD_HASTE_RATING_SHORT" }
local HEAL = { "ITEM_MOD_SPELL_HEALING_DONE_SHORT" }
local RANGED = { "ITEM_MOD_RANGED_ATTACK_POWER_SHORT", "ITEM_MOD_CRIT_RANGED_RATING_SHORT", "ITEM_MOD_HIT_RANGED_RATING_SHORT" }
--- Stats that never decide anything (shown nowhere): resistances, sockets, set bonuses.
local IGNORE = { RESISTANCE1_NAME = true, RESISTANCE2_NAME = true, RESISTANCE3_NAME = true, RESISTANCE4_NAME = true, RESISTANCE5_NAME = true,
  RESISTANCE6_NAME = true, EMPTY_SOCKET_RED = true, EMPTY_SOCKET_YELLOW = true, EMPTY_SOCKET_BLUE = true, EMPTY_SOCKET_META = true,
  EMPTY_SOCKET_PRISMATIC = true, EMPTY_SOCKET_NO_COLOR = true }
--- Every stat WoWBoxer knows (relevant to someone). A stat outside this list (and IGNORE) makes a comparison "in doubt".
E.KNOWN = {}
for _, l in ipairs({ PHYS, TANK, CASTER, HEAL, RANGED }) do for _, k in ipairs(l) do E.KNOWN[k] = true end end

local function addAll(t, list) for _, k in ipairs(list) do t[k] = true end end
--- The stats that count for a class and role: {[statKey] = true}.
function E.relevant(cls, role)
  local t = {}
  local caster = role == "healer" or (role == "ranged" and cls ~= "hunter") or cls == "mage" or cls == "priest" or cls == "warlock"
  if caster then
    addAll(t, CASTER)
    if role == "healer" or cls == "priest" then addAll(t, HEAL) end
  else
    addAll(t, PHYS)
    if role == "tank" then addAll(t, TANK) end
    if cls == "hunter" then addAll(t, RANGED); t[INT] = true end
    if cls == "paladin" or cls == "shaman" then t[INT] = true end
    if cls == "hunter" or cls == "rogue" then t[STR] = cls == "rogue" or nil end
  end
  return t
end

--- Compare two stat tables over the stats that count. Returns verdict, ups, downs: "better" (nothing down, something
--- up), "same", "worse" (nothing up), "mixed" (some up, some down) or "unknown" (a stat WoWBoxer does not know).
function E.compare(new, old, rel)
  new, old = new or {}, old or {}
  local ups, downs, keys = {}, {}, {}
  for k in pairs(new) do keys[k] = true end
  for k in pairs(old) do keys[k] = true end
  local unknown = false
  for k in pairs(keys) do
    if not IGNORE[k] then
      if not E.KNOWN[k] then
        if (tonumber(new[k]) or 0) ~= (tonumber(old[k]) or 0) then unknown = true end
      elseif rel[k] then
        local d = (tonumber(new[k]) or 0) - (tonumber(old[k]) or 0)
        if d > 0.05 then ups[#ups + 1] = { k, d } elseif d < -0.05 then downs[#downs + 1] = { k, d } end
      end
    end
  end
  local function byKey(a, b) return a[1] < b[1] end
  table.sort(ups, byKey); table.sort(downs, byKey)
  if unknown then return "unknown", ups, downs end
  if #ups > 0 and #downs == 0 then return "better", ups, downs end
  if #ups > 0 then return "mixed", ups, downs end
  if #downs > 0 then return "worse", ups, downs end
  return "same", ups, downs
end

--- One number for "how good is this for me" (owner, 5 Nov 2026: a white item next to a worn green must not ask).
--- Every stat that counts is worth 1 a point; Stamina and Spirit 0.6 (1 for a tank's Stamina); armour 0.02 a point
--- (50 armour ≈ one main stat); weapon DPS 3 a point; a stat WoWBoxer doesn't know 0.5; stats that don't count 0.
function E.weight(k, rel)
  if IGNORE[k] then return 0 end
  if not E.KNOWN[k] then return 0.5 end
  if not rel[k] then return 0 end
  if k == ARMOR then return 0.02 end
  if k == DPS then return 3 end
  if k == STA then return rel["ITEM_MOD_DODGE_RATING_SHORT"] and 1 or 0.6 end
  if k == SPI then return 0.6 end
  return 1
end
function E.score(stats, rel)
  local n = 0
  for k, v in pairs(stats or {}) do n = n + (tonumber(v) or 0) * E.weight(k, rel) end
  return n
end
--- New item is a lower tier than the old one: lower quality, or the same quality and a lower item level.
function E.lowerTier(new, old)
  local q, qo = new and new.info and new.info.quality, old and old.info and old.info.quality
  local l, lo = new and new.info and new.info.ilvl, old and old.info and old.info.ilvl
  if q and qo and q < qo then return true end
  if q and qo and q == qo and l and lo and l < lo then return true end
  return false
end

--- "+4 Strength, +2 Stamina" (the client's own stat names).
function E.statWords(list)
  local out = {}
  for _, x in ipairs(list) do
    local name = type(G[x[1]]) == "string" and G[x[1]] or x[1]:gsub("^ITEM_MOD_", ""):gsub("_SHORT$", ""):gsub("_", " "):lower()
    local v = math.abs(x[2])
    local n = (v == math.floor(v)) and tostring(v) or string.format("%.1f", v)
    out[#out + 1] = (x[2] > 0 and "+" or "-") .. n .. " " .. name
  end
  return table.concat(out, ", ")
end

-- ------------------------------------------------------------------ reading the client (pcall, data only)
local function itemInfo(link)
  local CI = G.C_Item
  local f = (CI and CI.GetItemInfo) or G.GetItemInfo
  if not (f and link) then return nil end
  local ok, name, _, quality, ilvl, minLevel, _, _, _, equipLoc = pcall(f, link)
  if not ok or not name then return nil end
  return { name = name, quality = quality, ilvl = ilvl, minLevel = minLevel, equipLoc = equipLoc }
end
local function itemStats(link)
  local CI = G.C_Item
  local f = (CI and CI.GetItemStats) or G.GetItemStats
  if not (f and link) then return nil end
  local ok, t = pcall(f, link)
  return ok and type(t) == "table" and t or nil
end
local function itemId(link) return link and tonumber(link:match("item:(%d+)")) end

local scanTip
--- The tooltip lines of a bag item or a worn item: {{text, r, g, b}, …}. C_TooltipInfo where it exists, else a
--- hidden GameTooltip (never shown).
function E.tipLines(bag, slot, inv)
  local out = {}
  local TI = G.C_TooltipInfo
  if TI and (TI.GetBagItem and TI.GetInventoryItem) then
    local ok, data = pcall(function() if inv then return TI.GetInventoryItem("player", inv) end return TI.GetBagItem(bag, slot) end)
    if ok and type(data) == "table" and type(data.lines) == "table" then
      for _, l in ipairs(data.lines) do
        for _, side in ipairs({ { l.leftText, l.leftColor }, { l.rightText, l.rightColor } }) do
          if type(side[1]) == "string" and side[1] ~= "" then
            local c = type(side[2]) == "table" and side[2] or {}
            out[#out + 1] = { side[1], c.r or 1, c.g or 1, c.b or 1 }
          end
        end
      end
      return out
    end
  end
  if not (G.CreateFrame and G.WorldFrame) then return out end
  if not scanTip then
    local ok, t = pcall(G.CreateFrame, "GameTooltip", "WoWBoxerScanTip", G.WorldFrame, "GameTooltipTemplate")
    if not ok or not t then return out end
    scanTip = t
  end
  pcall(scanTip.SetOwner, scanTip, G.WorldFrame, "ANCHOR_NONE")
  pcall(scanTip.ClearLines, scanTip)
  if inv then pcall(scanTip.SetInventoryItem, scanTip, "player", inv) else pcall(scanTip.SetBagItem, scanTip, bag, slot) end
  local n = scanTip.NumLines and scanTip:NumLines() or 0
  for i = 1, n do
    for _, side in ipairs({ "Left", "Right" }) do
      local fs = G["WoWBoxerScanTipText" .. side .. i]
      local t = fs and fs.GetText and fs:GetText()
      if type(t) == "string" and t ~= "" then
        local r, g, b = fs:GetTextColor()
        out[#out + 1] = { t, r or 1, g or 1, b or 1 }
      end
    end
  end
  pcall(scanTip.Hide, scanTip)
  return out
end
local function isRed(l) return l[2] > 0.95 and l[3] < 0.3 and l[4] < 0.3 end
local function startsWith(t, s) return type(s) == "string" and s ~= "" and t:sub(1, #s) == s end
--- What the tooltip says: {usable, bindOnEquip, effects = {text = true}} (effects = Equip: / Use: / Chance on hit: lines).
function E.readTip(lines)
  local r = { usable = true, boe = false, effects = {}, nEffects = 0 }
  local bound = false
  local boeText = type(G.ITEM_BIND_ON_EQUIP) == "string" and G.ITEM_BIND_ON_EQUIP or "Binds when equipped"
  local trig = { G.ITEM_SPELL_TRIGGER_ONEQUIP or "Equip:", G.ITEM_SPELL_TRIGGER_ONUSE or "Use:", G.ITEM_SPELL_TRIGGER_ONPROC or "Chance on hit:" }
  for i, l in ipairs(lines) do
    if i > 1 and isRed(l) then r.usable = false end
    if l[1] == boeText then r.boe = true end
    if l[1] == (G.ITEM_SOULBOUND or "Soulbound") or l[1] == (G.ITEM_BIND_ON_PICKUP or "Binds when picked up") then bound = true end
    for _, s in ipairs(trig) do if startsWith(l[1], s) and not r.effects[l[1]] then r.effects[l[1]] = true; r.nEffects = r.nEffects + 1 end end
  end
  if bound then r.boe = false end
  return r
end

-- ------------------------------------------------------------------ the decision (pure: tested without the game)
--- What to do with a new item. it = {link, info, stats, tip}; worn = {[invSlot] = {link, info, stats, tip}|nil};
--- rel = relevant stats. Returns {act = "equip"|"ask"|nil, slot, why, old}.
function E.decide(it, worn, rel)
  local loc = it.info and it.info.equipLoc
  local slots = loc and E.SLOTS[loc]
  if not slots then return { why = "not gear" } end
  if not it.tip.usable then return { why = "not usable", wait = true } end
  local id = itemId(it.link)
  for _, s in ipairs(slots) do local w = worn[s]; if w and itemId(w.link) == id then return { why = "already worn" } end end
  local function ask(slot, why, old) return { act = "ask", slot = slot, why = why, old = old } end
  local function result(slot, old, act, why) if it.tip.boe and act then return ask(slot, "boe", old) end return { act = act, slot = slot, why = why, old = old } end
  -- weapon layout changes are always a question
  if loc == "INVTYPE_2HWEAPON" and worn[17] then return result(16, worn[16], "ask", "layout") end
  if slots[1] == 17 and worn[16] and worn[16].info and worn[16].info.equipLoc == "INVTYPE_2HWEAPON" then return result(17, worn[17], "ask", "layout") end
  -- an empty slot: anything you can wear is better than nothing (trinkets too)
  for _, s in ipairs(slots) do if not worn[s] then return result(s, nil, "equip", "empty") end end
  if loc == "INVTYPE_TRINKET" then
    -- effects can't be compared: ask only when it could be an upgrade (quality / item level) over the weaker trinket
    local weak = slots[1]
    if E.lowerTier(worn[slots[1]], worn[slots[2]]) then weak = slots[1] elseif worn[slots[2]] then weak = slots[2] end
    if E.lowerTier(it, worn[weak]) then return { why = "trinket not better" } end
    return result(weak, worn[weak], "ask", "trinket")
  end
  if not it.stats then
    if E.lowerTier(it, worn[slots[1]]) then return { why = "no stats, not better" } end
    return result(slots[1], worn[slots[1]], "ask", "nostats")
  end
  -- compare with each slot it can go to; the best case wins (rings: the weaker ring is replaced)
  local best
  local RANK = { better = 4, mixed = 3, unknown = 2, same = 1, worse = 0 }
  for _, s in ipairs(slots) do
    local w = worn[s]
    local wrel = rel
    if s == 18 then wrel = setmetatable({ [DPS] = true }, { __index = rel }) end -- a wand or bow: its DPS always counts
    local v, ups, downs = E.compare(it.stats, w.stats or {}, wrel)
    if v == "better" and w.tip and w.tip.nEffects > 0 then
      for e in pairs(w.tip.effects) do if not it.tip.effects[e] then v = "effect" end end
    end
    local rank = v == "effect" and 3 or RANK[v]
    local delta = E.score(it.stats, wrel) - E.score(w.stats or {}, wrel)
    if not best or rank > best.rank or (rank == best.rank and delta > best.delta) then
      best = { rank = rank, v = v, ups = ups, downs = downs, slot = s, old = w, delta = delta, base = math.max(1, E.score(w.stats or {}, wrel)) }
    end
  end
  if best.v == "better" then return result(best.slot, best.old, "equip", "better") end
  if best.v == "mixed" or best.v == "unknown" or best.v == "effect" then
    -- a trade-off is only a question when the new item comes out ahead overall (weighted for your class and role);
    -- a lower-quality item (white next to green) must come out clearly ahead (25 %)
    if best.delta <= best.base * 0.02 then return { why = "worse overall" } end
    if E.lowerTier(it, best.old) and (it.info and best.old.info and (it.info.quality or 0) < (best.old.info.quality or 0)) and best.delta < best.base * 0.25 then
      return { why = "lower quality" }
    end
    local d = result(best.slot, best.old, "ask", best.v)
    d.ups, d.downs = best.ups, best.downs
    return d
  end
  return { why = best.v }
end

--- The question for an "ask": one or two plain sentences.
function E.question(d, it)
  local name = it.link or (it.info and it.info.name) or "this item"
  local old = d.old and (d.old.link or (d.old.info and d.old.info.name)) or nil
  local q = "Equip " .. name .. "?"
  local why
  if d.why == "boe" then why = "It binds to you when you equip it."
  elseif d.why == "layout" then why = "It changes your weapons (two-hand or one-hand and off-hand)."
  elseif d.why == "trinket" then why = "Trinkets have effects WoWBoxer can't compare."
  elseif d.why == "nostats" then why = "WoWBoxer can't read its stats on this client."
  elseif d.why == "effect" then why = "Your " .. (old or "item") .. " has an effect the new one doesn't."
  elseif d.why == "unknown" then why = "It has a stat WoWBoxer can't weigh."
  elseif d.why == "mixed" then why = "Better: " .. E.statWords(d.ups or {}) .. ". Worse: " .. E.statWords(d.downs or {}) .. "." end
  if old and d.why ~= "effect" then q = q .. " (replaces " .. old .. ")" end
  return q .. (why and ("\n" .. why) or "")
end

-- ------------------------------------------------------------------ bags and gear
E.seen = {}       -- item links already in your bags, worn or answered: never asked about again
E.waitLevel = {}  -- links too high (red) for now: looked at again after a level-up
E.worn = {}       -- [invSlot] = link (to notice what you take off)
E.asks = {}       -- queued questions
E.pending = false -- a scan waits for combat to end

local function bagSlots(b)
  local CC = G.C_Container
  local f = (CC and CC.GetContainerNumSlots) or G.GetContainerNumSlots
  if not f then return 0 end
  local ok, n = pcall(f, b)
  return ok and tonumber(n) or 0
end
local function bagLink(b, s)
  local CC = G.C_Container
  if CC and CC.GetContainerItemLink then local ok, l = pcall(CC.GetContainerItemLink, b, s); if ok then return l end end
  if G.GetContainerItemLink then local ok, l = pcall(G.GetContainerItemLink, b, s); if ok then return l end end
  if CC and CC.GetContainerItemInfo then
    local ok, t = pcall(CC.GetContainerItemInfo, b, s)
    return ok and t and t.hyperlink or nil
  end
  return nil
end
local function invLink(slot)
  if not G.GetInventoryItemLink then return nil end
  local ok, l = pcall(G.GetInventoryItemLink, "player", slot)
  return ok and l or nil
end
--- What you wear now, per slot: {link, info, stats, tip}.
function E.wornNow()
  local t = {}
  for s = 1, 19 do
    local l = invLink(s)
    if l then t[s] = { link = l, info = itemInfo(l), stats = itemStats(l), tip = E.readTip(E.tipLines(nil, nil, s)) } end
  end
  return t
end
--- Remember what is worn; whatever was worn before and is not now goes to `seen` (you took it off).
function E.noteWorn()
  for s = 1, 19 do
    local l = invLink(s)
    if E.worn[s] and E.worn[s] ~= l then E.seen[E.worn[s]] = true end
    E.worn[s] = l
    if l then E.seen[l] = true end
  end
end
--- The first scan after login: everything already in the bags counts as seen.
function E.snapshot()
  for b = 0, 4 do for s = 1, bagSlots(b) do local l = bagLink(b, s); if l then E.seen[l] = true end end end
  E.noteWorn()
  E.ready = true
end

local function myRel()
  local _, m = Core().me()
  local cls = m and m.cls
  if not cls and G.UnitClass then local _, f = G.UnitClass("player"); cls = type(f) == "string" and f:lower() or nil end
  return E.relevant(cls or "warrior", m and m.role or "melee")
end

--- Put on the item in bag/slot (only if it is still there). Returns true when the call went through.
function E.equip(bag, slot, link, inv)
  if bagLink(bag, slot) ~= link then
    -- moved: find it again
    local found
    for b = 0, 4 do for s = 1, bagSlots(b) do if not found and bagLink(b, s) == link then found = { b, s } end end end
    if not found then Core().log("info", "equip: " .. tostring(link) .. " is no longer in your bags"); return false end
  end
  if C().inCombat() then return false end
  local CI = G.C_Item
  local f = (CI and CI.EquipItemByName) or G.EquipItemByName
  if not f then Core().log("warn", "equip: no EquipItemByName on this client"); return false end
  if E.worn[inv] then E.seen[E.worn[inv]] = true end
  E.bindOk = (G.GetTime and G.GetTime() or 0) + 3 -- the player said yes: the game's "binds to you" question is answered
  local ok, err = pcall(f, link, inv)
  if not ok then Core().log("warn", "equip failed: " .. tostring(err)); return false end
  return true
end

--- Show the next queued question (one at a time; waits while another WoWBoxer question is open).
function E.nextAsk()
  local q = E.asks[1]
  if not q then return end
  local UI = ns.UI
  if not (UI and UI.Popup) then return end
  if UI.popup and UI.popup:IsShown() then
    if G.C_Timer and G.C_Timer.After then G.C_Timer.After(3, E.nextAsk) end
    return
  end
  table.remove(E.asks, 1)
  UI.Popup(q.text, {
    { "Equip", function()
      if C().inCombat() then
        Core().print("Auto-equip: in combat – equips " .. q.link .. " when the fight ends.")
        E.afterCombat = E.afterCombat or {}
        E.afterCombat[#E.afterCombat + 1] = q
      elseif E.equip(q.bag, q.slot, q.link, q.inv) then
        AU().did("equipped " .. q.link .. " (you said yes)")
      end
      E.nextAsk()
    end, "Puts it on now." },
    { "Keep in bag", function() Core().log("info", "equip: kept " .. q.link .. " in the bag"); E.nextAsk() end,
      "Leaves it in your bag. WoWBoxer won't ask about it again." } })
  Core().log("info", "equip: asked about " .. q.link .. " (" .. q.why .. ")")
end

--- Look at one new item and act: equip, queue a question, or nothing.
function E.consider(bag, slot, link)
  local info = itemInfo(link)
  if not info then return "later" end -- not cached yet: the next bag update tries again
  if not E.SLOTS[info.equipLoc or ""] then E.seen[link] = true; return "not gear" end
  E.seen[link] = true
  local it = { link = link, info = info, stats = itemStats(link), tip = E.readTip(E.tipLines(bag, slot)) }
  local d = E.decide(it, E.wornNow(), myRel())
  if d.wait then E.waitLevel[link] = true end
  if d.act == "equip" then
    if E.equip(bag, slot, link, d.slot) then AU().did("equipped " .. link .. (d.old and (" (better than " .. d.old.link .. ")") or "")) end
  elseif d.act == "ask" then
    E.asks[#E.asks + 1] = { bag = bag, slot = slot, link = link, inv = d.slot, why = d.why, text = E.question(d, it) }
    E.nextAsk()
  else
    Core().log("info", "equip: " .. link .. " – " .. tostring(d.why))
  end
  return d.act or d.why
end

--- Scan the bags for items not seen before.
function E.scan()
  if not E.ready then E.snapshot(); return end
  local on = AU() and AU().on("autoEquip")
  if not on then E.snapshot(); return end -- off: just remember what is there, so turning it on asks about nothing old
  if C().inCombat() then E.pending = true; return end
  if G.IsShiftKeyDown and G.IsShiftKeyDown() then
    Core().log("info", "auto: equip skipped (Shift held)")
    E.snapshot(); return
  end
  E.noteWorn()
  for b = 0, 4 do
    for s = 1, bagSlots(b) do
      local l = bagLink(b, s)
      if l and not E.seen[l] then E.consider(b, s, l) end
    end
  end
end

-- ------------------------------------------------------------------ events
local f = G.CreateFrame and G.CreateFrame("Frame") or nil
E.frame = f
local EVENTS = { "PLAYER_ENTERING_WORLD", "BAG_UPDATE_DELAYED", "PLAYER_EQUIPMENT_CHANGED", "PLAYER_REGEN_ENABLED", "PLAYER_LEVEL_UP",
  "EQUIP_BIND_CONFIRM", "GET_ITEM_INFO_RECEIVED" }
function E.Init()
  if not f then return end
  for _, ev in ipairs(EVENTS) do pcall(f.RegisterEvent, f, ev) end
end
function E.onEvent(event, a)
  if not Core().db then return end
  if event == "PLAYER_ENTERING_WORLD" then if not E.ready then E.snapshot() end
  elseif event == "BAG_UPDATE_DELAYED" or event == "GET_ITEM_INFO_RECEIVED" then E.scan()
  elseif event == "PLAYER_EQUIPMENT_CHANGED" then E.noteWorn()
  elseif event == "PLAYER_LEVEL_UP" then
    for l in pairs(E.waitLevel) do E.seen[l] = nil end
    E.waitLevel = {}
    if G.C_Timer and G.C_Timer.After then G.C_Timer.After(1, E.scan) else E.scan() end
  elseif event == "PLAYER_REGEN_ENABLED" then
    local list = E.afterCombat or {}
    E.afterCombat = nil
    for _, q in ipairs(list) do if E.equip(q.bag, q.slot, q.link, q.inv) then AU().did("equipped " .. q.link .. " (you said yes)") end end
    if E.pending then E.pending = false; E.scan() end
  elseif event == "EQUIP_BIND_CONFIRM" then
    -- the game asks "binds to you" after the player already said Equip in WoWBoxer's question: answer it once
    if E.bindOk and (G.GetTime and G.GetTime() or 0) <= E.bindOk then
      E.bindOk = nil
      local CI = G.C_Item
      local ep = G.EquipPendingItem or (CI and CI.EquipPendingItem)
      if ep then pcall(ep, a) end
      if G.StaticPopup_Hide then pcall(G.StaticPopup_Hide, "EQUIP_BIND") end
    end
  end
end
if f then
  f:SetScript("OnEvent", function(_, event, a)
    local ok, err = pcall(E.onEvent, event, a)
    if not ok then Core().log("error", "equip " .. event .. ": " .. tostring(err)) end
  end)
end

return E
