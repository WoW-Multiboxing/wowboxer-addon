--[[ WoWBoxer – core: saved variables, events, slash commands, combat queue, debug log, level-up offers.
  Every change to the game (macros, action bars, settings) is started by the player (a click or a /wbx command) and
  runs out of combat; in combat it waits for PLAYER_REGEN_ENABLED. ]]
local ADDON, ns = ...
local Core = {}
ns.Core = Core

local S, C, M, B, R, Sh, K = ns.State, ns.Compat, ns.Macros, ns.Bars, ns.Rules, ns.Share, ns.Kit

Core.VERSION = "0.1.0"
Core.LOG_MAX = 400

--- The version stamped into the installed TOC: "0.12.0" (tagged release), "0.13.0-test.1 (abc1234)" (local test
--- build from tools/install.ps1), or nil in a source checkout (unstamped) and the simulator.
function Core.addonVersion()
  local get = (_G.C_AddOns and _G.C_AddOns.GetAddOnMetadata) or _G.GetAddOnMetadata
  local ok, v = false, nil
  if get then ok, v = pcall(get, ADDON or "WoWBoxer", "Version") end
  if not ok or type(v) ~= "string" or v == "" or v:find("@", 1, true) then return nil end
  return v:sub(1, 40)
end
--- True only for a local test build ("-test.N" in the version); a tagged release never has it.
function Core.isTestBuild()
  local v = Core.addonVersion()
  return v ~= nil and v:find("-test.", 1, true) ~= nil
end

-- ------------------------------------------------------------------ chat + log
local function chat(msg)
  local f = _G.DEFAULT_CHAT_FRAME
  if f and f.AddMessage then f:AddMessage("|cff4fc3f7WoWBoxer|r: " .. tostring(msg)) end
end
Core.print = chat

