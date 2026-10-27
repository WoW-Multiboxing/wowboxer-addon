--[[ WoWBoxer – Squad tab (docs/ui-spec.md): one card per character, a small inline editor for add/edit, and an info
  box. Only SavedVariables change here; macros change when the player presses Place all. ]]
local _, ns = ...
local UI, W = ns.UI, ns.Widgets
local tab = { key = "squad", label = "Squad", icon = "Spell_Holy_PrayerOfFortitude", tip = "The characters you play together: names, classes, roles, who leads." }
local CARD_H = 48
local LIST_W = 640 -- + scrollbar

local function D() return ns.Data end
local function S() return ns.State end
local function Core() return ns.Core end
local function squad() return S().activeSquad(Core().db) end

local CLASS_TEX = "Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES"
local function setClassIcon(tex, cls)
  local tc = _G.CLASS_ICON_TCOORDS and _G.CLASS_ICON_TCOORDS[(cls or ""):upper()]
  if tc then tex:SetTexture(CLASS_TEX); if tex.SetTexCoord then tex:SetTexCoord(tc[1], tc[2], tc[3], tc[4]) end
  else W.setIcon(tex, nil) end
end
local function playsAsText(m, s)
  if m.leader then return "Leader · plays normally" end
  local L = S().leaderOf(s)
  return "Follows " .. (L and L.name or "the leader") .. " (" .. m.unit .. ")"
end

