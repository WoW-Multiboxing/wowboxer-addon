--[[ WoWBoxer – Auto greed in dungeons (Altsy, #help; the owner approved it on 10 Nov 2026).
  An automation option (Setup → Automation "Auto greed"), OFF by default, through WoW's normal loot API (RollOnLoot,
  hard rule 1). Only inside a 5-player dungeon – never in the open world or a raid. On a loot roll:
  - Greed on grey and white items;
  - Greed on green or better only when this character can't use the item (armour or weapon type, class: the red
    lines of its tooltip) or Auto-equip's evaluation (Equip.decide) says it is not an upgrade for its class and role;
  - never Need;
  - bind on pickup, and anything WoWBoxer isn't sure about (no item data, not gear, could be an upgrade): the roll
    stays with the player, with one chat line that says why.
  One short chat line per roll ("Greed: [item] – can't use"). In combat it waits until the fight ends (the roll window
  is open for a while) and rolls then if the roll is still open. Shift held skips it once. Data only (rule 2). ]]
local _, ns = ...
local LG = {}
ns.Loot = LG

local G = _G
local function Core() return ns.Core end
local function C() return ns.Compat end
local function AU() return ns.Auto end
local function EQ() return ns.Equip end

LG.GREED = 2 -- RollOnLoot: 0 pass, 1 need, 2 greed (never 1)
LG.pending = {} -- roll ids waiting for combat to end

-- ------------------------------------------------------------------ where
--- In a 5-player dungeon (instance type "party") and not in a raid group.
function LG.inDungeon()
  if not G.IsInInstance then return false end
  local ok, inside, kind = pcall(G.IsInInstance)
  if not (ok and inside) or kind ~= "party" then return false end
  if G.IsInRaid and G.IsInRaid() then return false end
  return true
end

-- ------------------------------------------------------------------ the decision (pure: tested without the game)
--- Red tooltip lines that mean "you can't use this" – armour or weapon type, class – and not "Requires Level N"
--- (an item that is only too high for now can still be an upgrade later: not sure, so the player rolls).
function LG.cantUse(lines)
  local lvl = type(G.ITEM_MIN_LEVEL) == "string" and G.ITEM_MIN_LEVEL:gsub("%%d", "%%d+") or "Requires Level %d+"
  for i, l in ipairs(lines or {}) do
    if i > 1 and l[2] > 0.95 and l[3] < 0.3 and l[4] < 0.3 then
      if not tostring(l[1]):find("^" .. lvl) then return true end
    end
  end
  return false
end
--- What to do with one roll. r = {quality, bop, canGreed, link, info, stats, tip = Equip.readTip(...), lines,
--- verdict = Equip.decide(...) or nil}. Returns "greed", why | nil, why (nil = the player rolls).
LG.NOT_UPGRADE = { worse = true, same = true, ["worse overall"] = true, ["lower quality"] = true, ["trinket not better"] = true,
  ["no stats, not better"] = true, ["already worn"] = true }
function LG.decide(r)
  if not r or r.canGreed == false then return nil, "no greed on this roll" end
  if r.bop then return nil, "binds when picked up" end
  local q = tonumber(r.quality)
  if not q then return nil, "no item data" end
  if q <= 1 then return "greed", q == 0 and "grey" or "white" end
  local loc = r.info and r.info.equipLoc
  if not (loc and EQ() and EQ().SLOTS[loc]) then return nil, "not gear" end
  if LG.cantUse(r.lines) then return "greed", "can't use" end
  local v = r.verdict
  if not v then return nil, "not sure" end
  if v.act then return nil, "could be an upgrade" end
  if LG.NOT_UPGRADE[v.why] then return "greed", "not an upgrade" end
  return nil, "not sure"
end

