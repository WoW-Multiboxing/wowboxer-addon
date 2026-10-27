--[[ WoWBoxer – compatibility layer.
  Capability probes instead of project IDs (Forever reported WOW_PROJECT_ID 1 on some beta builds and 18 on others).
  Every WoW API the addon uses goes through here, so missing or changed functions degrade gracefully and show up in
  /wbx selftest. ]]
local _, ns = ...
local C = {}
ns.Compat = C

local G = _G

function C.interface() local _, _, _, toc = GetBuildInfo(); return tonumber(toc) or 0 end
function C.buildString() local v, b = GetBuildInfo(); return tostring(v) .. "." .. tostring(b) end
--- "forever" | "era" | "tbc" | "other"
function C.game()
  local toc = C.interface()
  if toc >= 16000 and toc < 20000 then return "forever" end
  if toc >= 11000 and toc < 12000 then return "era" end
  if toc >= 20000 and toc < 30000 then return "tbc" end
  return "other"
end
function C.isForever() return C.game() == "forever" end

-- ------------------------------------------------------------------ secret values (Forever / Midnight API)
function C.isSecret(v)
  local f = G.issecretvalue
  if not f then return false end
  local ok, r = pcall(f, v)
  return ok and r or false
end
--- Unit name or nil (never a secret value).
function C.unitName(unit)
  local ok, name = pcall(UnitName, unit)
  if not ok or name == nil or C.isSecret(name) then return nil end
  return name
end
function C.unitExists(unit)
  local ok, r = pcall(UnitExists, unit)
  if not ok or C.isSecret(r) then return nil end
  return r and true or false
end

-- ------------------------------------------------------------------ player
local RACE_FILE = { Human = "human", Dwarf = "dwarf", NightElf = "nightelf", Gnome = "gnome", Orc = "orc", Scourge = "undead",
  Undead = "undead", Tauren = "tauren", Troll = "troll" }
--- Companion race key for the player. Skyborne race files are not known before launch [AFKLAR]: guessed by faction.
function C.playerRace()
  local _, file = UnitRace("player")
  if file and RACE_FILE[file] then return RACE_FILE[file] end
  if file and tostring(file):lower():find("sky") then
    return UnitFactionGroup("player") == "Alliance" and "high-order-skyborne" or "windshaper-skyborne"
  end
  return nil
end
function C.playerClass() local _, file = UnitClass("player"); return file and file:lower() or nil end
function C.playerLevel() return UnitLevel("player") or 1 end
function C.playerName() return C.unitName("player") end
function C.playerFaction() local f = UnitFactionGroup("player"); return f == "Alliance" and "alliance" or "horde" end
function C.inCombat() return InCombatLockdown() and true or false end

-- ------------------------------------------------------------------ spellbook
--- Set of spell names the player knows (from the spellbook). nil if no spellbook API was found.
function C.knownSpellNames()
  local names = {}
  local SB = G.C_SpellBook
  if SB and SB.GetNumSpellBookSkillLines and SB.GetSpellBookSkillLineInfo and SB.GetSpellBookItemName then
    local bank = (G.Enum and G.Enum.SpellBookSpellBank and G.Enum.SpellBookSpellBank.Player) or 0
    for i = 1, SB.GetNumSpellBookSkillLines() do
      local info = SB.GetSpellBookSkillLineInfo(i)
      if info then
        local off, num = info.itemIndexOffset or 0, info.numSpellBookItems or 0
        local future = G.Enum and G.Enum.SpellBookItemType and G.Enum.SpellBookItemType.FutureSpell
        for j = off + 1, off + num do
          local isFuture = false
          if SB.GetSpellBookItemInfo and future then
            local okI, item = pcall(SB.GetSpellBookItemInfo, j, bank)
            isFuture = okI and type(item) == "table" and item.itemType == future
          end
          if not isFuture then
            local ok, name = pcall(SB.GetSpellBookItemName, j, bank)
            if ok and type(name) == "string" and not C.isSecret(name) then names[name] = true end
          end
        end
      end
    end
    return names, "C_SpellBook"
  end
  if G.GetNumSpellTabs and G.GetSpellTabInfo and G.GetSpellBookItemName then
    for i = 1, G.GetNumSpellTabs() do
      local _, _, off, num = G.GetSpellTabInfo(i)
      for j = (off or 0) + 1, (off or 0) + (num or 0) do
        local kind = G.GetSpellBookItemInfo and G.GetSpellBookItemInfo(j, G.BOOKTYPE_SPELL or "spell")
        if kind ~= "FUTURESPELL" then
          local name = G.GetSpellBookItemName(j, G.BOOKTYPE_SPELL or "spell")
          if type(name) == "string" then names[name] = true end
        end
      end
    end
    return names, "GetSpellTabInfo"
  end
  return nil, "none"
