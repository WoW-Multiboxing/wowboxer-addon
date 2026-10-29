--[[ WoWBoxer – rules: what the addon is allowed to write.
  - Macro validation (applied to every macro before CreateMacro/EditMacro, even the ones we generate ourselves).
  - CVar allow-list with recommended values per squad role (only these can ever be changed, also from imports).
  - Recommended addons (display only). ]]
local _, ns = ...
local R = {}
ns.Rules = R

local sfind, smatch, slower, sgsub = string.find, string.match, string.lower, string.gsub

R.PREFIX = "WBX"
R.MACRO_LIMIT = 255
R.NAME_LIMIT = 16

-- Slash commands a WoWBoxer macro may contain. Everything else is rejected, in particular /run, /script, /console,
-- /click (code execution and button chaining) and chat commands (a line without a slash would be said in chat).
R.SLASH_WHITELIST = {
  ["/cast"] = true, ["/castsequence"] = true, ["/use"] = true,
  ["/startattack"] = true, ["/stopattack"] = true, ["/stopcasting"] = true,
  ["/petattack"] = true, ["/petfollow"] = true, ["/petpassive"] = true, ["/petstay"] = true, ["/petdefensive"] = true, ["/petaggressive"] = true,
  ["/target"] = true, ["/assist"] = true, ["/focus"] = true, ["/clearfocus"] = true, ["/cleartarget"] = true,
  ["/follow"] = true, ["/cancelaura"] = true, ["/cancelform"] = true, ["/stopmacro"] = true,
  -- Invite squad (docs/squad-v2-simple.md §3): a normal chat command; the others still accept by hand
  ["/invite"] = true,
}
R.SLASH_BLOCKED = { ["/run"] = true, ["/script"] = true, ["/console"] = true, ["/click"] = true, ["/dump"] = true }

