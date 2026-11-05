-- Auto-equip (owner, 5 Nov 2026): an automation option, OFF by default. A new item in the bags: strictly better →
-- equipped; bind on equip → asked; in doubt → asked; worse or not for you → nothing. Old items, items you take off
-- and items you said no to are never asked about again. Never in combat; Shift skips.
local dir = (arg[0]:match("^(.*)/[^/]+$") or ".")
local H = dofile(dir .. "/harness.lua")
local Mock = dofile(dir .. "/wowmock.lua")

local RED = { r = 1, g = 0.13, b = 0.13 }
local function link(id, name) return "|cff1eff00|Hitem:" .. id .. "::::::::20:::::|h[" .. name .. "]|h|r" end

local function boot(cls)
  local W = Mock.new(H, { name = "Dorin", class = cls or "PALADIN", race = "Human", level = 20 })
  local ns = H.loadAddon({ env = W.env })
  W.fire("ADDON_LOADED", "WoWBoxer"); W.fire("PLAYER_LOGIN")
  W.bags, W.inv, W.items, W.equipped, W.pendingEquip = { [0] = {} }, {}, {}, {}, {}
  local env = W.env
  env.C_Container = {
    GetContainerNumSlots = function(b) return b == 0 and 16 or 0 end,
    GetContainerItemLink = function(b, s) return W.bags[b] and W.bags[b][s] end,
  }
  env.GetItemInfo = function(l)
    local it = W.items[l]
    if not it or it.uncached then return nil end
    return it.name, l, it.quality or 2, it.ilvl or 20, 15, "Armor", "Mail", 1, it.loc
  end
  env.GetItemStats = function(l) local it = W.items[l]; return it and it.stats end
  local function lines(l)
    local it = W.items[l]
    if not it then return nil end
    local out = { { leftText = it.name } }
    if it.boe then out[#out + 1] = { leftText = "Binds when equipped" } end
    if it.red then out[#out + 1] = { leftText = "Requires Level 25", leftColor = RED } end
    for _, e in ipairs(it.effects or {}) do out[#out + 1] = { leftText = e } end
    return { lines = out }
  end
  env.C_TooltipInfo = {
    GetBagItem = function(b, s) return lines(W.bags[b] and W.bags[b][s]) end,
    GetInventoryItem = function(_, slot) return lines(W.inv[slot]) end,
  }
  env.GetInventoryItemLink = function(_, slot) return W.inv[slot] end
  env.EquipItemByName = function(l, slot)
    if W.combat then error("in combat") end
    W.equipped[#W.equipped + 1] = { l, slot }
    for b, bag in pairs(W.bags) do for s, x in pairs(bag) do if x == l then bag[s] = W.inv[slot] end end end
    W.inv[slot] = l
  end
  env.EquipPendingItem = function(slot) W.pendingEquip[#W.pendingEquip + 1] = slot end
  return W, ns
end
local function item(W, id, name, loc, stats, extra)
  local l = link(id, name)
  W.items[l] = { name = name, loc = loc, stats = stats }
  for k, v in pairs(extra or {}) do W.items[l][k] = v end
  return l
end
local function arrive(W, slot, l) W.bags[0][slot] = l; W.fire("BAG_UPDATE_DELAYED") end
local function popupShown(ns) return ns.UI.popup and ns.UI.popup:IsShown() end
local function popupText(ns) return ns.UI.popup and ns.UI.popup.text:GetText() or "" end
local function click(ns, label)
  for _, b in ipairs(ns.UI.popup.btns) do if b:IsShown() and b:GetText() == label then b:Click(); return true end end
  return false
end

-- ------------------------------------------------------------------ 1. the comparison itself (pure)
do
  local _, ns = boot()
  local E = ns.Equip
  local war = E.relevant("warrior", "melee")
  H.ok(war.ITEM_MOD_STRENGTH_SHORT and not war.ITEM_MOD_INTELLECT_SHORT, "warrior: Strength counts, Intellect not")
  local mage = E.relevant("mage", "ranged")
  H.ok(mage.ITEM_MOD_INTELLECT_SHORT and not mage.ITEM_MOD_STRENGTH_SHORT, "mage: Intellect counts, Strength not")
  local heal = E.relevant("paladin", "healer")
  H.ok(heal.ITEM_MOD_SPELL_HEALING_DONE_SHORT and heal.ITEM_MOD_INTELLECT_SHORT, "holy paladin: healing and Intellect")
  H.eq((E.compare({ ITEM_MOD_STRENGTH_SHORT = 5, ITEM_MOD_STAMINA_SHORT = 3 }, { ITEM_MOD_STRENGTH_SHORT = 3, ITEM_MOD_STAMINA_SHORT = 3 }, war)), "better", "more Strength, same Stamina: better")
  H.eq((E.compare({ ITEM_MOD_STRENGTH_SHORT = 6, ITEM_MOD_STAMINA_SHORT = 1 }, { ITEM_MOD_STRENGTH_SHORT = 3, ITEM_MOD_STAMINA_SHORT = 3 }, war)), "mixed", "up and down: mixed")
  H.eq((E.compare({ ITEM_MOD_STRENGTH_SHORT = 4, ITEM_MOD_INTELLECT_SHORT = 9 }, { ITEM_MOD_STRENGTH_SHORT = 3 }, war)), "better", "warrior: extra Intellect does not matter")
  H.eq((E.compare({ ITEM_MOD_INTELLECT_SHORT = 9 }, { ITEM_MOD_STRENGTH_SHORT = 3 }, war)), "worse", "warrior: an Intellect item instead of Strength is worse")
  H.eq((E.compare({ ITEM_MOD_STRENGTH_SHORT = 3, RESISTANCE2_NAME = 5 }, { ITEM_MOD_STRENGTH_SHORT = 3 }, war)), "same", "resistances never decide")
  H.eq((E.compare({ ITEM_MOD_STRENGTH_SHORT = 4, ITEM_MOD_WEIRD_NEW_SHORT = 2 }, { ITEM_MOD_STRENGTH_SHORT = 3 }, war)), "unknown", "a stat WoWBoxer does not know: in doubt")
  local _, ups, downs = E.compare({ ITEM_MOD_STRENGTH_SHORT = 6, ITEM_MOD_STAMINA_SHORT = 1 }, { ITEM_MOD_STRENGTH_SHORT = 3, ITEM_MOD_STAMINA_SHORT = 3 }, war)
  H.ok(E.statWords(ups):find("+3", 1, true) and E.statWords(downs):find("-2", 1, true), "stat words: " .. E.statWords(ups) .. " / " .. E.statWords(downs))
  local boe = E.readTip({ { "Belt", 1, 1, 1 }, { "Binds when equipped", 1, 1, 1 } })
  H.ok(boe.boe and boe.usable, "tooltip: bind on equip")
  local red = E.readTip({ { "Belt", 1, 1, 1 }, { "Plate", 1, 0.13, 0.13 } })
  H.ok(not red.usable, "tooltip: red text = not usable")
  local sb = E.readTip({ { "Belt", 1, 1, 1 }, { "Binds when equipped", 1, 1, 1 }, { "Soulbound", 1, 1, 1 } })
  H.ok(not sb.boe, "tooltip: soulbound is not a new bind")
end

-- ------------------------------------------------------------------ 2. off by default; old items never asked about
do
  local W, ns = boot()
  H.ok(not ns.Auto.on("autoEquip"), "Auto-equip is off by default")
  ns.Auto.preset()
  H.ok(not ns.Auto.on("autoEquip"), "Default squad values leave Auto-equip off")
  ns.Auto.defaults()
  H.ok(not ns.Auto.on("autoEquip"), "Default leaves Auto-equip off")
  W.inv[6] = item(W, 100, "Old Belt", "INVTYPE_WAIST", { ITEM_MOD_STRENGTH_SHORT = 3 })
  local had = item(W, 101, "Bag Belt", "INVTYPE_WAIST", { ITEM_MOD_STRENGTH_SHORT = 9 })
  W.bags[0][1] = had
  W.fire("PLAYER_ENTERING_WORLD")
  -- off: a better item arrives, nothing happens
  arrive(W, 2, item(W, 102, "Off Belt", "INVTYPE_WAIST", { ITEM_MOD_STRENGTH_SHORT = 8 }))
  H.eq(#W.equipped, 0, "off: nothing equipped")
  -- on: what was there before is never touched
  ns.Auto.set("autoEquip", true)
  W.fire("BAG_UPDATE_DELAYED")
  H.eq(#W.equipped, 0, "turning it on does not act on items you already had")
  H.ok(not popupShown(ns), "and asks nothing")
end

-- ------------------------------------------------------------------ 3. strictly better → equipped; worse → nothing
local function onBoot(cls)
  local W, ns = boot(cls)
  ns.Auto.set("autoEquip", true); ns.Auto.set("chat", true)
  W.fire("PLAYER_ENTERING_WORLD")
  return W, ns
end
do
  local W, ns = onBoot()
  local old = item(W, 200, "Old Belt", "INVTYPE_WAIST", { ITEM_MOD_STRENGTH_SHORT = 3, ITEM_MOD_STAMINA_SHORT = 3, RESISTANCE0_NAME = 40 })
  W.inv[6] = old; ns.Equip.noteWorn()
  local new = item(W, 201, "Better Belt", "INVTYPE_WAIST", { ITEM_MOD_STRENGTH_SHORT = 5, ITEM_MOD_STAMINA_SHORT = 3, RESISTANCE0_NAME = 45 })
  arrive(W, 1, new)
  H.eq(W.equipped[1] and W.equipped[1][1], new, "strictly better: equipped")
  H.eq(W.equipped[1] and W.equipped[1][2], 6, "into the waist slot")
  H.ok(W.chatHas("equipped"), "one chat line")
  H.ok(not popupShown(ns), "no question")
  -- the old belt is now in the bag: never asked about or equipped back
  W.fire("PLAYER_EQUIPMENT_CHANGED"); W.fire("BAG_UPDATE_DELAYED")
  H.eq(#W.equipped, 1, "the belt you took off is left alone")
  -- worse: nothing
  arrive(W, 3, item(W, 202, "Worse Belt", "INVTYPE_WAIST", { ITEM_MOD_STRENGTH_SHORT = 2, ITEM_MOD_STAMINA_SHORT = 2, RESISTANCE0_NAME = 30 }))
  H.eq(#W.equipped, 1, "worse: not equipped")
  H.ok(not popupShown(ns), "worse: not asked")
  -- an empty slot: anything you can wear
  local cloak = item(W, 203, "Cloak", "INVTYPE_CLOAK", { RESISTANCE0_NAME = 10 })
  arrive(W, 4, cloak)
  H.eq(W.inv[15], cloak, "empty slot: equipped")
  -- a shirt or a bag is not gear here
  arrive(W, 5, item(W, 204, "Shirt", "INVTYPE_BODY", {}))
  H.eq(W.inv[4], nil, "shirts are left alone")
end

-- ------------------------------------------------------------------ 4. in doubt → asked (Keep in bag never asks again)
do
  local W, ns = onBoot()
  W.inv[6] = item(W, 300, "Old Belt", "INVTYPE_WAIST", { ITEM_MOD_STRENGTH_SHORT = 3, ITEM_MOD_STAMINA_SHORT = 3 }); ns.Equip.noteWorn()
  local mixed = item(W, 301, "Odd Belt", "INVTYPE_WAIST", { ITEM_MOD_STRENGTH_SHORT = 6, ITEM_MOD_STAMINA_SHORT = 1 })
  arrive(W, 1, mixed)
  H.eq(#W.equipped, 0, "mixed: not equipped by itself")
  H.ok(popupShown(ns), "mixed: asked")
  H.ok(popupText(ns):find("Better:", 1, true) and popupText(ns):find("Worse:", 1, true), "the question says what is better and worse: " .. popupText(ns))
  H.ok(popupText(ns):find("Odd Belt", 1, true) and popupText(ns):find("Old Belt", 1, true), "and names both items")
  H.ok(click(ns, "Keep in bag"), "Keep in bag button")
  H.eq(#W.equipped, 0, "kept: not equipped")
  W.fire("BAG_UPDATE_DELAYED")
  H.ok(not popupShown(ns), "kept: never asked again")
  -- yes: equips
  local mixed2 = item(W, 302, "Odd Belt II", "INVTYPE_WAIST", { ITEM_MOD_STRENGTH_SHORT = 7, ITEM_MOD_STAMINA_SHORT = 1 })
  arrive(W, 2, mixed2)
  H.ok(click(ns, "Equip"), "Equip button")
  H.eq(W.inv[6], mixed2, "Equip: equipped")
  -- an effect the old one has and the new one lacks
  local fx = item(W, 303, "Proc Ring", "INVTYPE_FINGER", { ITEM_MOD_STRENGTH_SHORT = 2 }, { effects = { "Equip: Improves your chance to hit by 1%." } })
  W.inv[11] = fx; W.inv[12] = item(W, 304, "Ring Two", "INVTYPE_FINGER", { ITEM_MOD_STRENGTH_SHORT = 5 }); ns.Equip.noteWorn()
  arrive(W, 3, item(W, 305, "Plain Ring", "INVTYPE_FINGER", { ITEM_MOD_STRENGTH_SHORT = 3 }))
  H.ok(popupShown(ns) and popupText(ns):find("effect", 1, true) ~= nil, "lost effect: asked: " .. popupText(ns))
  click(ns, "Keep in bag")
end

-- ------------------------------------------------------------------ 5. bind on equip → always asked; the game's bind question answered after yes
do
  local W, ns = onBoot()
  W.inv[6] = item(W, 400, "Old Belt", "INVTYPE_WAIST", { ITEM_MOD_STRENGTH_SHORT = 3 }); ns.Equip.noteWorn()
  local boe = item(W, 401, "Fine Belt", "INVTYPE_WAIST", { ITEM_MOD_STRENGTH_SHORT = 9 }, { boe = true })
  arrive(W, 1, boe)
  H.eq(#W.equipped, 0, "bind on equip: not equipped by itself, even when better")
  H.ok(popupShown(ns) and popupText(ns):find("binds to you", 1, true) ~= nil, "bind on equip: asked, says it binds: " .. popupText(ns))
  click(ns, "Equip")
  H.eq(W.inv[6], boe, "yes: equipped")
  W.fire("EQUIP_BIND_CONFIRM", 6)
  H.eq(W.pendingEquip[1], 6, "the game's 'binds to you' question is answered once")
  W.fire("EQUIP_BIND_CONFIRM", 6)
  H.eq(#W.pendingEquip, 1, "and only right after your yes")
  -- a bind-on-equip item that is worse: nothing
  arrive(W, 2, item(W, 402, "Poor BoE", "INVTYPE_WAIST", { ITEM_MOD_STRENGTH_SHORT = 1 }, { boe = true }))
  H.ok(not popupShown(ns), "worse bind on equip: not asked")
end

-- ------------------------------------------------------------------ 6. not usable yet → after a level-up; combat waits; Shift skips; not cached waits
do
  local W, ns = onBoot()
  W.inv[6] = item(W, 500, "Old Belt", "INVTYPE_WAIST", { ITEM_MOD_STRENGTH_SHORT = 3 }); ns.Equip.noteWorn()
  local high = item(W, 501, "High Belt", "INVTYPE_WAIST", { ITEM_MOD_STRENGTH_SHORT = 9 }, { red = true })
  arrive(W, 1, high)
  H.eq(#W.equipped, 0, "red in the tooltip (level too high): not equipped")
  W.items[high].red = nil
  W.fire("PLAYER_LEVEL_UP", 25); W.flush()
  H.eq(W.inv[6], high, "after the level-up: equipped")
  -- combat
  W.combat = true
  local c = item(W, 502, "Fight Belt", "INVTYPE_WAIST", { ITEM_MOD_STRENGTH_SHORT = 12 })
  arrive(W, 2, c)
  H.eq(W.inv[6], high, "in combat: waits")
  W.combat = false
  W.fire("PLAYER_REGEN_ENABLED")
  H.eq(W.inv[6], c, "after combat: equipped")
  -- Shift
  W.mods.shift = true
  local s = item(W, 503, "Shift Belt", "INVTYPE_WAIST", { ITEM_MOD_STRENGTH_SHORT = 20 })
  arrive(W, 3, s)
  W.mods.shift = false
  W.fire("BAG_UPDATE_DELAYED")
  H.eq(W.inv[6], c, "Shift held: skipped")
  -- not cached yet: tried again when the item data arrives
  local u = item(W, 504, "Slow Belt", "INVTYPE_WAIST", { ITEM_MOD_STRENGTH_SHORT = 30 }, { uncached = true })
  arrive(W, 4, u)
  H.eq(W.inv[6], c, "not cached: waits")
  W.items[u].uncached = nil
  W.fire("GET_ITEM_INFO_RECEIVED")
  H.eq(W.inv[6], u, "item data arrived: equipped")
end

-- ------------------------------------------------------------------ 7. rings, trinkets and weapons
do
  local W, ns = onBoot()
  W.inv[11] = item(W, 600, "Weak Ring", "INVTYPE_FINGER", { ITEM_MOD_STRENGTH_SHORT = 1 })
  W.inv[12] = item(W, 601, "Strong Ring", "INVTYPE_FINGER", { ITEM_MOD_STRENGTH_SHORT = 8 })
  ns.Equip.noteWorn()
  local r = item(W, 602, "New Ring", "INVTYPE_FINGER", { ITEM_MOD_STRENGTH_SHORT = 4 })
  arrive(W, 1, r)
  H.eq(W.inv[11], r, "a ring replaces the weaker ring")
  H.eq(W.inv[12] and W.items[W.inv[12]].name, "Strong Ring", "the stronger ring stays")
  W.inv[13] = item(W, 603, "Trinket", "INVTYPE_TRINKET", {}); W.inv[14] = item(W, 604, "Trinket 2", "INVTYPE_TRINKET", {}); ns.Equip.noteWorn()
  arrive(W, 2, item(W, 605, "New Trinket", "INVTYPE_TRINKET", { ITEM_MOD_STAMINA_SHORT = 5 }))
  H.ok(popupShown(ns) and popupText(ns):find("Trinkets", 1, true) ~= nil, "trinkets: asked")
  click(ns, "Keep in bag")
  W.inv[16] = item(W, 606, "Sword", "INVTYPE_WEAPON", { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 8 })
  W.inv[17] = item(W, 607, "Shield", "INVTYPE_SHIELD", { RESISTANCE0_NAME = 200 }); ns.Equip.noteWorn()
  arrive(W, 3, item(W, 608, "Big Axe", "INVTYPE_2HWEAPON", { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 20 }))
  H.ok(popupShown(ns) and popupText(ns):find("weapons", 1, true) ~= nil, "two-hand over sword and shield: asked")
  click(ns, "Keep in bag")
  local wpn = item(W, 609, "Better Sword", "INVTYPE_WEAPON", { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 10 })
  arrive(W, 4, wpn)
  H.eq(W.inv[16], wpn, "a better one-hand: equipped")
  local errs = {}
  for _, e in ipairs(ns.Core.db.log) do if e.l == "error" then errs[#errs + 1] = e.m end end
  H.eq(#errs, 0, "no errors: " .. table.concat(errs, " / "))
end

-- ------------------------------------------------------------------ 8. a caster ignores Strength; Classic tooltip path without C_TooltipInfo
do
  local W, ns = onBoot("MAGE")
  W.inv[1] = item(W, 700, "Cap", "INVTYPE_HEAD", { ITEM_MOD_INTELLECT_SHORT = 5 }); ns.Equip.noteWorn()
  arrive(W, 1, item(W, 701, "Helm of Strength", "INVTYPE_HEAD", { ITEM_MOD_STRENGTH_SHORT = 10 }))
  H.eq(#W.equipped, 0, "mage: a Strength helm is not better")
  H.ok(not popupShown(ns), "and not asked")
  W.env.C_TooltipInfo = nil
  local hood = item(W, 702, "Hood", "INVTYPE_HEAD", { ITEM_MOD_INTELLECT_SHORT = 8 })
  arrive(W, 2, hood)
  H.eq(W.inv[1], hood, "no C_TooltipInfo (scan tooltip): still works")
end

-- ------------------------------------------------------------------ 8. smart questions (owner, 5 Nov 2026: a white item
-- next to a worn green must not ask)
do
  local W, ns = onBoot("PRIEST")
  local E = ns.Equip
  -- a priest wears a green robe with Intellect and Spirit
  W.inv[5] = item(W, 800, "Green Robe", "INVTYPE_CHEST", { ITEM_MOD_INTELLECT_SHORT = 4, ITEM_MOD_SPIRIT_SHORT = 3, RESISTANCE0_NAME = 30 }, { quality = 2, ilvl = 15 })
  ns.Equip.noteWorn()
  -- a white robe: more armour, no stats -> not asked, not equipped
  arrive(W, 1, item(W, 801, "White Robe", "INVTYPE_CHEST", { RESISTANCE0_NAME = 60 }, { quality = 1, ilvl = 18 }))
  H.ok(not popupShown(ns), "white robe next to a green one: not asked")
  H.eq(#W.equipped, 0, "and not equipped")
  -- a green with a little more Stamina but less Intellect and Spirit: worse overall -> not asked
  arrive(W, 2, item(W, 802, "Other Green Robe", "INVTYPE_CHEST", { ITEM_MOD_INTELLECT_SHORT = 2, ITEM_MOD_STAMINA_SHORT = 3, RESISTANCE0_NAME = 30 }, { quality = 2, ilvl = 16 }))
  H.ok(not popupShown(ns), "worse overall for a priest: not asked")
  -- a real trade-off that comes out ahead: asked
  arrive(W, 3, item(W, 803, "Better Robe", "INVTYPE_CHEST", { ITEM_MOD_INTELLECT_SHORT = 8, ITEM_MOD_SPIRIT_SHORT = 1, RESISTANCE0_NAME = 30 }, { quality = 2, ilvl = 18 }))
  H.ok(popupShown(ns) and popupText(ns):find("Better Robe", 1, true) ~= nil, "a trade-off that comes out ahead: asked")
  click(ns, "Keep in bag")
  -- a white that is far better than the green (25 % or more): asked
  arrive(W, 4, item(W, 804, "Big White Robe", "INVTYPE_CHEST", { ITEM_MOD_INTELLECT_SHORT = 12, RESISTANCE0_NAME = 30 }, { quality = 1, ilvl = 25 }))
  H.ok(popupShown(ns), "a white that is far better: asked")
  click(ns, "Keep in bag")
  -- a weaker trinket (lower quality) is not asked about
  W.inv[13] = item(W, 810, "Blue Trinket", "INVTYPE_TRINKET", {}, { quality = 3, ilvl = 20 })
  W.inv[14] = item(W, 811, "Green Trinket", "INVTYPE_TRINKET", {}, { quality = 2, ilvl = 20 }); ns.Equip.noteWorn()
  arrive(W, 5, item(W, 812, "White Trinket", "INVTYPE_TRINKET", {}, { quality = 1, ilvl = 20 }))
  H.ok(not popupShown(ns), "a white trinket next to green and blue ones: not asked")
  arrive(W, 6, item(W, 813, "Epic Trinket", "INVTYPE_TRINKET", {}, { quality = 4, ilvl = 20 }))
  H.ok(popupShown(ns) and popupText(ns):find("Green Trinket", 1, true) ~= nil, "a better-quality trinket: asked, replacing the weaker one: " .. popupText(ns))
  click(ns, "Keep in bag")
  -- the weights
  local rel = E.relevant("priest", "healer")
  H.ok(E.score({ ITEM_MOD_INTELLECT_SHORT = 1 }, rel) > E.score({ RESISTANCE0_NAME = 40 }, rel), "1 Intellect is worth more than 40 armour to a priest")
end

H.report("equip")
