--[[ WoWBoxer – Squad tab: squads, characters (class, race, role, leader / follower unit), "this is me". ]]
local _, ns = ...
local UI, W = ns.UI, ns.Widgets
local tab = { key = "squad", label = "Squad" }
local ROW_H = 50

local function D() return ns.Data end
local function S() return ns.State end
local function Core() return ns.Core end

local function squad() return S().activeSquad(Core().db) end

local function unitValues() local v = {}; for _, u in ipairs(ns.Engine.UNITS) do v[#v + 1] = { u, "via " .. u } end return v end
local function roleValues(cls) local v = {}; for _, r in ipairs(D().classes[cls].roles) do v[#v + 1] = { r, S().ROLE_NAME[r] } end return v end

function tab.build(p)
  local top = W.text(p, "GameFontHighlightSmall", nil, W.MUTED)
  top:SetPoint("TOPLEFT", 0, -6)
  top:SetText("Squad")
  p.squadCycle = W.cycle(p, { width = 220,
    values = function() local v = {}; for _, s in ipairs(Core().db.squads) do v[#v + 1] = { s.id, s.name .. " (" .. #s.members .. ")" } end return v end,
    get = function() return Core().db.active end,
    set = function(v) Core().db.active = v; Core().cdb.squadId, Core().cdb.memberId = nil, nil; Core().changed() end })
  p.squadCycle:SetPoint("LEFT", top, "RIGHT", 6, 0)
  p.link = W.check(p, "Followers use the leader's level", function(_, v) local s = squad(); if s then s.linkLevels = v; S().applyLink(s); Core().changed() end end)
  p.link:SetPoint("LEFT", p.squadCycle, "RIGHT", 10, 0)
  p.newSquad = W.button(p, "New squad", 90, 22, function()
    local s = S().newSquad({ name = "New squad", faction = ns.Compat.playerFaction() })
    table.insert(Core().db.squads, s); Core().db.active = s.id; Core().changed()
  end)
  p.newSquad:SetPoint("TOPRIGHT", 0, -2)
  p.delSquad = W.button(p, "Delete squad", 100, 22, function(self)
    local s = squad()
    if not s then return end
    if self.armed then
      for i, x in ipairs(Core().db.squads) do if x == s then table.remove(Core().db.squads, i) break end end
      Core().db.active = Core().db.squads[1] and Core().db.squads[1].id or nil
      self.armed = false; self:SetText("Delete squad"); Core().changed()
    else self.armed = true; self:SetText("Click to confirm") end
  end)
  p.delSquad:SetPoint("RIGHT", p.newSquad, "LEFT", -6, 0)

  local sf, content = W.scroll(p, 606, 236)
  sf:SetPoint("TOPLEFT", 0, -32)
  p.list = content
  p.pool = W.pool(content, function(parent)
    local r = W.box(parent, 0.08, 0.063, 0.043, 0.95)
    r:SetSize(600, ROW_H - 4)
    r.name = W.text(r, "GameFontNormal")
    r.name:SetPoint("TOPLEFT", 10, -6)
    r.sub = W.text(r, "GameFontHighlightSmall", nil, W.MUTED)
    r.sub:SetPoint("TOPLEFT", 10, -22)
    r.sub:SetWidth(250)
    r.role = W.cycle(r, { width = 120, values = function() return roleValues(r.m.cls) end, get = function() return r.m.role end,
      set = function(v) r.m.role = v; r.m.guide = ns.Kit.defaultGuideFor(r.m.cls, v); Core().changed() end })
    r.role:SetPoint("BOTTOMLEFT", 262, 3)
    r.unit = W.cycle(r, { width = 120, values = unitValues, get = function() return r.m.unit end, set = function(v) r.m.unit = v; Core().changed() end })
    r.unit:SetPoint("LEFT", r.role, "RIGHT", 4, 0)
    r.leaderBtn = W.button(r, "Make leader", 84, 20, function()
      for _, x in ipairs(squad().members) do x.leader = (x == r.m) end
      S().applyLink(squad()); Core().changed()
    end)
    r.leaderBtn:SetPoint("BOTTOMRIGHT", -4, 3)
    r.meBtn = W.button(r, "This is me", 80, 20, function() Core().setMe(squad().id, r.m.id) end)
    r.meBtn:SetPoint("TOPRIGHT", -84, -3)
    r.edit = W.button(r, "Edit", 54, 20, function() p.startEdit(r.m) end)
    r.edit:SetPoint("TOPRIGHT", -28, -3)
    r.del = W.button(r, "x", 20, 20, function()
      local s = squad()
      for i, x in ipairs(s.members) do if x == r.m then table.remove(s.members, i) break end end
      S().fixLeader(s); Core().changed()
    end)
    r.del:SetPoint("TOPRIGHT", -4, -3)
    W.tooltip(r.del, function(GT) GT:AddLine("Remove from the squad", 1, 0.82, 0) end)
    return r
  end)

  -- add character
  local addBox = W.box(p, 0.08, 0.063, 0.043, 0.95)
  addBox:SetPoint("BOTTOMLEFT", 0, 34)
  addBox:SetPoint("BOTTOMRIGHT", 0, 34)
  addBox:SetHeight(40)
  local at = W.text(addBox, "GameFontNormalSmall", nil, W.GOLD)
  at:SetPoint("LEFT", 8, 0)
  at:SetWidth(30)
  at:SetText("Add")
  p.addTitle = at
  p.newName = W.frame("EditBox", addBox, "InputBoxTemplate")
  p.newName:SetSize(110, 20)
  p.newName:SetAutoFocus(false)
  p.newName:SetPoint("LEFT", at, "RIGHT", 12, 0)
  p.newName:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  p.add = { cls = "priest", race = nil, role = nil }
  p.clsCycle = W.cycle(addBox, { width = 120, values = function() local v = {}; for _, c in ipairs(D().classOrder) do v[#v + 1] = { c, D().classes[c].n } end return v end,
    get = function() return p.add.cls end, set = function(v) p.add.cls = v; p.add.race = nil; p.add.role = nil; p.raceCycle.Refresh(); p.roleCycle.Refresh() end })
  p.clsCycle:SetPoint("LEFT", p.newName, "RIGHT", 8, 0)
  p.raceCycle = W.cycle(addBox, { width = 150, values = function() local v = {}; for _, r in ipairs(S().racesFor(p.add.cls)) do v[#v + 1] = { r.k, r.n } end return v end,
    get = function() return p.add.race or S().racesFor(p.add.cls)[1].k end, set = function(v) p.add.race = v end })
  p.raceCycle:SetPoint("LEFT", p.clsCycle, "RIGHT", 4, 0)
  p.roleCycle = W.cycle(addBox, { width = 110, values = function() return roleValues(p.add.cls) end,
    get = function() return p.add.role or D().classes[p.add.cls].roles[1] end, set = function(v) p.add.role = v end })
  p.roleCycle:SetPoint("LEFT", p.raceCycle, "RIGHT", 4, 0)
  function p.startEdit(m)
    p.editing = m
    p.add.cls, p.add.race, p.add.role = m.cls, m.race, m.role
    p.newName:SetText(m.name)
    p.addTitle:SetText("Edit")
    p.addBtn:SetText("Save")
    p.cancelEdit:Show()
    p.clsCycle.Refresh(); p.raceCycle.Refresh(); p.roleCycle.Refresh()
  end
  function p.stopEdit()
    p.editing = nil
    p.newName:SetText("")
    p.addTitle:SetText("Add")
    p.addBtn:SetText("Add")
    p.cancelEdit:Hide()
  end
  p.addBtn = W.button(addBox, "Add", 56, 22, function()
    local s = squad()
    if p.editing then
      local m = p.editing
      local name = ns.Rules.cleanText(p.newName:GetText() or "", 24)
      local keep = m.cls == p.add.cls
      local nm = S().newMember({ id = m.id, name = (name and name ~= "") and name or m.name, cls = p.add.cls, race = p.add.race, role = p.add.role,
        level = m.level, leader = m.leader, unit = m.unit, talented = m.talented, seq = m.seq, seqTarget = m.seqTarget,
        build = keep and m.build or nil, guide = (keep and m.role == p.add.role) and m.guide or nil,
        customSeq = keep and m.customSeq or nil, pins = keep and m.pins or nil })
      for i, x in ipairs(s.members) do if x == m then s.members[i] = nm end end
      Core().log("info", "edited " .. nm.name .. " (" .. nm.cls .. ")")
      p.stopEdit(); p.newName:ClearFocus()
      Core().changed()
      return
    end
    if not s then s = S().newSquad({ name = "My squad", faction = ns.Compat.playerFaction() }); table.insert(Core().db.squads, s); Core().db.active = s.id end
    if #s.members >= S().MAX_MEMBERS then Core().print("A squad holds at most " .. S().MAX_MEMBERS .. " characters."); return end
    local name = ns.Rules.cleanText(p.newName:GetText() or "", 24)
    local m = S().newMember({ name = name, cls = p.add.cls, race = p.add.race, role = p.add.role, leader = #s.members == 0, level = ns.Compat.playerLevel() })
    table.insert(s.members, m)
    S().fixLeader(s); S().applyLink(s)
    p.newName:SetText(""); p.newName:ClearFocus()
    Core().log("info", "added " .. m.name .. " (" .. m.cls .. ")")
    Core().changed()
  end)
  p.addBtn:SetPoint("RIGHT", -6, 0)
  p.cancelEdit = W.button(p, "Cancel edit", 90, 20, function() p.stopEdit() end)
  p.cancelEdit:SetPoint("BOTTOMRIGHT", addBox, "TOPRIGHT", 0, 2)
  p.cancelEdit:Hide()
  p.addMe = W.button(p, "Add this character", 140, 22, function()
    local info = Core().playerInfo()
    local s = squad()
    if not s then S().quickStart(Core().db, Core().cdb, info); Core().changed(); return end
    local m = S().newMember({ name = info.name, cls = info.cls, race = info.race, level = info.level, leader = #s.members == 0 })
    table.insert(s.members, m); S().fixLeader(s)
    Core().setMe(s.id, m.id)
  end)
  p.addMe:SetPoint("BOTTOMLEFT", 0, 4)
  p.help = W.text(p, "GameFontHighlightSmall", nil, W.MUTED)
  p.help:SetPoint("LEFT", p.addMe, "RIGHT", 10, 0)
  p.help:SetPoint("RIGHT", p, "RIGHT", 0, 0)
  p.help:SetText("Followers assist the leader via party1–4 or focus. Copy the squad to your other characters in Share.")
  if p.help.SetWordWrap then p.help:SetWordWrap(false) end
end

function tab.refresh(p)
  local s = squad()
  local _, me = Core().me()
  p.squadCycle.Refresh()
  p.link:SetChecked(s and s.linkLevels or false)
  p.delSquad:SetEnabled(s ~= nil)
  p.clsCycle.Refresh(); p.raceCycle.Refresh(); p.roleCycle.Refresh()
  p.addMe:SetShown(me == nil)
  p.pool:reset()
  local y = 0
  for _, m in ipairs(s and s.members or {}) do
    local r = p.pool:get()
    r.m = m
    r:SetPoint("TOPLEFT", 0, -y)
    y = y + ROW_H
    local col = W.classColor(m.cls)
    r.name:SetText(W.hex(col) .. m.name .. "|r" .. (m.leader and "  |cffffd100LEADER|r" or "") .. (m == me and "  |cff7cc7ffTHIS CHARACTER|r" or ""))
    local g = ns.Kit.guide(m.cls, m.guide)
    local race = ns.Kit.race(m.race)
    r.sub:SetText(D().classes[m.cls].n .. " · " .. (race and race.n or m.race) .. " · Level " .. m.level .. (g and (" · " .. g.spec) or "") ..
      (m.seq ~= "off" and (" · Seq " .. m.seq) or ""))
    r.role.Refresh()
    r.unit:SetShown(not m.leader); r.unit.Refresh()
    r.leaderBtn:SetShown(m.leader ~= true)
    r.meBtn:SetShown(m ~= me)
    if r.SetBackdropBorderColor then
      if p.editing == m then r:SetBackdropBorderColor(1, 0.82, 0, 1) else r:SetBackdropBorderColor(0.54, 0.43, 0.2, 1) end
    end
  end
  p.list:SetHeight(math.max(y, 10))
end

UI.RegisterTab(tab)
