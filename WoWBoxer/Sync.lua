--[[ WoWBoxer – squad sync between your own clients, as OFFERS only (docs/squad-overhaul.md §3.3).
  - "Send squad to my party": the share string (the same !WBX:1! data the Share tab uses, never macro text) goes to
    the party in numbered chunks (Q|id|i|n|chunk), one every GAP seconds. A receiving client checks it like a pasted
    string and shows "Dorin shares squad 'Undead trio' (3) – Review / Ignore". Review opens the Share import preview;
    only the Import click on THAT client changes anything. There is no auto-accept and no setting for one.
  - Leader preset switch: P|squad|preset|leader|name -> "Dorin switched to 'Dungeon' – Apply / Ignore" on clients that
    have the same squad and preset.
  - A session card after login when grouped: who is online, whose keys need an update (display only).
  Hard rule: a message never makes this client change keys, target, follow, cast, accept or invite by itself. Every
  offer is logged on both sides. ]]
local _, ns = ...
local SY = {}
ns.Sync = SY

SY.CHUNK = 200
SY.GAP = 0.3
SY.MAX_CHUNKS = 90
SY.TTL = 60
SY.inbox = {}
SY.queue = {}

local G = _G

local function Core() return ns.Core end
local function now() return (G.GetTime and G.GetTime()) or 0 end
local function clean(t) return (tostring(t or ""):gsub("[|\n\r]", "")):sub(1, 40) end

local function after(sec, fn) if G.C_Timer and G.C_Timer.After then G.C_Timer.After(sec, fn) else fn() end end
SY.RETRIES = 3
SY.RETRY_GAP = 1.5
--- Send one message; a throttled send is tried again (RETRIES times, RETRY_GAP apart) before it counts as failed.
local function send(msg, what, tries)
  tries = tries or 0
  local channel = (G.IsInRaid and G.IsInRaid()) and "RAID" or "PARTY"
  local last = tries >= SY.RETRIES
  local ok, reason, code = ns.Compat.sendAddon(ns.Team.PREFIX, msg, channel, what or "sync", last)
  if not ok and not last and (code == 3 or code == 8 or tostring(reason):find("Throttle", 1, true)) then
    after(SY.RETRY_GAP, function() send(msg, what, tries + 1) end)
  end
  return ok
end
local idN = 0
local function newId()
  idN = idN + 1
  local n = math.floor(((time and time()) or 0) % 100000) * 10 + idN % 10
  return string.format("%x", n % 0xFFFFF)
end

