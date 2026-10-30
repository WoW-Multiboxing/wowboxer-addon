--[[ WoWBoxer – the Squad bookmark (docs/squad-v2-simple.md §2): ONE screen with one job – who plays together.
  Rows (crown = leader, role, follows, remove, click = small inline editor), "Add character" by name for characters not
  in the party, "Add my party", a party suggestion, the squad keys, and ONE explicit action: Send to my other
  characters. Changes save at once ("Saved" flashes); nothing here switches the active squad except the squad
  dropdown itself (New squad… / Delete squad…). Readiness, Key map, Plan and Leader presets sit under More
  (UI/SquadPages.lua). Only WoWBoxer's own setup changes here; macros change when the player presses Place all /
  Update keys, and other clients only ever get offers they must click (Sync.lua). ]]
local _, ns = ...
local UI, W = ns.UI, ns.Widgets
local tab = { key = "squad", label = "Squad", icon = "Spell_Holy_PrayerOfFortitude", tip = "The characters you play together: who plays what and who leads." }
local SP = { pages = {}, byKey = {} }
ns.SquadPages = SP

local T = ns.Theme
local LIST_W = 648 -- + scrollbar
-- the war table look: party-frame rows (class edge, class icon, name over "Class · level", the follow line labelled)
local ROW_H, EDIT_H, ADD_H = W.themed() and 44 or 28, 58, 30
local LIST_H = 252
local TOP_H = 30
local NEW, DEL = "\1new", "\1del"
local SAVED = "|TInterface\\RaidFrame\\ReadyCheck-Ready:12:12|t Saved"

local function D() return ns.Data end
local function S() return ns.State end
local function Core() return ns.Core end
local function squad() return S().activeSquad(Core().db) end

