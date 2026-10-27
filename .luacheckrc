-- luacheck config: WoW addon code is Lua 5.1 with the WoW API as globals.
std = "lua51"
max_line_length = false
codes = true
ignore = {
  "212", -- unused argument (event handlers, callbacks)
  "213", -- unused loop variable
  "542", -- empty if branch
}
exclude_files = { "tests/vectors/**" }

files["WoWBoxer/Data/"] = { ignore = { "631" } }
files["tests/"] = { std = "+lua53", globals = { "arg" }, ignore = { "211", "311", "411", "421", "431" } }

-- Globals the addon defines
globals = {
  "WoWBoxerDB", "WoWBoxerCharDB", "SLASH_WOWBOXER1", "SLASH_WOWBOXER2", "SlashCmdList", "StaticPopupDialogs",
  "WoWBoxerMainFrame", "WoWBoxerMinimapMenu",
  "WoWBoxer_OnAddonCompartmentClick", "WoWBoxer_OnAddonCompartmentEnter", "WoWBoxer_OnAddonCompartmentLeave",
}

-- WoW API the addon reads (keep in sync with Compat.lua)
read_globals = {
  "unpack", "wipe", "date", "time", "debugstack", "geterrorhandler", "hooksecurefunc", "issecretvalue",
  "C_Timer", "C_Spell", "C_SpellBook", "C_AddOns", "C_CVar", "C_EncodingUtil", "C_ClassTalents", "C_Traits", "Enum",
  "GetBuildInfo", "GetLocale", "GetRealmName", "GetTime", "InCombatLockdown", "IsLoggedIn",
  "UnitName", "UnitClass", "UnitRace", "UnitLevel", "UnitFactionGroup", "UnitExists", "UnitIsUnit", "UnitInParty", "UnitInRaid",
  "UnitIsGroupLeader", "GetNumGroupMembers", "IsInGroup", "IsInRaid",
  "GetNumMacros", "GetMacroInfo", "GetMacroBody", "GetMacroIndexByName", "CreateMacro", "EditMacro", "DeleteMacro",
  "MAX_ACCOUNT_MACROS", "MAX_CHARACTER_MACROS",
  "PickupMacro", "PlaceAction", "PickupAction", "ClearCursor", "GetCursorInfo", "GetActionInfo", "HasAction", "GetActionText", "GetActionTexture",
  "GetCVar", "SetCVar", "GetCVarDefault",
  "GetAddOnInfo", "IsAddOnLoaded", "GetNumAddOns", "GetAddOnMetadata",
  "GetSpellInfo", "GetNumSpellTabs", "GetSpellTabInfo", "GetSpellBookItemName", "GetSpellBookItemInfo", "BOOKTYPE_SPELL",
  "IsSpellKnown", "IsPlayerSpell",
  "CreateFrame", "UIParent", "GameTooltip", "UISpecialFrames", "PlaySound", "SOUNDKIT", "StaticPopup_Show", "StaticPopup_Hide",
  "DEFAULT_CHAT_FRAME", "ChatFontNormal", "GameFontNormal", "GameFontHighlight", "GameFontHighlightSmall", "GameFontNormalSmall",
  "GameFontNormalLarge", "GameFontDisable", "GameFontDisableSmall", "GameFontNormalHuge", "RAID_CLASS_COLORS", "CLASS_ICON_TCOORDS",
  "Settings", "InterfaceOptions_AddCategory", "ReloadUI", "SetBindingMacro", "SaveBindings", "GetCurrentBindingSet",
  "ACCEPT", "CANCEL", "OKAY", "YES", "NO", "CLOSE",
  "GetBindingKey", "GetBindingAction", "SetBinding", "CHARACTER_BINDINGS", "GetCursorPosition", "Minimap",
  "IsAltKeyDown", "IsControlKeyDown", "IsShiftKeyDown", "AddonCompartmentFrame",
}
