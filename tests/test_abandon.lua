-- Abandon together (owner, 10 Nov 2026): a dropdown Automatically · Ask on every quest · Never (default Ask), stored as
-- settings.auto.abandonMode; the old on/off key is read until the mode is first set. Follower: each mode × has the quest /
-- lacks it / quest complete / Shift held / sender not the squad leader. Leader: both hook paths (Era globals, Forever
-- C_QuestLog), the quest captured on SetAbandonQuest, one QA per abandon.
local dir = (arg[0]:match("^(.*)/[^/]+$") or ".")
local H = dofile(dir .. "/harness.lua")
local Mock = dofile(dir .. "/wowmock.lua")

local PAL = { class = "PALADIN", race = "Scourge", level = 20 }
local HUN = { class = "HUNTER", race = "Orc", level = 20 }

--- A quest log the abandon calls work on. modern = Forever (C_QuestLog), else Era (globals). quests = {{id, title, complete}}.
local function questLog(W, modern, quests)
  local L = { quests = quests, calls = {} }
  local env = W.env
  local function rec(s) L.calls[#L.calls + 1] = s end
  local function byId(id) for i, q in ipairs(L.quests) do if q[1] == id then return i, q end end end
  if modern then
    env.C_QuestLog = {
      GetLogIndexForQuestID = function(id) return (byId(id)) end,
      IsComplete = function(id) local _, q = byId(id); return q and q[3] or false end,
      GetTitleForQuestID = function(id) local _, q = byId(id); return q and q[2] end,
      SetSelectedQuest = function(id) L.sel = id; rec("SetSelectedQuest(" .. id .. ")") end,
      GetSelectedQuest = function() return L.sel end,
      SetAbandonQuest = function() L.abandoning = L.sel; rec("SetAbandonQuest") end,
      GetAbandonQuest = function() return L.abandoning or 0 end,
      AbandonQuest = function()
        rec("AbandonQuest(" .. tostring(L.abandoning) .. ")")
        local i = byId(L.abandoning)
        if i then table.remove(L.quests, i) end
        L.abandoning = nil -- the client forgets it once it is gone
      end,
    }
    -- Forever keeps the old global as a wrapper: both functions are hooked, the leader must still send once
    env.AbandonQuest = function() return env.C_QuestLog.AbandonQuest() end
    env.SetAbandonQuest, env.GetAbandonQuestName, env.SelectQuestLogEntry, env.GetQuestLogSelection = nil, nil, nil, nil
    env.GetNumQuestLogEntries, env.GetQuestLogTitle = nil, nil
  else
    env.C_QuestLog = nil
    env.GetNumQuestLogEntries = function() return #L.quests end
    env.GetQuestLogTitle = function(i) local q = L.quests[i]; if q then return q[2], 10, nil, false, false, q[3] and 1 or nil, nil, q[1] end end
    env.SelectQuestLogEntry = function(i) L.sel = i; rec("SelectQuestLogEntry(" .. i .. ")") end
    env.GetQuestLogSelection = function() return L.sel or 0 end
    env.SetAbandonQuest = function() L.abandoning = L.sel; rec("SetAbandonQuest") end
    env.GetAbandonQuestName = function() local q = L.abandoning and L.quests[L.abandoning]; return q and q[2] or "" end
    env.AbandonQuest = function()
      local q = L.abandoning and L.quests[L.abandoning]
      rec("AbandonQuest(" .. tostring(q and q[2]) .. ")")
      if q then table.remove(L.quests, L.abandoning) end
      L.abandoning = nil
    end
  end
  function L.has(id) return byId(id) ~= nil end
  function L.abandoned() for _, c in ipairs(L.calls) do if c:find("^AbandonQuest") then return c end end end
  function L.reset() L.calls = {} end
  return L
end

--- hooksecurefunc that really hooks (the mock's is a no-op).
local function realHooks(env)
  env.hooksecurefunc = function(a, b, c)
    local t, name, fn = env, a, b
    if type(a) == "table" then t, name, fn = a, b, c end
    local orig = t[name]
    t[name] = function(...) orig(...); fn(...) end
  end
end

local function boot(me, modern, quests, setup)
  local W = Mock.new(H, { name = me, class = me == "Dorin" and "PALADIN" or "PRIEST", race = "Scourge", level = 20,
    party = me == "Dorin" and { party1 = "Anna", party2 = "Bo" } or { party1 = "Dorin", party2 = "Bo" },
    partyInfo = me == "Dorin" and { party1 = { class = "PRIEST", race = "Scourge", level = 20 }, party2 = HUN } or { party1 = PAL, party2 = HUN } })
  realHooks(W.env)
  local L = questLog(W, modern, quests)
  if setup then setup(W) end
  local ns = H.loadAddon({ env = W.env })
  W.fire("ADDON_LOADED", "WoWBoxer"); W.fire("PLAYER_LOGIN")
  local sq = ns.State.newSquad({ name = "Trio", members = {
    { name = "Dorin", cls = "paladin", race = "undead", role = "tank", leader = true },
    { name = "Anna", cls = "priest", race = "undead", role = "healer", unit = "party1" },
    { name = "Bo", cls = "hunter", race = "orc", role = "ranged", unit = "party1" } } })
  ns.Core.db.squads = { sq }; ns.Core.db.active = sq.id
  return W, ns, L
end
local function msg(W, from, text) W.fire("CHAT_MSG_ADDON", "WBXA", text, "PARTY", from) end
local function lastLog(ns) local l = ns.Core.db.log; return l[#l] and l[#l].m or "" end
local function popupShown(ns) return ns.UI.popup and ns.UI.popup:IsShown() end
local function closePopup(ns) if ns.UI.popup then ns.UI.popup:Hide() end end

-- ------------------------------------------------------------------ the setting: default, migration, dropdown
do
  local W, ns = boot("Anna", false, {})
  local AU = ns.Auto
  H.eq(AU.abandonMode(), "ask", "default: Ask on every quest")
  H.ok(not AU.on("abandon"), "Ask does not count as an automation that is on")
  local s = ns.Core.db.settings
  s.auto = { abandon = true }
  H.eq(AU.abandonMode(), "auto", "old abandon = true reads as Automatically")
  H.eq(s.auto.abandon, true, "reading never rewrites the saved data (a login keeps it as it was)")
  s.auto = { abandon = false }
  H.eq(AU.abandonMode(), "ask", "old abandon = false reads as Ask")
  s.auto = {}
  H.eq(AU.abandonMode(), "ask", "no old key: Ask")
  s.auto = { abandon = true }
  H.ok(AU.setAbandonMode("never"), "set a mode")
  H.ok(s.auto.abandonMode == "never" and s.auto.abandon == nil, "the first set stores abandonMode and drops the old key")
  H.ok(not AU.setAbandonMode("evil"), "an unknown mode is refused")
  H.eq(AU.abandonMode(), "never", "and changes nothing")
  s.auto = { abandonMode = "bogus", abandon = true }
  H.eq(AU.abandonMode(), "auto", "a broken abandonMode falls back to the old key")
  -- share strings and the settings list still carry the old on/off: on = Automatically, off keeps Ask / Never
  AU.setAbandonMode("never"); AU.set("abandon", false)
  H.eq(AU.abandonMode(), "never", "off keeps Never")
  AU.set("abandon", true)
  H.eq(AU.abandonMode(), "auto", "on = Automatically")
  AU.set("abandon", false)
  H.eq(AU.abandonMode(), "ask", "off after Automatically = Ask")
  AU.setAll(true); H.eq(AU.abandonMode(), "auto", "All on: Automatically")
  AU.setAll(false); H.eq(AU.abandonMode(), "never", "All off: Never")
  AU.defaults(); H.eq(AU.abandonMode(), "ask", "Default: Ask on every quest")
  AU.setAll(true); AU.preset(); H.eq(AU.abandonMode(), "ask", "Default squad values: Ask on every quest")
  -- the settings list sends the full choice
  local enc = ns.Settings.encode and ns.Settings.encode()
  if enc then H.ok(enc:find("abd=ask", 1, true), "the settings list carries abd=ask") end
  -- Automation page: a dropdown card with one line for the chosen value
  ns.UI.Open("automation")
  local p = ns.UI.panels.automation
  local dd = p.abandon and p.abandon.dd
  if H.ok(dd ~= nil, "Automation page: Abandon together is a dropdown") then
    H.ok(p.abandon.label:GetText() == "Abandon together", "its name")
    local vals = dd.opts.values()
    H.eq(#vals, 3, "three choices")
    H.eq(vals[1][2] .. "|" .. vals[2][2] .. "|" .. vals[3][2], "Automatically|Ask on every quest|Never", "the labels")
    H.eq(dd.opts.get(), "ask", "shows Ask on every quest")
    H.eq(p.abandon.line:GetText(), "Each follower asks: Abandon or Keep it.", "the line says what Ask does")
    dd.select("auto")
    H.ok(AU.abandonMode() == "auto" and p.abandon.line:GetText() == "Followers abandon it too, without asking.", "choosing Automatically")
    dd.select("never")
    H.ok(AU.abandonMode() == "never" and p.abandon.line:GetText() == "Followers keep the quest.", "choosing Never")
    for _, v in ipairs(vals) do H.ok(v[3] and #v[3] > 0, "each choice has its sentence: " .. v[2]) end
  end
  for _, c in ipairs(p.ticks) do H.ok(c.key ~= "abandon", "no on/off tick for Abandon together: " .. c.key) end
end

-- ------------------------------------------------------------------ follower: each mode × each case, both games
for _, modern in ipairs({ false, true }) do
  local game = modern and "Forever" or "Era"
  local function follower(mode, quests)
    local W, ns, L = boot("Anna", modern, quests)
    ns.Auto.setAbandonMode(mode)
    return W, ns, L
  end
  local QUESTS = function() return { { 101, "Wolves", false }, { 102, "Done Deal", true } } end

  -- Automatically
  do
    local W, ns, L = follower("auto", QUESTS())
    msg(W, "Dorin", "QA|101|Wolves")
    H.ok(L.abandoned() and not L.has(101) and not popupShown(ns), game .. " auto: has it → abandoned, no question")
    H.ok(lastLog(ns):find("auto: Abandoned", 1, true), game .. " auto: one log line")
    L.reset(); msg(W, "Dorin", "QA|103|Bears")
    H.eq(L.abandoned(), nil, game .. " auto: lacks it → nothing")
    msg(W, "Dorin", "QA|102|Done Deal")
    H.ok(L.abandoned() == nil and L.has(102), game .. " auto: a completed quest is never abandoned")
    L.quests[#L.quests + 1] = { 104, "Boars", false }
    W.mods.shift = true; msg(W, "Dorin", "QA|104|Boars"); W.mods.shift = false
    H.ok(L.abandoned() == nil and L.has(104) and lastLog(ns):find("skipped (Shift held)", 1, true), game .. " auto: Shift held → skipped")
    msg(W, "Stranger", "QA|104|Boars")
    H.ok(L.has(104), game .. " auto: a stranger's message is ignored")
    msg(W, "Bo", "QA|104|Boars")
    H.ok(L.has(104), game .. " auto: a squad member who is not the leader is ignored")
    ns.Core.db.settings.auto.chat = true
    msg(W, "Dorin", "QA|104|Boars")
    H.ok(not L.has(104), game .. " auto: the leader's message drops it")
  end

  -- Ask on every quest
  do
    local W, ns, L = follower("ask", QUESTS())
    L.quests[#L.quests + 1] = { 105, "Murlocs", false }
    msg(W, "Stranger", "QA|101|Wolves")
    H.ok(not popupShown(ns), game .. " ask: a stranger → no question")
    msg(W, "Bo", "QA|101|Wolves")
    H.ok(not popupShown(ns), game .. " ask: not the leader → no question")
    msg(W, "Dorin", "QA|103|Bears")
    H.ok(not popupShown(ns), game .. " ask: lacks it → no question")
    msg(W, "Dorin", "QA|102|Done Deal")
    H.ok(not popupShown(ns), game .. " ask: completed → no question")
    W.mods.shift = true; msg(W, "Dorin", "QA|101|Wolves"); W.mods.shift = false
    H.ok(not popupShown(ns) and L.has(101), game .. " ask: Shift held → skipped")
    msg(W, "Dorin", "QA|101|Wolves")
    H.ok(popupShown(ns), game .. " ask: has it → the question")
    H.eq(ns.UI.popup.text:GetText(), "Dorin abandoned Wolves. Abandon it here too?", game .. " ask: the text")
    H.eq(L.abandoned(), nil, game .. " ask: nothing happens before the click")
    local b = ns.UI.popup.btns
    H.ok(b[1]:GetText() == "Abandon" and b[2]:GetText() == "Keep it" and not b[3]:IsShown(), game .. " ask: Abandon / Keep it")
    -- a second one waits (one at a time, queued); the same quest twice is asked once
    msg(W, "Dorin", "QA|105|Murlocs"); msg(W, "Dorin", "QA|105|Murlocs")
    H.eq(ns.UI.popup.text:GetText(), "Dorin abandoned Wolves. Abandon it here too?", game .. " ask: the next one waits")
    b[1]:Click()
    H.ok(not L.has(101) and L.abandoned(), game .. " ask: Abandon drops it on that click")
    H.ok(popupShown(ns) and ns.UI.popup.text:GetText():find("Murlocs", 1, true), game .. " ask: then the queued one")
    L.reset()
    ns.UI.popup.btns[2]:Click()
    H.ok(L.has(105) and L.abandoned() == nil and not popupShown(ns), game .. " ask: Keep it keeps it")
    H.ok(lastLog(ns):find("kept Murlocs", 1, true), game .. " ask: one log line for Keep it")
    -- in combat: waits, then asks
    W.combat = true
    msg(W, "Dorin", "QA|105|Murlocs")
    H.ok(not popupShown(ns), game .. " ask: in combat → waits")
    W.combat = false; W.flush()
    H.ok(popupShown(ns), game .. " ask: after combat → the question")
    -- the quest is completed (or gone) before the click: nothing is abandoned
    L.quests[#L.quests][3] = true
    ns.UI.popup.btns[1]:Click()
    H.ok(L.has(105) and L.abandoned() == nil, game .. " ask: completed meanwhile → kept")
    -- while another WoWBoxer question is open
    L.quests[#L.quests][3] = false
    ns.UI.Popup("Another question", { { "OK", function() end } })
    msg(W, "Dorin", "QA|105|Murlocs")
    H.eq(ns.UI.popup.text:GetText(), "Another question", game .. " ask: waits for the open question")
    closePopup(ns); W.flush()
    H.ok(popupShown(ns) and ns.UI.popup.text:GetText():find("Murlocs", 1, true), game .. " ask: then asks")
    closePopup(ns)
  end

  -- Never
  do
    local W, ns, L = follower("never", QUESTS())
    msg(W, "Dorin", "QA|101|Wolves")
    H.ok(L.has(101) and L.abandoned() == nil and not popupShown(ns), game .. " never: has it → kept, no question")
    H.ok(lastLog(ns):find("kept here (Abandon together: Never)", 1, true), game .. " never: one log line")
    msg(W, "Dorin", "QA|103|Bears"); msg(W, "Dorin", "QA|102|Done Deal")
    H.ok(L.abandoned() == nil and not popupShown(ns), game .. " never: lacks it / completed → nothing")
    W.mods.shift = true; msg(W, "Dorin", "QA|101|Wolves"); W.mods.shift = false
    H.ok(L.has(101), game .. " never: Shift held → nothing")
    local n = #ns.Core.db.log
    msg(W, "Stranger", "QA|101|Wolves")
    H.ok(L.has(101) and not lastLog(ns):find("Abandon together", 1, true) or #ns.Core.db.log == n, game .. " never: a stranger → ignored")
  end
end

-- ------------------------------------------------------------------ leader: both hook paths, one QA per abandon
for _, modern in ipairs({ false, true }) do
  local game = modern and "Forever" or "Era"
  local W, ns, L = boot("Dorin", modern, { { 201, "Kobolds", false }, { 202, "Ogres", false } })
  local AU = ns.Auto
  local hk = AU.abandonHooks
  if modern then
    H.ok(hk["C_QuestLog.SetAbandonQuest"] and hk["C_QuestLog.AbandonQuest"] and hk.AbandonQuest, game .. ": C_QuestLog and the global are hooked")
  else
    H.ok(hk.SetAbandonQuest and hk.AbandonQuest and not hk["C_QuestLog.AbandonQuest"], game .. ": the globals are hooked")
  end
  local logged
  for _, e in ipairs(ns.Core.db.log) do if e.m:find("auto: abandon hooks", 1, true) then logged = e.m end end
  H.ok(logged and logged:find("AbandonQuest", 1, true), game .. ": the log names the hooks: " .. tostring(logged))
  local function qas() local t = {}; for _, m in ipairs(W.sent) do if m.prefix == "WBXA" and m.msg:find("^QA|") then t[#t + 1] = m.msg end end return t end
  -- the quest log's own abandon: select, SetAbandonQuest (the popup), AbandonQuest (its Accept)
  W.sent = {}
  if modern then
    W.env.C_QuestLog.SetSelectedQuest(201); W.env.C_QuestLog.SetAbandonQuest(); W.env.C_QuestLog.AbandonQuest()
  else
    W.env.SelectQuestLogEntry(1); W.env.SetAbandonQuest(); W.env.AbandonQuest()
  end
  H.eq(table.concat(qas(), " "), "QA|201|Kobolds", game .. ": the leader sends QA once, with id and name")
  if modern then
    -- the old global (a wrapper around C_QuestLog.AbandonQuest): both hooks fire, still one message
    W.sent = {}
    W.now = 50
    W.env.C_QuestLog.SetSelectedQuest(202); W.env.C_QuestLog.SetAbandonQuest(); W.env.AbandonQuest()
    H.eq(table.concat(qas(), " "), "QA|202|Ogres", game .. ": through the old global: still once")
  else
    -- the abandon popup cancelled: nothing is sent; the next real abandon sends once
    W.sent = {}
    W.now = 50
    W.env.SelectQuestLogEntry(1); W.env.SetAbandonQuest()
    H.eq(#qas(), 0, game .. ": SetAbandonQuest alone (popup cancelled) sends nothing")
    W.env.SelectQuestLogEntry(1); W.env.SetAbandonQuest(); W.env.AbandonQuest()
    H.eq(table.concat(qas(), " "), "QA|202|Ogres", game .. ": the next abandon: once")
  end
  -- nothing known: nothing sent
  W.sent = {}
  W.now = 100
  if modern then W.env.C_QuestLog.AbandonQuest() else L.sel = 0; W.env.AbandonQuest() end
  H.eq(#qas(), 0, game .. ": nothing to abandon → nothing sent")
  -- the diagnose lists the hooks
  ns.Core.selftest(true)
  local d = ns.Core.db.diag and ns.Core.db.diag[ns.Core.charKey]
  H.ok(d and d.auto and d.auto.abandonHooks and d.auto.abandonHooks.AbandonQuest and d.auto.abandonMode == "ask", game .. ": diag.auto.abandonHooks and abandonMode")
end

-- a follower that abandons a quest itself sends nothing
do
  local W, ns, L = boot("Anna", true, { { 301, "Spiders", false } })
  W.sent = {}
  W.env.C_QuestLog.SetSelectedQuest(301); W.env.C_QuestLog.SetAbandonQuest(); W.env.C_QuestLog.AbandonQuest()
  local n = 0
  for _, m in ipairs(W.sent) do if m.msg:find("^QA|") then n = n + 1 end end
  H.eq(n, 0, "a follower's own abandon sends nothing")
end

os.exit(H.report("abandon") and 0 or 1)