-- ------------------------------------------------------------------ sending
--- Offer the squad to the party (one click here; the others must click Review and Import there).
function SY.sendSquad(s)
  if not s then return false end
  if not ns.Compat.inParty() then Core().print("Join a party with your other characters first – the squad goes to your party."); return false end
  local str = Core().exportString(s)
  if not str then return false end
  local id, n = newId(), math.ceil(#str / SY.CHUNK)
  if n > SY.MAX_CHUNKS then Core().print("|cffff8a80This squad is too big to send.|r Use the Share tab and copy the string instead."); return false end
  for i = 1, n do
    local part = str:sub((i - 1) * SY.CHUNK + 1, i * SY.CHUNK)
    after((i - 1) * SY.GAP, function() send("Q|" .. id .. "|" .. i .. "|" .. n .. "|" .. part, "squad " .. i .. "/" .. n) end)
  end
  Core().log("info", "offered squad " .. s.name .. " to the party (" .. n .. " parts)")
  Core().print("Offered squad \"" .. s.name .. "\" to your party. Each client shows Review / Ignore – nothing changes there without a click.")
  return true
end
--- Tell the party this client switched preset (they get Apply / Ignore).
function SY.offerPreset(s, p)
  if not (s and p and ns.Compat.inParty()) then return false end
  local L = ns.State.member(s, p.leader)
  local ok = send("P|" .. s.id .. "|" .. p.id .. "|" .. clean(L and L.name or "?") .. "|" .. clean(p.name), "preset")
  Core().log("info", "offered preset " .. p.name)
  return ok
end

-- ------------------------------------------------------------------ receiving (offers only)
local function inParty(name) return ns.Squad.unitOf(name) ~= nil end
local function drop(sender, why) ns.Compat.drop("sync", sender, why) end

function SY.receive(text, sender)
  if type(text) ~= "string" or #text > 255 then return drop(sender, "too long or not text") end
  if not inParty(sender) then return drop(sender, "not in your party here (name not matched)") end -- only your own party
  local t = now()
  for k, v in pairs(SY.inbox) do if t - v.at > SY.TTL then SY.inbox[k] = nil end end
  local id, i, n, part = text:match("^Q|(%x+)|(%d+)|(%d+)|(.+)$")
  if id then
    i, n = tonumber(i), tonumber(n)
    if not (i and n) or n < 1 or n > SY.MAX_CHUNKS or i < 1 or i > n or #part > SY.CHUNK then return drop(sender, "bad squad chunk") end
    local key = (ns.Compat.nameKey(sender) or "?") .. ":" .. id
    local box = SY.inbox[key] or { n = n, parts = {}, got = 0, at = t }
    if box.n ~= n then return drop(sender, "squad chunk count changed") end
    if not box.parts[i] then box.parts[i] = part; box.got = box.got + 1 end
    box.at = t
    SY.inbox[key] = box
    if box.got == box.n then
      SY.inbox[key] = nil
      local str = table.concat(box.parts)
      local res, err = Core().importString(str)
      if not res then Core().log("warn", "squad from " .. sender .. " ignored: " .. tostring(err)); return end
      Core().log("info", "squad offer from " .. sender .. ": " .. res.squad.name)
      SY.offer({ kind = "squad", from = sender, str = str, name = res.squad.name, count = #res.squad.members })
    end
    return
  end
  local sid, pid, lname, pname = text:match("^P|(%w+)|(%w+)|([^|]+)|([^|]+)$")
  if sid then
    local s = ns.State.squad(Core().db, sid)
    local p = s and ns.State.preset(s, pid)
    if not p then return drop(sender, "preset of a squad or preset not on this client") end
    if s.activePreset == pid and ns.State.leaderOf(s) and ns.State.leaderOf(s).id == p.leader then return drop(sender, "preset already active") end
    Core().log("info", "preset offer from " .. sender .. ": " .. p.name)
    SY.offer({ kind = "preset", from = sender, squadId = sid, presetId = pid, name = p.name, leader = lname, sentName = pname })
    return
  end
  drop(sender, "unknown sync message")
end

-- ------------------------------------------------------------------ the offer card (one at a time)
local function card()
  if SY.frame then return SY.frame end
  local o = ns.Widgets.box(UIParent, 0.1, 0.09, 0.13, 0.96)
  o:SetFrameStrata("DIALOG")
  o:SetClampedToScreen(true)
  o:SetPoint("TOP", 0, -170)
  o.text = ns.Widgets.text(o, "GameFontHighlightSmall", nil, ns.Widgets.TEXT)
  o.text:SetPoint("TOPLEFT", 12, -10)
  o.text:SetPoint("TOPRIGHT", -12, -10)
  o.go = ns.Widgets.button(o, "Review", 90, 22, function() SY.accept() end, { "Review", function() return o.goTip end })
  o.go:SetPoint("BOTTOMRIGHT", -10, 8)
  o.no = ns.Widgets.button(o, "Ignore", 70, 22, function() SY.dismiss() end, "Closes this offer. Nothing changes.")
  o.no:SetPoint("RIGHT", o.go, "LEFT", -6, 0)
  o:Hide()
  _G.WoWBoxerOfferFrame = o
  SY.frame = o
  return o
end

function SY.show()
  local o = card()
  local x = SY.queue[1]
  if not x then o:Hide(); return end
  local text, go, goTip
  if x.kind == "squad" then
    text = "|cffffd100" .. x.from .. "|r shares |cffffd100\"" .. x.name .. "\"|r (" .. x.count .. ")"
    go, goTip = "Review", "Opens the import preview on the Share page. Nothing changes until you press Import squad there."
  elseif x.kind == "preset" then
    text = "|cffffd100" .. x.from .. "|r: |cffffd100\"" .. x.name .. "\"|r, " .. x.leader .. " leads"
    go, goTip = "Apply", "Makes " .. x.leader .. " the leader in WoWBoxer on this client. Your macros change after you press Update macros."
  elseif x.kind == "guide" then
    text, go, goTip = x.text, "Open guide", "Opens the 5-step squad guide on the Squad page."
  else
    text, go, goTip = x.text, "Open squad", "Opens the Squad page."
  end
  o.goTip = goTip
  o.text:SetText(text)
  ns.Widgets.setLabel(o.go, go)
  ns.Widgets.setLabel(o.no, (x.kind == "session" or x.kind == "guide") and "Close" or "Ignore")
  local maxW = math.min(460, (UIParent:GetWidth() or 800) * 0.9)
  local w = math.max(300, o.go:GetWidth() + o.no:GetWidth() + 26, math.min(maxW, ns.Widgets.measure(text, "GameFontHighlightSmall") + 24))
  o:SetWidth(w)
  o.text:SetWidth(w - 24)
  o:SetHeight(math.ceil(o.text:GetStringHeight() or 14) + 10 + 8 + 22 + 10)
  o:Show()
end
function SY.offer(x)
  -- one offer per sender and kind: a newer one replaces the older
  for i = #SY.queue, 1, -1 do local q = SY.queue[i]; if q.kind == x.kind and q.from == x.from then table.remove(SY.queue, i) end end
  SY.queue[#SY.queue + 1] = x
  SY.show()
end
function SY.dismiss()
  local x = table.remove(SY.queue, 1)
  if x and x.kind ~= "session" then Core().log("info", "ignored " .. x.kind .. " offer from " .. x.from) end
  SY.show()
end
--- The click on the offer card: Review (squad), Apply (preset) or Open squad (session card).
function SY.accept()
  local x = table.remove(SY.queue, 1)
  SY.show()
  if not x then return end
  if x.kind == "squad" then
    ns.UI.Open("share")
    local p = ns.UI.panels.share
    p.importBox:SetText(x.str)
    local h = p.importBox:GetScript("OnTextChanged")
    if h then h(p.importBox, true) end
    Core().log("info", "reviewing squad from " .. x.from)
  elseif x.kind == "preset" then
    local s = ns.State.squad(Core().db, x.squadId)
    if s and ns.State.applyPreset(s, x.presetId) then
      Core().log("info", "applied preset " .. x.name .. " from " .. x.from)
      Core().print("Preset \"" .. x.name .. "\" applied. Press Update macros to change your macros.")
      Core().changed()
    end
  elseif x.kind == "guide" then
    if ns.Help then ns.Help.ShowSquadGuide() end
  else
    ns.UI.Open("squad")
  end
end

-- ------------------------------------------------------------------ session card + version check (display only)
--- "Squad Undead trio · 3/3 online · macros OK on 2/3 · Wowtwo needs Update", or nil when solo.
function SY.sessionText()
  local s = Core().me()
  if not (s and #s.members > 1 and ns.Compat.inParty()) then return nil end
  local rows = ns.Squad.readiness()
  local online, ok, need, other = 0, 0, {}, {}
  local myVer = ns.Team.version()
  for _, r in ipairs(rows) do
    if r.signal then online = online + 1 end
    if r.ready and r.ready.keys == 0 then ok = ok + 1 elseif r.ready then need[#need + 1] = r.m.name end
    if r.version and r.version ~= myVer and not r.me then other[#other + 1] = r.m.name end
  end
  local text = "Squad |cffffd100" .. s.name .. "|r · " .. online .. "/" .. #rows .. " online · macros OK on " .. ok .. "/" .. #rows
  if #need > 0 then text = text .. " · " .. table.concat(need, ", ") .. (#need == 1 and " needs" or " need") .. " Update macros" end
  if #other > 0 then text = text .. " · |cfff0b43c" .. table.concat(other, ", ") .. " run another WoWBoxer version|r" end
  return text
end
function SY.sessionCard()
  local text = SY.sessionText()
  if not text then return false end
  SY.offer({ kind = "session", from = "", text = text })
  return true
end

function SY.Init()
  after(20, function() if ns.Team.active() then SY.sessionCard() end end)
end

return SY