--- Register a page: {key, label, tip, build(f, p), refresh(f, p), more = true for the pages under More}.
function SP.register(def) SP.pages[#SP.pages + 1] = def; SP.byKey[def.key] = def end

local CLASS_TEX = "Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES"
function SP.setClassIcon(tex, cls)
  local tc = _G.CLASS_ICON_TCOORDS and _G.CLASS_ICON_TCOORDS[(cls or ""):upper()]
  if tc then tex:SetTexture(CLASS_TEX); if tex.SetTexCoord then tex:SetTexCoord(tc[1], tc[2], tc[3], tc[4]) end
  else W.setIcon(tex, D().classes[cls] and ("ClassIcon_" .. cls) or nil) end
end
function SP.classValues() local v = {}; for _, c in ipairs(D().classOrder) do v[#v + 1] = { c, D().classes[c].n } end return v end
function SP.raceValues(m)
  local v = {}
  for _, r in ipairs(S().racesFor(m.cls)) do v[#v + 1] = { r.k, r.n } end
  return v
end
function SP.roleValues(m) local v = {}; for _, r in ipairs(D().classes[m.cls].roles) do v[#v + 1] = { r, S().ROLE_NAME[r] } end return v end
function SP.presetValues(s)
  local v = {}
  for _, p in ipairs(s and s.presets or {}) do
    local L = S().member(s, p.leader)
    v[#v + 1] = { p.id, p.name, (L and (L.name .. " leads") or "") .. ". Choosing it changes who leads (and the roles saved with it) in WoWBoxer; every client then updates its own macros." }
  end
  return v
end
local ORD = { "1st", "2nd", "3rd" }
--- "Leader" or "2nd in line · follows Anna" (the follow line: the squad order, docs/follow-line.md).
function SP.followsText(m, s)
  if m.leader then return "Leader" end
  local line = S().line(s)
  for i, x in ipairs(line) do
    if x == m then
      local n = i - 1
      return (ORD[n] or (n .. "th")) .. " in line · follows " .. (line[i - 1] and line[i - 1].name or "the leader")
    end
  end
  return "follows the leader"
end

-- ------------------------------------------------------------------ actions (each saves at once and flashes "Saved")
--- Flash "Saved" (or `text`) on the Squad page; `undo` = a function the Undo button runs.
function SP.saved(text, undo)
  SP.flash = { text = text or SAVED, undo = undo, at = (_G.GetTime and _G.GetTime()) or 0 }
  local id = SP.flash
  if not undo and _G.C_Timer and _G.C_Timer.After then
    _G.C_Timer.After(2.5, function() if SP.flash == id then SP.flash = nil; UI.Refresh() end end)
  end
end
local function changed(text, undo) SP.saved(text, undo); Core().changed() end
SP.changed = changed

--- Switch the leader preset here and offer it to the other clients (they must click Apply there).
function SP.choosePreset(id)
  local s = squad()
  if not (s and S().applyPreset(s, id)) then return end
  local p = S().preset(s, id)
  Core().log("info", "preset " .. p.name)
  if ns.Sync then ns.Sync.offerPreset(s, p) end
  changed()
end

--- The active squad; a squad with this character as leader is made when there is none (never a switch).
local function ensureSquad()
  local s = squad()
  if s then return s end
  Core().ensureMe()
  return squad()
end

--- Live party info by lower-case name.
local function partyByName()
  local out = {}
  for _, x in ipairs(ns.Squad.partyInfo()) do out[x.name:lower()] = x end
  return out
end

--- Add a character that is not in the party: name + class (race = the first race of the faction, editable later).
--- Returns the member, or nil, reason.
function SP.addByName(name, cls)
  local s = ensureSquad()
  if not s then return nil, "No squad" end
  name = ns.Rules.cleanText(name or "", 40)
  local base, realm = (name or ""):match("^([^%-]+)%-?(.*)$")
  base = base and ns.Rules.cleanText(base, 24)
  if not base or base == "" then return nil, "Type a name" end
  if not S().validClass(cls) then return nil, "Pick a class" end
  if #s.members >= S().MAX_MEMBERS then return nil, "A squad holds at most " .. S().MAX_MEMBERS .. " characters" end
  for _, m in ipairs(s.members) do if m.name:lower() == base:lower() then return nil, base .. " is already in the squad" end end
  local live = partyByName()[base:lower()]
  local m = S().newMember({ name = base, cls = cls, race = (live and live.cls == cls and live.race) or S().raceFor(cls, s.faction), unit = "party1",
    level = (live and live.level) or ns.Compat.playerLevel(), realm = realm ~= "" and realm or (live and live.realm) })
  table.insert(s.members, m)
  S().fixLeader(s); S().applyLink(s)
  Core().log("info", "added " .. m.name .. " by name")
  changed()
  return m
end
--- Kept for the guide / old callers: a follower with a placeholder name.
function SP.addCharacter() return SP.addByName("Character" .. (#(ensureSquad() or { members = {} }).members + 1), "priest") end

--- Party members (from the game) who are not in the squad yet.
function SP.partyMissing(s)
  local out = {}
  if not ns.Compat.inParty() then return out end
  local have = {}
  for _, m in ipairs(s and s.members or {}) do have[m.name:lower()] = true end
  for _, x in ipairs(ns.Squad.partyInfo()) do if not have[x.name:lower()] then out[#out + 1] = x end end
  return out
end
--- One party member running WoWBoxer (it sends team status) who is not in the squad: {name, cls} or nil.
function SP.suggestion(s)
  for _, x in ipairs(SP.partyMissing(s)) do if ns.Team.peer(x.name) then return x end end
  return nil
end

--- Everyone in the party who is not in the squad yet (by name). Returns how many were added.
function SP.addParty(only)
  local info = ns.Squad.partyInfo()
  local s = squad()
  if not s then
    s = S().fromParty(info, ns.Compat.playerFaction())
    table.insert(Core().db.squads, s); Core().db.active = s.id -- the first squad: there is nothing to switch from
    Core().cdb.squadId, Core().cdb.memberId = nil, nil
    Core().log("info", "squad from party (" .. #s.members .. ")")
    changed()
    return #s.members
  end
  local n, leaderName = 0, nil
  for _, x in ipairs(info) do
    local found
    for _, m in ipairs(s.members) do if m.name:lower() == x.name:lower() then found = m end end
    if not found and #s.members < S().MAX_MEMBERS and (not only or only:lower() == x.name:lower()) then
      found = S().newMember({ name = x.name, cls = x.cls, race = x.race or S().raceFor(x.cls, s.faction), level = x.level, unit = "party1", realm = x.realm })
      table.insert(s.members, found)
      n = n + 1
    end
    if x.leader then leaderName = x.name end
  end
  if leaderName and not only and n > 0 then for _, m in ipairs(s.members) do m.leader = m.name:lower() == leaderName:lower() end end
  S().fixLeader(s); S().applyLink(s)
  Core().log("info", "added " .. n .. " from the party")
  changed(n > 0 and SAVED or "Everyone is in")
  return n
end

--- Members who are in the party here get their race, level and realm from the game (WoWBoxer data only).
function SP.fillFromParty(s)
  if not (s and ns.Compat.inParty()) then return 0 end
  local live, n = partyByName(), 0
  for _, m in ipairs(s.members) do
    local x = live[m.name:lower()]
    if x and x.cls == m.cls then
      if x.race and x.race ~= m.race then m.race = x.race; n = n + 1 end
      if x.level and x.level ~= m.level and not s.linkLevels then m.level = x.level; n = n + 1 end
      if x.realm ~= m.realm then m.realm = x.realm; n = n + 1 end
    end
  end
  return n
end

--- Move member m one place up (-1) or down (+1): the order of the squad and of the follow line.
function SP.move(m, d)
  local s = squad()
  local i = S().slotOf(s, m)
  if not (i and S().moveMember(s, i, i + d)) then return false end
  Core().log("info", "moved " .. m.name .. " to " .. (i + d))
  changed()
  return true
end
--- "Line: Dorin → Anna → Bo" (the leader first, then the followers in squad order).
function SP.lineText(s)
  local names = {}
  for _, m in ipairs(S().line(s)) do names[#names + 1] = W.hex(W.classColor(m.cls)) .. m.name .. "|r" end
  return #names > 1 and ("Line: " .. table.concat(names, " → ")) or ""
end

function SP.makeLeader(m)
  local s = squad()
  if not (s and m) or m.leader then return false end
  S().setPlaysAs(s, m, "leader")
  Core().log("info", "leader " .. m.name)
  changed()
  return true
end

--- Remove a member (not this character); "Removed X · Undo" until the next change.
function SP.remove(m)
  local s = squad()
  local _, me = Core().me()
  if not (s and m) or m == me then return false end
  local idx
  for i, x in ipairs(s.members) do if x == m then idx = i end end
  if not idx then return false end
  table.remove(s.members, idx)
  local wasLeader = m.leader
  S().fixLeader(s)
  if SP.editing == m.id then SP.editing = nil end
  Core().log("info", "removed " .. m.name)
  changed("Removed " .. m.name, function()
    if #s.members >= S().MAX_MEMBERS then return end
    table.insert(s.members, math.min(idx, #s.members + 1), m)
    if wasLeader then for _, x in ipairs(s.members) do x.leader = (x == m) end end
    S().fixLeader(s)
    changed()
  end)
  return true
end

function SP.rename(s, name)
  name = ns.Rules.cleanText(name or "", 40)
  if not (s and name and name ~= "" and name ~= s.name) then return false end
  s.name = name
  changed()
  return true
end

--- A new squad that starts with this character as leader; the squad dropdown switches to it (the player chose it).
function SP.newSquad()
  local info = Core().playerInfo()
  local s = S().newSquad({ name = "New squad", faction = ns.Compat.playerFaction(),
    members = info.name and { { name = info.name, cls = info.cls, race = info.race, level = info.level, leader = true } } or nil })
  table.insert(Core().db.squads, s)
  Core().db.active = s.id
  Core().cdb.squadId, Core().cdb.memberId = s.id, s.members[1] and s.members[1].id or nil
  Core().log("info", "new squad")
  changed()
  return s
end
--- Delete the active squad (after the confirm); the next one becomes active, or a fresh one for this character.
function SP.deleteSquad()
  local s = squad()
  if not s then return false end
  for i, x in ipairs(Core().db.squads) do if x == s then table.remove(Core().db.squads, i) break end end
  Core().db.active = Core().db.squads[1] and Core().db.squads[1].id or nil
  Core().cdb.squadId, Core().cdb.memberId = nil, nil
  Core().log("info", "deleted squad " .. s.name)
  SP.editing = nil
  Core().ensureMe()
  changed()
  return true
end

-- ------------------------------------------------------------------ the main page
--- No squad, or only this character (and the player did not ask to add by name): the empty state.
function SP.isEmpty(s, f) return (not s or #s.members <= 1) and not (f and f.forceList) end
local function buildRow(f, parent)
  local themed = W.themed()
  local r = CreateFrame("Button", nil, parent)
  r:SetSize(LIST_W - 4, ROW_H - 4)
  r:RegisterForClicks("LeftButtonUp")
  r.bg = r:CreateTexture(nil, "BACKGROUND")
  r.bg:SetAllPoints()
  if themed then
    T.box(r, "panel2", "lineSoft", 6)
    r.bg:SetColorTexture(0, 0, 0, 0)
    r.bg.SetColorTexture = function() end -- the card's paint shows me / editing
    r.edge = r:CreateTexture(nil, "ARTWORK")
    r.edge:SetPoint("TOPLEFT", 1, -6)
    r.edge:SetPoint("BOTTOMLEFT", 1, 6)
    r.edge:SetWidth(3)
    r.wbxPaint = function(self)
      local pair = T.state("card", T.stateOf(false, false, self.m and self.m.id == SP.editing, self.wbxHovering))
      T.paint(self, pair[1])
    end
    W.onHover(r, r.wbxPaint, r.wbxPaint)
  else
    local hl = r:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.05)
  end
  r:SetScript("OnClick", function() if r.m then SP.editing = (SP.editing ~= r.m.id) and r.m.id or nil; UI.Refresh() end end)
  W.tip(r, function() return r.m and r.m.name or "" end, "Click to edit name, class, race, how it follows and sequence macros.")
  r.crown = CreateFrame("Button", nil, r)
  r.crown:SetSize(20, 20)
  r.crown:SetPoint("LEFT", themed and 10 or 4, 0)
  r.crown.tex = r.crown:CreateTexture(nil, "ARTWORK")
  r.crown.tex:SetAllPoints()
  r.crown.tex:SetTexture("Interface\\GroupFrame\\UI-Group-LeaderIcon")
  r.crown:SetScript("OnClick", function() SP.makeLeader(r.m) end)
  W.tip(r.crown, "Leader", function()
    return (r.m and r.m.leader) and (r.m.name .. " leads: the others follow and assist this character.")
      or "Click to make this character the leader. The others follow and assist the leader."
  end)
  r.name = W.line(r, "GameFontNormal")
  r.name.wbxCopy = "data"
  r.cls = W.line(r, "GameFontHighlightSmall", nil, W.MUTED)
  r.cls.wbxCopy = "data"
  if themed then
    r.icon = W.icon(r, 26, true)
    r.icon:SetPoint("LEFT", 36, 0)
    W.gameFont(r.name, 13) -- character names keep the game font
    r.name:SetPoint("TOPLEFT", 70, -6)
    r.name:SetWidth(134)
    r.cls:SetPoint("BOTTOMLEFT", 70, 6)
    r.cls:SetWidth(134)
  else
    r.name:SetPoint("LEFT", 30, 0)
    r.name:SetWidth(112)
    r.cls:SetPoint("LEFT", 146, 0)
    r.cls:SetWidth(62)
  end
  r.role = W.dropdown(r, { width = 104, values = function() return r.m and SP.roleValues(r.m) or {} end,
    get = function() return r.m and r.m.role end, set = function(v) if r.m and S().setRole(r.m, v) then changed() end end })
  r.role:SetPoint("LEFT", 210, 0)
  W.ddTip(r.role, "Role", "Picks the recommended macros and talent guide of this character.")
  r.follows = W.line(r, "GameFontHighlightSmall", nil, W.TEXT)
  r.follows:SetWidth(150)
  r.follows.wbxCopy = "data"
  if themed then
    r.followsHead = W.text(r, "GameFontNormalSmall", 9, W.MUTED)
    r.followsHead:SetPoint("TOPLEFT", 322, -7)
    r.followsHead:SetText("FOLLOW LINE")
    r.followsHead.wbxCopy = "label"
    r.follows:SetPoint("BOTTOMLEFT", 322, 7)
  else r.follows:SetPoint("LEFT", 322, 0) end
  r.me = W.line(r, "GameFontNormalSmall", nil, W.GOLD)
  r.me:SetPoint("LEFT", 478, 0)
  r.me:SetWidth(110)
  r.me:SetText("This character")
  r.me.wbxCopy = "label"
  r.remove = W.button(r, "x", 24, 20, function() SP.remove(r.m) end, { "Remove", "Removes this character from the squad. Undo is next to Saved. Its macros in the game stay." })
  r.remove:SetPoint("RIGHT", themed and -10 or -4, 0)
  return r
end

local function buildEditor(f, parent)
  local e = CreateFrame("Frame", nil, parent)
  e:SetSize(LIST_W - 4, EDIT_H - 4)
  e.bg = e:CreateTexture(nil, "BACKGROUND")
  e.bg:SetAllPoints()
  if W.themed() then e.bg:SetColorTexture(0, 0, 0, 0); T.box(e, "panel3", "line", 6) else e.bg:SetColorTexture(1, 0.82, 0, 0.07) end
  local function m() return S().member(squad(), SP.editing) end
  local function lbl(text)
    local l = W.text(e, "GameFontNormalSmall", nil, W.GOLD)
    l:SetText(text)
    l.wbxCopy = "label"
    return l
  end
  local nl = lbl("Name")
  nl:SetPoint("TOPLEFT", 30, -9)
  e.name = W.frame("EditBox", e, "InputBoxTemplate")
  e.name:SetSize(110, 20)
  e.name:SetAutoFocus(false)
  e.name:SetMaxLetters(24)
  e.name:SetPoint("LEFT", nl, "RIGHT", 10, 0)
  local function saveName(self)
    local x = m()
    local n = ns.Rules.cleanText(self:GetText() or "", 24)
    if x and n and n ~= "" and n ~= x.name then x.name = n; Core().log("info", "renamed to " .. n); changed() end
  end
  e.name:SetScript("OnEnterPressed", function(self) saveName(self); self:ClearFocus() end)
  e.name:SetScript("OnEditFocusLost", saveName)
  e.name:SetScript("OnEscapePressed", function(self) local x = m(); self:SetText(x and x.name or ""); self:ClearFocus() end)
  local function dd(width, values, get, set, title, tip)
    local d = W.dropdown(e, { width = width, values = function() local x = m(); return x and values(x) or {} end,
      get = function() local x = m(); return x and get(x) end, set = function(v) local x = m(); if x and set(x, v) ~= false then changed() end end })
    W.ddTip(d, title, tip)
    return d
  end
  e.cls = dd(96, function() return SP.classValues() end, function(x) return x.cls end, function(x, v) return S().setClass(squad(), x, v) end,
    "Class", "Changing the class starts the talent plan and own macros of this character over.")
  local cl = lbl("Class")
  cl:SetPoint("LEFT", e.name, "RIGHT", 14, 0)
  e.cls:SetPoint("LEFT", cl, "RIGHT", 6, 0)
  e.race = dd(128, SP.raceValues, function(x) return x.race end, function(x, v) x.race = v end, "Race", "Only races that can be this class.")
  local rl = lbl("Race")
  rl:SetPoint("LEFT", e.cls, "RIGHT", 14, 0)
  e.race:SetPoint("LEFT", rl, "RIGHT", 6, 0)
  -- order = the follow line (docs/follow-line.md)
  e.down = W.button(e, "Down", 54, 20, function() SP.move(m(), 1) end, "Moves this character one place down: later in the follow line. Your macros show what to update.")
  e.down:SetPoint("TOPRIGHT", -4, -5)
  e.up = W.button(e, "Up", 40, 20, function() SP.move(m(), -1) end, "Moves this character one place up: earlier in the follow line. Your macros show what to update.")
  e.up:SetPoint("RIGHT", e.down, "LEFT", -4, 0)
  -- line 2
  e.plays = dd(150, function() return ns.Book.playsAsValues() end, function(x) return x.leader and "leader" or x.unit end,
    function(x, v) return S().setPlaysAs(squad(), x, v) end, "Plays as", "Leader: plays normally. Follower: where the leader is in this character's party (party1–4 or focus); its macros use the leader's target through it. The place in the follow line is the squad order: Up / Down.")
  local pl = lbl("Plays as")
  pl:SetPoint("TOPLEFT", 30, -35)
  e.plays:SetPoint("LEFT", pl, "RIGHT", 6, 0)
  e.seq = W.seqControl(e, { member = m, width = 96, set = function(x, tier) x.seq = tier; changed() end })
  e.seq:SetPoint("LEFT", e.plays, "RIGHT", 12, 0)
  e.isMe = W.button(e, "That's me", 80, 22, function() local x = m(); if x then Core().setMe(squad().id, x.id); SP.saved() end end,
    "Tells WoWBoxer that the character you are logged in on is this one (its macros and role are used here).")
  e.isMe:SetPoint("BOTTOMRIGHT", -4, 4)
  function e.Refresh(x, me)
    if not e.name:HasFocus() then e.name:SetText(x.name) end
    e.cls.Refresh(); e.race.Refresh(); e.plays.Refresh(); e.seq.Refresh()
    e.isMe:SetShown(x ~= me)
    local i = S().slotOf(squad(), x) or 1
    e.up:SetEnabled(i > 1); e.down:SetEnabled(i < #squad().members)
  end
  return e
end

local function buildAddLine(f, parent)
  local a = CreateFrame("Frame", nil, parent)
  a:SetSize(LIST_W - 4, ADD_H - 2)
  a.label = W.text(a, "GameFontNormalSmall", nil, W.GOLD)
  a.label:SetPoint("LEFT", 8, 0)
  a.label:SetText("+ Add character")
  a.label.wbxCopy = "label"
  a.name = W.frame("EditBox", a, "InputBoxTemplate")
  a.name:SetSize(130, 20)
  a.name:SetAutoFocus(false)
  a.name:SetMaxLetters(40)
  a.name:SetPoint("LEFT", a.label, "RIGHT", 14, 0)
  a.cls = W.dropdown(a, { width = 104, placeholder = "Class",
    values = function() return SP.classValues() end, get = function() return a.pick end, set = function(v) a.pick = v end })
  a.cls:SetPoint("LEFT", a.name, "RIGHT", 8, 0)
  W.ddTip(a.cls, "Class", "The class of the character you add. Race and role can be changed later by clicking its row.")
  local function add()
    local mm, why = SP.addByName(a.name:GetText(), a.pick)
    if mm then a.name:SetText(""); a.name:ClearFocus(); a.why = nil else a.why = why; UI.Refresh() end
  end
  a.go = W.button(a, "Add", 50, 22, add, "Adds this character to the squad (a follower). For characters that are not in your party.")
  a.go:SetPoint("LEFT", a.cls, "RIGHT", 8, 0)
  a.name:SetScript("OnEnterPressed", add)
  a.name:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  a.note = W.line(a, "GameFontHighlightSmall", nil, W.ORANGE)
  a.note:SetPoint("LEFT", a.go, "RIGHT", 10, 0)
  a.note:SetPoint("RIGHT", a, "RIGHT", -4, 0)
  a.note.wbxCopy = "status"
  return a
end

SP.register({ key = "main", label = "Squad", tip = "Who plays together, who leads.",
  build = function(f, p)
    -- empty state: one sentence, two buttons
    f.empty = CreateFrame("Frame", nil, f)
    f.empty:SetAllPoints()
    f.empty.text = W.text(f.empty, "GameFontHighlight", nil, W.TEXT, "CENTER")
    f.empty.text:SetPoint("TOP", 0, -90)
    f.empty.text:SetWidth(LIST_W)
    f.empty.text:SetText("Who do you play together with?")
    f.empty.text.wbxCopy = "hint"
    f.empty.party = W.button(f.empty, "Use my party", 150, 32, function() SP.addParty() end,
      "Adds everyone in your party to this squad (names and classes from the game; the party leader leads).")
    f.empty.party.wbxBig = true
    f.empty.byName = W.button(f.empty, "Add by name", 150, 32, function() f.forceList = true; UI.Refresh(); f.add.name:SetFocus() end,
      "For characters that are not in your party: type a name and pick a class.")
    f.empty.byName.wbxBig = true
    f.empty.byName:SetPoint("TOP", f.empty.text, "BOTTOM", 0, -24)

    f.list = CreateFrame("Frame", nil, f)
    f.list:SetAllPoints()
    local sf, content = W.scroll(f.list, LIST_W, LIST_H)
    sf:SetPoint("TOPLEFT", 0, 0)
    f.sf, f.content = sf, content
    f.pool = W.pool(content, function(parent) return buildRow(f, parent) end)
    f.editor = buildEditor(f, content)
    f.add = buildAddLine(f, content)
    -- under the list: party, the one big action, squad keys, readiness
    local y = -LIST_H - 8
    f.party = W.button(f.list, "Add my party", 130, 26, function() SP.addParty() end,
      "Adds everyone in your party who is not in the squad yet (names and classes from the game).")
    f.party.wbxBig = true
    f.party:SetPoint("TOPLEFT", 0, y)
    f.sugg = W.line(f.list, "GameFontHighlightSmall", nil, W.TEXT)
    f.sugg:SetPoint("LEFT", f.party, "RIGHT", 10, 0)
    f.sugg:SetWidth(230)
    f.sugg.wbxCopy = "hint"
    f.suggAdd = W.button(f.list, "Add", 50, 22, function() if f.suggName then SP.addParty(f.suggName) end end,
      "Adds this character from your party to the squad (on this client only).")
    f.suggAdd:SetPoint("LEFT", f.sugg, "RIGHT", 4, 0)
    f.send = W.button(f.list, "Send to my other characters", 210, 26, function() if ns.Sync then ns.Sync.sendSquad(squad()) end end,
      { "Send to my other characters", "Offers this squad to your other clients in the party. Nothing changes there until you click Review and Import on that client. Then press Place all there." })
    f.send.wbxBig = true
    W.primary(f.send)
    f.send:SetPoint("TOPRIGHT", f.list, "TOPRIGHT", 0, y)
    -- squad keys: the player ticks them; built from the squad (Invite by name, the rest through party units)
    f.keys = CreateFrame("Frame", nil, f.list)
    f.keys:SetPoint("TOPLEFT", 0, y - 34)
    f.keys:SetSize(LIST_W + 20, 48)
    f.keys.label = W.text(f.keys, "GameFontNormalSmall", nil, W.GOLD)
    f.keys.label:SetPoint("TOPLEFT", 0, -5)
    f.keys.label:SetText("Squad macros")
    f.keys.label.wbxCopy = "label"
    f.keys.ticks = {}
    for i = 1, #ns.Macros.SQUAD_KEYS do
      local c = W.check(f.keys, "Macro", function(self, v) if self.key then ns.Book.setSquadKey(self.key, v); SP.saved() end end)
      c:SetPoint("TOPLEFT", 92 + ((i - 1) % 4) * 136, -((math.floor((i - 1) / 4)) * 22))
      W.tip(c, function() return c.label:GetText() end, function() return c.key and ns.Book.helperShort(c.key) .. " Ticked: WoWBoxer makes this macro for this character." or "" end)
      f.keys.ticks[i] = c
    end
    f.keys.state = W.line(f.keys, "GameFontHighlightSmall", nil, W.GREEN, "RIGHT")
    f.keys.state:SetPoint("TOPRIGHT", -20, -27)
    f.keys.state:SetWidth(110)
    f.keys.state.wbxCopy = "hint"
    f.keys.update = W.button(f.keys, "Update macros", 100, 22, function() Core().sync({ replace = Core().cdb.replace }) end,
      "Creates or updates your squad macros (and any other changed macros) and puts new ones on your bars.")
    f.keys.update:SetPoint("TOPRIGHT", -20, -22)
    W.setStyle(f.keys.update, "raised")
    f.lineText = W.line(f.list, "GameFontHighlightSmall", nil, W.TEXT)
    f.lineText:SetPoint("TOPLEFT", W.themed() and 12 or 0, y - 34 - 52)
    f.lineText:SetWidth(LIST_W - (W.themed() and 24 or 0))
    f.lineText.wbxCopy = "data"
    if W.themed() then
      -- the follow line as a night-2 strip (§3)
      f.lineBox = CreateFrame("Frame", nil, f.list)
      f.lineBox:SetPoint("TOPLEFT", f.lineText, "TOPLEFT", -12, 7)
      f.lineBox:SetPoint("BOTTOMRIGHT", f.lineText, "BOTTOMRIGHT", 12, -7)
      T.box(f.lineBox, "night2", "lineSoft", 6)
      f.lineBox:SetFrameLevel(math.max(0, (f.list:GetFrameLevel() or 1)))
    end
    local lineHit = CreateFrame("Frame", nil, f.list)
    lineHit:SetAllPoints(f.lineText)
    W.tip(lineHit, "Follow line", "Follow (line) on each character follows the one before it. Change the order with Up / Down in a row; your macros update.")
    f.status = W.line(f.list, "GameFontHighlightSmall", nil, W.MUTED)
    f.status:SetPoint("BOTTOMLEFT", 0, 4)
    f.status:SetWidth(LIST_W - 80)
    f.status.wbxCopy = "hint"
    f.readyBtn = W.button(f.list, "Readiness", 80, 20, function() SP.select(p, "ready") end, "One line per character: party, unit, macros, Follow/Assist, settings.")
    f.readyBtn:SetPoint("BOTTOMRIGHT", 0, 2)
  end,
  refresh = function(f, p)
    local s = squad()
    local _, me = Core().me()
    local n = s and #s.members or 0
    local missing = SP.partyMissing(s)
    local empty = SP.isEmpty(s, f)
    f.empty:SetShown(empty); f.list:SetShown(not empty)
    if empty then
      local np = #missing
      f.empty.party:SetShown(np > 0)
      W.setLabel(f.empty.party, "Use my party (" .. np .. ")")
      f.empty.party:ClearAllPoints()
      if np > 0 then
        f.empty.party:SetPoint("TOPRIGHT", f.empty.text, "BOTTOM", -8, -24)
        f.empty.byName:ClearAllPoints(); f.empty.byName:SetPoint("TOPLEFT", f.empty.text, "BOTTOM", 8, -24)
      else
        f.empty.byName:ClearAllPoints(); f.empty.byName:SetPoint("TOP", f.empty.text, "BOTTOM", 0, -24)
      end
      return
    end
    if SP.fillFromParty(s) > 0 then Core().log("info", "squad: race/level from the party") end
    f.pool:reset()
    local y = 0
    local editing = S().member(s, SP.editing)
    if not editing then SP.editing = nil end
    for _, m in ipairs(s and s.members or {}) do
      local r = f.pool:get()
      r:ClearAllPoints()
      r:SetPoint("TOPLEFT", 0, -y)
      r.m = m
      r.crown.tex:SetAlpha(m.leader and 1 or 0.18)
      r.name:SetText(W.hex(W.classColor(m.cls)) .. m.name .. "|r")
      if r.icon then
        local cc = W.classColor(m.cls)
        SP.setClassIcon(r.icon, m.cls)
        r.edge:SetColorTexture(cc[1], cc[2], cc[3], 1)
        r.cls:SetText(D().classes[m.cls].n .. (m.level and (" · level " .. m.level) or ""))
        T.paint(r, nil, m.id == SP.editing and "gold" or (m == me and "line" or "lineSoft"))
        r.wbxPaint(r)
      else r.cls:SetText(D().classes[m.cls].n .. " ·") end
      r.role.Refresh()
      r.follows:SetText(SP.followsText(m, s))
      r.me:SetShown(m == me)
      r.remove:SetShown(m ~= me)
      local on = m.id == SP.editing
      r.bg:SetColorTexture(m == me and 0.3 or 0, m == me and 0.24 or 0, 0, on and 0.4 or (m == me and 0.25 or 0.22))
      y = y + ROW_H
      if on then
        f.editor:ClearAllPoints()
        f.editor:SetPoint("TOPLEFT", 0, -y)
        f.editor.Refresh(m, me)
        y = y + EDIT_H
      end
    end
    f.editor:SetShown(editing ~= nil)
    f.add:ClearAllPoints()
    f.add:SetPoint("TOPLEFT", 0, -y)
    f.add:SetShown(n < S().MAX_MEMBERS)
    f.add.cls.Refresh()
    f.add.note:SetText(f.add.why or "")
    y = y + ADD_H
    f.content:SetHeight(math.max(10, y))
    W.tidyScroll(f.sf, y)
    -- party
    f.party:SetShown(#missing > 0)
    W.setLabel(f.party, "Add my party (" .. #missing .. ")")
    local sg = SP.suggestion(s)
    f.suggName = sg and sg.name or nil
    f.sugg:SetShown(sg ~= nil); f.suggAdd:SetShown(sg ~= nil)
    f.sugg:ClearAllPoints()
    if #missing > 0 then f.sugg:SetPoint("LEFT", f.party, "RIGHT", 10, 0) else f.sugg:SetPoint("TOPLEFT", 0, -LIST_H - 13) end
    if sg then f.sugg:SetText(sg.name .. " (" .. D().classes[sg.cls].n .. ") is in your party") end
    f.send:SetEnabled(s ~= nil and ns.Compat.inParty() and n > 1)
    SP.refreshKeys(f)
    f.lineText:SetText(SP.lineText(s))
    -- status line: readiness, composition, unit hint, versions
    local hints = {}
    local rows = ns.Squad.readiness()
    local ready = 0
    for _, row in ipairs(rows) do if row.ready and row.ready.keys == 0 then ready = ready + 1 end end
    hints[#hints + 1] = ready .. "/" .. #rows .. " ready"
    for _, h in ipairs(S().composition(s)) do hints[#hints + 1] = h end
    local hu, L = ns.Squad.unitHint()
    if hu then hints[#hints + 1] = "|cfff0b43c" .. L.name .. " is " .. hu .. " here|r" end
    local myVer = ns.Team.version()
    for _, row in ipairs(rows) do
      if row.version and row.version ~= myVer and not row.me then hints[#hints + 1] = "|cfff0b43c" .. row.m.name .. " runs WoWBoxer " .. row.version .. "|r" end
    end
    f.status:SetText(table.concat(hints, " · "))
    f.readyBtn:SetShown(n > 1)
  end })

--- The squad keys block: one tick per key this character can have, and whether they are on the bars.
function SP.refreshKeys(f)
  local ctx = Core().compute()
  local list = ctx and ns.Book.squadKeyList(ctx) or {}
  for i, c in ipairs(f.keys.ticks) do
    local k = list[i]
    c:SetShown(k ~= nil); c.key = k and k.key or nil
    if k then c.label:SetText(k.label); c:SetChecked(k.on); c:SetEnabled(not ns.Compat.inCombat()) end
  end
  local todo, any = 0, false
  if ctx then
    local placed = {}
    for _, b in ipairs(ctx.bars.items) do placed[b.name] = b.status == "placed" end
    for _, it in ipairs(ctx.macros.items) do
      if it.group == "helper" then
        any = true
        if it.status == "create" or it.status == "update" or not placed[it.name] then todo = todo + 1 end
      end
    end
  end
  f.keys:SetShown(#list > 0)
  f.keys.update:SetShown(todo > 0)
  f.keys.update:SetEnabled(not ns.Compat.inCombat())
  f.keys.state:SetShown(todo == 0)
  f.keys.state:SetText(any and "On your bars" or "")
  return todo
end

-- ------------------------------------------------------------------ Leader presets, notes, everyone's sequence keys (under More)
SP.register({ key = "presets", label = "Leader presets", more = true, tip = "Who leads for what you do, saved to switch back; notes; everyone's sequence macros.",
  build = function(f)
    f.preset = W.dropdown(f, { width = 190, placeholder = "No preset saved",
      values = function() return SP.presetValues(squad()) end,
      get = function() local s = squad(); return s and s.activePreset end,
      set = function(v) SP.choosePreset(v) end })
    local pl = W.labelled(f, "Leader preset", f.preset)
    pl:SetPoint("TOPLEFT", 0, -6)
    W.ddTip(f.preset, "Leader preset", "Who leads for what you do (e.g. \"Questing – Dorin leads\"). Choosing one changes the leader here and offers the switch to your other clients – they apply it with one click.")
    f.savePreset = W.button(f, "Save preset", 100, 22, function()
      local s = squad()
      local p0 = s and S().savePreset(s, nil)
      if p0 then Core().print("Saved preset \"" .. p0.name .. "\".") end
      changed()
    end, "Saves who leads now (and everyone's role) as a preset you can switch back to.")
    f.savePreset:SetPoint("LEFT", f.preset, "RIGHT", 8, 0)
    f.allSeq = W.dropdown(f, { width = 110, placeholder = "Choose…",
      values = function() return { { "off", "Off" }, { "simple", "Simple" }, { "medium", "Medium" }, { "advanced", "Advanced" } } end,
      get = function() return nil end,
      set = function(v)
        local s = squad()
        for _, m in ipairs(s and s.members or {}) do
          if ns.Engine.seqSupported(m.cls) then if v ~= "off" then m.seqTier = v end m.seq = v end
        end
        changed()
      end })
    local al = W.labelled(f, "All sequences", f.allSeq)
    al:SetPoint("TOPLEFT", 0, -40)
    W.ddTip(f.allSeq, "Everyone's sequence macros", "Sets sequence macros for every character whose class has them. Each client then updates its own macros.")
    local nl = W.text(f, "GameFontNormalSmall", nil, W.GOLD)
    nl:SetPoint("TOPLEFT", 0, -78)
    nl:SetText("Notes")
    nl.wbxCopy = "label"
    f.notes = W.frame("EditBox", f, "InputBoxTemplate")
    f.notes:SetSize(LIST_W - 60, 20)
    f.notes:SetAutoFocus(false)
    f.notes:SetMaxLetters(200)
    f.notes:SetPoint("LEFT", nl, "RIGHT", 12, 0)
    local function saveNotes(self)
      local s = squad()
      local t = ns.Rules.cleanText(self:GetText() or "", 200) or ""
      if s and t ~= (s.notes or "") then s.notes = t; changed() end
    end
    f.notes:SetScript("OnEnterPressed", function(self) saveNotes(self); self:ClearFocus() end)
    f.notes:SetScript("OnEditFocusLost", saveNotes)
    f.notes:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  end,
  refresh = function(f)
    local s = squad()
    f.preset.Refresh(); f.allSeq.Refresh()
    f.preset:SetEnabled(s ~= nil and #(s.presets or {}) > 0)
    f.savePreset:SetEnabled(s ~= nil and #s.members > 0)
    if not f.notes:HasFocus() then f.notes:SetText(s and s.notes or "") end
  end })

-- ------------------------------------------------------------------ the tab: top bar (squad, Rename, Saved, More) + pages
function SP.select(p, key)
  if not SP.byKey[key] then key = "main" end
  p.page = key
  UI.Refresh()
end

function SP.moreValues()
  local v = {}
  for _, def in ipairs(SP.pages) do if def.more then v[#v + 1] = { def.key, def.label, def.tip } end end
  return v
end

local function buildTop(p)
  local t = CreateFrame("Frame", nil, p)
  t:SetPoint("TOPLEFT", 0, 0)
  t:SetPoint("TOPRIGHT", 0, 0)
  t:SetHeight(24)
  p.top = t
  p.squadPick = W.dropdown(t, { width = 200,
    values = function()
      local v = {}
      for _, s in ipairs(Core().db.squads) do v[#v + 1] = { s.id, s.name .. " (" .. #s.members .. ")" } end
      v[#v + 1] = { NEW, "New squad…", "Starts a new squad with this character. Your other squads stay." }
      v[#v + 1] = { DEL, "Delete squad…", "Deletes this squad from WoWBoxer (asks first). Your macros in the game stay." }
      return v
    end,
    get = function() return Core().db.active end,
    set = function(v)
      if v == NEW then SP.newSquad()
      elseif v == DEL then p.confirm:Show(); UI.Refresh()
      elseif v ~= Core().db.active then
        Core().db.active = v; Core().cdb.squadId, Core().cdb.memberId = nil, nil; SP.editing = nil; changed()
      end
    end })
  p.squadPick:SetPoint("TOPLEFT", 0, 0)
  W.ddTip(p.squadPick, "Squad", "The squad this character uses. Only this list switches squads; New squad… and Delete squad… are at the bottom.")
  p.nameBox = W.frame("EditBox", t, "InputBoxTemplate")
  p.nameBox:SetSize(190, 20)
  p.nameBox:SetAutoFocus(false)
  p.nameBox:SetMaxLetters(40)
  p.nameBox:SetPoint("LEFT", p.squadPick, "LEFT", 6, 0)
  p.nameBox:Hide()
  local function done(self, save) if save then SP.rename(squad(), self:GetText()) end self:Hide(); self:ClearFocus(); UI.Refresh() end
  p.nameBox:SetScript("OnEnterPressed", function(self) done(self, true) end)
  p.nameBox:SetScript("OnEscapePressed", function(self) done(self, false) end)
  p.nameBox:SetScript("OnEditFocusLost", function(self) if self:IsShown() then done(self, true) end end)
  p.rename = W.button(t, "Rename", 70, 22, function()
    local s = squad()
    if not s then return end
    p.nameBox:SetText(s.name); p.nameBox:Show(); p.nameBox:SetFocus(); UI.Refresh()
  end, "Type a new name for this squad, then Enter.")
  p.rename:SetPoint("LEFT", p.squadPick, "RIGHT", 8, 0)
  p.saved = W.line(t, "GameFontHighlightSmall", nil, W.GREEN)
  p.saved:SetPoint("LEFT", p.rename, "RIGHT", 10, 0)
  p.saved:SetWidth(150)
  p.saved.wbxCopy = "status"
  p.undo = W.button(t, "Undo", 56, 20, function() local fl = SP.flash; SP.flash = nil; if fl and fl.undo then fl.undo() end end,
    "Puts the removed character back.")
  p.undo:SetPoint("LEFT", p.saved, "RIGHT", 4, 0)
  p.more = W.dropdown(t, { width = 96, placeholder = "More",
    values = function() return SP.moreValues() end, get = function() return nil end, set = function(v) SP.select(p, v) end })
  p.more:SetPoint("TOPRIGHT", 0, 0)
  W.ddTip(p.more, "More", "Readiness, key map, levelling plan and leader presets.")
  p.back = W.button(t, "Back", 60, 22, function() SP.select(p, "main") end, "Back to your squad.")
  p.back:SetPoint("TOPLEFT", 0, 0)
  p.title = W.text(t, "GameFontNormal", nil, W.GOLD)
  p.title:SetPoint("LEFT", p.back, "RIGHT", 10, 0)
  p.title.wbxCopy = "label"
  -- delete confirm (over the top bar)
  local c = W.box(t, 0.12, 0.05, 0.03, 1)
  c:SetAllPoints()
  c:SetFrameLevel((t:GetFrameLevel() or 1) + 10)
  c:EnableMouse(true)
  c.text = W.line(c, "GameFontHighlightSmall", nil, W.TEXT)
  c.text:SetPoint("LEFT", 8, 0)
  c.text:SetWidth(300)
  c.text.wbxCopy = "hint"
  c.yes = W.button(c, "Delete", 70, 20, function() c:Hide(); SP.deleteSquad() end, "Deletes this squad from WoWBoxer. Your macros in the game stay.")
  c.yes:SetPoint("RIGHT", -4, 0)
  c.no = W.button(c, "Cancel", 70, 20, function() c:Hide(); UI.Refresh() end, "Keeps the squad.")
  c.no:SetPoint("RIGHT", c.yes, "LEFT", -6, 0)
  c:Hide()
  p.confirm = c
end

function tab.build(p)
  p.page = "main"
  buildTop(p)
  p.frames = {}
  for _, def in ipairs(SP.pages) do
    local f = CreateFrame("Frame", nil, p)
    f:SetPoint("TOPLEFT", 0, -TOP_H)
    f:SetPoint("BOTTOMRIGHT", 0, 0)
    f:Hide()
    def.build(f, p)
    p.frames[def.key] = f
  end
end

function tab.refresh(p)
  local main = p.page == "main"
  local s = squad()
  local empty = main and SP.isEmpty(s, p.frames.main)
  local asking = p.confirm:IsShown()
  if asking then main = false end -- the delete confirm covers the top bar
  p.squadPick:SetShown(main and not p.nameBox:IsShown() and (not empty or #Core().db.squads > 1))
  p.rename:SetShown(main and not empty); p.more:SetShown(main and not empty)
  p.squadPick.Refresh(); p.more.Refresh()
  p.rename:SetEnabled(s ~= nil)
  local fl = SP.flash
  p.saved:SetShown(main and fl ~= nil); p.saved:SetText(fl and fl.text or "")
  p.undo:SetShown(main and fl ~= nil and fl.undo ~= nil)
  p.back:SetShown(not main and not asking); p.title:SetShown(not main and not asking)
  p.title:SetText(SP.byKey[p.page] and SP.byKey[p.page].label or "")
  if p.confirm:IsShown() then p.confirm.text:SetText("Delete \"" .. (s and s.name or "?") .. "\"?") end
  for _, def in ipairs(SP.pages) do p.frames[def.key]:SetShown(def.key == p.page) end
  local def = SP.byKey[p.page]
  if def then def.refresh(p.frames[p.page], p) end
end

UI.RegisterTab(tab)
