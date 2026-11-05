--[[ WoWBoxer – team relay (docs/compliance.md; CLAUDE.md hard rules 1, 2 and 5). Display and settings only:
  - Forward whispers (option "whispers", on): a follower that gets a whisper from someone outside the squad sends it
    to the party; the squad leader's client shows it in chat ("Anna ← Bob: …"). GM / Blizzard whispers are tagged
    and play a sound. Secret (chat-lockdown) texts and Battle.net whispers are never forwarded.
  - Follow warning (option "followWarn", on): when a follower's follow breaks out of combat, the leader gets a raid
    warning + sound. Not after a loading screen, while dead, on a flight, or when the leader flies / just zoned.
  - Shared sell list (option "shareSell"): the sell list (settings.sellList) is the same on every squad window; the
    newest edit wins. Each window still only sells when IT opens a merchant (Auto.onMerchant).
  Messages (prefix WBXR) come only from squad members in the party and are data: a fixed format, cleaned text,
  never code. Nothing here casts, targets, moves, follows or presses a key. ]]
local _, ns = ...
local RL = {}
ns.Relay = RL

local G = _G
RL.PREFIX = "WBXR"
RL.MAX_TEXT = 200          -- characters of a forwarded whisper
RL.SETTLE = 1.0            -- seconds after AUTOFOLLOW_END before the follower decides it is a break
RL.ZONE_QUIET = 8          -- seconds after a loading screen without warnings
RL.WARN_EVERY = 6          -- seconds between two warnings for the same follower
RL.SELL_MAX = 100          -- items on the sell list
RL.CHUNK = 200

local function Core() return ns.Core end
local function C() return ns.Compat end
local function AU() return ns.Auto end
local function now() return (G.GetTime and G.GetTime()) or 0 end
local function stamp() return (G.GetServerTime and G.GetServerTime()) or (G.time and G.time()) or 0 end
local function settings() return Core().db and Core().db.settings or {} end

-- ------------------------------------------------------------------ helpers
--- Chat text as plain data: links become [Name], colour codes and separators go, length capped.
function RL.plain(text, max)
  if type(text) ~= "string" then return nil end
  local t = text:gsub("|H.-|h(.-)|h", "%1"):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", ""):gsub("[|\r\n]", " ")
  return t:sub(1, max or RL.MAX_TEXT)
end
local function short(n) return C().baseName(n) end -- realm-free, full name kept (Compat names)
local function send(msg)
  if not C().inParty() then return false end
  return (C().sendAddon(RL.PREFIX, msg, (G.IsInRaid and G.IsInRaid()) and "RAID" or "PARTY", "relay " .. msg:sub(1, 1)))
end
local function iAmLeader() return AU().isLeader() end
local function squadSize() local s = Core().me(); return s and #s.members or 0 end

-- ------------------------------------------------------------------ 1. whispers
--- Follower: a whisper arrived (CHAT_MSG_WHISPER text, sender, …, flags = 6th argument).
function RL.onWhisper(text, sender, flags)
  if not AU().on("whispers") or iAmLeader() or squadSize() < 2 then return false end
  local body, who = C().safe(text), short(sender)
  if type(body) ~= "string" or not who then return false end   -- secret (chat lockdown) or unknown: never
  if AU().member(who) then return false end                        -- squad-internal whispers stay where they are
  local gm = (C().safe(flags) == "GM" or C().safe(flags) == "DEV") and 1 or 0
  who = RL.plain(who, 40)
  return send("W|" .. gm .. "|" .. who .. "|" .. RL.plain(body))
end
--- Leader: show a forwarded whisper.
function RL.showWhisper(from, gm, who, text)
  if not iAmLeader() or not AU().on("whispers") then return false end
  local tag = gm and "|cff00ccff<GM>|r " or ""
  local line = "|cffff80ff[" .. from.name .. "] " .. tag .. who .. " whispers: " .. text .. "|r"
  local frame = G.DEFAULT_CHAT_FRAME
  if frame and frame.AddMessage then frame:AddMessage(line) end
  if gm then
    RL.sound()
    RL.warn(from.name .. " got a GM whisper")
  end
  Core().log("info", "relay: whisper to " .. from.name .. " from " .. who .. (gm and " (GM)" or ""))
  return true
end

-- ------------------------------------------------------------------ 2. follow warning
RL.zonedAt = -1e9
RL.warnedAt = {}
local function quiet() return now() - RL.zonedAt < RL.ZONE_QUIET end
local function selfBusy()
  if C().safe(G.UnitAffectingCombat and G.UnitAffectingCombat("player")) then return "combat" end
  if G.UnitIsDeadOrGhost and C().safe(G.UnitIsDeadOrGhost("player")) then return "dead" end
  if G.UnitOnTaxi and C().safe(G.UnitOnTaxi("player")) then return "flight" end
  if quiet() then return "loading screen" end
  return nil