-- ------------------------------------------------------------------ editor (add + edit)
local function buildEditor(p)
  local e = W.box(p, 0.09, 0.07, 0.045, 0.97)
  e:SetPoint("BOTTOMLEFT", 0, 0)
  e:SetPoint("BOTTOMRIGHT", 0, 0)
  e:SetHeight(84)
  e.title = W.text(e, "GameFontNormal", nil, W.GOLD)
  e.title:SetPoint("TOPLEFT", 10, -8)
  e.name = W.frame("EditBox", e, "InputBoxTemplate")
  e.name:SetSize(120, 20)
  e.name:SetAutoFocus(false)
  e.name:SetMaxLetters(24)
  e.name:SetPoint("TOPLEFT", 16, -28)
  e.name:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  e.v = {}
  local function cyc(width, values, key)
    return W.cycle(e, { width = width, values = values, get = function() return e.v[key] end, set = function(v) e.v[key] = v; e.refresh() end })
  end
  e.cls = cyc(118, function() local v = {}; for _, c in ipairs(D().classOrder) do v[#v + 1] = { c, D().classes[c].n } end return v end, "cls")
  e.cls:SetPoint("LEFT", e.name, "RIGHT", 8, 0)
  e.race = cyc(160, function() local v = {}; for _, r in ipairs(S().racesFor(e.v.cls)) do v[#v + 1] = { r.k, r.n } end return v end, "race")
  e.race:SetPoint("LEFT", e.cls, "RIGHT", 4, 0)
  e.role = cyc(116, function() local v = {}; for _, r in ipairs(D().classes[e.v.cls].roles) do v[#v + 1] = { r, S().ROLE_NAME[r] } end return v end, "role")
  e.role:SetPoint("LEFT", e.race, "RIGHT", 4, 0)
  e.plays = cyc(170, function()
    local v = { { "leader", "Leader" } }
    for _, u in ipairs(ns.Engine.UNITS) do v[#v + 1] = { u, "Follower (" .. u .. ")" } end
    return v
  end, "plays")
  e.plays:SetPoint("TOPLEFT", 10, -56)
  e.save = W.button(e, "Add", 90, 22, function() p.saveEditor() end, "Saves the character in WoWBoxer. Nothing changes in the game.")
  e.save:SetPoint("BOTTOMRIGHT", -8, 6)
  e.cancel = W.button(e, "Cancel", 70, 22, function() p.closeEditor() end, "Closes the editor without saving.")
  e.cancel:SetPoint("RIGHT", e.save, "LEFT", -6, 0)
  e.remove = W.button(e, "Remove", 80, 22, function(self)
    if not self.armed then self.armed = true; W.setLabel(self, "Sure?"); return end
    self.armed = false; W.setLabel(self, "Remove")
    local s = squad()
    for i, x in ipairs(s.members) do if x == e.member then table.remove(s.members, i) break end end
    S().fixLeader(s)
    Core().log("info", "removed " .. e.member.name)
    p.closeEditor(); Core().changed()
  end, "Removes this character from the squad (click twice).")
  e.remove:SetPoint("RIGHT", e.cancel, "LEFT", -6, 0)
  function e.refresh()
    -- keep race/role valid for the class
    local okRace = false
    for _, r in ipairs(S().racesFor(e.v.cls)) do if r.k == e.v.race then okRace = true end end
    if not okRace then e.v.race = S().racesFor(e.v.cls)[1].k end
    if not ns.Engine.contains(D().classes[e.v.cls].roles, e.v.role) then e.v.role = D().classes[e.v.cls].roles[1] end
    e.cls.Refresh(); e.race.Refresh(); e.role.Refresh(); e.plays.Refresh()
  end
  e:Hide()
  return e
end

function tab.build(p)
  local top = W.text(p, "GameFontNormal", nil, W.GOLD)
  top:SetPoint("TOPLEFT", 0, -6)
  top:SetText("Squad")
  p.squadCycle = W.cycle(p, { width = 230,
    values = function() local v = {}; for _, s in ipairs(Core().db.squads) do v[#v + 1] = { s.id, s.name .. " (" .. #s.members .. ")" } end return v end,
    get = function() return Core().db.active end,
    set = function(v) Core().db.active = v; Core().cdb.squadId, Core().cdb.memberId = nil, nil; Core().changed() end })
  p.squadCycle:SetPoint("LEFT", top, "RIGHT", 8, 0)
  p.delSquad = W.button(p, "Delete squad", 100, 22, function(self)
    local s = squad()
    if not s then return end
    if not self.armed then self.armed = true; W.setLabel(self, "Click to confirm"); return end
    for i, x in ipairs(Core().db.squads) do if x == s then table.remove(Core().db.squads, i) break end end
    Core().db.active = Core().db.squads[1] and Core().db.squads[1].id or nil
    self.armed = false; W.setLabel(self, "Delete squad"); Core().changed()
  end, "Deletes this squad from WoWBoxer (click twice). Your macros in the game stay.")
  p.delSquad:SetPoint("LEFT", p.squadCycle, "RIGHT", 6, 0)
  p.addChar = W.button(p, "Add character", 120, 22, function() p.openEditor(nil) end, "Adds another character you play together with this one.")
  p.addChar:SetPoint("TOPRIGHT", 0, -2)
  p.newSquad = W.button(p, "New squad", 90, 22, function()
    local s = S().newSquad({ name = "New squad", faction = ns.Compat.playerFaction() })
    table.insert(Core().db.squads, s); Core().db.active = s.id; Core().changed()
  end, "Starts an empty squad. Your current squad stays and can be picked again.")
  p.newSquad:SetPoint("RIGHT", p.addChar, "LEFT", -6, 0)

  local sf, content = W.scroll(p, LIST_W, 296)
  sf:SetPoint("TOPLEFT", 0, -32)
  p.list = content
  p.pool = W.pool(content, function(parent)
    local r = W.box(parent, 0.08, 0.063, 0.043, 0.95)
    r:SetSize(LIST_W - 4, CARD_H - 4)
    r.badge = r:CreateTexture(nil, "ARTWORK")
    r.badge:SetSize(30, 30)
    r.badge:SetPoint("LEFT", 8, 0)
    r.name = W.line(r, "GameFontNormal")
    r.name:SetPoint("TOPLEFT", 46, -7)
    r.name:SetWidth(300)
    r.sub = W.line(r, "GameFontHighlightSmall", nil, W.MUTED)
    r.sub:SetPoint("TOPLEFT", 46, -24)
    r.sub:SetWidth(300)
    r.role = W.line(r, "GameFontHighlightSmall", nil, W.TEXT)
    r.role:SetPoint("TOPLEFT", 352, -7)
    r.role:SetWidth(110)
    r.plays = W.line(r, "GameFontHighlightSmall", nil, W.MUTED)
    r.plays:SetPoint("TOPLEFT", 352, -24)
    r.plays:SetWidth(170)
    W.tooltip(r, function(GT) GT:AddLine(r.name:GetText() or "", 1, 1, 1); GT:AddLine(r.sub:GetText() or "", 0.8, 0.8, 0.8, true); GT:AddLine(r.plays:GetText() or "", 0.8, 0.8, 0.8, true) end)
    r.edit = W.button(r, "Edit", 54, 20, function() p.openEditor(r.m) end, "Change name, class, race, role or who this character follows.")
    r.edit:SetPoint("TOPRIGHT", -6, -4)
    r.me = W.button(r, "This is me", 82, 20, function() Core().setMe(squad().id, r.m.id) end,
      "Tells WoWBoxer that the character you are logged in on is this one (its keys and role are used here).")
    r.me:SetPoint("BOTTOMRIGHT", -6, 4)
    r.lead = W.button(r, "Make leader", 84, 20, function()
      for _, x in ipairs(squad().members) do x.leader = (x == r.m) end
      S().applyLink(squad()); Core().changed()
    end, "Makes this character the leader: the others' keys use its target. Update the keys on every client afterwards.")
    r.lead:SetPoint("RIGHT", r.edit, "LEFT", -4, 0)
    return r
  end)

  -- info box (shown when the editor is closed)
  p.info = W.box(p, 0.06, 0.05, 0.03, 0.95)
  p.info:SetPoint("BOTTOMLEFT", 0, 0)
  p.info:SetPoint("BOTTOMRIGHT", 0, 0)
  p.info:SetHeight(84)
  p.infoText = W.text(p.info, "GameFontHighlightSmall", nil, W.MUTED)
  p.infoText:SetPoint("TOPLEFT", 10, -8)
  p.infoText:SetPoint("TOPRIGHT", -10, -8)
  p.infoText:SetText("The leader plays normally. Followers' keys use the leader's target through party1–4 or focus, and heal the leader. " ..
    "Every client runs WoWBoxer on its own: set the squad up once, then import the same string on every character (Share tab). " ..
    "One key press is always one action on one character.")
  p.link = W.check(p.info, "Followers use the leader's level", function(_, v) local s = squad(); if s then s.linkLevels = v; S().applyLink(s); Core().changed() end end)
  p.link:SetPoint("BOTTOMLEFT", 6, 4)

  p.editor = buildEditor(p)
  function p.openEditor(m)
    local e = p.editor
    e.member = m
    if m then
      e.v = { cls = m.cls, race = m.race, role = m.role, plays = m.leader and "leader" or m.unit }
      e.name:SetText(m.name)
      e.title:SetText("Edit " .. m.name)
      W.setLabel(e.save, "Save")
      e.remove:Show()
    else
      e.v = { cls = "priest", plays = "party1" }
      e.name:SetText("")
      e.title:SetText("Add a character")
      W.setLabel(e.save, "Add")
      e.remove:Hide()
    end
    e.remove.armed = false; W.setLabel(e.remove, "Remove")
    e.refresh()
    e:Show(); p.info:Hide()
    UI.Refresh()
  end
  function p.closeEditor()
    p.editor.member = nil
    p.editor:Hide(); p.info:Show()
    UI.Refresh()
  end
  function p.saveEditor()
    local e = p.editor
    local s = squad()
    if not s then
      s = S().newSquad({ name = "My squad", faction = ns.Compat.playerFaction() })
      table.insert(Core().db.squads, s); Core().db.active = s.id
    end
    local name = ns.Rules.cleanText(e.name:GetText() or "", 24)
    local v = e.v
    local leader = v.plays == "leader"
    local unit = (not leader) and v.plays or nil
    if e.member then
      local m = e.member
      local keep = m.cls == v.cls
      local nm = S().newMember({ id = m.id, name = (name and name ~= "") and name or m.name, cls = v.cls, race = v.race, role = v.role,
        level = m.level, leader = leader, unit = unit or m.unit, talented = m.talented, seq = m.seq, seqTarget = m.seqTarget,
        build = keep and m.build or nil, guide = (keep and m.role == v.role) and m.guide or nil,
        customSeq = keep and m.customSeq or nil, pins = keep and m.pins or nil })
      for i, x in ipairs(s.members) do if x == m then s.members[i] = nm end end
      if leader then for _, x in ipairs(s.members) do x.leader = (x == nm) end end
      S().fixLeader(s)
      Core().log("info", "edited " .. nm.name .. " (" .. nm.cls .. ")")
    else
      if #s.members >= S().MAX_MEMBERS then Core().print("A squad holds at most " .. S().MAX_MEMBERS .. " characters."); return end
      local m = S().newMember({ name = name, cls = v.cls, race = v.race, role = v.role, leader = leader or #s.members == 0, unit = unit,
        level = ns.Compat.playerLevel() })
      table.insert(s.members, m)
      if m.leader then for _, x in ipairs(s.members) do x.leader = (x == m) end end
      S().fixLeader(s); S().applyLink(s)
      Core().log("info", "added " .. m.name .. " (" .. m.cls .. ")")
    end
    e.name:ClearFocus()
    p.closeEditor()
    Core().changed()
  end
end

function tab.refresh(p)
  local s = squad()
  local _, me = Core().me()
  p.squadCycle.Refresh()
  p.link:SetChecked(s and s.linkLevels or false)
  p.delSquad:SetEnabled(s ~= nil)
  p.pool:reset()
  local y = 0
  for _, m in ipairs(s and s.members or {}) do
    local r = p.pool:get()
    r.m = m
    r:SetPoint("TOPLEFT", 0, -y)
    y = y + CARD_H
    setClassIcon(r.badge, m.cls)
    r.name:SetText(W.hex(W.classColor(m.cls)) .. m.name .. "|r" .. (m.leader and "  |cffffd100Leader|r" or "") .. (m == me and "  |cff7cc7ff(you)|r" or ""))
    local g = ns.Kit.guide(m.cls, m.guide)
    local race = ns.Kit.race(m.race)
    r.sub:SetText(D().classes[m.cls].n .. " · " .. (race and race.n or m.race) .. " · Level " .. m.level .. (g and (" · " .. g.spec) or "") ..
      (m.seq ~= "off" and (" · Sequences " .. m.seq) or ""))
    r.role:SetText(S().ROLE_NAME[m.role] or m.role)
    r.plays:SetText(playsAsText(m, s))
    r.lead:SetShown(not m.leader)
    r.me:SetShown(m ~= me)
    if r.SetBackdropBorderColor then
      if p.editor.member == m then r:SetBackdropBorderColor(0.49, 0.78, 1, 1)
      elseif m == me then r:SetBackdropBorderColor(1, 0.82, 0, 1)
      else r:SetBackdropBorderColor(0.54, 0.43, 0.2, 1) end
    end
  end
  p.list:SetHeight(math.max(y, 10))
end

UI.RegisterTab(tab)
