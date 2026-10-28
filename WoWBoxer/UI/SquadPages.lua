--[[ WoWBoxer – Squad sub-pages Readiness, Key map and Plan (docs/squad-overhaul.md §3.2). Other characters' state
  comes from the display-only team messages; each client can only fix itself, so fixes are buttons on this
  character's row and the other rows say on which window to fix them. ]]
local _, ns = ...
local W, SP = ns.Widgets, ns.SquadPages
local LIST_W = 648
local READY = "Interface\\RaidFrame\\ReadyCheck-Ready"
local NOT_READY = "Interface\\RaidFrame\\ReadyCheck-NotReady"
local WAITING = "Interface\\RaidFrame\\ReadyCheck-Waiting"

local function Core() return ns.Core end
local function S() return ns.State end
local function squad() return S().activeSquad(Core().db) end

local function header(f, cols, y)
  f.heads = {}
  for _, c in ipairs(cols) do
    local t = W.line(f, "GameFontNormalSmall", nil, W.GOLD, c[3] or "LEFT")
    t:SetPoint("TOPLEFT", c[2], y or 0)
    t:SetWidth(c[4] or 60)
    t:SetText(c[1])
    t.wbxCopy = "label"
    f.heads[#f.heads + 1] = t
  end
end

-- ------------------------------------------------------------------ Readiness
local RCOLS = { { "Character", 4, "LEFT", 128 }, { "In party", 140, "CENTER", 56 }, { "Unit", 200, "CENTER", 56 }, { "Keys", 260, "CENTER", 56 },
  { "Follow/Assist", 320, "CENTER", 84 }, { "Settings", 408, "CENTER", 60 }, { "Signal", 472, "CENTER", 48 } }
local CHECKS = { "party", "unit", "keys", "helpers", "cvars", "signal" }
--- {party, unit, keys, helpers, cvars, signal} = true / false / nil (unknown) for one readiness row.
function SP.readyChecks(row)
  local rd = row.ready
  local c = { party = row.inParty and true or false, signal = row.signal and true or false }
  if rd then
    c.unit = rd.unit == 1 or (rd.unit == 0 and false) or nil
    c.keys = rd.keys == 0
    c.helpers = rd.helpers == 1
    c.cvars = rd.cvars == 0
  end
  return c
end
--- The one fix this client can make for itself: {label, tip, fn} or nil.
function SP.myFix(row)
  local rd = row.ready
  if not rd then return nil end
  local hu = ns.Squad.unitHint()
  if hu then return { "Use " .. hu, "Your keys follow the leader through " .. hu .. " here (WoWBoxer's setting only; then Update keys).", function() Core().setPlaysAs(hu) end } end
  if rd.keys > 0 or rd.helpers == 0 then
    return { "Update keys", "Creates or updates your WoWBoxer macros and puts missing keys on your bars.", function() Core().sync({ replace = Core().cdb.replace }) end }
  end
  if rd.cvars > 0 then
    return { "Apply settings", "Changes the recommended game settings on this client (the old values are kept for Restore).", function() Core().applyCVars(Core().cdb.importCVars) end }
  end
  return nil
end

SP.register({ key = "ready", label = "Readiness", tip = "Is everyone set up? One line per character; fix your own line here.",
  build = function(f)
    header(f, RCOLS)
    local sf, content = W.scroll(f, LIST_W, 10 * 26)
    sf:SetPoint("TOPLEFT", 0, -18)
    f.sf, f.list = sf, content
    f.pool = W.pool(content, function(parent)
      local r = CreateFrame("Frame", nil, parent)
      r:SetSize(LIST_W - 4, 24)
      r.bg = r:CreateTexture(nil, "BACKGROUND")
      r.bg:SetAllPoints()
      r.name = W.line(r, "GameFontHighlightSmall", nil, W.TEXT)
      r.name:SetPoint("LEFT", 4, 0)
      r.name:SetWidth(128)
      r.icons = {}
      for i, key in ipairs(CHECKS) do
        local col = RCOLS[i + 1]
        local t = r:CreateTexture(nil, "ARTWORK")
        t:SetSize(16, 16)
        t:SetPoint("CENTER", r, "LEFT", col[2] + col[4] / 2, 0)
        r.icons[key] = t
      end
      r.fix = W.button(r, "Fix", 60, 20, function() if r.fixFn then r.fixFn() end end, { "Fix", function() return r.fixTip end })
      r.fix:SetPoint("RIGHT", -2, 0)
      r.where = W.line(r, "GameFontHighlightSmall", nil, W.MUTED, "RIGHT")
      r.where:SetPoint("RIGHT", -4, 0)
      r.where:SetWidth(100)
      W.tooltip(r, function(GT) GT:AddLine(r.title or "", 1, 0.82, 0); for _, l in ipairs(r.lines or {}) do GT:AddLine(l, 1, 1, 1, true) end end)
      return r
    end)
    f.note = W.text(f, "GameFontHighlightSmall", nil, W.MUTED)
    f.note:SetPoint("TOPLEFT", 0, -18 - 10 * 26 - 8)
    f.note:SetWidth(LIST_W)
    f.note:SetJustifyV("TOP")
    if f.note.SetMaxLines then f.note:SetMaxLines(5) end
  end,
  refresh = function(f)
    f.pool:reset()
    local rows = ns.Squad.readiness()
    local myVer = ns.Team.version()
    local notes = {}
    for i, row in ipairs(rows) do
      local r = f.pool:get()
      r:ClearAllPoints()
      r:SetPoint("TOPLEFT", 0, -(i - 1) * 26)
      r.bg:SetColorTexture(row.me and 0.3 or 0, row.me and 0.24 or 0, 0, row.me and 0.25 or 0.22)
      r.name:SetText(W.hex(W.classColor(row.m.cls)) .. row.m.name .. "|r" .. (row.me and " |cffffd100(you)|r" or ""))
      local c = SP.readyChecks(row)
      for _, key in ipairs(CHECKS) do
        local v = c[key]
        r.icons[key]:SetTexture(v == true and READY or v == false and NOT_READY or WAITING)
      end
      local rd = row.ready
      r.title = row.m.name
      r.lines = {
        "In party: " .. (c.party and "yes" or "no"),
        "Unit: " .. (c.unit == true and "the leader is where the keys expect him" or c.unit == false and "the keys point at another party member" or "unknown"),
        "Keys: " .. (rd and (rd.keys == 0 and "up to date" or (rd.keys .. " to create, update or place")) or "unknown"),
        "Follow/Assist on a bar: " .. (rd and (rd.helpers == 1 and "yes" or "no") or "unknown"),
        "Game settings: " .. (rd and (rd.cvars == 0 and "applied" or (rd.cvars .. " to change")) or "unknown"),
        "Signal: " .. (row.signal and ("WoWBoxer " .. (row.version or "?")) or "none – is WoWBoxer running there and in your party?"),
      }
      if row.me then
        local fix = SP.myFix(row)
        r.fix:SetShown(fix ~= nil); r.where:Hide()
        if fix then W.setLabel(r.fix, fix[1]); r.fixTip, r.fixFn = fix[2], fix[3]; r.fix:SetEnabled(not ns.Compat.inCombat()) end
      else
        r.fix:Hide()
        local bad = false
        for _, key in ipairs(CHECKS) do if c[key] == false then bad = true end end
        r.where:SetShown(bad and row.signal)
        r.where:SetText("Fix there")
      end
      if row.version and row.version ~= myVer and not row.me then
        notes[#notes + 1] = "|cfff0b43c" .. row.m.name .. " runs WoWBoxer " .. row.version .. "|r (here " .. myVer .. ")"
      end
    end
    f.list:SetHeight(math.max(10, #rows * 26))
    notes[#notes + 1] = "Fix your line here, others on their clients"
    f.note:SetText(table.concat(notes, "\n"))
  end })

-- ------------------------------------------------------------------ Key map: same key, same job
local KX, KW = 136, 40
SP.register({ key = "keymap", label = "Key map", tip = "Same key, same job: which spell each character has on each key.",
  build = function(f)
    local h = W.line(f, "GameFontNormalSmall", nil, W.GOLD)
    h:SetPoint("TOPLEFT", 4, 0)
    h:SetWidth(KX - 8)
    h:SetText("Character")
    f.heads = {}
    for i, k in ipairs(ns.Squad.KEYS) do
      local t = W.line(f, "GameFontNormalSmall", nil, W.GOLD, "CENTER")
      t:SetPoint("TOPLEFT", KX + (i - 1) * KW, 0)
      t:SetWidth(KW)
      t:SetText(k[2])
      f.heads[i] = t
    end
    local sf, content = W.scroll(f, LIST_W, 9 * 30)
    sf:SetPoint("TOPLEFT", 0, -18)
    f.sf, f.list = sf, content
    f.pool = W.pool(content, function(parent)
      local r = CreateFrame("Frame", nil, parent)
      r:SetSize(LIST_W - 4, 28)
      r.name = W.line(r, "GameFontHighlightSmall", nil, W.TEXT)
      r.name:SetPoint("LEFT", 4, 0)
      r.name:SetWidth(KX - 8)
      r.cells = {}
      for i = 1, #ns.Squad.KEYS do
        local c = CreateFrame("Frame", nil, r)
        c:SetSize(26, 26)
        c:SetPoint("CENTER", r, "LEFT", KX + (i - 1) * KW + KW / 2, 0)
        c.bg = c:CreateTexture(nil, "BACKGROUND")
        c.bg:SetAllPoints()
        c.icon = W.icon(c, 24)
        c.icon:SetPoint("CENTER")
        W.tooltip(c, function(GT) GT:AddLine(c.title or "", 1, 0.82, 0); GT:AddLine(c.text or "", 1, 1, 1, true) end)
        r.cells[i] = c
      end
      return r
    end)
    f.note = W.text(f, "GameFontHighlightSmall", nil, W.MUTED)
    f.note:SetPoint("TOPLEFT", 0, -18 - 9 * 30 - 6)
    f.note:SetWidth(LIST_W - 150)
    f.note:SetJustifyV("TOP")
    if f.note.SetMaxLines then f.note:SetMaxLines(4) end
    f.copy = W.button(f, "Cheat sheet", 100, 22, function() SP.showCheatSheet(f) end,
      "Shows the key map as text: Select all, Ctrl+C, and paste it wherever you keep notes.")
    f.copy:SetPoint("TOPRIGHT", 0, -18 - 9 * 30 - 4)
    -- the cheat sheet box
    local box = W.box(f, 0.09, 0.07, 0.045, 0.99)
    box:SetAllPoints()
    box:SetFrameLevel((f:GetFrameLevel() or 1) + 20)
    box:EnableMouse(true)
    box.wbxModal = true
    box:Hide()
    f.sheet = box
    local sb
    box.edit, sb = W.editBox(box, LIST_W - 40, 300)
    sb:SetPoint("TOPLEFT", 12, -12)
    box.edit:SetScript("OnTextChanged", function(self, user) if user and box.text then self:SetText(box.text); self:HighlightText() end end)
    box.close = W.button(box, "Close", 80, 22, function() box:Hide() end, "Closes the cheat sheet.")
    box.close:SetPoint("BOTTOMRIGHT", -10, 10)
    box.sel = W.button(box, "Select all", 90, 22, function() box.edit:SetFocus(); box.edit:HighlightText() end, "Selects the text, so Ctrl+C copies it.")
    box.sel:SetPoint("RIGHT", box.close, "LEFT", -6, 0)
  end,
  refresh = function(f)
    local s = squad()
    local map = ns.Squad.keyMap(s)
    -- the header shows this client's key for each column when the key is on a bar
    for i, k in ipairs(map.cols) do
      local label = k[2]
      local slot = Core().cdb.slots["WBX " .. k[1]]
      local keys = slot and ns.Binds.keysFor("WBX " .. k[1], slot) or {}
      if keys[1] and k[1]:match("^K") then label = ns.Binds.short(keys[1].key) end
      f.heads[i]:SetText(label)
    end
    f.pool:reset()
    for i, row in ipairs(map.rows) do
      local r = f.pool:get()
      r:ClearAllPoints()
      r:SetPoint("TOPLEFT", 0, -(i - 1) * 30)
      r.name:SetText(W.hex(W.classColor(row.m.cls)) .. row.m.name .. "|r")
      for j, k in ipairs(map.cols) do
        local c, cell = r.cells[j], row.cells[k[1]]
        local someone = false
        for _, other in ipairs(map.rows) do if other.cells[k[1]] then someone = true end end
        if cell then
          W.setIcon(c.icon, cell.icon); c.icon:Show(); c.bg:SetColorTexture(0, 0, 0, 0.4)
          c.title, c.text = row.m.name .. " – " .. (k[2]:match("^%d$") and ("Key " .. k[2]) or k[2]), cell.label
        else
          c.icon:Hide()
          local gap = someone and k[1]:match("^K") ~= nil
          c.bg:SetColorTexture(gap and 0.45 or 0, 0, 0, gap and 0.35 or 0.15)
          c.title, c.text = row.m.name, gap and "No spell on this key yet (level or class) – the others have one here." or "Not used by this character."
        end
      end
    end
    f.list:SetHeight(math.max(10, #map.rows * 30))
    f.note:SetText("Same key, same job on every client" ..
      (map.gaps > 0 and ("\n|cfff0b43c" .. map.gaps .. " gap" .. (map.gaps == 1 and "" or "s") .. "|r (red): not everyone has it") or ""))
    f.sheet.text = ns.Squad.cheatSheet(s)
  end })
function SP.showCheatSheet(f)
  f.sheet.text = ns.Squad.cheatSheet(squad())
  f.sheet.edit:SetText(f.sheet.text)
  f.sheet:Show()
  f.sheet.edit:SetFocus(); f.sheet.edit:HighlightText()
end

-- ------------------------------------------------------------------ Plan: levelling together
local PCOLS = { { "Character", 4, "LEFT", 128 }, { "Level", 136, "CENTER", 44 }, { "Next trainer visit", 188, "LEFT", 220 }, { "Next talent", 416, "LEFT", 228 } }
SP.register({ key = "plan", label = "Plan", tip = "Levelling together: levels, the next trainer visit and the next talent of everyone.",
  build = function(f)
    header(f, PCOLS)
    local sf, content = W.scroll(f, LIST_W, 10 * 26)
    sf:SetPoint("TOPLEFT", 0, -18)
    f.sf, f.list = sf, content
    f.pool = W.pool(content, function(parent)
      local r = CreateFrame("Frame", nil, parent)
      r:SetSize(LIST_W - 4, 24)
      r.bg = r:CreateTexture(nil, "BACKGROUND")
      r.bg:SetAllPoints()
      r.bg:SetColorTexture(0, 0, 0, 0.22)
      r.cols = {}
      for i, c in ipairs(PCOLS) do
        local t = W.line(r, "GameFontHighlightSmall", nil, i == 1 and W.TEXT or W.TEXT, c[3])
        t:SetPoint("LEFT", c[2], 0)
        t:SetWidth(c[4])
        if i >= 3 then t.wbxCopy = "data" end
        r.cols[i] = t
      end
      W.tooltip(r, function(GT) GT:AddLine(r.title or "", 1, 0.82, 0); for _, l in ipairs(r.lines or {}) do GT:AddLine(l, 1, 1, 1, true) end end)
      return r
    end)
    f.link = W.check(f, "Leader's level", function(_, v) local s = squad(); if s then s.linkLevels = v; S().applyLink(s); Core().changed() end end)
    f.link:SetPoint("TOPLEFT", -4, -18 - 10 * 26 - 6)
    W.tip(f.link, "Leader's level", "For planning: everyone is shown at the leader's level (levels from the team status win when a client reports one).")
    f.note = W.text(f, "GameFontHighlightSmall", nil, W.MUTED)
    f.note:SetPoint("TOPLEFT", 0, -18 - 10 * 26 - 34)
    f.note:SetWidth(LIST_W)
    f.note:SetText("Levels from team status, else the squad")
  end,
  refresh = function(f)
    local s = squad()
    f.link:SetChecked(s and s.linkLevels or false)
    f.pool:reset()
    for i, row in ipairs(ns.Squad.readiness()) do
      local m = row.m
      local lvl = row.level or m.level
      local probe = { cls = m.cls, race = m.race, role = m.role, level = lvl, talented = m.talented, build = m.build, guide = m.guide }
      local r = f.pool:get()
      r:ClearAllPoints()
      r:SetPoint("TOPLEFT", 0, -(i - 1) * 26)
      local tl, names = ns.Squad.nextTrainer(probe)
      local nt = ns.Squad.nextTalent(probe)
      r.cols[1]:SetText(W.hex(W.classColor(m.cls)) .. m.name .. "|r" .. (row.me and " |cffffd100(you)|r" or ""))
      r.cols[2]:SetText(tostring(lvl))
      r.cols[3]:SetText(tl and ("Level " .. tl .. ": " .. table.concat(names, ", ")) or "Nothing new")
      r.cols[4]:SetText(nt and ("Level " .. nt.level .. ": " .. nt.name) or (lvl < 10 and "From level 10" or "Plan complete"))
      r.title = m.name
      r.lines = { "Level " .. lvl .. (row.signal and not row.me and " (reported by its client)" or ""),
        tl and ("Next trainer visit at level " .. tl .. ": " .. table.concat(names, ", ")) or "No new spells from the trainer in the data.",
        nt and ("Next talent: " .. nt.name .. " at level " .. nt.level) or "No next talent in the plan." }
    end
    f.list:SetHeight(math.max(10, #(s and s.members or {}) * 26))
  end })