end
RL.selfBusy = selfBusy
--- Follower: follow ended. Wait a moment, then tell the leader unless there is a good reason.
function RL.onFollowEnd()
  if not AU().on("followWarn") or iAmLeader() or squadSize() < 2 or not C().inParty() then return false end
  RL.endedAt = now()
  local at = RL.endedAt
  local function check()
    if RL.endedAt ~= at or (ns.Team and ns.Team.following) then return end
    local why = selfBusy()
    if why then Core().log("info", "relay: follow ended (" .. why .. ") – no warning"); return end
    send("F|1")
  end
  if G.C_Timer and G.C_Timer.After then G.C_Timer.After(RL.SETTLE, check) else check() end
  return true
end
--- Leader: a follower reports a broken follow.
function RL.followBroke(from)
  if not iAmLeader() or not AU().on("followWarn") then return false end
  local why = selfBusy()
  if why then Core().log("info", "relay: " .. from.name .. " stopped following (" .. why .. " here) – no warning"); return false end
  if now() - (RL.warnedAt[from.name] or -1e9) < RL.WARN_EVERY then return false end
  RL.warnedAt[from.name] = now()
  RL.warn(from.name .. " stopped following!")
  RL.sound()
  Core().log("info", "relay: follow warning for " .. from.name)
  return true
end

-- ------------------------------------------------------------------ display helpers
function RL.warn(text)
  local rw, info = G.RaidWarningFrame, G.ChatTypeInfo and G.ChatTypeInfo.RAID_WARNING
  if G.RaidNotice_AddMessage and rw then pcall(G.RaidNotice_AddMessage, rw, text, info or { r = 1, g = 0.3, b = 0.1 }) end
  Core().print("|cffff6020" .. text .. "|r")
  RL.lastWarn = text
end
function RL.sound()
  if not G.PlaySound then return end
  local kit = G.SOUNDKIT and G.SOUNDKIT.RAID_WARNING or 8959
  pcall(G.PlaySound, kit, "Master")
end

