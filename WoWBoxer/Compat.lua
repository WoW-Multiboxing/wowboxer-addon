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
--- v, or nil when it is a secret value (never compare or store secrets).
function C.safe(v) if C.isSecret(v) then return nil end return v end
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
--- Cached until the spellbook changes (Core calls C.invalidateSpellbook on SPELLS_CHANGED / LEARNED_* / level-up).
local bookCache, bookSource
function C.invalidateSpellbook() bookCache, bookSource = nil, nil end
function C.knownSpellNames()
  if bookCache ~= nil then return bookCache or nil, bookSource end
  local names, src = C.scanSpellbook()
  bookCache, bookSource = names or false, src
  return names, src
end
function C.scanSpellbook()
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
--- Open Blizzard's key binding UI: Quick Keybind mode where it exists (Forever), else the Key Bindings panel.
--- Returns the way it was opened, or nil. Out of combat only (the caller checks).
function C.openKeyBindings()
  if G.QuickKeybindFrame and G.ShowUIPanel then
    local ok = pcall(G.ShowUIPanel, G.QuickKeybindFrame)
    if ok then return "quick" end
  end
  if G.KeyBindingFrame_LoadUI then pcall(G.KeyBindingFrame_LoadUI) end
  if G.KeyBindingFrame and G.ShowUIPanel then
    local ok = pcall(G.ShowUIPanel, G.KeyBindingFrame)
    if ok then return "panel" end
  end
  local St = G.Settings
  if St and St.OpenToCategory and St.KEYBINDINGS_CATEGORY_ID then
    local ok = pcall(St.OpenToCategory, St.KEYBINDINGS_CATEGORY_ID)
    if ok then return "settings" end
  end
  return nil
end

-- ------------------------------------------------------------------ talents (read-only)
local function spellName(id)
  if not id then return nil end
  local CS = G.C_Spell
  local ok, n
  if CS and CS.GetSpellName then ok, n = pcall(CS.GetSpellName, id) elseif G.GetSpellInfo then ok, n = pcall(G.GetSpellInfo, id) end
  return ok and C.safe(n) or nil
end
--- Talent ranks the character has spent, by talent name: {[name] = rank}, source.
--- Forever: the active C_Traits config (as Leatrix Plus / Questie read it). Other clients: GetTalentInfo.
--- Never changes anything (no PurchaseRank / CommitConfig).
function C.talentRanks()
  local CT, TR = G.C_ClassTalents, G.C_Traits
  if CT and CT.GetActiveConfigID and TR and TR.GetConfigInfo and TR.GetTreeNodes and TR.GetNodeInfo then
    local ok, configID = pcall(CT.GetActiveConfigID)
    configID = ok and C.safe(configID) or nil
    local config = configID and select(2, pcall(TR.GetConfigInfo, configID))
    if type(config) == "table" and type(config.treeIDs) == "table" then
      local out = {}
      for _, treeID in ipairs(config.treeIDs) do
        local okN, nodes = pcall(TR.GetTreeNodes, C.safe(treeID))
        for _, nodeID in ipairs(okN and type(nodes) == "table" and nodes or {}) do
          local okI, node = pcall(TR.GetNodeInfo, configID, C.safe(nodeID))
          if okI and type(node) == "table" then
            local rank = C.safe(node.ranksPurchased)
            if type(rank) ~= "number" or rank == 0 then rank = C.safe(node.activeRank) end
            if type(rank) == "number" and rank > 0 and type(node.entryIDs) == "table" and TR.GetEntryInfo and TR.GetDefinitionInfo then
              local entryID = node.activeEntry and node.activeEntry.entryID or node.entryIDs[1]
              local okE, entry = pcall(TR.GetEntryInfo, configID, entryID)
              local okD, def = pcall(TR.GetDefinitionInfo, okE and type(entry) == "table" and entry.definitionID or nil)
              local name = okD and type(def) == "table" and (C.safe(def.overrideName) or spellName(C.safe(def.spellID))) or nil
              if name then out[name] = (out[name] or 0) + rank end
            end
          end
        end
      end
      return out, "C_Traits"
    end
  end
  if G.GetNumTalentTabs and G.GetNumTalents and G.GetTalentInfo then
    local out = {}
    local okT, tabs = pcall(G.GetNumTalentTabs)
    for t = 1, okT and tonumber(tabs) or 0 do
      local okN, n = pcall(G.GetNumTalents, t)
      for i = 1, okN and tonumber(n) or 0 do
        local okI, name, _, _, _, rank = pcall(G.GetTalentInfo, t, i)
        if okI and name and tonumber(rank) and rank > 0 then out[name] = rank end
      end
    end
    return out, "GetTalentInfo"
  end
  return nil, "none"
end

-- Frames of the extra bars (same names in Classic Era and the modern UI). Bar 1 is always shown.
local BAR_FRAME = { [61] = "MultiBarBottomLeft", [49] = "MultiBarBottomRight", [25] = "MultiBarRight", [37] = "MultiBarLeft" }
--- false when the bar starting at `first` exists but is hidden (not enabled in the interface options / Edit Mode).
function C.barVisible(first)
  local name = BAR_FRAME[first]
  local f = name and G[name]
  if not f or not f.IsShown then return true end
  local ok, shown = pcall(f.IsShown, f)
  return not ok or shown == true
end
--- > 0 when action bar 1 shows a stance/form/stealth page instead of slots 1-12 (Warrior, Druid, Rogue ...).
function C.bonusBarOffset()
  local f = (G.C_ActionBar and G.C_ActionBar.GetBonusBarOffset) or G.GetBonusBarOffset
  if not f then return 0 end
  local ok, v = pcall(f)
  return ok and tonumber(v) or 0
end
--- Classes whose bar 1 changes with stance/form/stealth: their keys default to the Bottom Left bar.
C.PAGED_CLASSES = { warrior = true, druid = true, rogue = true }

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
