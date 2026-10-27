--[[ WoWBoxer – the Squad bookmark (docs/squad-overhaul.md §3): the shared plan of who plays what, so every client
  builds the right keys, shows the team and stays in sync. Sub-pages: Home (party-frame cards), Edit squad (table with
  drag to reorder, dropdowns, Add my party, templates), Readiness, Key map and Plan (UI/SquadPages.lua).
  Only WoWBoxer's own setup changes here; macros change when the player presses Place all / Update keys, and other
  clients only ever get offers they must click (Sync.lua). ]]
local _, ns = ...
local UI, W = ns.UI, ns.Widgets
local tab = { key = "squad", label = "Squad", icon = "Spell_Holy_PrayerOfFortitude", tip = "The characters you play together: who plays what, who leads, how ready everyone is." }
local SP = { pages = {}, byKey = {} }
ns.SquadPages = SP

local LIST_W = 648 -- + scrollbar
local CARD_W, CARD_H, CARD_GAP = 212, 90, 6
local ROW_H = 58

local function D() return ns.Data end
local function S() return ns.State end
local function Core() return ns.Core end
local function squad() return S().activeSquad(Core().db) end

--- Register a sub-page: {key, label, tip, build(f, p), refresh(f, p)}.
function SP.register(def) SP.pages[#SP.pages + 1] = def; SP.byKey[def.key] = def end

local CLASS_TEX = "Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES"
function SP.setClassIcon(tex, cls)
  local tc = _G.CLASS_ICON_TCOORDS and _G.CLASS_ICON_TCOORDS[(cls or ""):upper()]
  if tc then tex:SetTexture(CLASS_TEX); if tex.SetTexCoord then tex:SetTexCoord(tc[1], tc[2], tc[3], tc[4]) end
  else W.setIcon(tex, D().classes[cls] and ("ClassIcon_" .. cls) or nil) end
end
SP.ROLE_ICON = { tank = "Ability_Defend", healer = "Spell_Holy_Heal", melee = "Ability_MeleeDamage", ranged = "Spell_Fire_FireBolt02" }
function SP.playsAsText(m, s)
  if m.leader then return "Leads" end
  local L = S().leaderOf(s)
  return "Follows " .. (L and L.name or "the leader") .. " (" .. m.unit .. ")"
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
    v[#v + 1] = { p.id, p.name, (L and (L.name .. " leads") or "") .. ". Choosing it changes who leads (and the roles saved with it) in WoWBoxer; every client then updates its own keys." }
  end
  return v
end
--- Switch the leader preset here and offer it to the other clients (they must click Apply there).
function SP.choosePreset(id)
  local s = squad()
  if not (s and S().applyPreset(s, id)) then return end
  local p = S().preset(s, id)
  Core().log("info", "preset " .. p.name)
  if ns.Sync then ns.Sync.offerPreset(s, p) end
  Core().changed()
end

-- ------------------------------------------------------------------ Home: cards like party frames
local function buildCard(parent)
  local r = W.box(parent, 0.08, 0.063, 0.043, 0.95)
  r:SetSize(CARD_W, CARD_H)
  r.badge = r:CreateTexture(nil, "ARTWORK")
  r.badge:SetSize(28, 28)
  r.badge:SetPoint("TOPLEFT", 8, -8)
  r.crown = r:CreateTexture(nil, "ARTWORK")
  r.crown:SetSize(14, 14)
  r.crown:SetPoint("TOPRIGHT", -8, -8)
  r.crown:SetTexture("Interface\\GroupFrame\\UI-Group-LeaderIcon")
  r.roleIcon = W.icon(r, 14)
  r.roleIcon:SetPoint("TOPRIGHT", -26, -8)
  r.name = W.line(r, "GameFontNormal")
  r.name:SetPoint("TOPLEFT", 42, -9)
  r.name:SetPoint("TOPRIGHT", -44, -9)
  r.sub = W.line(r, "GameFontHighlightSmall", nil, W.MUTED)
  r.sub:SetPoint("TOPLEFT", 42, -25)
  r.sub:SetPoint("TOPRIGHT", -8, -25)
  r.keys = W.line(r, "GameFontHighlightSmall", nil, W.TEXT)
  r.keys:SetPoint("TOPLEFT", 8, -44)
  r.keys:SetPoint("TOPRIGHT", -8, -44)
  r.state = W.line(r, "GameFontHighlightSmall", nil, W.MUTED)
  r.state:SetPoint("TOPLEFT", 8, -58)
  r.state:SetPoint("TOPRIGHT", -8, -58)
  r.manaBg = r:CreateTexture(nil, "ARTWORK")
  r.manaBg:SetPoint("BOTTOMLEFT", 8, 8)
  r.manaBg:SetPoint("BOTTOMRIGHT", -8, 8)
  r.manaBg:SetHeight(5)
  r.manaBg:SetColorTexture(0, 0, 0, 0.6)
  r.mana = r:CreateTexture(nil, "OVERLAY")
  r.mana:SetPoint("BOTTOMLEFT", r.manaBg, "BOTTOMLEFT", 0, 0)
  r.mana:SetHeight(5)
  r.mana:SetColorTexture(0.25, 0.5, 1, 0.9)
  W.tooltip(r, function(GT, self)
    local m = self.m
    if not m then return end
    GT:AddLine(m.name, 1, 0.82, 0)
    for _, l in ipairs(self.tipLines or {}) do GT:AddLine(l, 1, 1, 1, true) end
  end)
  return r
end

--- What a card says about member m: {sub, keys, keysColor, state, mana (0–1 or nil), tip lines}
function SP.cardInfo(row, s)
  local m, rd = row.m, row.ready
  local info = { tip = {} }
  local lvl = row.level or m.level
  info.sub = (row.me and "|cffffd100This character|r · " or "") .. "Lv " .. lvl .. " · " .. (S().ROLE_NAME[m.role] or m.role) .. " · Slot " .. (S().slotOf(s, m) or "?")
  if rd then
    if rd.keys == 0 then info.keys, info.keysColor = "Keys OK", W.GREEN
    else info.keys, info.keysColor = rd.keys .. (rd.keys == 1 and " key" or " keys") .. " to update", W.ORANGE end
  elseif row.me then info.keys, info.keysColor = "Keys –", W.MUTED
  else info.keys, info.keysColor = row.inParty and "No signal (is WoWBoxer on there?)" or "Not in your party", W.MUTED end
  local st = row.me and ns.Team.collect() or row.st
  local parts = {}
  if st then
    if not m.leader then parts[#parts + 1] = (st.follow == 1 or st.combat == 1) and "|cff8fbf6aFollowing|r" or "|cfff0b43cNot following|r" end
    local L = S().leaderOf(s)
    local lst = (L and L ~= m) and (L == select(2, Core().me()) and ns.Team.collect() or ns.Team.peer(L.name)) or nil
    if not m.leader and lst and lst.target ~= "-" and st.target ~= "?" then
      parts[#parts + 1] = (st.target == lst.target) and "|cff8fbf6asame target|r" or "|cfff0b43cother target|r"
    end
    info.mana = (st.mana and st.mana >= 0) and (st.mana / 100) or nil
  end
  info.state = #parts > 0 and table.concat(parts, " · ") or SP.playsAsText(m, s)
  info.tip[#info.tip + 1] = D().classes[m.cls].n .. " · " .. ((ns.Kit.race(m.race) or {}).n or m.race) .. " · " .. SP.playsAsText(m, s)
  local tags = {}
  for _, t in ipairs(S().tagsOf(m)) do tags[#tags + 1] = S().TAG_NAME[t] end
  if #tags > 0 then info.tip[#info.tip + 1] = "Tags: " .. table.concat(tags, ", ") end
  if m.seq ~= "off" then info.tip[#info.tip + 1] = "Sequence keys: " .. m.seq end
  if row.version then info.tip[#info.tip + 1] = "WoWBoxer " .. row.version end
  info.tip[#info.tip + 1] = "Shown from what each client reports – display only, it never acts for you."
  return info
end

SP.register({ key = "home", label = "Home", tip = "Everyone in the squad at a glance: level, keys, follow, target, mana.",
  build = function(f, p)
    local sf, content = W.scroll(f, LIST_W, 2 * (CARD_H + CARD_GAP))
    sf:SetPoint("TOPLEFT", 0, 0)
    f.cards = content
    f.pool = W.pool(content, function(parent) return buildCard(parent) end)
    f.hints = W.text(f, "GameFontHighlightSmall", nil, W.MUTED)
    f.hints:SetPoint("TOPLEFT", 0, -2 * (CARD_H + CARD_GAP) - 6)
    f.hints:SetWidth(LIST_W + 20)
    f.hints:SetJustifyV("TOP")
    if f.hints.SetMaxLines then f.hints:SetMaxLines(4) end
    -- leader preset row
    f.preset = W.dropdown(f, { width = 190, placeholder = "No preset saved",
      values = function() return SP.presetValues(squad()) end,
      get = function() local s = squad(); return s and s.activePreset end,
      set = function(v) SP.choosePreset(v) end })
    local pl = W.labelled(f, "Leader preset", f.preset)
    pl:SetPoint("BOTTOMLEFT", 0, 40)
    W.ddTip(f.preset, "Leader preset", "Who leads for what you do (e.g. \"Questing – Dorin leads\"). Choosing one changes the leader here and offers the switch to your other clients – they apply it with one click.")
    f.savePreset = W.button(f, "Save as preset", 110, 22, function()
      local s = squad()
      local p0 = s and S().savePreset(s, nil)
      if p0 then Core().print("Saved preset \"" .. p0.name .. "\".") end
      Core().changed()
    end, "Saves who leads now (and everyone's role) as a preset you can switch back to.")
    f.savePreset:SetPoint("LEFT", f.preset, "RIGHT", 8, 0)
    -- buttons
    f.edit = W.button(f, "Edit squad", 96, 24, function() SP.select(p, "edit") end, "Add, remove, reorder and change the characters of this squad.")
    f.edit:SetPoint("BOTTOMLEFT", 0, 0)
    f.send = W.button(f, "Send squad to my party", 170, 24, function() if ns.Sync then ns.Sync.sendSquad(squad()) end end,
      "Offers this squad to your other clients in the party. Nothing changes there until you click Review and Import on that client.")
    f.send:SetPoint("LEFT", f.edit, "RIGHT", 6, 0)
    f.ready = W.button(f, "Readiness", 90, 24, function() SP.select(p, "ready") end, "One line per character: party, unit, keys, Follow/Assist, settings.")
    f.ready:SetPoint("LEFT", f.send, "RIGHT", 6, 0)
  end,
  refresh = function(f)
    local s = squad()
    f.pool:reset()
    local rows = ns.Squad.readiness()
    for i, row in ipairs(rows) do
      local r = f.pool:get()
      local col, line = (i - 1) % 3, math.floor((i - 1) / 3)
      r:ClearAllPoints()
      r:SetPoint("TOPLEFT", col * (CARD_W + CARD_GAP), -line * (CARD_H + CARD_GAP))
      r.m = row.m
      local info = SP.cardInfo(row, s)
      SP.setClassIcon(r.badge, row.m.cls)
      r.crown:SetShown(row.m.leader)
      W.setIcon(r.roleIcon, SP.ROLE_ICON[row.m.role])
      r.name:SetText(W.hex(W.classColor(row.m.cls)) .. row.m.name .. "|r")
      r.sub:SetText(info.sub)
      r.keys:SetText(info.keys); r.keys:SetTextColor(info.keysColor[1], info.keysColor[2], info.keysColor[3])
      r.state:SetText(info.state)
      r.mana:SetShown(info.mana ~= nil)
      if info.mana then r.mana:SetWidth(math.max(1, (CARD_W - 16) * info.mana)) end
      r.tipLines = info.tip
      if r.SetBackdropBorderColor then
        if row.me then r:SetBackdropBorderColor(1, 0.82, 0, 1) else r:SetBackdropBorderColor(0.54, 0.43, 0.2, 1) end
      end
    end
    f.cards:SetHeight(math.max(10, math.ceil(#rows / 3) * (CARD_H + CARD_GAP)))
    local hints = {}
    for _, h in ipairs(S().composition(s)) do hints[#hints + 1] = h end
    local hu, L = ns.Squad.unitHint()
    if hu then hints[#hints + 1] = "|cfff0b43c" .. L.name .. " is " .. hu .. " here|r – My keys offers to use " .. hu .. "." end
    if s and #s.members == 1 then hints[#hints + 1] = "Playing with more characters? Edit squad → Add my party (when grouped) or a template." end
    local chain = {}
    for _, m in ipairs(s and s.members or {}) do if not m.leader then chain[#chain + 1] = m.name end end
    local Lm = S().leaderOf(s)
    if Lm and #chain > 0 then hints[#hints + 1] = "Follow chain: " .. table.concat(chain, ", ") .. " → " .. Lm.name .. "." end
    f.hints:SetText(table.concat(hints, "\n"))
    f.preset.Refresh()
    f.preset:SetEnabled(s ~= nil and #(s.presets or {}) > 0)
    f.savePreset:SetEnabled(s ~= nil and #s.members > 0)
    f.send:SetEnabled(s ~= nil and ns.Compat.inParty() and #s.members > 1)
  end })

-- ------------------------------------------------------------------ Edit squad: one row per character
local function rowDrop(f, r)
  -- drop at the cursor: the row under it gets this member
  local s = squad()
  local x, y = _G.GetCursorPosition()
  local _ = x
  local target
  for _, other in ipairs(f.pool.rows) do
    if other:IsShown() and other.index then
      local k = other:GetEffectiveScale() or 1
      local top, bottom = other:GetTop(), other:GetBottom()
      if top and bottom and y / k <= top and y / k >= bottom then target = other.index end
    end
  end
  f.dropLine:Hide()
  if s and target and r.index and S().moveMember(s, r.index, target) then
    Core().log("info", "moved " .. r.m.name .. " to slot " .. target)
    Core().changed()
  end
end

local function buildRow(f, parent)
  local r = CreateFrame("Frame", nil, parent)
  r:SetSize(LIST_W - 4, ROW_H - 4)
  r.bg = r:CreateTexture(nil, "BACKGROUND")
  r.bg:SetAllPoints()
  r.bg:SetColorTexture(0, 0, 0, 0.22)
  -- grip: drag to reorder
  r.grip = CreateFrame("Button", nil, r)
  r.grip:SetSize(14, ROW_H - 12)
  r.grip:SetPoint("LEFT", 4, 0)
  for i = 1, 3 do
    local t = r.grip:CreateTexture(nil, "ARTWORK")
    t:SetColorTexture(0.66, 0.6, 0.49, 0.9)
    t:SetSize(10, 2)
    t:SetPoint("CENTER", 0, (i - 2) * 5)
  end
  r.grip:RegisterForDrag("LeftButton")
  r.grip:SetScript("OnDragStart", function() f.dragging = r; f.dropLine:Show() end)
  r.grip:SetScript("OnDragStop", function() if f.dragging == r then f.dragging = nil; rowDrop(f, r) end end)
  W.tip(r.grip, "Change the order", "Drag up or down. Slot 1 is your main window, as in WoWBoxer Window Layouts.")
  r.num = W.text(r, "GameFontNormal", nil, W.GOLD, "CENTER")
  r.num:SetPoint("TOPLEFT", 20, -9)
  r.num:SetWidth(16)
  r.name = W.frame("EditBox", r, "InputBoxTemplate")
  r.name:SetSize(98, 20)
  r.name:SetAutoFocus(false)
  r.name:SetMaxLetters(24)
  r.name:SetPoint("TOPLEFT", 46, -5)
  local function saveName(self)
    local n = ns.Rules.cleanText(self:GetText() or "", 24)
    if r.m and n and n ~= "" and n ~= r.m.name then r.m.name = n; Core().log("info", "renamed to " .. n); Core().changed() end
  end
  r.name:SetScript("OnEnterPressed", function(self) saveName(self); self:ClearFocus() end)
  r.name:SetScript("OnEditFocusLost", saveName)
  r.name:SetScript("OnEscapePressed", function(self) self:SetText(r.m and r.m.name or ""); self:ClearFocus() end)
  local function dd(width, values, get, set, title, tip)
    local d = W.dropdown(r, { width = width, values = function() return r.m and values(r.m) or {} end,
      get = function() return r.m and get(r.m) end, set = function(v) if r.m then set(r.m, v); Core().changed() end end })
    W.ddTip(d, title, tip)
    return d
  end
  r.cls = dd(96, function() return SP.classValues() end, function(m) return m.cls end, function(m, v) S().setClass(squad(), m, v) end,
    "Class", "Changing the class starts the talent plan and own keys of this character over.")
  r.cls:SetPoint("TOPLEFT", 150, -3)
  r.race = dd(128, SP.raceValues, function(m) return m.race end, function(m, v) m.race = v end, "Race", "Only races that can be this class.")
  r.race:SetPoint("LEFT", r.cls, "RIGHT", 6, 0)
  r.role = dd(104, SP.roleValues, function(m) return m.role end, function(m, v) S().setRole(m, v) end,
    "Role", "Picks the recommended keys and talent guide of this character.")
  r.role:SetPoint("LEFT", r.race, "RIGHT", 6, 0)
  r.remove = W.button(r, "Remove", 64, 22, function(self)
    if not self.armed then self.armed = true; W.setLabel(self, "Sure?"); return end
    self.armed = false; W.setLabel(self, "Remove")
    local s = squad()
    for i, x in ipairs(s.members) do if x == r.m then table.remove(s.members, i) break end end
    S().fixLeader(s)
    Core().log("info", "removed " .. r.m.name)
    Core().changed()
  end, "Removes this character from the squad (click twice). Its macros in the game stay.")
  r.remove:SetPoint("TOPRIGHT", -4, -3)
  -- line 2
  r.plays = dd(150, function() return ns.Book.playsAsValues() end, function(m) return m.leader and "leader" or m.unit end,
    function(m, v) S().setPlaysAs(squad(), m, v) end, "Plays as", "Leader: plays normally. Follower: its keys use the leader's target through the unit (party1–4 or focus).")
  r.plays:SetPoint("TOPLEFT", 46, -29)
  r.seq = W.seqControl(r, { member = function() return r.m end, width = 96 })
  r.seq:SetPoint("LEFT", r.plays, "RIGHT", 10, 0)
  r.me = W.button(r, "This is me", 90, 22, function() Core().setMe(squad().id, r.m.id) end,
    "Tells WoWBoxer that the character you are logged in on is this one (its keys and role are used here).")
  r.me:SetPoint("TOPRIGHT", -4, -29)
  r.meText = W.text(r, "GameFontNormalSmall", nil, W.GOLD, "RIGHT")
  r.meText:SetPoint("RIGHT", r.me, "RIGHT", 0, 0)
  r.meText:SetText("You")
  return r
end

SP.register({ key = "edit", label = "Edit squad", tip = "Names, classes, roles, who leads, sequence keys, order.",
  build = function(f)
    f.nameBox = W.frame("EditBox", f, "InputBoxTemplate")
    f.nameBox:SetSize(170, 20)
    f.nameBox:SetAutoFocus(false)
    f.nameBox:SetMaxLetters(40)
    local nl = W.text(f, "GameFontNormalSmall", nil, W.GOLD)
    nl:SetPoint("TOPLEFT", 0, -5)
    nl:SetText("Squad name")
    f.nameBox:SetPoint("LEFT", nl, "RIGHT", 12, 0)
    local function saveSquadName(self)
      local s = squad()
      local n = ns.Rules.cleanText(self:GetText() or "", 40)
      if s and n and n ~= "" and n ~= s.name then s.name = n; Core().changed() end
    end
    f.nameBox:SetScript("OnEnterPressed", function(self) saveSquadName(self); self:ClearFocus() end)
    f.nameBox:SetScript("OnEditFocusLost", saveSquadName)
    f.nameBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    f.add = W.button(f, "Add character", 110, 22, function() SP.addCharacter() end, "Adds another character you play together with this one (a follower).")
    f.add:SetPoint("TOPRIGHT", 0, 0)
    f.party = W.button(f, "Add my party", 104, 22, function() SP.addParty() end,
      "Adds everyone in your party who is not in the squad yet (names and classes from the game; the party leader leads).")
    f.party:SetPoint("RIGHT", f.add, "LEFT", -6, 0)

    local sf, content = W.scroll(f, LIST_W, 4 * ROW_H)
    sf:SetPoint("TOPLEFT", 0, -28)
    f.list = content
    f.pool = W.pool(content, function(parent) return buildRow(f, parent) end)
    f.dropLine = f:CreateTexture(nil, "OVERLAY")
    f.dropLine:SetColorTexture(1, 0.82, 0, 0.8)
    f.dropLine:SetHeight(2)
    f.dropLine:SetPoint("TOPLEFT", sf, "BOTTOMLEFT", 0, -2)
    f.dropLine:SetPoint("TOPRIGHT", sf, "BOTTOMRIGHT", 0, -2)
    f.dropLine:Hide()

    -- footer
    f.template = W.dropdown(f, { width = 140, placeholder = "Choose…",
      values = function() local v = {}; for _, t in ipairs(S().TEMPLATES) do v[#v + 1] = { t.key, t.name, t.tip .. " Starts a new squad; your other squads stay." } end return v end,
      get = function() return nil end,
      set = function(v)
        local s = S().fromTemplate(v, ns.Compat.playerFaction())
        if not s then return end
        table.insert(Core().db.squads, s); Core().db.active = s.id
        Core().cdb.squadId, Core().cdb.memberId = nil, nil
        Core().print("New squad \"" .. s.name .. "\" from a template. Rename the characters, then pick yourself with This is me.")
        Core().changed()
      end })
    local tl = W.labelled(f, "New from template", f.template)
    tl:SetPoint("BOTTOMLEFT", 0, 36)
    W.ddTip(f.template, "Templates", "Duo, Trio, Quad, 5-man or the Undead trio example. Creates a new squad; your current one stays.")
    f.allSeq = W.dropdown(f, { width = 110, placeholder = "Choose…",
      values = function() return { { "off", "Off" }, { "simple", "Simple" }, { "medium", "Medium" }, { "advanced", "Advanced" } } end,
      get = function() return nil end,
      set = function(v)
        local s = squad()
        for _, m in ipairs(s and s.members or {}) do
          if ns.Engine.seqSupported(m.cls) then if v ~= "off" then m.seqTier = v end m.seq = v end
        end
        Core().changed()
      end })
    local al = W.labelled(f, "Everyone's sequence keys", f.allSeq)
    al:SetPoint("LEFT", f.template, "RIGHT", 16, 0)
    W.ddTip(f.allSeq, "Everyone's sequence keys", "Sets sequence keys for every character whose class has them. Each client then updates its own keys.")
    f.new = W.button(f, "New squad", 86, 22, function()
      local s = S().newSquad({ name = "New squad", faction = ns.Compat.playerFaction() })
      table.insert(Core().db.squads, s); Core().db.active = s.id; Core().changed()
    end, "Starts an empty squad. Your current squad stays and can be picked again.")
    f.new:SetPoint("BOTTOMLEFT", 0, 0)
    f.dup = W.button(f, "Duplicate", 80, 22, function()
      local s = squad()
      if not s then return end
      local copy = S().newSquad({ name = s.name .. " (copy)", faction = s.faction, linkLevels = s.linkLevels, members = s.members, presets = {} })
      for _, m in ipairs(copy.members) do m.id = S().uid("m") end
      S().fixLeader(copy)
      table.insert(Core().db.squads, copy); Core().db.active = copy.id; Core().changed()
    end, "Makes a copy of this squad to try changes on.")
    f.dup:SetPoint("LEFT", f.new, "RIGHT", 6, 0)
    f.del = W.button(f, "Delete squad", 100, 22, function(self)
      local s = squad()
      if not s then return end
      if not self.armed then self.armed = true; W.setLabel(self, "Click to confirm"); return end
      for i, x in ipairs(Core().db.squads) do if x == s then table.remove(Core().db.squads, i) break end end
      Core().db.active = Core().db.squads[1] and Core().db.squads[1].id or nil
      self.armed = false; W.setLabel(self, "Delete squad"); Core().changed()
    end, "Deletes this squad from WoWBoxer (click twice). Your macros in the game stay.")
    f.del:SetPoint("LEFT", f.dup, "RIGHT", 6, 0)
  end,
  refresh = function(f)
    local s = squad()
    local _, me = Core().me()
    if not f.nameBox:HasFocus() then f.nameBox:SetText(s and s.name or "") end
    f.pool:reset()
    for i, m in ipairs(s and s.members or {}) do
      local r = f.pool:get()
      r:ClearAllPoints()
      r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
      r.m, r.index = m, i
      r.num:SetText(i)
      if not r.name:HasFocus() then r.name:SetText(m.name) end
      r.cls.Refresh(); r.race.Refresh(); r.role.Refresh(); r.plays.Refresh(); r.seq.Refresh()
      r.me:SetShown(m ~= me); r.meText:SetShown(m == me)
      r.remove.armed = false; W.setLabel(r.remove, "Remove")
      r.remove:SetEnabled(#s.members > 1 or m ~= me)
      r.bg:SetColorTexture(m == me and 0.3 or 0, m == me and 0.24 or 0, 0, m == me and 0.25 or 0.22)
    end
    f.list:SetHeight(math.max(10, #(s and s.members or {}) * ROW_H))
    f.add:SetEnabled(s ~= nil and #s.members < S().MAX_MEMBERS)
    f.party:SetEnabled(ns.Compat.inParty())
    f.del:SetEnabled(s ~= nil)
    f.template.Refresh(); f.allSeq.Refresh()
  end })

--- A new follower in the active squad (a squad is created when there is none).
function SP.addCharacter()
  local s = squad()
  if not s then
    s = S().newSquad({ name = "My squad", faction = ns.Compat.playerFaction() })
    table.insert(Core().db.squads, s); Core().db.active = s.id
  end
  if #s.members >= S().MAX_MEMBERS then Core().print("A squad holds at most " .. S().MAX_MEMBERS .. " characters."); return nil end
  local m = S().newMember({ name = "Character " .. (#s.members + 1), cls = "priest", race = S().raceFor("priest", s.faction), leader = #s.members == 0,
    unit = "party1", level = ns.Compat.playerLevel() })
  table.insert(s.members, m)
  S().fixLeader(s); S().applyLink(s)
  Core().log("info", "added " .. m.name)
  Core().changed()
  return m
end
--- Everyone in the party who is not in the squad yet (by name). Returns how many were added.
function SP.addParty()
  local s = squad()
  local info = ns.Squad.partyInfo()
  if not s then
    s = S().fromParty(info, ns.Compat.playerFaction())
    table.insert(Core().db.squads, s); Core().db.active = s.id
    Core().cdb.squadId, Core().cdb.memberId = nil, nil
    Core().log("info", "squad from party (" .. #s.members .. ")")
    Core().changed()
    return #s.members
  end
  local n = 0
  local leaderName
  for _, x in ipairs(info) do
    local found
    for _, m in ipairs(s.members) do if m.name:lower() == x.name:lower() then found = m end end
    if not found and #s.members < S().MAX_MEMBERS then
      found = S().newMember({ name = x.name, cls = x.cls, race = x.race or S().raceFor(x.cls, s.faction), level = x.level, unit = "party1" })
      table.insert(s.members, found)
      n = n + 1
    end
    if x.leader then leaderName = x.name end
  end
  if leaderName then for _, m in ipairs(s.members) do m.leader = m.name:lower() == leaderName:lower() end end
  S().fixLeader(s); S().applyLink(s)
  Core().log("info", "added " .. n .. " from the party")
  Core().print(n > 0 and ("Added " .. n .. " character" .. (n == 1 and "" or "s") .. " from your party.") or "Everyone in your party is already in the squad.")
  Core().changed()
  return n
end

-- ------------------------------------------------------------------ the tab: page buttons + squad picker
function SP.select(p, key)
  if not SP.byKey[key] then key = "home" end
  p.page = key
  UI.Refresh()
end

function tab.build(p)
  p.page = "home"
  p.nav = {}
  local prev
  for _, def in ipairs(SP.pages) do
    local b = W.button(p, def.label, 60, 22, function() SP.select(p, def.key) end, def.tip)
    if prev then b:SetPoint("LEFT", prev, "RIGHT", 4, 0) else b:SetPoint("TOPLEFT", 0, 0) end
    b.sel = b:CreateTexture(nil, "OVERLAY")
    b.sel:SetPoint("BOTTOMLEFT", 6, 2)
    b.sel:SetPoint("BOTTOMRIGHT", -6, 2)
    b.sel:SetHeight(2)
    b.sel:SetColorTexture(1, 0.82, 0, 1)
    p.nav[def.key] = b
    prev = b
  end
  p.squadPick = W.dropdown(p, { width = 170,
    values = function() local v = {}; for _, s in ipairs(Core().db.squads) do v[#v + 1] = { s.id, s.name .. " (" .. #s.members .. ")" } end return v end,
    get = function() return Core().db.active end,
    set = function(v) Core().db.active = v; Core().cdb.squadId, Core().cdb.memberId = nil, nil; Core().changed() end })
  p.squadPick:SetPoint("TOPRIGHT", 0, 0)
  W.ddTip(p.squadPick, "Squad", "The squad this character uses. Switching changes only WoWBoxer's own setup.")
  p.frames = {}
  for _, def in ipairs(SP.pages) do
    local f = CreateFrame("Frame", nil, p)
    f:SetPoint("TOPLEFT", 0, -32)
    f:SetPoint("BOTTOMRIGHT", 0, 0)
    f:Hide()
    def.build(f, p)
    p.frames[def.key] = f
  end
end

function tab.refresh(p)
  p.squadPick.Refresh()
  for _, def in ipairs(SP.pages) do
    local on = def.key == p.page
    p.frames[def.key]:SetShown(on)
    p.nav[def.key].sel:SetShown(on)
    if on then p.nav[def.key]:LockHighlight() else p.nav[def.key]:UnlockHighlight() end
  end
  local def = SP.byKey[p.page]
  if def then def.refresh(p.frames[p.page], p) end
end

UI.RegisterTab(tab)