-- ------------------------------------------------------------------ 3. shared sell list
--- The sell list (item names), cleaned.
function RL.sellList()
  local s = settings()
  local out = {}
  for _, n in ipairs(type(s.sellList) == "table" and s.sellList or {}) do if type(n) == "string" and n ~= "" then out[#out + 1] = n end end
  return out
end
local function clean(name)
  name = RL.plain(tostring(name or ""), 60)
  name = name and name:gsub("[;%[%]]", ""):gsub("^%s+", ""):gsub("%s+$", "")
  if not name or name == "" then return nil end
  return name
end
--- Replace the list (from an edit here or a newer list from the squad).
function RL.setSellList(list, at, noSend)
  local out, seen = {}, {}
  for _, n in ipairs(list or {}) do
    local c = clean(n)
    if c and not seen[c:lower()] and #out < RL.SELL_MAX then seen[c:lower()] = true; out[#out + 1] = c end
  end
  local s = settings()
  s.sellList, s.sellListAt = out, at or stamp()
  if not noSend then RL.sendSellList() end
  return out
end
function RL.addSell(name)
  local c = clean(name)
  if not c then return false end
  local l = RL.sellList()
  for _, n in ipairs(l) do if n:lower() == c:lower() then return false end end
  l[#l + 1] = c
  RL.setSellList(l)
  return c
end
function RL.removeSell(name)
  local c = clean(name)
  if not c then return false end
  local l, out, gone = RL.sellList(), {}, false
  for _, n in ipairs(l) do if n:lower() == c:lower() then gone = true else out[#out + 1] = n end end
  if gone then RL.setSellList(out) end
  return gone and c or false
end
--- Send the list in chunks: L|at|i|n|part (part = names joined by ";").
function RL.sendSellList()
  if not AU().on("shareSell") or squadSize() < 2 or not C().inParty() then return 0 end
  local at = tonumber(settings().sellListAt) or 0
  local body = table.concat(RL.sellList(), ";")
  local parts = {}
  repeat parts[#parts + 1] = body:sub(1, RL.CHUNK); body = body:sub(RL.CHUNK + 1) until body == ""
  for i, p in ipairs(parts) do send("L|" .. at .. "|" .. i .. "|" .. #parts .. "|" .. p) end
  return #parts
end
RL.inbox = {}
function RL.receiveSell(from, at, i, n, part)
  if not AU().on("shareSell") then return false end
  if not (at and i and n) or n < 1 or n > 20 or i < 1 or i > n then return false end
  if at <= (tonumber(settings().sellListAt) or 0) then return false end   -- ours is as new or newer
  local key = from.name .. ":" .. at
  local box = RL.inbox[key] or { parts = {}, got = 0 }
  RL.inbox[key] = box
  if not box.parts[i] then box.parts[i] = part; box.got = box.got + 1 end
  if box.got < n then return false end
  RL.inbox[key] = nil
  local list = {}
  for name in (table.concat(box.parts) .. ";"):gmatch("([^;]*);") do if name ~= "" then list[#list + 1] = name end end
  RL.setSellList(list, at, true)
  Core().log("info", "relay: sell list from " .. from.name .. " (" .. #list .. " items)")
  return true
end

-- ------------------------------------------------------------------ messages (data only)
function RL.receive(prefix, text, _, sender)
  if prefix ~= RL.PREFIX or type(text) ~= "string" or #text > 255 then return end
  C().arrived(prefix, sender)
  local m = AU().member(sender, true)
  if not m then return C().drop(prefix, sender, "not a squad member in your party (name not matched)") end -- only squad members in the party
  local kind = text:sub(1, 2)
  if kind == "W|" then
    local gm, who, body = text:match("^W|([01])|([^|]+)|(.*)$")
    if gm then RL.showWhisper(m, gm == "1", who, body) end
  elseif kind == "F|" then RL.followBroke(m)
  elseif kind == "L|" then
    local at, i, n, part = text:match("^L|(%d+)|(%d+)|(%d+)|(.*)$")
    if at then RL.receiveSell(m, tonumber(at), tonumber(i), tonumber(n), part) end
  end
end

-- ------------------------------------------------------------------ slash: /wbx sell …
--- "/wbx sell" lists, "/wbx sell add <item or link>", "/wbx sell remove <item>", "/wbx sell clear".
function RL.slash(rest)
  local cmd, arg = (rest or ""):match("^(%S*)%s*(.-)%s*$")
  cmd = (cmd or ""):lower()
  if cmd == "add" and arg ~= "" then
    local c = RL.addSell(arg)
    Core().print(c and ("Sell list: added " .. c .. ".") or "Sell list: already on it.")
  elseif (cmd == "remove" or cmd == "rm") and arg ~= "" then
    local c = RL.removeSell(arg)
    Core().print(c and ("Sell list: removed " .. c .. ".") or "Sell list: not on it.")
  elseif cmd == "clear" then RL.setSellList({}); Core().print("Sell list: cleared.")
  else
    local l = RL.sellList()
    Core().print("Sell list (" .. #l .. "): " .. (#l > 0 and table.concat(l, ", ") or "empty") ..
      ". /wbx sell add [item] · /wbx sell remove [item]")
  end
end

-- ------------------------------------------------------------------ events
local f = CreateFrame("Frame")
RL.frame = f
function RL.Init()
  local CI = G.C_ChatInfo
  local regp = (CI and CI.RegisterAddonMessagePrefix) or G.RegisterAddonMessagePrefix
  if regp then pcall(regp, RL.PREFIX) end
  for _, ev in ipairs({ "CHAT_MSG_ADDON", "CHAT_MSG_WHISPER", "AUTOFOLLOW_END", "PLAYER_ENTERING_WORLD", "LOADING_SCREEN_DISABLED",
    "GROUP_ROSTER_UPDATE" }) do pcall(f.RegisterEvent, f, ev) end
end
RL.announcedAt = -1e9
f:SetScript("OnEvent", function(_, event, a, b, c, d, e, g)
  if not Core().db then return end
  local ok, err = pcall(function()
    if event == "CHAT_MSG_ADDON" then RL.receive(a, b, c, d)
    elseif event == "CHAT_MSG_WHISPER" then RL.onWhisper(a, b, g)
    elseif event == "AUTOFOLLOW_END" then RL.onFollowEnd()
    elseif event == "PLAYER_ENTERING_WORLD" or event == "LOADING_SCREEN_DISABLED" then RL.zonedAt = now()
    elseif event == "GROUP_ROSTER_UPDATE" then
      -- someone joined: offer our list once a minute (the newest list wins on every window)
      if now() - RL.announcedAt > 60 then RL.announcedAt = now(); RL.sendSellList() end
    end
  end)
  if not ok then Core().log("error", "relay " .. event .. ": " .. tostring(err)) end
end)

return RL
