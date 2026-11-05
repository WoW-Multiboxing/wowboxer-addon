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
function C.game() return ns.gameOf(C.interface()) end
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
  Undead = "undead", Tauren = "tauren", Troll = "troll", Draenei = "draenei", BloodElf = "bloodelf" }
--- Companion race key for a race file name ("Scourge" -> "undead"), or nil.
function C.raceKey(file) return file and RACE_FILE[file] or nil end
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
    local name, icon, body = C.macroInfo(i)
    if name then out[#out + 1] = { index = i, name = name, body = body or "", icon = icon } end
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

-- ------------------------------------------------------------------ locale
--- True on clients whose spell names are not English (the data's names then need translating in macros).
function C.needsLocalNames()
  local loc = G.GetLocale and G.GetLocale() or "enUS"
  return loc ~= "enUS" and loc ~= "enGB"
end
--- The client's name for a spell ID (localised), or nil.
--- The icon file ID of a spell from the client (rank IDs of the data, first that answers), or nil.
function C.spellTexture(spell)
  if not spell or not spell.ranks then return nil end
  local CS = G.C_Spell
  local f = (CS and CS.GetSpellTexture) or G.GetSpellTexture
  if not f then return nil end
  for _, r in ipairs(spell.ranks) do
    if r.id then
      local ok, tex = pcall(f, r.id)
      tex = ok and C.safe(tex) or nil
      if type(tex) == "number" and tex > 0 then return tex end
    end
  end
  return nil
end

function C.spellName(id)
  if not id then return nil end
  local CS = G.C_Spell
  local ok, n
  if CS and CS.GetSpellName then ok, n = pcall(CS.GetSpellName, id) elseif G.GetSpellInfo then ok, n = pcall(G.GetSpellInfo, id) end
  return ok and type(n) == "string" and C.safe(n) or nil
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
--- Talent points not spent yet, or nil when this client cannot tell (read-only).
function C.unspentTalentPoints(m, level)
  if G.UnitCharacterPoints then
    local ok, n = pcall(G.UnitCharacterPoints, "player")
    n = ok and tonumber(C.safe(n)) or nil
    if n then return n end
  end
  if C.isForever() and ns.Kit then
    local ok, ranks = pcall(C.talentRanks)
    if ok and ranks and m then
      local st = ns.Kit.talentStatus(m, ranks, level)
      return math.max(0, st.available - st.spent)
    end
  end
  return nil
end
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
--- The game's Settings object for a CVar, or nil (Classic Era 1.15 / modern: Settings.GetSetting(variable)).
function C.cvarSetting(name)
  local S = G.Settings
  if not (S and S.GetSetting) then return nil end
  local ok, s = pcall(S.GetSetting, name)
  if ok and type(s) == "table" and s.SetValue then return s end
  return nil
end
--- Set a CVar so that it STICKS (docs/feedback-2026-10-30-night.md §2): through the Settings system when the CVar has
--- a setting (deselectOnClick is the "Sticky Targeting" checkbox, negated), else C_CVar.SetCVar. Always reads back.
--- Returns stuck (true = the value is now `want`), method, after.
function C.setCVarSure(name, want)
  local s = C.cvarSetting(name)
  local method = "SetCVar"
  if s then
    method = "setting"
    local okv, cur = pcall(s.GetValue, s)
    if okv and type(cur) == "boolean" then
      local b = want == "1"
      pcall(s.SetValue, s, b)
      if tostring(C.getCVar(name)) ~= want then pcall(s.SetValue, s, not b); method = "setting (negated)" end
    else
      pcall(s.SetValue, s, tonumber(want) or want)
    end
  end
  if tostring(C.getCVar(name)) ~= want then
    C.setCVar(name, want) -- the plain way as a last try
    if s then method = method .. "+SetCVar" end
  end
  local after = C.getCVar(name)
  return tostring(after) == want, method, after
end
--- Open the game's options where a setting lives (Controls for Sticky Targeting). [AFKLAR: category ids on Forever]
function C.openOptions(name)
  local S = G.Settings
  if S and S.OpenToCategory then
    local cats = {}
    for _, c in ipairs({ "Controls" }) do cats[#cats + 1] = c end
    if S.CONTROLS_CATEGORY_ID then table.insert(cats, 1, S.CONTROLS_CATEGORY_ID) end
    if G.CONTROLS_LABEL then cats[#cats + 1] = G.CONTROLS_LABEL end
    for _, cat in ipairs(cats) do if pcall(S.OpenToCategory, cat) then return "settings" end end
  end
  if G.SettingsPanel and G.ShowUIPanel and pcall(G.ShowUIPanel, G.SettingsPanel) then return "panel" end
  if G.InterfaceOptionsFrame_Show and pcall(G.InterfaceOptionsFrame_Show) then return "interface" end
  if G.ToggleGameMenu and pcall(G.ToggleGameMenu) then return "menu" end
  return nil
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

-- ------------------------------------------------------------------ character names (the ONE place names are compared)
-- Era/TBC: "Name" or "Name-Realm". Forever: two-part names, first + last, no realm ("Rip And"); the game may also
-- hand them over as "Rip And-Realm". Old saved squads hold only the first name ("Rip"). Every name comparison in
-- WoWBoxer goes through C.sameName / C.nameKey so all of these match each other.
--- The name without "-Realm", trimmed, inner spaces collapsed, case kept ("Rip And"); nil for nil/secret/empty.
function C.baseName(n)
  n = C.safe(n)
  if type(n) ~= "string" then return nil end
  n = n:gsub("%c", "")
  n = n:match("^%s*([^%-]*)") or ""      -- everything before the first "-" (realm)
  n = n:gsub("%s+", " "):match("^%s*(.-)%s*$")
  if n == "" then return nil end
  return n
end
--- Lower-case comparison key of a name ("rip and"), or nil.
function C.nameKey(n) local b = C.baseName(n); return b and b:lower() or nil end
--- Lower-case first name ("rip"), or nil.
function C.firstNameKey(n) local k = C.nameKey(n); return k and (k:match("^(%S+)") or k) or nil end
--- Is it a two-part (or longer) name?
function C.isFullName(n) local k = C.nameKey(n); return k ~= nil and k:find(" ", 1, true) ~= nil end
--- Same character? Exact (realm-free, case-free) match, or one side has only the first name and it matches the
--- other side's first name (old squads / Forever two-part names).
function C.sameName(a, b)
  local ka, kb = C.nameKey(a), C.nameKey(b)
  if not (ka and kb) then return false end
  if ka == kb then return true end
  local sa, sb = ka:find(" ", 1, true) ~= nil, kb:find(" ", 1, true) ~= nil
  if sa == sb then return false end      -- two different single names, or two different full names
  return (sa and ka:match("^(%S+)") or ka) == (sb and kb:match("^(%S+)") or kb)
end
--- Exact match is how sameName ranks first: 2 = exact, 1 = first-name match, 0 = no match.
function C.nameScore(a, b)
  local ka, kb = C.nameKey(a), C.nameKey(b)
  if not (ka and kb) then return 0 end
  if ka == kb then return 2 end
  return C.sameName(a, b) and 1 or 0
end
--- The entry of `list` whose name (field `field`, default "name") best matches `name`: an exact match wins over a
--- first-name match. Returns entry, score.
function C.findByName(list, name, field)
  field = field or "name"
  local best, bestScore = nil, 0
  for _, x in ipairs(list or {}) do
    local sc = C.nameScore(type(x) == "table" and x[field] or x, name)
    if sc > bestScore then best, bestScore = x, sc; if sc == 2 then break end end
  end
  return best, bestScore
end

-- ------------------------------------------------------------------ addon messages (send result + drops, logged)
-- Forever (modern API) returns an Enum.SendAddonMessageResult code: 0 = success, anything else = not sent. Older
-- clients return true/false or nothing. pcall returning true is NOT success.
C.SEND_RESULT = { [0] = "Success", "InvalidPrefix", "InvalidMessage", "AddonMessageThrottle", "InvalidChatType", "NotInGroup",
  "TargetRequired", "InvalidChannel", "ChannelThrottle", "GeneralError", "NotInGuild", "AddOnMessageLockdown", "TargetOffline" }
function C.sendResultName(code)
  local E = G.Enum and G.Enum.SendAddonMessageResult
  if type(E) == "table" then for k, v in pairs(E) do if v == code then return tostring(k) end end end
  return C.SEND_RESULT[code] or tostring(code)
end
C.sendStats = { ok = 0, failed = 0 }
C.sendWarned = {}
C.SEND_WARN_EVERY = 120 -- background sends (team status): one chat line per reason this often
--- Send an addon message and check the result. what = a short label for the log ("team", "squad", "relay" …);
--- loud = the player asked for this send (always told in chat when it fails). Returns ok, reason.
function C.sendAddon(prefix, msg, channel, what, loud)
  local CI = G.C_ChatInfo
  local f = (CI and CI.SendAddonMessage) or G.SendAddonMessage
  local ok, r, reason
  if not f then ok, reason = false, "no SendAddonMessage API"
  else
    local pok, res = pcall(f, prefix, msg, channel)
    if not pok then ok, reason = false, "error: " .. tostring(res)
    elseif res == nil or res == true or res == 0 then ok = true
    elseif res == false then ok, reason = false, "refused (false)"
    else ok, r, reason = false, res, C.sendResultName(res) .. " (" .. tostring(res) .. ")" end
  end
  local Core = ns.Core
  if ok then C.sendStats.ok = C.sendStats.ok + 1; return true end
  C.sendStats.failed = C.sendStats.failed + 1
  C.sendStats.last = (what or prefix) .. ": " .. reason
  if Core and Core.log then Core.log("warn", "send " .. (what or prefix) .. " on " .. tostring(channel) .. " failed: " .. reason .. " (" .. #tostring(msg) .. " chars)") end
  local key = (what or prefix) .. ":" .. tostring(r or reason)
  local t = (G.GetTime and G.GetTime()) or 0
  if Core and Core.print and (loud or t - (C.sendWarned[key] or -1e9) >= C.SEND_WARN_EVERY) then
    C.sendWarned[key] = t
    Core.print("|cffff8a80Could not send to your other characters|r (" .. (what or prefix) .. ": " .. reason .. ").")
  end
  return false, reason, r
end
C.arrivals = {}  -- "prefix sender" (exactly as the game gives it) -> count
--- A WoWBoxer message arrived (CHAT_MSG_ADDON): counted per prefix + raw sender; the first one per sender is logged.
function C.arrived(prefix, sender)
  local key = tostring(prefix) .. " " .. tostring(C.safe(sender) or "<secret>")
  local n = (C.arrivals[key] or 0) + 1
  C.arrivals[key] = n
  if n == 1 and ns.Core and ns.Core.log then ns.Core.log("info", "first " .. tostring(prefix) .. " message from \"" .. tostring(C.safe(sender) or "<secret>") .. "\"") end
end
C.dropped = {}
C.DROP_LOG_EVERY = 30
--- A WoWBoxer message that arrived but was not used: logged with the reason (once per sender+reason every 30 s).
function C.drop(prefix, sender, reason)
  local key = tostring(prefix) .. ":" .. tostring(sender) .. ":" .. tostring(reason)
  local t = (G.GetTime and G.GetTime()) or 0
  if t - (C.dropped[key] or -1e9) < C.DROP_LOG_EVERY then return end
  C.dropped[key] = t
  if ns.Core and ns.Core.log then ns.Core.log("info", "dropped " .. tostring(prefix) .. " from " .. tostring(sender) .. ": " .. tostring(reason)) end
end

-- ------------------------------------------------------------------ group
--- Which partyN holds a character with this name (nil if not in party or unknown). Exact match first.
function C.partyUnitOf(name)
  if not C.nameKey(name) then return nil end
  local list = {}
  for i = 1, 4 do
    local u = "party" .. i
    local n = C.unitName(u)
    if n then list[#list + 1] = { name = n, unit = u } end
  end
  local x = C.findByName(list, name)
  return x and x.unit or nil
end
function C.inParty() return (G.IsInGroup and G.IsInGroup()) or (G.GetNumGroupMembers and G.GetNumGroupMembers() > 0) or false end

--- Which cast-bar CVar candidates exist here, plus every CVar whose name has "cast" in it (read-only, diagnose).
function C.cvarProbe()
  local r = { candidates = {}, found = {} }
  for _, c in ipairs(ns.Rules.CAST_CVARS) do r.candidates[c[1]] = C.getCVar(c[1]) ~= nil end
  local list
  local CC = G.C_Console
  if CC and CC.GetAllCommands then local ok, l = pcall(CC.GetAllCommands); if ok then list = l end end
  if not list and G.ConsoleGetAllCommands then local ok, l = pcall(G.ConsoleGetAllCommands); if ok then list = l end end
  r.source = list and "console" or "none"
  for _, cmd in ipairs(list or {}) do
    local n = type(cmd) == "table" and cmd.command or nil
    if type(n) == "string" and n:lower():find("cast", 1, true) and #r.found < 40 then r.found[#r.found + 1] = n end
  end
  table.sort(r.found)
  return r
end
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
