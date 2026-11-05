--[[ WoWBoxer – "Report a problem": builds a plain-text report the player copies (Ctrl+C) and pastes in #setup-help on
  Discord. Read-only: it never sends anything anywhere (no addon messages, no chat channels, no files) and changes
  nothing in the game. Without "include names" every character, realm and squad name is replaced, also in the log. ]]
local _, ns = ...
local RP = {}
ns.Report = RP

local G = _G
RP.LOG_LINES = 30
RP.LINE_MAX = 180
RP.MAX_ADDONS = 80
RP.MAX_LEN = 9000

local function Core() return ns.Core end
local function C() return ns.Compat end
local function cut(s, n) s = tostring(s or ""); if #s > n then return s:sub(1, n - 1) .. "…" end return s end

--- Every enabled (loaded) addon: {{name, version}} by name, at most RP.MAX_ADDONS.
function RP.addons()
  local A = G.C_AddOns
  local num = (A and A.GetNumAddOns) or G.GetNumAddOns
  local info = (A and A.GetAddOnInfo) or G.GetAddOnInfo
  local loaded = (A and A.IsAddOnLoaded) or G.IsAddOnLoaded
  local meta = (A and A.GetAddOnMetadata) or G.GetAddOnMetadata
  local out = {}
  if not (num and info) then return out end
  local ok, n = pcall(num)
  for i = 1, (ok and tonumber(n)) or 0 do
    local ok2, name = pcall(info, i)
    if ok2 and type(name) == "string" then
      local okl, isOn = true, true
      if loaded then okl, isOn = pcall(loaded, name) end
      if okl and isOn then
        local okv, v = false, nil
        if meta then okv, v = pcall(meta, name, "Version") end
        out[#out + 1] = { name, (okv and type(v) == "string" and not v:find("@", 1, true)) and cut(v, 30) or "?" }
      end
    end
  end
  table.sort(out, function(a, b) return a[1]:lower() < b[1]:lower() end)
  while #out > RP.MAX_ADDONS do table.remove(out) end
  return out
end

--- The names to hide: this character, its realm, every squad member and every party member.
function RP.names()
  local list = {}
  local function add(n) if type(n) == "string" and #n >= 2 then list[#list + 1] = n end end
  local info = Core().playerInfo() or {}
  add(info.name)
  add(G.GetRealmName and G.GetRealmName())
  local s = Core().me()
  for _, m in ipairs(s and s.members or {}) do add(m.name) end
  for _, sq in ipairs((Core().db and Core().db.squads) or {}) do
    if type(sq) == "table" then add(sq.name); for _, m in ipairs(sq.members or {}) do add(m.name) end end
  end
  for i = 1, 4 do add(C().unitName("party" .. i)) end
  table.sort(list, function(a, b) return #a > #b end) -- "Dorin-Realm" before "Dorin"
  return list
end
--- Replace each name (whole word, any case) with <name>; the realm with <realm>. A letter or digit (or a UTF-8 byte)
--- right before or after means it is part of another word ("Bo" in "Bottom") and stays.
local function wordChar(c) return c ~= "" and (c:find("^%w") ~= nil or c:byte() >= 128) end
function RP.redact(text, names)
  local realm = G.GetRealmName and G.GetRealmName()
  for _, n in ipairs(names) do
    local low, ln, out, i = text:lower(), n:lower(), {}, 1
    local rep = n == realm and "<realm>" or "<name>"
    while true do
      local a, b = low:find(ln, i, true)
      if not a then break end
      if not wordChar(text:sub(a - 1, a - 1)) and not wordChar(text:sub(b + 1, b + 1)) then
        out[#out + 1] = text:sub(i, a - 1); out[#out + 1] = rep
      else out[#out + 1] = text:sub(i, b) end
      i = b + 1
    end
    out[#out + 1] = text:sub(i)
    text = table.concat(out)
  end
  return text
end

--- The report as one string. opts = {what = "what happened", names = true to keep names}.
function RP.build(opts)
  opts = opts or {}
  local core = Core()
  local db, cdb = core.db or {}, core.cdb or {}
  local st = db.settings or {}
  local L = {}
  local function add(s) L[#L + 1] = s end
  add("WoWBoxer problem report")
  add("What happened: " .. cut((opts.what and opts.what ~= "") and opts.what or "(please describe it here)", 400))
  add("")
  add("WoWBoxer: " .. (core.addonVersion() or core.VERSION))
  local ver, build, _, toc = "?", "?", nil, C().interface()
  if G.GetBuildInfo then ver, build, _, toc = G.GetBuildInfo() end
  add("Game: " .. C().game() .. " " .. tostring(ver) .. " (build " .. tostring(build) .. ") · interface " .. tostring(toc) ..
    " · locale " .. tostring(G.GetLocale and G.GetLocale() or "?"))
  local info = core.playerInfo() or {}
  local cls = ns.Data and ns.Data.classes[info.cls or ""]
  local s, m = core.me()
  local who = (cls and cls.n or tostring(info.cls)) .. " " .. tostring(info.level)
  if m then
    who = who .. " · " .. tostring(ns.State.ROLE_NAME[m.role] or m.role) .. " · " .. (m.leader and "leader" or ("follower via " .. tostring(m.unit)))
    local slot = ns.State.slotOf and ns.State.slotOf(s, m)
    who = who .. " · squad slot " .. tostring(slot or "?") .. " of " .. #s.members
  else who = who .. " · no squad yet" end
  if opts.names then who = who .. " · " .. tostring(core.charKey) end
  add("Character: " .. who)
  local pw, ph
  if G.GetPhysicalScreenSize then pw, ph = G.GetPhysicalScreenSize() end
  local ui = G.UIParent and G.UIParent.GetEffectiveScale and G.UIParent:GetEffectiveScale()
  add(string.format("Screen: %s x %s · UI scale %.2f · window size %s", tostring(pw or "?"), tostring(ph or "?"), tonumber(ui) or 0, tostring(st.scale or 1)))
  local auto = {}
  if ns.Auto then for _, o in ipairs(ns.Auto.OPTIONS) do if ns.Auto.on(o[1]) then auto[#auto + 1] = o[1] end end end
  add("Settings: " .. table.concat({
    "mode " .. (st.advanced and "Advanced" or "Standard"),
    "main bar " .. tostring(cdb.primaryBar or "-"), "other bar " .. tostring(cdb.secondaryBar or "-"),
    "ask to replace " .. (cdb.askReplace ~= false and "on" or "off"),
    "sequence " .. tostring(m and m.seq or "-"),
    "accept from " .. tostring(st.acceptFrom or "squad"),
    "automation " .. (#auto > 0 and table.concat(auto, ",") or "off"),
    "reminders " .. (st.reminders == false and "off" or "on"),
  }, " · "))
  local ac, cc = C().numMacros()
  local am, cm = C().macroLimits()
  local wbx = 0
  if G.GetMacroInfo then
    for i = 1, am + cm do local n = G.GetMacroInfo(i); if type(n) == "string" and n:sub(1, 3) == "WBX" then wbx = wbx + 1 end end
  end
  add("Macros: character " .. cc .. "/" .. cm .. " · account " .. ac .. "/" .. am .. " · WBX macros " .. wbx)
  local q = {}
  for _, x in ipairs(core.queue or {}) do q[#q + 1] = x.label end
  add("Waiting until combat ends: " .. (#q > 0 and table.concat(q, ", ") or "nothing") .. (C().inCombat() and " (in combat now)" or ""))
  add("")
  local log = db.log or {}
  add("Log (last " .. math.min(RP.LOG_LINES, #log) .. "):")
  for i = math.max(1, #log - RP.LOG_LINES + 1), #log do
    local e = log[i]
    local t = G.date and G.date("%H:%M:%S", e.t) or tostring(e.t)
    add(" " .. t .. " " .. tostring(e.l) .. ": " .. cut(e.m, RP.LINE_MAX))
  end
  add("")
  local list = RP.addons()
  local names = {}
  for _, a in ipairs(list) do names[#names + 1] = a[1] .. " " .. a[2] end
  add("Addons (" .. #list .. " loaded): " .. table.concat(names, ", "))
  local text = table.concat(L, "\n")
  if not opts.names then text = RP.redact(text, RP.names()) end
  if #text > RP.MAX_LEN then text = text:sub(1, RP.MAX_LEN - 20) .. "\n… (report cut)" end
  return text
end