--- True if name is one of ours ("WBX" prefix, case-sensitive).
function R.isOurs(name) return type(name) == "string" and name:sub(1, #R.PREFIX) == R.PREFIX end

--- Returns true or false, reason.
function R.validateMacro(name, body)
  if type(name) ~= "string" or type(body) ~= "string" then return false, "name and body must be text" end
  if not R.isOurs(name) then return false, "macro name must start with " .. R.PREFIX end
  if #name > R.NAME_LIMIT then return false, "macro name longer than " .. R.NAME_LIMIT .. " characters" end
  if sfind(name, "[%c]") then return false, "control character in name" end
  if body == "" then return false, "empty macro" end
  if #body > R.MACRO_LIMIT then return false, "macro longer than " .. R.MACRO_LIMIT .. " characters (" .. #body .. ")" end
  for i = 1, #body do
    local b = body:byte(i)
    if (b < 32 and b ~= 10) or b == 127 then return false, "control character in macro" end
  end
  local n = 0
  for line in (body .. "\n"):gmatch("([^\n]*)\n") do
    n = n + 1
    if line == "" then
      -- empty line: harmless
    elseif sfind(line, "^#") then
      if not (line == "#showtooltip" or sfind(line, "^#showtooltip ") or line == "#show" or sfind(line, "^#show ")) then
        return false, "line " .. n .. ": only #showtooltip is allowed"
      end
    else
      local cmd = smatch(line, "^(/%S+)")
      if not cmd then return false, "line " .. n .. ": every line must start with a slash command" end
      cmd = slower(cmd)
      if R.SLASH_BLOCKED[cmd] then return false, "line " .. n .. ": " .. cmd .. " is not allowed" end
      if not R.SLASH_WHITELIST[cmd] then return false, "line " .. n .. ": " .. cmd .. " is not on the whitelist" end
    end
  end
  return true
end

-- ------------------------------------------------------------------ CVars
-- Only these can be changed by WoWBoxer. leader/follower = recommended value; nil = leave as is.
-- Every entry is checked on the running client first (missing CVars are skipped).
R.CVARS = {
  { name = "autoLootDefault", leader = "1", follower = "1", label = "Auto loot", why = "Loot with one click on every character." },
  { name = "deselectOnClick", leader = "1", follower = "1", label = "Clear target on click", why = "On (the game's normal): clicking empty ground clears your target. WoWBoxer's macros use mouseover and the leader's target, so sticky targeting is not needed." },
  { name = "autoSelfCast", leader = "1", follower = "1", label = "Auto self cast", why = "Friendly spells fall back to yourself when nothing friendly is targeted." },
  { name = "maxfpsbk", leader = "30", follower = "30", label = "Background FPS cap", why = "Windows in the background draw at most 30 frames per second, so several clients run smoothly." },
  { name = "Sound_EnableSoundWhenGameIsInBG", leader = "1", follower = "0", label = "Sound in background", why = "Only the leader plays sound when its window is in the background." },
  { name = "Sound_EnableErrorSpeech", leader = "1", follower = "0", label = "Error speech", why = "Followers do not say \"Not enough mana\" and similar out loud." },
  { name = "showTargetOfTarget", leader = "1", follower = "1", label = "Target of target", why = "See who your target is attacking." },
  { name = "ActionButtonUseKeyDown", leader = "1", follower = "1", label = "Cast on key down", why = "Actions fire when the macro goes down (the game's default)." },
  { name = "AutoPushSpellToActionBar", leader = "0", follower = "0", label = "No auto-placed spells", why = "New spells are not dropped onto your bars, so WoWBoxer macros stay where you put them." },
  { name = "autoClearAFK", leader = "1", follower = "1", label = "Clear AFK automatically", why = "Moving or acting clears AFK." },
  { name = "nameplateShowEnemies", leader = "1", follower = "1", label = "Enemy nameplates", why = "Health bars over enemies: see what the squad is fighting." },
  { name = "nameplateShowFriends", leader = "1", follower = "1", label = "Friendly nameplates", why = "Health bars over your squad and other friends: easier healing and mouseover." },
  { name = "nameplateShowSelf", leader = "1", follower = "1", label = "Personal nameplate", why = "Your own health and mana under your character (modern clients only)." },
}
-- Cast bars on friendly nameplates / party frames: the names differ per client and are not verified
-- [AFKLAR: real CVar names on Forever and Era – the diagnose lists every CVar with "cast" in its name (cvarProbe)].
-- Only the candidates that exist on the running client are offered (a missing CVar is never shown or set).
R.CAST_CVARS = {
  { "nameplateShowFriendlyCastBar", "Friendly cast bars" }, { "nameplateShowFriendlyCastBars", "Friendly cast bars" },
  { "nameplateShowCastBars", "Nameplate cast bars" }, { "showVKeyCastbar", "Cast bars on nameplates" },
  { "showPartyCastbar", "Party cast bars" }, { "raidFramesDisplayCastBars", "Raid frame cast bars" },
}
for _, c in ipairs(R.CAST_CVARS) do
  R.CVARS[#R.CVARS + 1] = { name = c[1], leader = "1", follower = "1", label = c[2], cast = true,
    why = "Shows cast bars, so you see what your friends (and enemies) are casting." }
end
R.CVAR_BY_NAME = {}
for _, c in ipairs(R.CVARS) do R.CVAR_BY_NAME[c.name] = c end

--- Valid CVar value from an import: short, plain characters only.
function R.cleanCVarValue(v)
  if type(v) == "number" then v = tostring(v) end
  if type(v) ~= "string" or #v == 0 or #v > 16 or not sfind(v, "^[%w%.%-]+$") then return nil end
  return v
end

-- ------------------------------------------------------------------ recommended addons (display only)
R.ADDONS = {
  { name = "Questie", why = "Quest objectives on the map; every character sees the same quests." },
  { name = "Leatrix_Plus", why = "Quality of life (faster loot, automation off by default)." },
  { name = "WhatsTraining", why = "Shows what your trainer has for you; WoWBoxer's macros update when you learn new spells." },
  { name = "TomTom", why = "Waypoints for the leader." },
}
function R.cleanAddonName(v)
  if type(v) ~= "string" or #v == 0 or #v > 64 or not sfind(v, "^[%w_%-%.]+$") then return nil end
  return v
end

--- Trimmed, single-line text for names from imports or the UI.
function R.cleanText(v, maxLen)
  if type(v) ~= "string" then return nil end
  v = sgsub(v, "[%c]", "")
  v = smatch(v, "^%s*(.-)%s*$")
  if #v > maxLen then v = v:sub(1, maxLen) end
  return v
end
