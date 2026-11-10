--[[ WoWBoxer – the same settings on all your characters (bug sweep 9 Nov 2026).
  WoWBoxer's settings live in WoWBoxerDB, which the game keeps per WoW ACCOUNT. A multiboxer has one account per
  character, so "Advanced on" on Rip's account is not on for Rup and Rap. After the player changes a setting, a small
  card offers "Use the same on my other characters"; Send to my other characters offers them too. The others get an
  offer card and use them only after a click.
  Rule 2: a settings message is data only – every value is checked against this list; unknown keys and values are
  dropped. "Accept from: Everyone" never travels (like the share string), nor does anything outside the list. ]]
local _, ns = ...
local ST = {}
ns.Settings = ST

local G = _G
local function Core() return ns.Core end
local function AU() return ns.Auto end
local function st() return Core().db.settings end
local function cdb() return Core().cdb end
local function now() return (G.GetTime and G.GetTime()) or 0 end

ST.SCALES = { 0.7, 0.8, 0.9, 1, 1.1, 1.2, 1.3 }
local FROM_OK = { squad = true, friends = true }
local function b2s(v) return v and "1" or "0" end
local function s2b(v) if v == "1" then return true elseif v == "0" then return false end return nil end

--- The settings that travel: {key, label, get() -> text, set(text) -> ok, show(text) -> words}. Text values only.
ST.ITEMS = {
  { "adv", "Advanced mode", function() return b2s(st().advanced == true) end,
    function(v) local b = s2b(v); if b == nil then return false end st().advanced = b and true or nil; return true end,
    function(v) return v == "1" and "Advanced" or "Standard" end },
  -- one switch for team messages and the team box (1.3.0; the old "tf" window switch is gone, an old "tf" is dropped)
  { "team", "Team status", function() return b2s(st().team ~= false) end,
    function(v) local b = s2b(v); if b == nil then return false end st().team = b and nil or false; return true end },
  { "anim", "Animations", function() return b2s(st().animations ~= false) end,
    function(v) local b = s2b(v); if b == nil then return false end st().animations = b; return true end },
  { "strip", "Sequence strip", function() return b2s(st().seqStrip ~= false) end,
    function(v) local b = s2b(v); if b == nil then return false end st().seqStrip = b; return true end },
  { "mm", "Minimap button", function() return b2s(not st().minimapHidden) end,
    function(v) local b = s2b(v); if b == nil then return false end
      if ns.Minimap and ns.Minimap.SetHidden then ns.Minimap.SetHidden(not b) else st().minimapHidden = (not b) or nil end
      return true end },
  { "scale", "Window size", function() local x = tonumber(st().scale) or 1; return string.format("%.1f", math.floor(x * 10 + 0.5) / 10) end,
    function(v) local x = tonumber(v); if not x then return false end
      for _, s in ipairs(ST.SCALES) do if math.abs(s - x) < 0.01 then st().scale = s; return true end end
      return false end,
    function(v) return math.floor((tonumber(v) or 1) * 100 + 0.5) .. " %" end },
  { "rem", "Level-up reminders", function() return b2s(cdb().reminders ~= false) end,
    function(v) local b = s2b(v); if b == nil then return false end cdb().reminders = ns.State.offOrNil(b); return true end },
  -- the extra-line switches of this character (#help 10 Nov): the lines switched OFF, "" = all on
  { "ln", "Extra lines in macros", function()
      local _, me = Core().me()
      if not me then return "" end
      local off = {}
      for _, x in ipairs(ns.Macros.LINES) do if not ns.Macros.lineOn(x.key, me.lines, me) then off[#off + 1] = x.key end end
      return table.concat(off, ",") end,
    function(v)
      if type(v) ~= "string" or v:find("[^%a,]") then return false end
      local _, me = Core().me()
      if not me then return false end
      local off = {}
      for k in v:gmatch("[^,]+") do if ns.Macros.LINE_BY[k] then off[k] = true end end
      local t = {}
      for _, x in ipairs(ns.Macros.LINES) do if x.key ~= "assist" and off[x.key] then t[x.key] = false end end
      me.lines = ns.State.cleanLines(t)
      me.assist = ns.State.offOrNil(not off.assist)
      return true end,
    function(v)
      if v == "" then return "all on" end
      local names = {}
      for k in tostring(v):gmatch("[^,]+") do local x = ns.Macros.LINE_BY[k]; if x then names[#names + 1] = x.short end end
      return table.concat(names, ", ") .. " off" end },
  { "ask", "Ask to replace buttons", function() return b2s(cdb().askReplace ~= false) end,
    function(v) local b = s2b(v); if b == nil then return false end cdb().askReplace = b; return true end },
  { "from", "Accept from", function() local f = st().acceptFrom; return FROM_OK[f] and f or (f == nil and "squad" or "") end,
    function(v) if not FROM_OK[v] then return false end st().acceptFrom = v; return true end,
    function(v) return AU().FROM_SHORT[v] or v end },
  { "rew", "Quest reward", function() return AU().rewardRule() end,
    function(v) for _, r in ipairs(AU().REWARD_RULES) do if r == v then st().autoReward = v; return true end end return false end },
  { "auto", "Automation", function()
      local on = {}
      for _, o in ipairs(AU().OPTIONS) do if AU().on(o[1]) then on[#on + 1] = o[1] end end
      return table.concat(on, ",") end,
    function(v)
      if type(v) ~= "string" or v:find("[^%w,]") then return false end
      local want = {}
      for k in v:gmatch("[^,]+") do if AU().BY_KEY[k] then want[k] = true end end
      for _, o in ipairs(AU().OPTIONS) do AU().set(o[1], want[o[1]] == true) end
      return true end,
    function(v) local n = 0; for _ in tostring(v):gmatch("[^,]+") do n = n + 1 end return n .. " on" end },
  -- after "auto" (its on/off for abandon is Automatically or not; this is the full choice)
  { "abd", "Abandon together", function() return AU().abandonMode() end,
    function(v) return AU().setAbandonMode(v) end,
    function(v) for _, m in ipairs(AU().ABANDON_MODES) do if m[1] == v then return m[2] end end return v end },
  { "ov", "Accept from per row", function()
      local t, out = st().acceptOverride, {}
      if type(t) == "table" then
        local keys = {}
        for k in pairs(AU().ACCEPTS) do keys[#keys + 1] = k end
        table.sort(keys)
        for _, k in ipairs(keys) do if FROM_OK[t[k]] then out[#out + 1] = k .. ":" .. t[k] end end
      end
      return table.concat(out, ",") end,
    function(v)
      if type(v) ~= "string" or v:find("[^%w,:]") then return false end
      local t = {}
      for k, f in v:gmatch("(%w+):(%w+)") do if AU().ACCEPTS[k] and FROM_OK[f] then t[k] = f end end
      -- an "Everyone" row on this client stays (it never travels, so it is never taken away either)
      local old = st().acceptOverride
      if type(old) == "table" then for k, f in pairs(old) do if f == "everyone" and t[k] == nil then t[k] = f end end end
      st().acceptOverride = next(t) and t or nil
      return true end,
    function(v) local n = 0; for _ in tostring(v):gmatch("[^,]+") do n = n + 1 end return n == 0 and "none" or (n .. " row(s)") end },
}
ST.BY_KEY = {}
for _, it in ipairs(ST.ITEMS) do ST.BY_KEY[it[1]] = it end
ST.MAX = 900 -- characters (a settings text is about 250)

--- My settings as one text: "adv=1;team=1;…" (data only).
function ST.encode()
  local parts = {}
  for _, it in ipairs(ST.ITEMS) do
    local ok, v = pcall(it[3])
    if ok and type(v) == "string" and (v ~= "" or it[1] == "auto" or it[1] == "ov" or it[1] == "ln") then parts[#parts + 1] = it[1] .. "=" .. v end
  end
  return table.concat(parts, ";")
end
--- A settings text -> {key = value} with only known keys and plain values; nil when it is not one.
function ST.decode(text)
  if type(text) ~= "string" or #text > ST.MAX or text:find("[|\n\r]") then return nil end
  local t, n = {}, 0
  for k, v in text:gmatch("([%w]+)=([^;]*)") do
    if ST.BY_KEY[k] and #v <= 400 then t[k] = v; n = n + 1 end
  end
  if n == 0 then return nil end
  return t
end
--- What would change here: {{label, from, to}} (words), for the offer card and the log.
function ST.diff(t)
  local out = {}
  for _, it in ipairs(ST.ITEMS) do
    local v = t[it[1]]
    if v ~= nil then
      local ok, cur = pcall(it[3])
      if ok and cur ~= v then
        local show = it[5] or function(x) return x == "1" and "on" or x == "0" and "off" or x end
        out[#out + 1] = { it[2], show(cur), show(v), key = it[1] }
      end
    end
  end
  return out
end
--- Use these settings here (the player clicked Use them). Returns how many changed.
function ST.apply(t, from)
  local n = 0
  for _, it in ipairs(ST.ITEMS) do
    local v = t[it[1]]
    if v ~= nil then
      local okC, cur = pcall(it[3])
      if not okC or cur ~= v then
        local ok, done = pcall(it[4], v)
        if ok and done then n = n + 1 else Core().log("warn", "settings from " .. tostring(from) .. ": " .. it[1] .. " not used") end
      end
    end
  end
  ST.base = ST.encode() -- what we just took is not a change to offer back
  Core().log("info", "settings from " .. tostring(from) .. " used: " .. n .. " changed")
  if ns.UI and ns.UI.ApplyWindowSettings then pcall(ns.UI.ApplyWindowSettings) end
  if ns.TeamFrame and ns.TeamFrame.Refresh then pcall(ns.TeamFrame.Refresh) end
  if ns.SeqStrip then ns.SeqStrip.markDirty(); if ns.SeqStrip.request then ns.SeqStrip.request() end end
  Core().changed()
  return n
end

-- ------------------------------------------------------------------ sending (one click)
--- Send my settings to the squad in the party. Each client shows an offer card. Returns ok.
function ST.send(quiet)
  if not ns.Compat.inParty() then
    if not quiet then Core().print("Join a party with your other characters first – the settings go to your party.") end
    return false
  end
  local ok = ns.Sync.sendChunks("G", ST.encode(), "settings")
  ST.base = ST.encode()
  if ok then
    Core().log("info", "offered settings to the party")
    if not quiet then Core().print("Sent your WoWBoxer settings to your party. Each character shows Use them / Ignore – nothing changes there without a click.") end
  end
  return ok
end
--- A settings offer arrived (Sync joined the parts). Only from a squad member in the party.
function ST.received(text, sender)
  local who = AU().member(sender, true)
  if not who then return ns.Compat.drop("settings", sender, "not a squad member in your party") end
  local t = ST.decode(text)
  if not t then return ns.Compat.drop("settings", sender, "not a settings message") end
  local d = ST.diff(t)
  if #d == 0 then Core().log("info", "settings from " .. tostring(sender) .. ": already the same"); return end
  local words = {}
  for i, x in ipairs(d) do if i <= 4 then words[#words + 1] = x[1] .. " " .. x[3] end end
  if #d > 4 then words[#words + 1] = (#d - 4) .. " more" end
  Core().log("info", "settings offer from " .. tostring(sender) .. ": " .. #d .. " change(s)")
  ns.Sync.offer({ kind = "settings", from = who.name, t = t, n = #d, text = table.concat(words, ", "), diff = d })
end

-- ------------------------------------------------------------------ the question after a change
ST.DELAY = 2     -- seconds after the last change
ST.base = nil    -- my settings when they were last offered, taken or loaded
--- Called after the player changed something (Core.changed, window settings): offer to copy the settings once they
--- settle. Only in a party with a squad of two or more (else there is nobody to send them to).
function ST.check()
  if not (Core().db and Core().cdb) then return end
  local ok, sig = pcall(ST.encode)
  if not ok then return end
  if ST.base == nil then ST.base = sig; return end
  if sig == ST.base then return end
  ST.changedAt = now()
  if ST.pending then return end
  ST.pending = true
  local function fire()
    ST.pending = false
    local ok2, cur = pcall(ST.encode)
    if not ok2 or cur == ST.base then return end
    if now() - (ST.changedAt or 0) < ST.DELAY - 0.05 and G.C_Timer and G.C_Timer.After then
      ST.pending = true; G.C_Timer.After(ST.DELAY, fire); return
    end
    ST.base = cur
    ST.ask()
  end
  if G.C_Timer and G.C_Timer.After then G.C_Timer.After(ST.DELAY, fire) else fire() end
end
function ST.ask()
  if not (ns.Team.active() and ns.Sync) then return false end
  ns.Sync.offer({ kind = "push", from = "", text = "You changed WoWBoxer settings. Use the same on your other characters?" })
  return true
end

function ST.Init() ST.base = select(2, pcall(ST.encode)) end

return ST