--- Debug log in SavedVariables (WoWBoxerDB.log), readable after /reload or logout.
function Core.log(level, msg)
  local db = Core.db
  if not db then return end
  local entry = { t = time and time() or 0, c = Core.charKey or "?", l = level, m = tostring(msg) }
  local log = db.log
  log[#log + 1] = entry
  while #log > Core.LOG_MAX do table.remove(log, 1) end
  if db.settings.debug then chat("[" .. level .. "] " .. tostring(msg)) end
end

-- ------------------------------------------------------------------ combat queue
Core.queue = {}
--- Run fn now, or after combat. label is shown to the player.
function Core.whenSafe(label, fn)
  if C.inCombat() then
    for _, q in ipairs(Core.queue) do if q.label == label then q.fn = fn; return false end end
    Core.queue[#Core.queue + 1] = { label = label, fn = fn }
    chat(label .. ": waiting until combat ends.")
    Core.log("info", "queued until combat ends: " .. label)
    return false
  end
  local ok, err = pcall(fn)
  if not ok then Core.log("error", label .. ": " .. tostring(err)); chat("|cffff6060" .. label .. " failed:|r " .. tostring(err)) end
  return true
end
function Core.runQueue()
  local q = Core.queue
  Core.queue = {}
  for _, item in ipairs(q) do Core.whenSafe(item.label, item.fn) end
end

-- ------------------------------------------------------------------ who am I
function Core.playerInfo()
  return { name = C.playerName(), cls = C.playerClass(), race = C.playerRace(), level = C.playerLevel(), faction = C.playerFaction() }
end
--- squad, member for this character (synced with the live character), or nil
function Core.me()
  local db, cdb = Core.db, Core.cdb
  if not db then return nil end
  local info = Core.playerInfo()
  local s, m = S.findMe(db, cdb, info.name)
  if m then
    if S.syncFromGame(m, info) then Core.log("warn", "member " .. m.name .. " had another class; reset to " .. tostring(m.cls)) end
    S.applyLink(s)
  end
  return s, m
end
function Core.setMe(squadId, memberId)
  Core.cdb.squadId, Core.cdb.memberId = squadId, memberId
  Core.cdb.slots = {}
  Core.changed()
end

--- Run fn with Core.compute memoised: one window refresh asks for the same plan several times (header, tab,
--- checklist); inside a batch it is computed once. Outside a batch every call is fresh.
local memo, depth = nil, 0
function Core.batch(fn, ...)
  depth = depth + 1
  local ok, err = pcall(fn, ...)
  depth = depth - 1
  if depth == 0 then memo = nil end
  if not ok then error(err, 0) end
end
function Core.compute()
  if depth > 0 then
    if not memo then memo = { Core.computeFresh() } end
    return memo[1], memo[2]
  end
  return Core.computeFresh()
end
--- Desired macros + plans for this character. Returns ctx table or nil, reason.
function Core.computeFresh()
  local s, m = Core.me()
  if not m then return nil, "This character is not in a squad yet." end
  local live = M.liveCheck()
  local L = C.playerLevel()
  Core.liveLeaderUnit(s, m)
  local lineUnit = ns.Squad and ns.Squad.lineFor(s, m) or nil
  local desired = M.desired(m, L, { live = live, extras = Core.cdb.extras, squad = s, squadKeys = Core.cdb.squadKeys, lineUnit = lineUnit,
    overrides = Core.cdb.overrides, ovCtx = { squad = s, me = m }, keyLines = Core.cdb.keyLines })
  for _, d in ipairs(desired) do d.keepOff = Core.keptOff(d.name, d.group) end
  M.setTag(Core.macroTag())
  local mplan = M.plan(desired, Core.cdb.skip)
  local bplan = B.plan(desired, Core.cdb, Core.cdb.skip)
  local ctx = { squad = s, member = m, level = L, live = live, desired = desired, macros = mplan, bars = bplan,
    missing = M.missingFromBook(m, L, live) }
  Core.ctxGen, Core.lastCtx = (Core.ctxGen or 0) + 1, ctx -- the strip on the action bars reuses it
  return ctx
end

--- The leader's party unit as THIS client sees it (Salamipouch, #help 10 Nov: a hunter's Assist pointed at party2
--- after every update). Party numbers differ per window, and a squad sent from another character carries that
--- character's view, so a follower in a party uses the unit where the leader really is here. Focus users and a leader
--- who is not in the party keep the saved unit. WoWBoxer data only; the macros follow after the usual Update click.
function Core.liveLeaderUnit(s, m)
  if not (s and m) or m.leader or m.unit == "focus" or not C.inParty() then return nil end
  local L = S.leaderOf(s)
  local u = L and ns.Squad and ns.Squad.unitOf(L.name)
  if u and u ~= m.unit then
    Core.log("info", "leader " .. tostring(L.name) .. " is " .. u .. " in this party (was " .. tostring(m.unit) .. ")")
    m.unit = u
  end
  return u
end

--- This character's tag for general (account) macro slots: 2 characters, unique among the characters of this WoW
--- account (WoWBoxerDB is account-wide, like the general macros), from the name where it can ("Rip" -> "Ri").
--- Kept in db.macroTags[charKey] from the first general macro on (persist = true, Macros.apply), so the names of its
--- general macros never change; before that it is only worked out (nothing is saved).
function Core.macroTag(persist)
  local db = Core.db
  if not (db and Core.charKey) then return nil end
  local tags = type(db.macroTags) == "table" and db.macroTags or {}
  if type(tags[Core.charKey]) == "string" then return tags[Core.charKey] end
  local used = {}
  for k, t in pairs(tags) do if k ~= Core.charKey then used[t] = true end end
  local letters = (Core.charKey:match("^([^%-]*)") or ""):gsub("[^%w]", "")
  local a, b = letters:sub(1, 1):upper(), letters:sub(2, 2):lower()
  local cands = {}
  if a ~= "" and b ~= "" then cands[#cands + 1] = a .. b end
  local first = a ~= "" and a or "Z"
  for i = 2, 9 do cands[#cands + 1] = first .. i end
  for c = 65, 90 do for i = 0, 9 do cands[#cands + 1] = string.char(c) .. i end end
  for _, t in ipairs(cands) do
    if not used[t] then
      if persist then
        db.macroTags = tags; tags[Core.charKey] = t
        Core.log("info", "general macro tag " .. t .. " for " .. Core.charKey)
      end
      return t
    end
  end
  return nil
end

--- "Keep off my bars" (docs/squad-v2-simple.md §4): such a key is never placed by Place all and never counted as
--- "not on a bar" or reminded about. Own keys and extra keys are kept off until the player has placed them once.
function Core.keptOff(name, group)
  local cdb = Core.cdb
  local v = cdb.offBars[name]
  if v ~= nil then return v and true or false end
  if group == "custom" or group == "extra" then return not cdb.placedOnce[name] end
  return false
end
function Core.setKeptOff(name, off)
  Core.cdb.offBars[name] = off and true or false
  Core.log("info", (off and "keep off bars: " or "allow on bars: ") .. name)
  Core.changed()
end

--- Save the line unit seen now (only after a click: Update / Place / the checklist Fix).
function Core.saveLineUnit(u)
  local s, m = Core.me()
  if not m or m.leader then return nil end
  if not u then
    local lu, _, how = ns.Squad.lineFor(s, m)
    if how ~= "party" and how ~= "leader" then return nil end
    u = lu
  end
  if u and u ~= "focus" and m.lineUnit ~= u then m.lineUnit = u; Core.log("info", "follow line: " .. u) end
  return u
end
--- The checklist / banner Fix "Use partyN": WoWBoxer data only; the macro follows after Update keys.
function Core.setLineUnit(u)
  Core.saveLineUnit(u)
  Core.changed()
end

--- Key groups per book page: "Place spells" (left page) and "Place squad keys" (right page).
Core.PAGE_GROUPS = { spells = { kit = true, extra = true, sequence = true }, squad = { helper = true } }
--- Only the items of ctx's plan whose key is in one of `groups` (all when groups is nil).
local function only(items, desired, groups)
  if not groups then return items end
  local ok = {}
  for _, d in ipairs(desired) do if groups[d.group] then ok[d.name] = true end end
  local out = {}
  for _, it in ipairs(items) do if ok[it.name] then out[#out + 1] = it end end
  return out
end
Core.onlyGroups = only
--- Create/update the macros, then place them on the bars. opts: {replace=bool, barsOnly=bool, macrosOnly=bool,
--- page = "spells" | "squad" (only that page's keys)}
function Core.sync(opts)
  opts = opts or {}
  local groups = opts.page and Core.PAGE_GROUPS[opts.page] or nil
  return Core.whenSafe(opts.page == "squad" and "Place squad macros" or opts.page == "spells" and "Place spells" or "Update WoWBoxer macros", function()
    Core.saveLineUnit()
    local ctx, why = Core.compute()
    if not ctx then chat(why); return end
    local mres = { created = 0, updated = 0, failed = {} }
    if not opts.barsOnly then mres = M.apply({ items = only(ctx.macros.items, ctx.desired, groups) }) end
    local bres = { placed = 0, skipped = 0, failed = {} }
    local ask = {}
    local waitCursor = not opts.macrosOnly and C.cursorBusy()
    if waitCursor then
      -- bug sweep 9 Nov 2026: "bar *: your cursor is holding something" – the player still held a dragged macro or spell.
      -- Tell it in plain words and place the macros as soon as the cursor is empty (no error, nothing lost).
      Core.waitForCursor(opts)
    elseif not opts.macrosOnly then
      local again = Core.compute() -- indices and statuses after creating macros
      local items = only(again.bars.items, again.desired, groups)
      bres = B.apply({ items = items }, Core.cdb, opts.replace)
      if not opts.replace then
        for _, it in ipairs(items) do if it.status == "occupied" or it.status == "ours" then ask[#ask + 1] = it end end
      end
    end
    Core.cdb.lastSync = { level = ctx.level, at = time and time() or 0 }
    local msg = string.format("%d macros created, %d updated, %d placed on your bars", mres.created, mres.updated, bres.placed)
    if ctx.macros.counts.noslot > 0 then msg = msg .. string.format(", %d without a free macro slot (%s)", ctx.macros.counts.noslot, table.concat(ctx.macros.noslotNames, ", ")) end
    if bres.skipped > 0 then msg = msg .. string.format(", %d left where they were (the button holds something else)", bres.skipped) end
    chat(msg .. ".")
    Core.log("info", "sync L" .. ctx.level .. ": " .. msg)
    for _, f in ipairs(mres.failed) do Core.log("error", "macro " .. f.name .. ": " .. f.err) end
    for _, f in ipairs(bres.failed) do Core.log("error", "bar " .. f.name .. ": " .. f.err) end
    if #mres.failed + #bres.failed > 0 then chat("|cffff6060Some changes failed|r – see /wbx log.") end
    Core.lastOffer = nil
    if ns.Minimap and ns.Minimap.SetAttention then ns.Minimap.SetAttention(false) end
    Core.changed()
    Core.flyKeys(ctx, mres.changed, bres.list)
    if ns.SeqStrip then ns.SeqStrip.markDirty(); ns.SeqStrip.request() end
    if #ask > 0 then Core.askReplace(ask, opts) end
  end)
end
--- What the mouse cursor holds, in plain words ("a spell", "a macro", "an item" …).
function Core.cursorWhat()
  local kind = _G.GetCursorInfo and C.safe((_G.GetCursorInfo()))
  local words = { spell = "a spell", macro = "a macro", item = "an item", petaction = "a pet action", money = "money", mount = "a mount",
    companion = "a pet", equipmentset = "an equipment set", battlepet = "a pet", merchant = "an item", flyout = "a flyout" }
  return words[tostring(kind)] or "something"
end
Core.CURSOR_WAIT = 120   -- seconds: after that the player presses Place again
--- The cursor holds something: Place waits for it to be empty, then places (bars only – the macros are already made).
function Core.waitForCursor(opts)
  local what = Core.cursorWhat()
  chat("Your mouse cursor is holding " .. what .. ", so WoWBoxer can't put macros on your bars yet. Drop it on a button or press Escape – the macros go on your bars right after.")
  Core.log("info", "bars wait for the cursor (it holds " .. what .. ")")
  local first = not Core.cursorWait
  Core.cursorWait = { opts = opts, since = (_G.GetTime and _G.GetTime()) or 0 }
  if first then Core.pollCursor() end
end
function Core.pollCursor()
  local w = Core.cursorWait
  if not w then return end
  local t = (_G.GetTime and _G.GetTime()) or 0
  if C.cursorBusy() then
    if t - w.since > Core.CURSOR_WAIT then
      Core.cursorWait = nil
      Core.log("info", "bars: stopped waiting for the cursor")
      chat("WoWBoxer stopped waiting for your cursor. Press Place all again when it is empty.")
      return
    end
    if _G.C_Timer and _G.C_Timer.After then _G.C_Timer.After(0.5, Core.pollCursor) end
    return
  end
  Core.cursorWait = nil
  local o = {}
  for k, v in pairs(w.opts or {}) do o[k] = v end
  o.barsOnly = true
  Core.log("info", "bars: the cursor is free, placing now")
  Core.sync(o)
end
--- CURSOR_CHANGED (where the client has it): don't wait for the next poll.
function Core.onCursorChanged() if Core.cursorWait and not C.cursorBusy() then Core.pollCursor() end end

--- WBX macros this character no longer uses (a key that became a plain spell, Pet attack, an unticked squad key):
--- names as in the game. Offered for removal on the banner; never deleted without the click.
function Core.unusedMacros()
  local ctx = Core.compute()
  return ctx and ctx.macros.unused or {}
end
function Core.removeUnused()
  return Core.whenSafe("Remove unused macros", function()
    local names = Core.unusedMacros()
    local n = M.deleteUnused(names)
    chat(Core.plural(n, "unused WBX macro", "unused WBX macros") .. " removed" .. (n > 0 and (": " .. table.concat(names, ", ")) or "") .. ".")
    Core.log("info", "removed unused macros: " .. n .. " (" .. table.concat(names, ", ") .. ")")
    Core.changed()
  end)
end
--- What a button holds, in words ("Smite", "your macro Heals", "WBX K5", "an item").
local function holds(cur)
  if not cur then return "nothing" end
  if cur.kind == "macro" then return R.isOurs(cur.name) and tostring(cur.name) or ("your macro " .. tostring(cur.name or "?")) end
  if cur.kind == "spell" then return tostring(cur.name or "a spell") end
  if cur.kind == "item" then return "an item" end
  return tostring(cur.kind)
end
Core.holdsText = holds
--- Some macros' buttons hold something else: ask once (owner, 5 Nov 2026: replacing a button needs a yes).
--- "Ask to replace buttons" off (cdb.askReplace == false): never ask, never replace.
function Core.askReplace(items, opts)
  if Core.cdb.askReplace == false or not (ns.UI and ns.UI.Popup) then return false end
  local lines = {}
  for i, it in ipairs(items) do
    if i > 4 then lines[#lines + 1] = "and " .. (#items - 4) .. " more"; break end
    local same = it.current and it.current.kind == "spell" and it.label == it.current.name
    lines[#lines + 1] = it.name .. " on " .. B.slotLabel(it.slot) .. " replaces " .. holds(it.current) .. (same and " (same spell)" or "")
  end
  Core.log("info", "asked to replace " .. #items .. " button(s)")
  ns.UI.Popup("Replace " .. (#items == 1 and "this button" or ("these " .. #items .. " buttons")) .. "?\n" .. table.concat(lines, "\n"), {
    { "Replace", function()
      Core.log("info", "replace: yes (" .. #items .. ")")
      Core.sync({ barsOnly = true, replace = true, page = opts and opts.page })
    end, "Puts the WoWBoxer macros on these buttons. What was there is remembered for Reset to default." },
    { "Keep", function() Core.log("info", "replace: kept") end, "Leaves the buttons as they are. Drag the macros yourself from My macros." },
  })
  return true
end

--- The keys that were just created, updated or placed fly to their action buttons (purely visual, Fly.lua).
function Core.flyKeys(ctx, ...)
  if not (ns.Fly and ns.Fly.enabled()) then return 0 end
  local seen, list = {}, {}
  local byName = {}
  for _, d in ipairs(ctx.desired) do byName[d.name] = d end
  for _, names in ipairs({ ... }) do
    for _, name in ipairs(names or {}) do
      local slot = Core.cdb.slots[name]
      if not seen[name] and slot then
        seen[name] = true
        local d = byName[name]
        list[#list + 1] = { slot = slot, icon = ns.Book and ns.Book.iconFor(d, d) or nil, from = ns.Book and ns.Book.cellFrame(name) }
      end
    end
  end
  return ns.Fly.play(list)
end

-- ------------------------------------------------------------------ bridge for WoWBoxer Window Layouts (WS-C)
--- Which character this account has logged in, for the window app (it reads WTF\Account\<ACC>\SavedVariables--- WoWBoxer.lua; contract in wowboxer-layouts/docs/classes-and-accounts.md). Only our own SavedVariables are written.
function Core.writeBridge(event)
  local db = Core.db
  if not db then return end
  local b = type(db.bridge) == "table" and db.bridge or {}
  local _, cls = UnitClass("player")
  b.version = 1
  b.character = C.playerName() or b.character
  b.realm = (GetRealmName and C.safe(GetRealmName())) or b.realm
  b.class = cls and cls:upper() or b.class
  b.level = C.playerLevel()
  local t = time and time() or 0
  if event == "login" then b.loggedInAt = t end
  b.savedAt = t
  db.bridge = b
end

-- ------------------------------------------------------------------ single character
--- A character that is in no squad gets a solo squad (leader = itself) the first time the window opens, so the
--- Keys tab works right away. Only SavedVariables change; nothing is written to the game.
function Core.ensureMe()
  if not Core.db then return nil end
  local _, m = Core.me()
  if m then return m end
  local info = Core.playerInfo()
  if not info.name or not info.cls then return nil end
  local _, mm = S.quickStart(Core.db, Core.cdb, info)
  Core.log("info", "solo setup for " .. tostring(info.name))
  return mm
end

--- First-time bar choice: Warriors, Druids and Rogues see a stance/form page on bar 1, so their keys start on
--- Bottom Left (main) and Bottom Right (other); everybody else on Bar 1 and Bottom Left.
function Core.defaultBars()
  local cdb = Core.cdb
  if not cdb then return end
  local paged = C.PAGED_CLASSES[C.playerClass() or ""]
  if not cdb.primaryBar then cdb.primaryBar = paged and 61 or 1 end
  if not cdb.secondaryBar then cdb.secondaryBar = paged and 49 or 61 end
end

--- "leader" or a follower unit (party1-4, focus) for this character. A follower needs a leader in the squad: a solo
--- character gets a placeholder "Leader" member (rename it on the Squad tab, or import the real squad).
function Core.setPlaysAs(v)
  local s, m = Core.me()
  if not m then return end
  if v == "leader" then
    for _, x in ipairs(s.members) do x.leader = (x == m) end
  elseif ns.Engine.contains(ns.Engine.UNITS, v) then
    m.leader, m.unit = false, v
    if not S.leaderOf(s) then
      table.insert(s.members, 1, S.newMember({ name = "Leader", cls = m.cls, race = m.race, level = m.level, leader = true }))
      chat("Added a placeholder leader to your squad. Rename it on the Squad tab, or import your squad.")
    end
  else return end
  Core.log("info", "plays as " .. v)
  Core.changed()
end

-- ------------------------------------------------------------------ drag & drop, bar memory
--- Put WBX macro `name` on the cursor so the player can drop it on any action button. Creates or updates the macro
--- first when needed. Returns true or false, reason. Out of combat only (macro writes are #nocombat).
function Core.pickup(name)
  if C.inCombat() then return false, "Not in combat." end
  local ctx, why = Core.compute()
  if not ctx then return false, why end
  local item
  for _, it in ipairs(ctx.macros.items) do if it.name == name then item = it end end
  if not item then return false, "Unknown macro " .. tostring(name) end
  if item.status == "spell" then -- a plain spell: the spell itself goes on the cursor, no macro
    for _, b in ipairs(ctx.bars.items) do
      if b.name == name and b.spellId then return Core.pickedSpell(B.pickupSpell(b.spellId, "drag " .. name)) end
    end
    for _, d in ipairs(ctx.desired) do
      if d.name == name then
        local id = C.bestRankId(d.spell)
        if id then return Core.pickedSpell(B.pickupSpell(id, "drag " .. name)) end
        return false, d.label .. " is not in your spellbook yet."
      end
    end
  end
  if item.status == "noslot" then return false, "No free macro slot (character and general). Delete a macro in /macro first." end
  if item.status == "invalid" then return false, item.why or "invalid macro" end
  if item.status == "create" or item.status == "update" or item.status == "skipped" then
    if item.status == "skipped" then Core.cdb.skip[name] = nil; ctx = Core.compute(); for _, it in ipairs(ctx.macros.items) do if it.name == name then item = it end end end
    if item.status == "create" or item.status == "update" then
      local res = M.apply({ items = { item } })
      if #res.failed > 0 then return false, res.failed[1].err end
      Core.log("info", "drag: " .. item.status .. " " .. name)
    end
  end
  local idx = M.findIndex(name)
  if not idx then return false, "Macro not found." end
  B.pickupMacro(idx, "drag " .. name)
  return true
end
function Core.pickedSpell(ok) if ok then return true end return false, "Could not pick up the spell." end
--- Same for a spell from the spell list: it becomes an extra key "WBX <Spell>" (kept for this character).
function Core.pickupSpell(spellId)
  if C.inCombat() then return false, "Not in combat." end
  local _, me = Core.me()
  if me then
    for _, s in ipairs(K.customSpellsOf(me)) do
      if s.id == spellId and ns.Engine.isPlain(s, K.memberCtx(me)) then
        local id = C.bestRankId(s)
        if not id then return false, s.name .. " is not in your spellbook yet." end
        return Core.pickedSpell(B.pickupSpell(id, "drag spell " .. s.name))
      end
    end
  end
  local extras = Core.cdb.extras
  local have = false
  for _, id in ipairs(extras) do if id == spellId then have = true end end
  if not have then extras[#extras + 1] = spellId end
  local ctx, why = Core.compute()
  if not ctx then return false, why end
  for _, d in ipairs(ctx.desired) do if d.key == "X:" .. spellId then return Core.pickup(d.name) end end
  if not have then table.remove(extras) end
  return false, "That spell has no macro (passive, or not for this character and plan)."
end
--- Remember where the player put each WBX macro (any action slot), so Place all keeps it there.
function Core.scanBars()
  local cdb = Core.cdb
  if not cdb then return end
  local found = {}
  for slot = 1, 120 do
    local a = C.actionInfo(slot)
    if a and a.kind == "macro" and R.isOurs(a.name) then
      local key = M.keyName(a.name) -- a general macro ("WBXRi K1") is key WBX K1
      if not found[key] then found[key] = slot end
    end
  end
  local spellSlots = cdb.spellSlots or {}
  for name, slot in pairs(cdb.slots) do
    local a = C.actionInfo(slot)
    if a and a.kind == "macro" and M.isMacro(a.name, name) then found[name] = slot end -- keep the remembered one if still there
    -- a plain spell's button (Bars.plan checks it still holds that spell)
    if a and a.kind == "spell" and spellSlots[name] and not found[name] then found[name] = slot end
  end
  for name in pairs(spellSlots) do if not found[name] then spellSlots[name] = nil end end
  cdb.slots = found
  for name in pairs(found) do cdb.placedOnce[name] = true end
  B.watch() -- a slot the player dragged a WBX macro onto keeps what was there before (Reset to default)
end

-- ------------------------------------------------------------------ key bindings
function Core.openKeyBindings()
  if C.inCombat() then chat("Not in combat."); return end
  if ns.UI and ns.UI.frame then ns.UI.frame:Hide() end
  local how = C.openKeyBindings()
  Core.log("info", "open key bindings: " .. tostring(how))
  if not how then chat("Could not open the key bindings here: use the game menu > Key Bindings.") end
end
--- "Smite (Key 2)" for a WBX macro name; the name itself when it is not one of this character's keys.
function Core.keyLabel(name)
  local ok, ctx = pcall(Core.compute)
  if ok and ctx then
    for _, it in ipairs(ctx.macros.items) do
      if it.name == name then return it.label .. (ns.Book and (" (" .. ns.Book.kindName(it) .. ")") or "") end
    end
  end
  return name
end
local function plural(n, one, many) return n .. " " .. (n == 1 and one or many) end
Core.plural = plural
function Core.bindKey(name, key)
  local ctx = Core.compute()
  for _, it in ipairs(ctx and ctx.macros.items or {}) do
    if it.name == name and it.status == "spell" then
      chat(it.label .. " is the spell itself on your bar (no macro), so it takes the keybind of its action button: press that button's key, or set it in the game's Key Bindings.")
      return false
    end
  end
  return Core.whenSafe("Bind " .. name, function()
    local ok, info = ns.Binds.bind(name, key)
    if ok then
      chat(Core.keyLabel(name) .. " now has keybind " .. key .. (info and info ~= ("MACRO " .. name) and (" (was: " .. ns.Binds.bindingText(info) .. ")") or "") .. " on this character.")
      Core.log("info", "bind " .. key .. " -> " .. name .. " (was " .. tostring(info) .. ")")
    else chat("|cffff6060Could not bind:|r " .. tostring(info)); Core.log("warn", "bind failed " .. name .. ": " .. tostring(info)) end
    Core.changed()
  end)
end
--- Put WBX macro `name` on action slot `slot` (the button a key already presses). Out of combat, after a click/key
--- press; whatever the button held goes back to nothing (the player confirmed that).
function Core.placeOn(name, slot, key)
  return Core.whenSafe("Put " .. name .. " on a button", function()
    local ok, why = Core.pickup(name) -- creates / updates the macro first
    if not ok then chat("|cffff6060Could not place:|r " .. tostring(why)); return end
    B.clearCursor("placeOn")
    local spellId = Core.plainSpellId(name)
    local placed, err
    if spellId then
      placed, err = B.placeSpell(spellId, slot, "placeOn " .. tostring(key))
      if placed then Core.cdb.spellSlots = Core.cdb.spellSlots or {}; Core.cdb.spellSlots[name] = true end
    else placed, err = B.placeMacro(M.findIndex(name), slot, "placeOn " .. tostring(key)) end
    if not placed then chat("|cffff6060Could not place:|r " .. tostring(err)); return end
    Core.cdb.slots[name] = slot
    Core.cdb.placedOnce[name] = true
    chat(Core.keyLabel(name) .. " is now on " .. ns.Binds.buttonName(slot) .. (key and (" (keybind " .. key .. ")") or "") .. ".")
    Core.log("info", "place " .. name .. " on slot " .. slot .. " for keybind " .. tostring(key))
    Core.changed()
  end)
end
--- The spell ID to put on a bar for key `name` when it is a plain spell (no macro), else nil.
function Core.plainSpellId(name)
  local ctx = Core.compute()
  for _, d in ipairs(ctx and ctx.desired or {}) do if d.name == name and d.plain then return C.bestRankId(d.spell) end end
  return nil
end
--- "Give 3 back to button 3": the key presses action button 3 again (the macro stays where it is on the bars).
function Core.giveBack(key)
  return Core.whenSafe("Give " .. key .. " back", function()
    if ns.Binds.giveBack(key) then
      chat("Keybind " .. key .. " is back on " .. ns.Binds.buttonName(ns.Binds.DEFAULT_KEYS[key]) .. ".")
      Core.log("info", "give back keybind " .. key)
    end
    Core.changed()
  end)
end
function Core.unbindKey(name)
  return Core.whenSafe("Unbind " .. name, function()
    local n = ns.Binds.unbind(name)
    chat(plural(n, "keybind", "keybinds") .. " removed from " .. Core.keyLabel(name) .. ".")
    Core.log("info", "unbind " .. name .. ": " .. n)
    Core.changed()
  end)
end

-- ------------------------------------------------------------------ CVars
function Core.cvarPlan(overrides)
  local _, m = Core.me()
  local role = (m and not m.leader) and "follower" or "leader"
  local out = {}
  for _, c in ipairs(R.CVARS) do
    local cur = C.getCVar(c.name)
    local want = (overrides and overrides[c.name]) or c[role]
    out[#out + 1] = { name = c.name, label = c.label, why = c.why, current = cur, want = want, exists = cur ~= nil,
      backup = Core.cdb.cvarBackup[c.name], status = cur == nil and "missing" or (want == nil and "leave") or (tostring(cur) == want and "ok")
        or ((Core.cdb.cvarStuck or {})[c.name] and "stuck") or "change" }
  end
  return out, role
end
function Core.applyCVars(overrides)
  return Core.whenSafe("Apply settings", function()
    local n, stuck = 0, {}
    Core.cdb.cvarLog = Core.cdb.cvarLog or {}
    Core.cdb.cvarStuck = Core.cdb.cvarStuck or {}
    for _, c in ipairs(Core.cvarPlan(overrides)) do
      if (c.status == "change" or c.status == "stuck") and R.CVAR_BY_NAME[c.name] then
        if Core.cdb.cvarBackup[c.name] == nil then Core.cdb.cvarBackup[c.name] = tostring(c.current) end
        local ok, method, after = C.setCVarSure(c.name, c.want)
        Core.cdb.cvarLog[c.name] = { before = c.current, want = c.want, after = after, method = method }
        Core.cdb.cvarStuck[c.name] = (not ok) or nil
        if ok then n = n + 1 else stuck[#stuck + 1] = c.label; Core.log("warn", "cvar did not stick: " .. c.name .. " (" .. method .. ", now " .. tostring(after) .. ")") end
      end
    end
    chat(n .. " setting(s) changed. Restore puts the old values back." .. (#stuck > 0 and (" |cfff0b43cDidn't stick:|r " .. table.concat(stuck, ", ") .. " – Setup → Open Options.") or ""))
    Core.log("info", "cvars applied: " .. n .. (#stuck > 0 and (", did not stick: " .. #stuck) or ""))
    Core.changed()
  end)
end
function Core.restoreCVars()
  return Core.whenSafe("Restore settings", function()
    local n = 0
    for name, v in pairs(Core.cdb.cvarBackup) do
      if R.CVAR_BY_NAME[name] and C.setCVarSure(name, v) then n = n + 1 end
    end
    Core.cdb.cvarBackup, Core.cdb.cvarStuck = {}, {}
    chat(n .. " setting(s) restored.")
    Core.log("info", "cvars restored: " .. n)
    Core.changed()
  end)
end

-- ------------------------------------------------------------------ import / export
function Core.importString(str)
  local res, err, warn = Sh.import(str, C.game())
  if not res then Core.log("warn", "import rejected: " .. tostring(err)); return nil, err end
  return res, nil, warn
end
--- Apply a validated import: replaces a squad with the same id, else adds it. Settings are not applied here.
function Core.applyImport(res)
  local db = Core.db
  local replaced = false
  -- this character's own leader unit and follow-line slot are its own view of the party: an import from another
  -- character (whose party numbers differ) must not overwrite them (bug 7, #help 10 Nov)
  local _, old = Core.me()
  local keep = old and not old.leader and { name = old.name, unit = old.unit, lineUnit = old.lineUnit } or nil
  for i, s in ipairs(db.squads) do if s.id == res.squad.id then db.squads[i] = res.squad; replaced = true end end
  if keep then
    for _, x in ipairs(res.squad.members or {}) do
      if not x.leader and C.sameName(x.name, keep.name) then x.unit, x.lineUnit = keep.unit, keep.lineUnit end
    end
  end
  if not replaced then db.squads[#db.squads + 1] = res.squad end
  db.active = res.squad.id
  if next(res.cvars) then Core.cdb.importCVars = res.cvars end
  if #res.addons > 0 then db.settings.addons = res.addons end
  if res.auto and ns.Auto then ns.Auto.import(res.auto); Core.log("info", "imported the squad's automation choice") end
  Core.cdb.squadId, Core.cdb.memberId = nil, nil
  local _, m = Core.me()
  Core.log("info", "imported squad " .. res.squad.name .. " (" .. #res.squad.members .. " characters), me=" .. tostring(m and m.name))
  Core.changed()
  return m
end
function Core.exportString(squad)
  squad = squad or S.activeSquad(Core.db)
  if not squad then return nil end
  return Sh.export(squad, { game = C.game(), addons = Core.db.settings.addons, auto = ns.Auto and ns.Auto.export() or nil })
end

-- ------------------------------------------------------------------ Advanced mode: own targeting per key (Override.lua)
function Core.advanced() return Core.db and Core.db.settings.advanced == true end
--- Set (or with nil: remove = "Back to WoWBoxer's version") the override of key `name`. WoWBoxer data only; the macro
--- follows after the usual Update click, out of combat.
function Core.setOverride(name, ov)
  if not R.isOurs(name) then return false end
  Core.cdb.overrides[name] = ov and ns.Override.clean(ov) or nil
  Core.log("info", (Core.cdb.overrides[name] and "override " or "override removed ") .. name)
  Core.changed()
  return true
end
--- "WoWBoxer's version" of key `name`: no own targeting or text, and no own extra-line choices (the switches apply).
function Core.backToDefault(name)
  if not R.isOurs(name) then return false end
  if Core.cdb.keyLines then Core.cdb.keyLines[name] = nil; if not next(Core.cdb.keyLines) then Core.cdb.keyLines = nil end end
  return Core.setOverride(name, nil)
end

-- ------------------------------------------------------------------ extra lines (Macros.LINES; #help 10 Nov)
--- A character's switch for extra line `key` (all its macros; member m, default this character), kept on the member
--- like "Take the leader's target" (m.assist). WoWBoxer data only: the macros change after the usual Update click,
--- checked against 255 like every change.
function Core.setLine(key, on, m)
  if not M.LINE_BY[key] then return false end
  if not m then local _; _, m = Core.me() end
  if not m then return false end
  if key == "assist" then
    m.assist = S.offOrNil(on and true or false)
  else
    local t = m.lines or {}
    t[key] = S.offOrNil(on and true or false)
    m.lines = S.cleanLines(t)
  end
  Core.log("info", "extra line " .. key .. (on and " on" or " off") .. " (all macros of " .. tostring(m.name) .. ")")
  Core.changed()
  return true
end
function Core.lineOn(key, m) if not m then local _; _, m = Core.me() end return M.lineOn(key, m and m.lines, m) end
--- One macro's own choice for extra line `key` (true/false; nil = follow the switch). It beats the switch and survives
--- updates and level-ups; "WoWBoxer's version" clears it.
function Core.setKeyLine(name, key, on)
  if not (R.isOurs(name) and M.LINE_BY[key]) then return false end
  local all = Core.cdb.keyLines or {}
  local t = all[name] or {}
  if on == nil then t[key] = nil else t[key] = on and true or false end
  all[name] = next(t) and t or nil
  Core.cdb.keyLines = next(all) and all or nil
  Core.log("info", "extra line " .. key .. " " .. (on == nil and "as the switch" or on and "on" or "off") .. " in " .. name)
  Core.changed()
  return true
end
--- One click on a macro's card: turn that line off in this macro (or on again). Returns the new state or nil.
function Core.toggleKeyLine(name, key)
  local c = Core.compute()
  for _, d in ipairs(c and c.desired or {}) do
    if d.name == name then
      for _, x in ipairs(M.linesOf(d, Core.cdb.keyLines)) do
        if x.key == key then Core.setKeyLine(name, key, not x.on); return not x.on end
      end
    end
  end
  return nil
end

--- "Also heal Bo's pet": the key's current targets with Bo's pet after the leader (one click, heal keys).
function Core.alsoHeal(name, owner)
  local ctx, cur = ns.Override.ctx(), Core.cdb.overrides[name]
  local base
  if cur and cur.targets and #cur.targets > 0 then base = cur.targets
  else
    local c = Core.compute()
    for _, d in ipairs(c and c.desired or {}) do if d.name == name then base = ns.Override.fromBody(d.engineBody or d.body, ctx) end end
  end
  local targets, put = {}, false
  local pet = { who = "member", name = owner, pet = true, help = true, nodead = true }
  for _, t in ipairs(base or {}) do
    if t.who == "member" and t.pet and C.sameName(t.name, owner) then return false end -- already there
    if not put and t.who == "player" then targets[#targets + 1] = pet; put = true end
    targets[#targets + 1] = t
    if not put and t.who == "leader" then targets[#targets + 1] = pet; put = true end
  end
  if not put then targets[#targets + 1] = pet end
  local ov = { targets = targets }
  if cur then for _, k in ipairs({ "mod", "reset", "startattack", "petattack" }) do ov[k] = cur[k] end end
  return Core.setOverride(name, ov)
end

--- A spell becomes an own macro "single spell" (the engine's custom priority with one step; parity unchanged).
--- Returns its index (WBX C<i>) or nil, reason. preset: nil | "enemy" | "friendly" | "self" | {pet = member name}.
function Core.newSingle(spell, preset)
  local _, m = Core.me()
  if not (m and spell) then return nil, "No spell" end
  m.customSeq = m.customSeq or {}
  for i, c in ipairs(m.customSeq) do if c.kind == "priority" and #c.steps == 1 and c.steps[1] == spell.name then return i end end
  if #m.customSeq >= S.CUSTOM_MAX then return nil, "You have " .. S.CUSTOM_MAX .. " own macros already – delete one first" end
  local help = ns.Engine.makeMacro(spell, K.memberCtx(m)):find("help", 1, true) ~= nil
  if preset == "enemy" then help = false elseif preset == "friendly" or preset == "self" or type(preset) == "table" then help = true end
  local c = S.cleanCustom({ { name = spell.name, kind = "priority", aim = help and "help" or "harm", steps = { spell.name } } })[1]
  m.customSeq[#m.customSeq + 1] = c
  local i = #m.customSeq
  local name = "WBX C" .. i
  if preset == "self" then Core.cdb.overrides[name] = ns.Override.clean({ targets = { { who = "player", help = true } } })
  elseif type(preset) == "table" and preset.pet then
    Core.cdb.overrides[name] = ns.Override.clean({ targets = { { who = "mouseover", help = true, nodead = true },
      { who = "member", name = preset.pet, pet = true, help = true, nodead = true } } })
  else Core.cdb.overrides[name] = nil end
  Core.log("info", "own macro: C" .. i .. " made from the spell " .. spell.name)
  Core.changed()
  return i
end

-- ------------------------------------------------------------------ Reset to default (docs/advanced-mode.md §5)
local function wbxMacros()
  local out = {}
  for _, x in ipairs(C.characterMacros()) do if R.isOurs(x.name) then out[#out + 1] = x end end
  local tag = Core.macroTag()
  for _, x in ipairs(C.accountMacros()) do if M.isMineAccount(x.name, tag) then out[#out + 1] = x end end
  return out
end
--- Plain summary of what a reset with choices ch {char, account, macros, cvars} removes.
function Core.resetSummary(ch)
  local parts = {}
  if ch.char then
    local n = 0
    for _ in pairs(Core.cdb.overrides or {}) do n = n + 1 end
    parts[#parts + 1] = "this character's settings" .. (n > 0 and (", " .. plural(n, "macro override", "macro overrides")) or "")
  end
  if ch.account then
    local b = 0
    for _, l in pairs(Core.db.builds or {}) do b = b + #l end
    parts[#parts + 1] = "all " .. plural(#Core.db.squads, "squad", "squads") .. " and " .. plural(b, "saved build", "saved builds")
  end
  if ch.bars then
    local n, before = 0, Core.barsUnknown()
    for _ in pairs(Core.cdb.barOriginal or {}) do n = n + 1 end
    parts[#parts + 1] = plural(n, "action button", "action buttons") .. " put back" ..
      (#before > 0 and (" (" .. Core.buttonList(before) .. " were changed before WoWBoxer kept a copy)") or "")
  end
  if ch.macros then parts[#parts + 1] = plural(#wbxMacros(), "WBX macro", "WBX macros") end
  if ch.cvars then
    local n = 0
    for _ in pairs(Core.cdb.cvarBackup or {}) do n = n + 1 end
    parts[#parts + 1] = plural(n, "game setting", "game settings") .. " put back"
  end
  return #parts > 0 and table.concat(parts, ", ") or "nothing"
end
--- Slots that hold a WBX macro but have no stored original (changed before 0.11.1): they can't be put back.
function Core.barsUnknown()
  local out = {}
  local orig = Core.cdb.barOriginal or {}
  for slot = 1, 120 do
    local c = B.content(slot)
    if c.kind == "macro" and R.isOurs(c.name) and orig[slot] == nil then out[#out + 1] = slot end
  end
  return out
end
--- "Button 3 and 8" / "Bottom Left Bar button 2 and Button 9".
function Core.buttonList(slots)
  local t = {}
  for _, s in ipairs(slots) do t[#t + 1] = (s <= 12 and ("Button " .. s)) or ns.Binds.buttonName(s) end
  if #t <= 1 then return t[1] or "" end
  return table.concat(t, ", ", 1, #t - 1) .. " and " .. t[#t]
end

--- Do the reset (out of combat, after the player typed RESET). Only WoWBoxer's own data, WBX macros and the CVars it
--- changed (restored first, then the backup is forgotten). Returns the summary line.
function Core.resetToDefault(ch)
  if C.inCombat() then return "Not in combat." end
  local summary = Core.resetSummary(ch)
  local report = { restored = {}, failed = {} }
  if ch.bars then -- first, while the WBX macros still exist: every slot WoWBoxer changed gets its original back
    for _, slot in ipairs(Core.barsUnknown()) do report.failed[#report.failed + 1] = Core.buttonList({ slot }) .. " (changed before WoWBoxer kept a copy)" end
    for slot, orig in pairs(Core.cdb.barOriginal or {}) do
      local ok, why = B.restoreSlot(slot, orig, "reset")
      if ok then report.restored[#report.restored + 1] = "slot " .. slot else report.failed[#report.failed + 1] = Core.buttonList({ slot }) .. ": " .. tostring(why) end
    end
    Core.cdb.barOriginal, Core.cdb.barSeen = {}, {}
  end
  if ch.char then
    local nb = ns.Binds.restoreAll() -- keys WoWBoxer bound go back to what they did before (needs bindPrev: first)
    if nb > 0 then Core.log("info", "reset: " .. nb .. " keybinds restored"); report.restored[#report.restored + 1] = nb .. " keybinds" end
  end
  if ch.cvars then
    local n = 0
    for name, v in pairs(Core.cdb.cvarBackup) do
      if R.CVAR_BY_NAME[name] then
        if C.setCVarSure(name, v) then n = n + 1 else report.failed[#report.failed + 1] = "setting " .. name .. " (didn't stick – Open Options)" end
      end
    end
    Core.cdb.cvarBackup = {}
    if n > 0 then report.restored[#report.restored + 1] = n .. " settings" end
    Core.log("info", "reset: " .. n .. " cvars restored")
  end
  if ch.macros then
    local list = wbxMacros()
    table.sort(list, function(a, b) return a.index > b.index end) -- highest first: indices move when one is deleted
    local n = 0
    for _, x in ipairs(list) do if R.isOurs(x.name) and pcall(DeleteMacro, x.index) then n = n + 1 end end
    Core.log("info", "reset: " .. n .. " WBX macros deleted")
  end
  if ch.account then
    Core.db.squads, Core.db.active, Core.db.builds = {}, nil, {}
    K.setBuilds(Core.db.builds)
    Core.cdb.squadId, Core.cdb.memberId = nil, nil
  end
  if ch.char then
    local keep = Core.cdb.cvarBackup -- only the CVars tick forgets the backup (Restore needs it)
    for k in pairs(Core.cdb) do Core.cdb[k] = nil end
    S.initDB(Core.db, Core.cdb)
    Core.cdb.cvarBackup, Core.cdb.welcomed = keep or {}, true
    Core.defaultBars()
    Core.db.settings.advanced = nil -- a full reset goes back to Standard mode
    Core.db.settings.auto, Core.db.settings.acceptFrom, Core.db.settings.acceptOverride = {}, nil, nil -- and Automation off
  end
  Core.db.lastReset = { at = time and time() or 0, char = Core.charKey, restored = report.restored, failed = report.failed }
  Core.lastOffer = nil
  Core.ensureMe()
  local notes = #report.failed > 0 and (" Could not restore: " .. table.concat(report.failed, "; ") .. ".") or ""
  chat("Reset to default: " .. summary .. "." .. notes)
  Core.log("info", "reset to default: " .. summary .. notes)
  Core.changed()
  return summary:gsub("^%l", string.upper) .. "." .. notes, report
end

-- ------------------------------------------------------------------ own talent builds (WoWBoxer's data only)
--- Save an imported build (WH.import result) as `name`; use = pick it for this character (same class only).
--- Never touches the game's talents (no LearnTalent): the player spends points in the game's talent window.
function Core.saveBuild(res, name, use, link)
  local db = Core.db
  local cls = res.cls
  db.builds[cls] = db.builds[cls] or {}
  local list = db.builds[cls]
  if #list >= S.BUILDS_MAX then return nil, "At most " .. S.BUILDS_MAX .. " builds per class" end
  name = R.cleanText(name or "", 40)
  if not name or name == "" then name = "Wowhead " .. res.split end
  local saved = (_G.date and _G.date("%Y-%m-%d")) or nil
  local b = S.cleanBuilds({ [cls] = { { id = S.uid("u"), label = name, kind = res.kind, order = res.order, talented = res.talented, link = link, saved = saved } } })[cls][1]
  list[#list + 1] = b
  Core.log("info", "build saved: " .. cls .. " " .. name .. " (" .. #b.order .. " points)")
  local _, m = Core.me()
  if use and m and m.cls == cls then Core.useGuide(b.id) end
  Core.changed()
  return b
end
--- Pick a guide or build for this character (its own imported squad build is dropped).
function Core.useGuide(id)
  local _, m = Core.me()
  if not m then return end
  m.guide, m.build, m.buildName = id, {}, nil
  Core.log("info", "guide " .. tostring(id))
  Core.changed()
end
function Core.renameBuild(cls, id, name)
  name = R.cleanText(name or "", 40)
  for _, b in ipairs(Core.db.builds[cls] or {}) do
    if b.id == id and name and name ~= "" then b.label = name; Core.changed(); return true end
  end
  return false
end
--- Delete a build; every member that used it falls back to the default guide for its role.
function Core.deleteBuild(cls, id)
  local list = Core.db.builds[cls] or {}
  for i, b in ipairs(list) do
    if b.id == id then
      table.remove(list, i)
      if #list == 0 then Core.db.builds[cls] = nil end
      for _, s in ipairs(Core.db.squads) do
        for _, m in ipairs(s.members) do if m.cls == cls and m.guide == id then m.guide = K.defaultGuideFor(m.cls, m.role) end end
      end
      Core.log("info", "build deleted: " .. b.label)
      Core.changed()
      return true
    end
  end
  return false
end

-- ------------------------------------------------------------------ login checks (questions, nothing without a click)
--- A 1–= key that presses a WBX macro directly (the 0.9.4 bind bug): ask once per login to give it back.
function Core.loginChecks()
  local lost = ns.Binds.lostButtons()
  if #lost > 0 and ns.UI and ns.UI.Popup and not Core.askedFix then
    Core.askedFix = true
    local keys, btns = {}, {}
    for _, l in ipairs(lost) do keys[#keys + 1] = l.key; btns[#btns + 1] = tostring(l.slot) end
    local one = #lost == 1
    ns.UI.Popup("Key " .. table.concat(keys, ", ") .. (one and " presses" or " press") .. " a WoWBoxer macro directly, so action button " ..
      table.concat(btns, ", ") .. (one and " has" or " have") .. " no keybind.", {
      { "Fix now", function() for _, l in ipairs(lost) do Core.giveBack(l.key) end end, "Puts back ACTIONBUTTON" .. lost[1].slot .. (one and "" or " (and the others)") .. ". The macro stays on your bars." },
      { "Not now", function() end, "Asks again at the next login." } })
    Core.log("info", "login: asked to give back " .. table.concat(keys, ","))
    return true
  end
  if ns.BarFit and ns.BarFit.offer and ns.BarFit.offer() then return true end
  if ns.Auto and ns.Auto.nudge then return ns.Auto.nudge() end
  return false
end

-- ------------------------------------------------------------------ level-up offers
--- What a reminder is about (docs/squad-v2-simple.md §4): only real changes – a new key or a key whose macro text
--- changed – and never a key the player keeps off the bars. Returns signature, count, items.
function Core.pending(ctx)
  local items, parts = {}, { tostring(ctx.level) }
  local keep = {}
  for _, d in ipairs(ctx.desired) do keep[d.name] = d.keepOff end
  for _, it in ipairs(ctx.macros.items) do
    if (it.status == "create" or it.status == "update") and not keep[it.name] then
      items[#items + 1] = it
      parts[#parts + 1] = it.name .. "=" .. it.body
    end
  end
  return table.concat(parts, "|"), #items, items
end
--- Level-up reminders on (default) or off (Setup). Off: no toast and no chat line; the book still shows the dots.
function Core.remindersOn() return Core.cdb.reminders ~= false end
--- Compare what the character should have with what it has; offer an update (never applied without a click).
--- At most one chat line, and only for something new: the same pending state is not shown again after a reload
--- (cdb.offerShown), and never after "Don't show again" (cdb.offerSeen). A new change shows again.
function Core.checkOffer(reason)
  local ctx = Core.compute()
  if not ctx then return end
  local sig, n = Core.pending(ctx)
  if n == 0 or Core.lastOffer == sig then return end
  Core.lastOffer = sig
  Core.log("info", "offer (" .. reason .. "): " .. n .. " macro(s) changed at level " .. ctx.level)
  local cdb = Core.cdb
  if not cdb.lastSync then return end -- only players who already use WoWBoxer keys
  if cdb.offerShown == sig or cdb.offerSeen == sig then return end
  cdb.offerShown = sig
  if ns.Minimap and ns.Minimap.SetAttention then ns.Minimap.SetAttention(true) end
  if not Core.remindersOn() then return end
  chat(string.format("%s changed at level %d. Open |cffffd100/wbx|r (or type |cffffd100/wbx sync|r) to update them.", plural(n, "macro", "macros"), ctx.level))
  if ns.UI and ns.UI.ShowOffer then ns.UI.ShowOffer(ctx, sig) end
end
--- "Don't remind me about these changes" on the toast: this pending state never shows again on this character (a new
--- change does). on = false (unticked again) takes it back.
function Core.dontShowAgain(sig, on)
  if on == false then
    if Core.cdb.offerSeen == sig then Core.cdb.offerSeen = nil end
    Core.log("info", "reminder: remind me again")
    return
  end
  Core.cdb.offerSeen = sig
  Core.log("info", "reminder: don't remind me about these changes")
end

-- ------------------------------------------------------------------ change notification for the UI
function Core.changed()
  if ns.SeqStrip then ns.SeqStrip.markDirty() end
  if ns.Settings then ns.Settings.check() end
  if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
end

-- ------------------------------------------------------------------ selftest (for testing without looking at the screen)
function Core.selftest(quiet)
  C.invalidateSpellbook()
  local db = Core.db
  local r = { at = time and time() or 0, version = Core.VERSION, build = Core.addonVersion(), probe = C.probe(), player = Core.playerInfo() }
  local ctx, why = Core.compute()
  if ctx then
    r.member = { name = ctx.member.name, cls = ctx.member.cls, role = ctx.member.role, leader = ctx.member.leader, unit = ctx.member.unit, seq = ctx.member.seq }
    r.macros = { counts = ctx.macros.counts, free = ctx.macros.free, charMax = ctx.macros.charMax, unused = ctx.macros.unused, items = {} }
    for _, it in ipairs(ctx.macros.items) do r.macros.items[#r.macros.items + 1] = { it.name, it.status, it.label, #it.body } end
    r.bars = { counts = ctx.bars.counts, items = {} }
    for _, it in ipairs(ctx.bars.items) do r.bars.items[#r.bars.items + 1] = { it.name, it.slot, it.status, it.current and (it.current.kind .. ":" .. tostring(it.current.name or it.current.id)) or "-" } end
    r.missing = {}
    for _, s in ipairs(ctx.missing) do r.missing[#r.missing + 1] = s.name end
  else r.error = why end
  local cv = Core.cvarPlan()
  r.cvars = {}
  for _, c in ipairs(cv) do
    local lg = (Core.cdb.cvarLog or {})[c.name]
    r.cvars[c.name] = { cur = c.current, want = c.want, status = c.status, setting = C.cvarSetting(c.name) ~= nil,
      before = lg and lg.before, after = lg and lg.after, method = lg and lg.method }
  end
  local okP, probe = pcall(C.cvarProbe)
  r.cvarProbe = okP and probe or { error = tostring(probe) }
  r.addons = {}
  for _, a in ipairs(R.ADDONS) do r.addons[a.name] = C.addonState(a.name) end
  r.party = {}
  for i = 1, 4 do r.party["party" .. i] = C.unitName("party" .. i) or "-" end
  r.focus = C.unitName("focus") or "-"
  -- talent read-back probe (read-only): which API answered and how many talents matched the data
  local okT, ranks, src = pcall(C.talentRanks)
  if okT then
    r.talents = { source = src, names = 0 }
    for _ in pairs(ranks or {}) do r.talents.names = r.talents.names + 1 end
    if ranks and ctx then
      local st = K.talentStatus(ctx.member, ranks, ctx.level)
      r.talents.spent, r.talents.off, r.talents.unknown = st.spent, #st.off, #st.unknown
      r.talents.unknownNames = { unpack(st.unknown, 1, math.min(5, #st.unknown)) }
    end
  end
  -- fly-to-bar probe: which action buttons exist and are visible (bar addons hide Blizzard's), Blizzard's own tracker
  r.fly = { iconIntro = _G.IconIntroTracker ~= nil, buttons = {} }
  if ns.Fly then for _, slot in ipairs({ 1, 13, 25, 37, 49, 61, 145 }) do r.fly.buttons[tostring(slot)] = ns.Fly.buttonForSlot(slot) ~= nil end end
  r.strip = { query = _G.QueryCastSequence ~= nil, macroSpell = _G.GetMacroSpell ~= nil, actionText = _G.GetActionText ~= nil,
    shown = ns.SeqStrip and ns.SeqStrip.shown or 0, on = ns.SeqStrip and ns.SeqStrip.enabled() or false }
  if ns.Team then
    local s, me = Core.me()
    local peers = {}
    for k, p in pairs(ns.Team.peers) do peers[k] = { level = p.level, version = p.version, keys = p.ready and p.ready.keys or nil } end
    r.team = { active = ns.Team.active(), version = ns.Team.version(), members = s and #s.members or 0, presets = s and #(s.presets or {}) or 0,
      me = me and me.name or nil, peers = peers, sends = { ok = C.sendStats.ok, failed = C.sendStats.failed, last = C.sendStats.last } }
    -- names exactly as the game gives them (Forever two-part names): player + party units, with realm
    local raw = {}
    for _, u in ipairs({ "player", "party1", "party2", "party3", "party4" }) do
      local ok, n, realm = pcall(UnitName, u)
      if ok and n ~= nil and not C.isSecret(n) then raw[u] = tostring(n) .. ((realm and not C.isSecret(realm) and realm ~= "") and ("-" .. tostring(realm)) or "") end
    end
    r.team.names = raw
    r.team.arrivals = {}
    for k, v in pairs(C.arrivals) do r.team.arrivals[k] = v end
    r.team.squadNames = {}
    for _, m in ipairs(s and s.members or {}) do r.team.squadNames[#r.team.squadNames + 1] = m.name .. " -> " .. tostring(ns.Squad.unitOf(m.name) or "-") end
  end
  -- docs/sequences-all-classes.md §5 [AFKLAR]: spell names of the v8.5 sequences on this client (by spell ID), and
  -- what can only be seen in play (left open here, results go into LOG.md)
  local sq = { names = {}, open = { "combo points for followers with Take the leader's target off", "!Auto Shot after Aimed Shot (clip?)",
    "warrior priority lines fall through (Execute / Overpower / Victory Rush)" } }
  for _, n in ipairs({ "Primal Bite", "Arcane Wrath", "Frostfire Bolt", "Riptide", "Lava Burst", "Stormstrike", "Hemorrhage" }) do
    local found
    for _, cls in ipairs(ns.Data.classOrder) do
      for _, s in ipairs(ns.Data.spells[cls] or {}) do if not found and s.name == n then found = s end end
    end
    local id = found and found.ranks and found.ranks[1] and found.ranks[1].id
    local client = id and C.spellName(id) or nil
    sq.names[n] = { id = id, client = client, ok = client == n }
  end
  if ctx then sq.mine = { cls = ctx.member.cls, role = ctx.member.role, seq = ctx.member.seq, leader = ctx.member.leader } end
  r.seqCheck = sq
  -- keybinds that press a WBX macro directly, with what they did before (read_log shows them)
  -- squad automation: which APIs this client has, and which options are on ([AFKLAR] until the launch test)
  if ns.Auto then
    local okA, aprobe = pcall(ns.Auto.probe)
    local on = {}
    for _, o in ipairs(ns.Auto.OPTIONS) do on[o[1]] = ns.Auto.on(o[1]) end
    r.auto = { api = okA and aprobe or { error = tostring(aprobe) }, on = on, last = ns.Auto.last }
  end
  -- the 12 main buttons and their keybinds at login: slot, content, key ("button 3 missing" is visible in the files)
  r.buttons = {}
  for slot = 1, 12 do
    local c = B.content(slot)
    local keys = {}
    for _, k in ipairs(ns.Binds.keysFor("", slot)) do keys[#keys + 1] = k.key end
    r.buttons[slot] = { content = c.kind .. (c.name and (":" .. c.name) or (c.id and (":" .. c.id) or "")), keys = table.concat(keys, " ") }
  end
  r.bindingSet = ns.Binds.currentSet()
  -- own macros C1–C8 and the last steps of their flows (docs/feedback-2026-10-30-night.md §1)
  if ctx then
    r.ownMacros = {}
    for i, c in ipairs(ctx.member.customSeq or {}) do
      local st
      for _, it in ipairs(ctx.macros.items) do if it.name == "WBX C" .. i then st = it.status end end
      r.ownMacros[i] = { name = c.name, kind = c.kind, steps = table.concat(c.steps or {}, ","), status = st, override = Core.cdb.overrides["WBX C" .. i] ~= nil }
    end
    r.ownFlow = {}
    for k = #db.log, 1, -1 do
      local e = db.log[k]
      if e.m:find("^own macro") then table.insert(r.ownFlow, 1, e.m) end
      if #r.ownFlow >= 20 then break end
    end
  end
  r.lastReset = db.lastReset
  local nOrig = 0
  for _ in pairs(Core.cdb.barOriginal or {}) do nOrig = nOrig + 1 end
  r.barOriginal = nOrig
  local okB, direct = pcall(ns.Binds.directWbx)
  r.binds = { direct = okB and direct or { error = tostring(direct) }, prev = Core.cdb.bindPrev, lost = okB and ns.Binds.lostButtons() or nil }
  r.ui = { dropdown = (ns.Widgets and ns.Widgets.hasBlizzardDropdown and ns.Widgets.hasBlizzardDropdown()) and "blizzard" or "own" }
  r.ui.helpPlate = (ns.Help and ns.Help.blizzard and ns.Help.blizzard()) and "blizzard" or "own"
  r.ui.helpUsed = ns.Help and ns.Help.diag or nil
  db.diag[Core.charKey or "?"] = r
  Core.log("info", "selftest written to WoWBoxerDB.diag[" .. tostring(Core.charKey) .. "]")
  if ns.Squad and ns.Team then
    local ok, rows = pcall(ns.Squad.readiness)
    local parts = {}
    for _, row in ipairs(ok and rows or {}) do
      if not row.me then parts[#parts + 1] = row.m.name .. "=" .. (row.inParty and "party" or "not in party") .. "/" .. (row.signal and "signal" or "no signal") end
    end
    if #parts > 0 then Core.log("info", "team sees: " .. table.concat(parts, ", ") .. " (sent " .. C.sendStats.ok .. ", failed " .. C.sendStats.failed .. ")") end
  end
  if not quiet then chat("Selftest done. /reload (or log out) to save it to WTF\\...\\SavedVariables\\WoWBoxer.lua.") end
  return r
end

-- ------------------------------------------------------------------ slash commands
local HELP = {
  "/wbx – open or close the window",
  "/wbx discord | youtube | website – the link to copy; /wbx help – help on Discord (#setup-help)",
  "/wbx report – Report a problem: a text to copy into #setup-help (nothing is sent)",
  "/wbx sync – create/update your macros and place new ones on your bars (same as Place all)",
  "/wbx minimap – show or hide the minimap button",
  "/wbx guide – start the first-run guide again at step 1",
  "/wbx bars – list where each macro is and its keybind",
  "/wbx keys – open the game's key bindings (Quick Keybind mode where available)",
  "/wbx team on|off – team status panel (display only: follow, target, mana of your other clients)",
  "/wbx sell [add|remove] [item] – your sell list (sold with Sell junk; shared with Share sell list)",
  "/wbx scale 0.9 – window size (0.7–1.3); /wbx reset – window back to the middle; /wbx reset all – Reset to default…",
  "/wbx show – list your macros and what would change",
  "/wbx cvars | /wbx cvars restore – apply recommended settings / put the old ones back",
  "/wbx selftest – write a diagnostic report to the saved variables",
  "/wbx shots – screenshots of every WoWBoxer page (for the website; read-only)",
  "/wbx log [n] – show the last n log lines; /wbx debug – toggle debug messages",
  "/wbx sound – warning sound on/off (follow warning, GM whispers); the warning text stays",
  "/wbx barfit – which action bars are visible and whether every button fits in this window (read-only)",
  "/wbx names – how the game names your party and which squad member each one matches (read-only)",
}
--- /wbx names: the names exactly as the game gives them, the squad match per member, and the send results.
function Core.namesReport()
  local lines = {}
  for _, u in ipairs({ "player", "party1", "party2", "party3", "party4" }) do
    local ok, n, realm = pcall(UnitName, u)
    if ok and n ~= nil and not C.isSecret(n) then
      lines[#lines + 1] = u .. ": \"" .. tostring(n) .. "\"" .. ((realm and not C.isSecret(realm) and realm ~= "") and (" realm \"" .. tostring(realm) .. "\"") or "")
    end
  end
  local s, me = Core.me()
  for _, m in ipairs(s and s.members or {}) do
    local u = m == me and "player (you)" or ns.Squad.unitOf(m.name)
    local p = ns.Team and ns.Team.peer(m.name)
    lines[#lines + 1] = "squad \"" .. m.name .. "\" -> " .. (u or "|cffff8a80not in your party here|r") .. (m == me and "" or (p and ", signal" or ", no signal"))
  end
  if not me then lines[#lines + 1] = "|cffff8a80This character is not in a squad.|r" end
  local got = {}
  for k, v in pairs(C.arrivals) do got[#got + 1] = k .. " x" .. v end
  table.sort(got)
  lines[#lines + 1] = "received: " .. (#got > 0 and table.concat(got, ", ") or "nothing yet")
  lines[#lines + 1] = "addon messages: " .. C.sendStats.ok .. " sent, " .. C.sendStats.failed .. " failed" .. (C.sendStats.last and (" (last: " .. C.sendStats.last .. ")") or "")
  return lines
end
function Core.slash(msg)
  msg = (msg or ""):match("^%s*(.-)%s*$")
  local cmd, rest = msg:match("^(%S*)%s*(.-)$")
  cmd = (cmd or ""):lower()
  if cmd == "" then if ns.UI and ns.UI.Toggle then ns.UI.Toggle() else chat("window not available") end
  elseif cmd == "?" or cmd == "commands" then for _, l in ipairs(HELP) do chat(l) end
  elseif cmd == "help" then
    for _, l in ipairs(HELP) do chat(l) end
    if ns.Community then
      chat("Help on Discord: " .. ns.Community.chatLink("discordHelp", "#setup-help") .. " · " .. ns.Community.chatLink("report", "Report a problem"))
      ns.Community.ShowLink("discordHelp")
    end
  elseif cmd == "discord" or cmd == "youtube" or cmd == "website" then if ns.Community then ns.Community.ShowLink(cmd) end
  elseif cmd == "report" then if ns.Community then ns.Community.ShowReport() end
  elseif cmd == "sync" then Core.sync({ replace = rest == "replace" })
  elseif cmd == "sound" then
    local on = rest == "on" or (rest ~= "off" and not ns.Auto.on("warnSound"))
    ns.Auto.set("warnSound", on)
    Core.log("info", "automation warnSound " .. (on and "on" or "off") .. " (/wbx sound)")
    chat("Warning sound " .. (on and "on." or "off – the warnings still show on screen and in chat."))
    if ns.UI and ns.UI.Refresh and ns.UI.frame and ns.UI.frame:IsShown() then ns.UI.Refresh() end
  elseif cmd == "names" then for _, l in ipairs(Core.namesReport()) do chat(l) end
  elseif cmd == "barfit" then
    local m = ns.BarFit and ns.BarFit.update("/wbx barfit")
    chat(ns.BarFit and ns.BarFit.summary(m) or "bars: not measured")
    for _, b in ipairs(m and m.bars or {}) do
      chat(string.format("  %s: %d buttons, %d outside, %d under another bar (%s)", b.label, b.buttons, b.outside, b.covered, b.anchor))
    end
  elseif cmd == "sell" then if ns.Relay then ns.Relay.slash(rest) end
  elseif cmd == "team" then
    -- one switch (Talex, #help 10 Nov: "team off" then "team on" did not bring the box back – `on and nil or false`
    -- is always false in Lua, and the window had a second switch of its own)
    local on = rest == "on" or (rest == "" and Core.db.settings.team == false)
    if rest == "off" then on = false end
    if ns.TeamFrame then ns.TeamFrame.SetShown(on) else Core.db.settings.team = S.offOrNil(on and true or false) end
    if not on then chat("Team status off: nothing is sent or shown.")
    else chat("Team status on. " .. (ns.Team and ns.Team.whyHidden and ns.Team.whyHidden() or "")) end
  elseif cmd == "audit" then
    if ns.UI then ns.UI.Open() end
    local res = ns.Audit and ns.Audit.run()
    chat("Layout audit: " .. (res and #res or 0) .. " finding(s), saved for the next /reload.")
  elseif cmd == "shots" then if ns.Shots then ns.Shots.run() end
  elseif cmd == "keys" then Core.openKeyBindings()
  elseif cmd == "guide" then if ns.Book then ns.Book.ShowGuide() end
  elseif cmd == "reset" and rest == "all" then
    if ns.Advanced then ns.Advanced.openReset() end -- the same two-step window; never resets directly
  elseif cmd == "reset" then
    Core.db.settings.window, Core.db.settings.scale = nil, nil
    if Core.cdb then Core.cdb.window = nil end
    if ns.UI and ns.UI.ApplyWindowSettings then ns.UI.ApplyWindowSettings() end
    chat("Window position and size reset.")
  elseif cmd == "scale" then
    local v = tonumber(rest)
    if not v then chat("Window scale is " .. tostring(Core.db.settings.scale or 1) .. ". Example: /wbx scale 0.9"); return end
    Core.db.settings.scale = math.max(0.7, math.min(1.3, v))
    if ns.UI and ns.UI.ApplyWindowSettings then ns.UI.ApplyWindowSettings() end
    chat("Window scale " .. Core.db.settings.scale .. ".")
  elseif cmd == "bars" then
    local ctx, why = Core.compute()
    if not ctx then chat(why); return end
    for _, it in ipairs(ctx.bars.items) do
      local keys = {}
      for _, k in ipairs(ns.Binds.keysFor(it.name, it.status == "placed" and it.slot or nil)) do keys[#keys + 1] = k.key end
      chat(string.format("  %s – %s: %s%s", it.name, it.label or "", it.status == "placed" and B.slotLabel(it.slot) or ("not placed (" .. it.status .. ")"),
        #keys > 0 and (" · keybind " .. table.concat(keys, ", ")) or ""))
    end
  elseif cmd == "minimap" then if ns.Minimap then ns.Minimap.SetHidden(not Core.db.settings.minimapHidden) end
  elseif cmd == "show" then
    local ctx, why = Core.compute()
    if not ctx then chat(why) return end
    chat(string.format("%s, level %d (%s): %d to create, %d to update, %d unchanged, %d free macro slots.", ctx.member.name, ctx.level,
      ctx.member.leader and "leader" or ("follows via " .. ctx.member.unit), ctx.macros.counts.create, ctx.macros.counts.update, ctx.macros.counts.same, ctx.macros.free))
    for _, it in ipairs(ctx.macros.items) do chat("  " .. it.name .. " – " .. it.label .. " [" .. it.status .. "]") end
  elseif cmd == "cvars" then if rest == "restore" then Core.restoreCVars() else Core.applyCVars(Core.cdb.importCVars) end
  elseif cmd == "selftest" then Core.selftest()
  elseif cmd == "debug" then Core.db.settings.debug = not Core.db.settings.debug; chat("debug " .. (Core.db.settings.debug and "on" or "off"))
  elseif cmd == "log" then
    local n = tonumber(rest) or 10
    local log = Core.db.log
    for i = math.max(1, #log - n + 1), #log do local e = log[i]; chat(date("%H:%M:%S", e.t) .. " " .. e.l .. " " .. e.m) end
  else chat("unknown command. /wbx help") end
end

-- ------------------------------------------------------------------ events
local frame = CreateFrame("Frame")
Core.frame = frame
local function safeRegister(ev) pcall(frame.RegisterEvent, frame, ev) end
safeRegister("ADDON_LOADED")
safeRegister("PLAYER_LOGIN")

local spellsTimer, barsTimer, macrosTimer
function Core.onEvent(event, ...)
  if event == "ADDON_LOADED" then
    local name = ...
    if name ~= ADDON then return end
    Core.db, Core.cdb = S.initDB(_G.WoWBoxerDB, _G.WoWBoxerCharDB)
    _G.WoWBoxerDB, _G.WoWBoxerCharDB = Core.db, Core.cdb
  elseif event == "PLAYER_LOGIN" then
    Core.charKey = (C.playerName() or "?") .. "-" .. (GetRealmName and GetRealmName() or "?")
    Core.writeBridge("login")
    if not Core.cdb.welcomed then
      Core.cdb.welcomed = true
      chat("loaded. Type |cffffd100/wbx|r or click the minimap button to set up this character's macros.")
    end
    safeRegister("PLAYER_LOGOUT")
    safeRegister("UI_SCALE_CHANGED")
    safeRegister("DISPLAY_SIZE_CHANGED")
    Core.log("info", "login " .. Core.charKey .. " " .. C.buildString() .. " (" .. C.game() .. ", toc " .. C.interface() .. ")")
    safeRegister("PLAYER_LEVEL_UP")
    safeRegister("PLAYER_REGEN_ENABLED")
    safeRegister("CURSOR_CHANGED")
    safeRegister("SPELLS_CHANGED")
    safeRegister("LEARNED_SPELL_IN_TAB")
    safeRegister("LEARNED_SPELL_IN_SKILL_LINE")
    Core.defaultBars()
    safeRegister("ACTIONBAR_SLOT_CHANGED")
    safeRegister("UPDATE_BINDINGS")
    safeRegister("UPDATE_MACROS")
    Core.scanBars()
    if ns.Minimap and ns.Minimap.Init then ns.Minimap.Init() end
    if ns.Team and ns.Team.Init then ns.Team.Init() end
    if ns.SeqStrip and ns.SeqStrip.Init then ns.SeqStrip.Init() end
    if ns.Sync and ns.Sync.Init then ns.Sync.Init() end
    if ns.Settings and ns.Settings.Init then ns.Settings.Init() end
    if ns.Auto and ns.Auto.Init then ns.Auto.Init() end
    if ns.Equip and ns.Equip.Init then ns.Equip.Init() end
    if ns.Loot and ns.Loot.Init then ns.Loot.Init() end
    if ns.Relay and ns.Relay.Init then ns.Relay.Init() end
    if C_Timer and C_Timer.After then C_Timer.After(3, function() Core.checkOffer("login") end) end
    if C_Timer and C_Timer.After then C_Timer.After(6, function() local ok, err = pcall(Core.loginChecks); if not ok then Core.log("error", "login checks: " .. tostring(err)) end end) end
    -- read-only diagnose a few seconds after login, so a /reload is enough to see how the addon behaves in this client
    if C_Timer and C_Timer.After then
      C_Timer.After(5, function()
        if ns.BarFit then ns.BarFit.update("login") end
        local ok, err = pcall(Core.selftest, true)
        if not ok then Core.log("error", "auto selftest: " .. tostring(err)) end
      end)
    end
  elseif event == "PLAYER_LOGOUT" then
    Core.writeBridge("logout") -- also fires on /reload, right before SavedVariables are written
    if ns.BarFit then ns.BarFit.update("logout") end
  elseif event == "UI_SCALE_CHANGED" or event == "DISPLAY_SIZE_CHANGED" then
    -- the window app (Auto-fit) or the player changed the window or the UI scale: measure again once it settles
    if C_Timer and C_Timer.After and ns.BarFit then C_Timer.After(1, function() ns.BarFit.update(event) end) end
  elseif event == "CURSOR_CHANGED" then Core.onCursorChanged()
  elseif event == "PLAYER_REGEN_ENABLED" then
    Core.runQueue()
    if ns.BarFit and ns.BarFit.afterCombat then ns.BarFit.afterCombat() end
  elseif event == "PLAYER_LEVEL_UP" then
    local lvl = ...
    Core.log("info", "level up to " .. tostring(lvl))
    C.invalidateSpellbook()
    if C_Timer and C_Timer.After then C_Timer.After(1, function() Core.checkOffer("level " .. tostring(lvl)) end) else Core.checkOffer("level") end
  elseif event == "SPELLS_CHANGED" or event == "LEARNED_SPELL_IN_TAB" or event == "LEARNED_SPELL_IN_SKILL_LINE" then
    C.invalidateSpellbook()
    if spellsTimer then return end
    spellsTimer = true
    local function run() spellsTimer = nil; Core.checkOffer("spells") end
    if C_Timer and C_Timer.After then C_Timer.After(2, run) else run() end
  elseif event == "ACTIONBAR_SLOT_CHANGED" then
    -- many fire at once (page swaps, drags): rescan once, a moment later
    if barsTimer then return end
    barsTimer = true
    local function run() barsTimer = nil; Core.scanBars(); Core.changed() end
    if C_Timer and C_Timer.After then C_Timer.After(0.3, run) else run() end
  elseif event == "UPDATE_BINDINGS" then
    Core.changed()
  elseif event == "UPDATE_MACROS" then
    -- a macro was made, changed or deleted (here or in /macro): refresh once, so "x of 18", the banner and the
    -- book all count the same macros
    if macrosTimer then return end
    macrosTimer = true
    local function run() macrosTimer = nil; Core.changed() end
    if C_Timer and C_Timer.After then C_Timer.After(0.2, run) else run() end
  end
end
frame:SetScript("OnEvent", function(_, event, ...) Core.onEvent(event, ...) end)

_G.SLASH_WOWBOXER1 = "/wbx"
_G.SLASH_WOWBOXER2 = "/wowboxer"
_G.SlashCmdList["WOWBOXER"] = function(msg) Core.slash(msg) end

-- used by the UI
Core.K = K