-- ------------------------------------------------------------------ reading the client (pcall, data only)
local scanTip
--- The tooltip lines of a loot roll item: {{text, r, g, b}, …} (C_TooltipInfo where it exists, else a hidden tooltip).
--- [AFKLAR: C_TooltipInfo.GetLootRollItem on Forever]
function LG.tipLines(rollID)
  local out = {}
  local TI = G.C_TooltipInfo
  if TI and TI.GetLootRollItem then
    local ok, data = pcall(TI.GetLootRollItem, rollID)
    if ok and type(data) == "table" and type(data.lines) == "table" then
      for _, l in ipairs(data.lines) do
        local c = type(l.leftColor) == "table" and l.leftColor or {}
        if type(l.leftText) == "string" and l.leftText ~= "" then out[#out + 1] = { l.leftText, c.r or 1, c.g or 1, c.b or 1 } end
      end
      return out
    end
  end
  if not (G.CreateFrame and G.WorldFrame) then return out end
  if not scanTip then
    local ok, t = pcall(G.CreateFrame, "GameTooltip", "WoWBoxerLootTip", G.WorldFrame, "GameTooltipTemplate")
    if not ok or not t then return out end
    scanTip = t
  end
  if not scanTip.SetLootRollItem then return out end
  pcall(scanTip.SetOwner, scanTip, G.WorldFrame, "ANCHOR_NONE")
  pcall(scanTip.ClearLines, scanTip)
  pcall(scanTip.SetLootRollItem, scanTip, rollID)
  local n = scanTip.NumLines and scanTip:NumLines() or 0
  for i = 1, n do
    local fs = G["WoWBoxerLootTipTextLeft" .. i]
    local t = fs and fs.GetText and fs:GetText()
    if type(t) == "string" and t ~= "" then local r, g, b = fs:GetTextColor(); out[#out + 1] = { t, r or 1, g or 1, b or 1 } end
  end
  pcall(scanTip.Hide, scanTip)
  return out
end
--- Everything decide() needs about roll `rollID`, read from the client.
function LG.read(rollID)
  if not G.GetLootRollItemInfo then return nil end
  local ok, _, name, _, quality, bop, _, canGreed = pcall(G.GetLootRollItemInfo, rollID)
  if not ok or not name then return nil end
  local link = G.GetLootRollItemLink and select(2, pcall(G.GetLootRollItemLink, rollID)) or nil
  if type(link) ~= "string" then link = nil end
  local r = { quality = quality, bop = bop and true or false, canGreed = canGreed ~= false, link = link, name = name }
  if link and EQ() then
    r.info = EQ().itemInfo(link)
    r.stats = EQ().itemStats(link)
    r.lines = LG.tipLines(rollID)
    r.tip = EQ().readTip(r.lines)
    if r.info and EQ().SLOTS[r.info.equipLoc or ""] then
      local ok2, v = pcall(EQ().decide, { link = link, info = r.info, stats = r.stats, tip = r.tip }, EQ().wornNow(), EQ().myRel())
      if ok2 then r.verdict = v end
    end
  end
  return r
end

-- ------------------------------------------------------------------ acting
--- A loot roll started (START_LOOT_ROLL). Only with the option on, only in a 5-player dungeon.
function LG.onRoll(rollID)
  if not (AU() and AU().on("greed")) or not LG.inDungeon() then return end
  if G.IsShiftKeyDown and G.IsShiftKeyDown() then Core().log("info", "greed: skipped (Shift held)"); return end
  if C().inCombat() then
    LG.pending[#LG.pending + 1] = rollID
    Core().log("info", "greed: roll " .. tostring(rollID) .. " waits until combat ends")
    return
  end
  LG.handle(rollID)
end
function LG.handle(rollID)
  local r = LG.read(rollID)
  local item = (r and (r.link or r.name)) or "this item"
  local act, why = LG.decide(r)
  if act == "greed" then
    local ok = G.RollOnLoot and pcall(G.RollOnLoot, rollID, LG.GREED)
    if ok then
      Core().print("Greed: " .. item .. " – " .. why)
      Core().log("info", "greed: " .. item .. " (" .. why .. ")")
    else
      Core().log("warn", "greed: could not roll on " .. item)
    end
    return "greed", why
  end
  Core().print("Roll yourself: " .. item .. " – " .. why)
  Core().log("info", "greed: left to the player: " .. item .. " (" .. why .. ")")
  return nil, why
end
--- Combat ended: the rolls that waited, if they are still open.
function LG.afterCombat()
  local q = LG.pending
  LG.pending = {}
  for _, id in ipairs(q) do
    local open = true
    if G.GetLootRollTimeLeft then local ok, t = pcall(G.GetLootRollTimeLeft, id); open = ok and (tonumber(t) or 0) > 0 end
    if open and AU().on("greed") and LG.inDungeon() then LG.handle(id) end
  end
end

local f = G.CreateFrame and G.CreateFrame("Frame") or nil
LG.frame = f
function LG.Init()
  if not f then return end
  for _, ev in ipairs({ "START_LOOT_ROLL", "PLAYER_REGEN_ENABLED" }) do pcall(f.RegisterEvent, f, ev) end
  f:SetScript("OnEvent", function(_, event, a)
    if not Core().db then return end
    local ok, err = pcall(function()
      if event == "START_LOOT_ROLL" then LG.onRoll(a)
      elseif event == "PLAYER_REGEN_ENABLED" then if #LG.pending > 0 then LG.afterCombat() end end
    end)
    if not ok then Core().log("error", "greed " .. event .. ": " .. tostring(err)) end
  end)
end

return LG