end
--- Is any rank of a data spell known by ID? (talent spells and spells missing from the book scan)
function C.knowsAnyRank(spell)
  local f = G.IsPlayerSpell or G.IsSpellKnown
  if not f or not spell or not spell.ranks then return false end
  for _, r in ipairs(spell.ranks) do
    if r.id then local ok, yes = pcall(f, r.id); if ok and yes then return true end end
  end
  return false
end

-- ------------------------------------------------------------------ macros
function C.macroLimits()
  return G.MAX_ACCOUNT_MACROS or 120, G.MAX_CHARACTER_MACROS or 18
end
function C.numMacros() local a, c = GetNumMacros(); return a or 0, c or 0 end
--- name, icon, body for a macro index (nil when empty)
function C.macroInfo(index)
  local ok, name, icon, body = pcall(GetMacroInfo, index)
  if not ok then return nil end
  return name, icon, body
end
--- All character-specific macros: {{index, name, body}}
function C.characterMacros()
  local accMax = C.macroLimits()
  local _, numChar = C.numMacros()
  local out = {}
  for i = accMax + 1, accMax + numChar do
    local name, _, body = C.macroInfo(i)
    if name then out[#out + 1] = { index = i, name = name, body = body or "" } end
  end
  return out
end
function C.accountMacros()
  local numAcc = C.numMacros()
  local out = {}
  for i = 1, numAcc do
    local name, _, body = C.macroInfo(i)
    if name then out[#out + 1] = { index = i, name = name, body = body or "" } end
  end
  return out
end

-- ------------------------------------------------------------------ action bars
--- {kind, id, name?} for an action slot, or nil when empty.
function C.actionInfo(slot)
  local ok, kind, id = pcall(GetActionInfo, slot)
  if not ok or not kind then return nil end
  local info = { kind = kind, id = id }
  if kind == "macro" and id then info.name = C.macroInfo(id) end
  if kind == "spell" and id then
    local CS = G.C_Spell
    if CS and CS.GetSpellName then info.name = CS.GetSpellName(id)
    elseif G.GetSpellInfo then info.name = G.GetSpellInfo(id) end
  end
  return info
end
function C.cursorBusy() return G.GetCursorInfo and G.GetCursorInfo() ~= nil end

-- ------------------------------------------------------------------ CVars
function C.getCVar(name)
  local CV = G.C_CVar
  local ok, v
  if CV and CV.GetCVar then ok, v = pcall(CV.GetCVar, name) else ok, v = pcall(G.GetCVar, name) end
  if ok then return v end
  return nil
end
function C.setCVar(name, value)
  local CV = G.C_CVar
  if CV and CV.SetCVar then return pcall(CV.SetCVar, name, value) end
  return pcall(G.SetCVar, name, value)
end

-- ------------------------------------------------------------------ addons
--- "loaded" | "installed" (present but not loaded) | "missing"
function C.addonState(name)
  local A = G.C_AddOns
  local isLoaded = (A and A.IsAddOnLoaded) or G.IsAddOnLoaded
  local getInfo = (A and A.GetAddOnInfo) or G.GetAddOnInfo
  if isLoaded then local ok, l = pcall(isLoaded, name); if ok and l then return "loaded" end end
  if getInfo then
    local ok, n, _, _, _, reason = pcall(getInfo, name)
    if ok and n and reason ~= "MISSING" then return "installed" end
  end
  return "missing"
end

-- ------------------------------------------------------------------ group
--- Which partyN holds a character with this name (nil if not in party or unknown).
function C.partyUnitOf(name)
  if not name then return nil end
  for i = 1, 4 do
    local u = "party" .. i
    local n = C.unitName(u)
    if n and n:lower() == name:lower() then return u end
  end
  return nil
end
function C.inParty() return (G.IsInGroup and G.IsInGroup()) or (G.GetNumGroupMembers and G.GetNumGroupMembers() > 0) or false end

--- Probe results for /wbx selftest.
function C.probe()
  local r = { interface = C.interface(), build = C.buildString(), game = C.game(), locale = G.GetLocale and G.GetLocale() or "?" }
  local names = { "C_Spell", "C_SpellBook", "C_AddOns", "C_CVar", "C_EncodingUtil", "C_ClassTalents", "C_Traits", "issecretvalue",
    "GetSpellInfo", "GetNumSpellTabs", "IsPlayerSpell", "IsSpellKnown", "CreateMacro", "EditMacro", "PickupMacro", "PlaceAction",
    "GetActionInfo", "GetCursorInfo", "SetBindingMacro", "InCombatLockdown", "WOW_PROJECT_ID", "MAX_CHARACTER_MACROS", "MAX_ACCOUNT_MACROS",
    "BackdropTemplateMixin", "Settings" }
  r.api = {}
  for _, n in ipairs(names) do local v = G[n]; r.api[n] = v ~= nil and type(v) or "missing" end
  r.projectId = G.WOW_PROJECT_ID
  r.maxAccount, r.maxCharacter = C.macroLimits()
  local _, src = C.knownSpellNames()
  r.spellbook = src
  return r
end
