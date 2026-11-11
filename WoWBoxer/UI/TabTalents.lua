--[[ WoWBoxer – Talents tab: the character's guide (picked from a list that shows each guide's source and type) or
  own build, what to take at this level, "plan ahead" to a chosen level, and the whole point order by level. Forever talent data; on other clients it is shown with a warning. ]]
local _, ns = ...
local UI, W = ns.UI, ns.Widgets
local tab = { key = "talents", label = "Talents", icon = "Ability_Marksmanship", tip = "The talent order of your guide and the next point to take." }
--- Rail state word: talent points not spent yet ("1 POINT"), where the client can tell.
function tab.badge(ctx)
  local n = ctx and ctx.member and ns.Compat.unspentTalentPoints(ctx.member, ctx.level)
  if n and n > 0 then return n .. (n == 1 and " POINT" or " POINTS"), "warn" end
end
local ROW_H = 20
local OWN = "\1own" -- the build that came with the squad (m.build)
local LEFT_W, LIST_W = 300, 322

local KIND = { ["exact-order"] = "Exact point order from the guide", ["final-derived"] = "Guide's final build; order by WoWBoxer",
  priorities = "Priorities only (no point order)", adaptation = "WoWBoxer adaptation of a guide" }

function tab.build(p)
  local lg = W.text(p, "GameFontHighlightSmall", nil, W.MUTED)
  lg:SetPoint("TOPLEFT", 0, -6)
  lg:SetText("Guide")
  p.guide = W.dropdown(p, { width = 300,
    values = function()
      local _, m = ns.Core.me()
      local v = {}
      if not m then return v end
      if m.build and #m.build > 0 then v[#v + 1] = { OWN, (m.buildName or "Own build") .. " (from your squad)", "The build that came with your squad (" .. #m.build .. " points)." } end
      for _, g in ipairs(ns.Kit.guidesOf(m.cls)) do
        v[#v + 1] = { g.id, g.user and ("My build: " .. g.label .. " (yours)" .. (g.stale and " |cffd9b36c– needs update|r" or "")) or (g.label .. (g.default and " *" or "")), tab.guideTip(g) }
      end
      return v
    end,
    get = function() local _, m = ns.Core.me(); if not m then return nil end; return (m.build and #m.build > 0) and OWN or m.guide end,
    set = function(v) if v ~= OWN then ns.Core.useGuide(v) end end })
  p.guide:SetPoint("LEFT", lg, "RIGHT", 6, 0)
  W.ddTip(p.guide, "Guide", "The talent guide WoWBoxer follows for this character. * = recommended for your role. Each guide shows its source and type when you hover it in the list.")
  -- Import a Wowhead link, copy one, rename / delete your own build
  p.importBtn = W.button(p, "Import", 70, 22, function() tab.openImport(p) end,
    "Paste a Wowhead " .. ns.Wowhead.gameName() .. " talent link and save it as your own build. It only changes WoWBoxer's plan: you still spend the points in the game's talent window.")
  p.importBtn:SetPoint("TOPRIGHT", p, "TOPRIGHT", -4, -2)
  p.linkBtn = W.button(p, "Wowhead link", 100, 22, function() tab.copyLink() end, "Shows this guide or build as a Wowhead talent link to copy (Ctrl+C) and open on Wowhead.")
  p.linkBtn:SetPoint("RIGHT", p.importBtn, "LEFT", -6, 0)
  p.renBtn = W.button(p, "Rename", 64, 20, function() tab.startRename(p) end, "Gives your build another name.")
  p.renBtn:SetPoint("LEFT", p.guide, "RIGHT", 8, 0)
  p.delBtn = W.button(p, "Delete", 56, 20, function(self)
    W.menu(self, { { "Yes, delete this build", function() local g = tab.current(); if g and g.user then ns.Core.deleteBuild(g.cls or tab.cls(), g.id) end end },
      { "No", function() end } })
  end, "Deletes your build (asks first). Characters that used it go back to the recommended guide.")
  p.delBtn:SetPoint("LEFT", p.renBtn, "RIGHT", 4, 0)
  p.renBox = W.frame("EditBox", p, "InputBoxTemplate")
  p.renBox:SetSize(290, 20)
  p.renBox:SetAutoFocus(false)
  p.renBox:SetMaxLetters(40)
  p.renBox:SetPoint("LEFT", p.guide, "LEFT", 6, 0)
  p.renBox:Hide()
  local function renDone(self, save)
    local g = tab.current()
    if save and g and g.user then ns.Core.renameBuild(tab.cls(), g.id, self:GetText()) end
    self:Hide(); self:ClearFocus(); UI.Refresh()
  end
  p.renBox:SetScript("OnEnterPressed", function(self) renDone(self, true) end)
  p.renBox:SetScript("OnEscapePressed", function(self) renDone(self, false) end)
  p.kind = W.text(p, "GameFontHighlightSmall", nil, W.GREEN)
  p.kind:SetPoint("TOPLEFT", 0, -30)
  p.kind:SetWidth(LEFT_W)

  local nb = W.box(p, 0.16, 0.13, 0.08, 0.95)
  nb:SetPoint("TOPLEFT", p.kind, "BOTTOMLEFT", 0, -6)
  nb:SetWidth(LEFT_W)
  nb:SetHeight(120)
  p.nb = nb
  p.nextTitle = W.text(nb, "GameFontNormal", nil, W.GOLD)
  p.nextTitle:SetPoint("TOPLEFT", 10, -8)
  p.nextTitle:SetPoint("TOPRIGHT", -10, -8)
  p.nextIcon = W.icon(nb, 30)
  p.nextIcon:SetPoint("TOPLEFT", p.nextTitle, "BOTTOMLEFT", 0, -6)
  p.nextName = W.text(nb, "GameFontHighlight", nil, W.TEXT)
  p.nextName:SetPoint("TOPLEFT", p.nextIcon, "TOPRIGHT", 8, 0)
  p.nextName:SetWidth(LEFT_W - 58)
  p.nextSub = W.text(nb, "GameFontHighlightSmall", nil, W.MUTED)
  p.nextSub:SetPoint("TOPLEFT", p.nextName, "BOTTOMLEFT", 0, -2)
  p.nextSub:SetPoint("TOPRIGHT", p.nextName, "BOTTOMRIGHT", 0, -2)
  p.then_ = W.text(nb, "GameFontHighlightSmall", nil, W.TEXT)
  p.then_:SetPoint("TOPLEFT", p.nextIcon, "BOTTOMLEFT", 0, -8)
  p.then_:SetWidth(LEFT_W - 20)
  p.then_.wbxCopy = "data"
  p.readback = W.text(p, "GameFontHighlightSmall", nil, W.TEXT)
  p.readback:SetPoint("TOPLEFT", nb, "BOTTOMLEFT", 0, -8)
  p.readback:SetWidth(LEFT_W)
  p.readback:SetJustifyV("TOP")
  p.source = W.text(p, "GameFontHighlightSmall", nil, W.MUTED)
  p.source:SetPoint("TOPLEFT", p.readback, "BOTTOMLEFT", 0, -8)
  p.source:SetWidth(LEFT_W)
  p.source.wbxCopy = "data" -- guide source + the licence credit (exact wording required)
  p.aheadText = W.text(p, "GameFontHighlightSmall", nil, { 0.85, 0.72, 1 })
  p.aheadText:SetPoint("TOPLEFT", p.readback, "BOTTOMLEFT", 0, -8)
  p.aheadText:SetWidth(LEFT_W)
  if p.aheadText.SetMaxLines then p.aheadText:SetMaxLines(3) end
  p.aheadText.wbxCopy = "data"
  p.source:ClearAllPoints()
  p.source:SetPoint("TOPLEFT", p.aheadText, "BOTTOMLEFT", 0, -8)
  p.prio = W.text(p, "GameFontHighlightSmall", nil, W.TEXT)
  p.prio:SetPoint("TOPLEFT", p.source, "BOTTOMLEFT", 0, -8)
  p.prio:SetWidth(LEFT_W)
  if p.prio.SetMaxLines then p.prio:SetMaxLines(8) end
  p.prio.wbxCopy = "data"

  local head = W.text(p, "GameFontNormal", nil, W.GOLD)
  head:SetPoint("TOPLEFT", LEFT_W + 16, -30)
  head:SetText("Point order")
  -- plan ahead: the points from now up to a chosen level (display only; you spend them in the game)
  p.ahead = W.dropdown(p, { width = 120,
    values = function()
      local v, L = {}, ns.Compat.playerLevel()
      local top = ns.Engine.maxLevel()
      for _, x in ipairs({ L + 1, L + 2, L + 5, L + 10 }) do if x <= top then v[#v + 1] = { x, "Plan to " .. x } end end
      if L < top then v[#v + 1] = { top, "Plan to " .. top } end
      return v
    end,
    get = function() return tab.planTo() end,
    set = function(v) ns.Core.cdb.planTo = v; ns.Core.changed() end })
  p.ahead:SetPoint("TOPRIGHT", p, "TOPRIGHT", -4, -26)
  W.ddTip(p.ahead, "Plan ahead", "Highlights your guide's points from now up to this level and sums them up. Display only: you spend the points in the game's talent window.")
  local sf, content = W.scroll(p, LIST_W, 340)
  sf:SetPoint("TOPLEFT", LEFT_W + 16, -50)
  p.list = content
  p.sf = sf
  p.pool = W.pool(content, function(parent)
    local r = CreateFrame("Frame", nil, parent)
    r:SetSize(LIST_W - 4, ROW_H)
    r.bg = r:CreateTexture(nil, "BACKGROUND")
    r.bg:SetAllPoints()
    r.lvl = W.text(r, "GameFontHighlightSmall")
    r.lvl:SetPoint("LEFT", 4, 0)
    r.lvl:SetWidth(44)
    r.icon = W.icon(r, 16)
    r.icon:SetPoint("LEFT", 50, 0)
    r.rank = W.text(r, "GameFontHighlightSmall", nil, W.MUTED, "RIGHT")
    r.rank:SetPoint("RIGHT", -4, 0)
    r.name = W.line(r, "GameFontHighlightSmall")
    r.name:SetPoint("LEFT", 72, 0)
    r.name:SetPoint("RIGHT", -40, 0)
    W.tooltip(r, function(GT) GT:AddLine(r.name:GetText() or "", 1, 0.82, 0) end)
    return r
  end)
end

local function cls() local _, m = ns.Core.me(); return m and m.cls end
tab.cls = cls
--- The guide or build this character uses (nil for a squad build).
function tab.current() local _, m = ns.Core.me(); if not m or (m.build and #m.build > 0) then return nil end return ns.Kit.guide(m.cls, m.guide) end
function tab.startRename(p)
  local g = tab.current()
  if not (g and g.user) then return end
  p.renBox:SetText(g.label); p.renBox:Show(); p.renBox:SetFocus(); UI.Refresh()
end
--- The plan as a Wowhead link in the copy box (or why there is none).
function tab.copyLink()
  local _, m = ns.Core.me()
  if not m then return end
  local order = ns.Kit.plan(m)
  local link = #order > 0 and ns.Wowhead.encode(m.cls, order, m.talented, true) or nil
  if link then ns.CopyBox.ShowCopy("Wowhead link", link)
  else ns.Core.print(#order == 0 and "This guide has no point order." or "This build has a talent Wowhead's calculator does not have, so it can't be a Wowhead link.") end
  return link
end

-- ------------------------------------------------------------------ the Import window
local CLASS_N = function(c) return ns.Data.classes[c] and ns.Data.classes[c].n or c end
--- The preview lines for a link: text, warnings (orange), result.
function tab.preview(link)
  if not link or link:match("^%s*$") then return "Paste a Wowhead talent link (" .. ns.Wowhead.gameName() .. ").", "", nil end
  local r = ns.Wowhead.import(link)
  if r.error then return "|cffff8a80" .. r.error .. "|r", "", nil end
  local E = ns.Engine
  local first, last = E.levelForPoint(0, r.talented), E.levelForPoint(r.points - 1, r.talented)
  local text = CLASS_N(r.cls) .. " · " .. r.split .. " · " .. r.points .. " points · " .. (r.hasOrder and "exact click order" or "order by WoWBoxer") ..
    " (levels " .. first .. "–" .. last .. ")"
  local warn = {}
  for _, w in ipairs(r.warnings) do warn[#warn + 1] = w end
  local _, m = ns.Core.me()
  if m and m.cls ~= r.cls then warn[#warn + 1] = "A " .. CLASS_N(r.cls) .. " build: Save as keeps it for your " .. CLASS_N(r.cls) .. " characters."
  elseif m and r.talented ~= (m.talented or 0) then warn[#warn + 1] = "The link uses Talented rank " .. r.talented .. "; this character has " .. (m.talented or 0) .. " (not changed)." end
  return text, table.concat(warn, "\n"), r
end
local function importFrame(p)
  if p.imp then return p.imp end
  local f = W.box(p, 0.11, 0.085, 0.05, 0.99)
  f:SetPoint("TOPLEFT", 20, -30)
  f:SetPoint("BOTTOMRIGHT", -20, 40)
  f:SetFrameLevel((p:GetFrameLevel() or 1) + 30)
  f:EnableMouse(true)
  f.wbxModal = true
  f.title = W.text(f, "GameFontNormalLarge", 15, W.GOLD)
  f.title:SetPoint("TOPLEFT", 16, -14)
  f.title:SetText("Import a talent build")
  f.title.wbxCopy = "label"
  f.close = W.button(f, "Close", 70, 22, function() f:Hide() end, "Closes this. Nothing is saved.")
  f.close:SetPoint("TOPRIGHT", -12, -10)
  local ll = W.text(f, "GameFontNormalSmall", nil, W.GOLD)
  ll:SetPoint("TOPLEFT", 16, -48)
  ll:SetText("Wowhead link")
  ll.wbxCopy = "label"
  f.link = W.frame("EditBox", f, "InputBoxTemplate")
  f.link:SetHeight(20)
  f.link:SetPoint("TOPLEFT", 22, -64)
  f.link:SetPoint("TOPRIGHT", -16, -64)
  f.link:SetAutoFocus(false)
  f.link:SetMaxLetters(ns.Wowhead.MAX_LINK + 20)
  f.link:SetScript("OnTextChanged", function() tab.refreshImport(p) end)
  f.link:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  W.tip(f.link, "Wowhead link", "Paste (Ctrl+V) a link from Wowhead's " .. ns.Wowhead.gameName() .. " talent calculator. WoWBoxer only reads it – nothing in it is run.")
  f.info = W.text(f, "GameFontHighlight", nil, W.TEXT)
  f.info:SetPoint("TOPLEFT", 16, -96)
  f.info:SetPoint("TOPRIGHT", -16, -96)
  f.info.wbxCopy = "data"
  f.warn = W.text(f, "GameFontHighlightSmall", nil, W.ORANGE)
  f.warn:SetPoint("TOPLEFT", f.info, "BOTTOMLEFT", 0, -6)
  f.warn:SetPoint("TOPRIGHT", f.info, "BOTTOMRIGHT", 0, -6)
  if f.warn.SetMaxLines then f.warn:SetMaxLines(5) end
  f.warn.wbxCopy = "data"
  local nl = W.text(f, "GameFontNormalSmall", nil, W.GOLD)
  nl:SetPoint("BOTTOMLEFT", 16, 50)
  nl:SetText("Name")
  nl.wbxCopy = "label"
  f.name = W.frame("EditBox", f, "InputBoxTemplate")
  f.name:SetSize(220, 20)
  f.name:SetAutoFocus(false)
  f.name:SetMaxLetters(40)
  f.name:SetPoint("LEFT", nl, "RIGHT", 12, 0)
  f.name:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  f.status = W.text(f, "GameFontHighlightSmall", nil, W.GREEN)
  f.status:SetPoint("BOTTOMLEFT", 16, 18)
  f.status:SetPoint("BOTTOMRIGHT", f, "BOTTOM", 0, 18)
  f.status.wbxCopy = "data"
  local function save(use)
    local _, _, r = tab.preview(f.link:GetText())
    if not r then return end
    local b, why = ns.Core.saveBuild(r, f.name:GetText(), use, f.link:GetText():match("^%s*(.-)%s*$"))
    local _, m = ns.Core.me()
    if not b then f.status:SetText("|cffff8a80" .. tostring(why) .. "|r"); return end
    if m and m.cls ~= r.cls then f.status:SetText("Saved for " .. CLASS_N(r.cls) .. " – pick it on a " .. CLASS_N(r.cls) .. ".")
    elseif use then f:Hide()
    else f.status:SetText("Saved: " .. b.label .. " – pick it in the Guide list.") end
  end
  f.use = W.button(f, "Save and use", 110, 24, function() save(true) end, "Saves the build and picks it for this character. Nothing changes in the game's talents.")
  f.use:SetPoint("BOTTOMRIGHT", -12, 12)
  f.save = W.button(f, "Save as", 80, 24, function() save(false) end, "Saves the build under the name above. It shows first in the Guide list under My builds.")
  f.save:SetPoint("RIGHT", f.use, "LEFT", -6, 0)
  f:Hide()
  p.imp = f
  return f
end
function tab.openImport(p)
  local f = importFrame(p)
  f.link:SetText(""); f.name:SetText(""); f.status:SetText(""); f.lastSplit = nil
  f:Show()
  tab.refreshImport(p)
  f.link:SetFocus()
end
function tab.refreshImport(p)
  local f = p.imp
  if not (f and f:IsShown()) then return end
  local text, warn, r = tab.preview(f.link:GetText())
  f.info:SetText(text); f.warn:SetText(warn)
  local _, m = ns.Core.me()
  f.save:SetEnabled(r ~= nil)
  f.use:SetEnabled(r ~= nil and m ~= nil and m.cls == r.cls)
  local def = r and ("Wowhead " .. r.split) or nil
  if def and (f.name:GetText() == "" or f.name:GetText() == f.lastSplit) then f.name:SetText(def) end
  f.lastSplit = def
end

local KIND_SHORT = { ["exact-order"] = "Exact order", ["final-derived"] = "Final build, order by WoWBoxer", priorities = "Priorities only",
  adaptation = "Adaptation" }
--- A guide's source and type in one tooltip text.
function tab.guideTip(g)
  local src = g.source or {}
  local parts = { (KIND_SHORT[g.kind] or g.kind or "?") .. "." }
  if g.stale then parts[1] = "|cffd9b36c" .. g.stale .. "|r " .. parts[1] end
  parts[#parts + 1] = "Source: " .. (src.site or "?") .. (src.author and (", " .. src.author) or "") .. (src.updated and (" (" .. src.updated .. ")") or "") .. "."
  if src.scope then parts[#parts + 1] = "Levels " .. src.scope .. "." end
  if src.url then parts[#parts + 1] = src.url end
  if g.note and g.note ~= "" then parts[#parts + 1] = g.note end
  return table.concat(parts, " ")
end
--- True when the talent trees in the data are this client's own (Forever on Forever, TBC on TBC; Era still has
--- Forever's trees), so talents spent in the game can be compared with the plan.
function tab.treesMatch()
  local g = ns.Data.game
  if g and (g.key == "tbc" or g.key == "era") then return ns.Compat.game() == g.key end
  return ns.Compat.isForever()
end
--- Talent guides of this game are not written yet (TBC, plan step 4): one plain line instead of an empty list.
function tab.comingText()
  local name = ns.Data.game and ns.Data.game.name or "this game"
  return "Talent guides for " .. name .. " are coming. Meanwhile import a Wowhead link (Import) or follow your own plan."
end
--- The talent data credit of this game. Forever: the live client's trees (11 Nov 2026); the seed's other data still
--- carries the Zephras CC BY 4.0 credit (docs/compliance.md).
function tab.creditText()
  local g = ns.Data.game
  if g and (g.key == "tbc" or g.key == "era") then return "Talent data: Blizzard client tables (build " .. tostring(ns.Data.meta.build) .. "). Names (c) Blizzard Entertainment." end
  return "Talent trees: Blizzard client tables (build " .. tostring(ns.Data.meta.build) .. "), checked against Wowhead. Other data: Zephras (zephras.com), CC BY 4.0, changed by WoWBoxer; The Forever Era"
end
--- The level "Plan ahead" looks to (default: 5 levels on, at most the max level).
function tab.planTo()
  local L = ns.Compat.playerLevel()
  local v = tonumber(ns.Core.cdb.planTo)
  if not v or v <= L then v = math.min(ns.Engine.maxLevel(), L + 5) end
  return v
end
--- {points, text} for the guide's points after level `from` up to level `to`.
function tab.aheadSummary(m, order, from, to)
  local E, T = ns.Engine, ns.Kit.tree(m.cls)
  local a, b = E.pointsAt(from, m.talented), E.pointsAt(to, m.talented)
  local counts, seen = {}, {}
  for i = a + 1, math.min(b, #order) do
    local k = order[i]
    if T.byKey[k] then if not counts[k] then seen[#seen + 1] = k end counts[k] = (counts[k] or 0) + 1 end
  end
  local parts = {}
  for _, k in ipairs(seen) do parts[#parts + 1] = T.byKey[k].n .. (counts[k] > 1 and (" x" .. counts[k]) or "") end
  local n = math.max(0, math.min(b, #order) - a)
  return n, n > 0 and ("By level " .. to .. ": " .. n .. (n == 1 and " point – " or " points – ") .. table.concat(parts, ", ")) or ""
end

function tab.refresh(p)
  local Core, K, E = ns.Core, ns.Kit, ns.Engine
  local _, m = Core.me()
  p.pool:reset()
  if not m then p.kind:SetText("Add this character to a squad first (Squad tab)."); p.nextTitle:SetText(""); p.nextName:SetText(""); p.nextSub:SetText(""); p.then_:SetText(""); p.source:SetText(""); p.prio:SetText(""); return end
  p.guide.Refresh()
  local T = K.tree(m.cls)
  local order, kind = K.plan(m)
  local g = K.guide(m.cls, m.guide)
  local level = ns.Compat.playerLevel()
  local warn = tab.treesMatch() and "" or "|cffd9b36c(WoW: Forever talents – this client differs)|r "
  if kind == "build" then p.kind:SetText(warn .. (m.buildName or "Your own build") .. " (" .. #order .. " points, from your squad)")
  elseif g and g.user and g.stale then p.kind:SetText(warn .. "|cffd9b36cYour build needs an update for the live talents|r (hover the Guide list for what changed)")
  elseif g and g.user then p.kind:SetText(warn .. "Your build · " .. (KIND_SHORT[g.kind] or g.kind))
  elseif not g and #K.dataGuidesOf(m.cls) == 0 then p.kind:SetText(tab.comingText())
  else p.kind:SetText(warn .. (g and (KIND[g.kind] or g.kind) or "No guide")) end
  local cur = tab.current()
  local mine = cur ~= nil and cur.user == true
  p.renBtn:SetShown(mine and not p.renBox:IsShown()); p.delBtn:SetShown(mine and not p.renBox:IsShown())
  p.guide:SetShown(not p.renBox:IsShown())
  tab.refreshImport(p)
  local have = E.pointsAt(level, m.talented)
  -- next point
  local nextIdx = have > 0 and have or 1
  local k = order[nextIdx]
  -- spec: "Next at level N" (the point for this level; before level 10 the first point)
  p.nextTitle:SetText(have > 0 and ("Next at level " .. E.levelForPoint(nextIdx - 1, m.talented) .. "  |cffa89a7e(" .. have .. " points by now)|r")
    or ("First point at level " .. E.firstPointLevel(m.talented)))
  if k and T.byKey[k] then
    local n = T.byKey[k]
    local rank = 0
    for i = 1, nextIdx do if order[i] == k then rank = rank + 1 end end
    W.setIcon(p.nextIcon, n.f or n.i)
    p.nextName:SetText(n.n)
    p.nextSub:SetText("Rank " .. rank .. " of " .. n.m .. " · " .. (T.trees[n.t + 1] and T.trees[n.t + 1].n or ""))
  else W.setIcon(p.nextIcon, nil); p.nextName:SetText(#order == 0 and "No point order" or "Build complete"); p.nextSub:SetText("") end
  local thenParts = {}
  for i = nextIdx + 1, math.min(#order, nextIdx + 3) do
    local n = T.byKey[order[i]]
    if n then thenParts[#thenParts + 1] = n.n .. " (" .. E.levelForPoint(i - 1, m.talented) .. ")" end
  end
  p.then_:SetText(#thenParts > 0 and ("Then: " .. table.concat(thenParts, ", ")) or "")
  local th = (p.nextTitle:GetStringHeight() or 14) + math.max(30, (p.nextName:GetStringHeight() or 14) + 2 + (p.nextSub:GetStringHeight() or 12))
    + (#thenParts > 0 and (8 + (p.then_:GetStringHeight() or 12)) or 0)
  p.nb:SetHeight(math.ceil(8 + th + 6 + 10))
  if g and kind == "guide" then
    local src = g.source or {}
    p.source:SetText("Source: " .. (src.site or "?") .. (src.author and (", " .. src.author) or "") .. (src.updated and (" (" .. src.updated .. ")") or "") ..
      "\n" .. tab.creditText())
  else p.source:SetText(tab.creditText()) end
  p.prio:SetText(g and g.kind == "priorities" and g.priorities and g.priorities:sub(1, 600) or "")
  p.readback:SetText(tab.readbackText(m, level))
  p.ahead.Refresh()
  local to = tab.planTo()
  local _, aheadText = tab.aheadSummary(m, order, level, to)
  p.aheadText:SetText(aheadText)
  local toIdx = E.pointsAt(to, m.talented)
  -- list
  local y, counts, current = 0, {}, nil
  for i, key in ipairs(order) do
    local n = T.byKey[key]
    if n then
      counts[key] = (counts[key] or 0) + 1
      local r = p.pool:get()
      r:SetPoint("TOPLEFT", 0, -y)
      local lvl = E.levelForPoint(i - 1, m.talented)
      r.lvl:SetText("Lv " .. lvl)
      W.setIcon(r.icon, n.f or n.i)
      r.name:SetText(n.n)
      r.rank:SetText(counts[key] .. "/" .. n.m)
      local past, now = i < nextIdx, i == nextIdx
      local planned = not past and not now and i <= toIdx
      if now then current = y end
      if planned then r.bg:SetColorTexture(0.6, 0.45, 1, 0.12)
      else r.bg:SetColorTexture(1, 0.82, 0, now and 0.18 or (i % 2 == 0 and 0.03 or 0)) end
      local c = past and W.MUTED or W.TEXT
      r.name:SetTextColor(c[1], c[2], c[3])
      local lc = now and W.GOLD or c
      r.lvl:SetTextColor(lc[1], lc[2], lc[3])
      y = y + ROW_H
    end
  end
  p.list:SetHeight(math.max(y, 10))
  if current and p.sf.SetVerticalScroll then pcall(p.sf.SetVerticalScroll, p.sf, math.max(0, current - 3 * ROW_H)) end
end

--- One or two lines comparing the talents spent in game with the plan (Forever only: other clients have other trees).
function tab.readbackText(m, level)
  local C = ns.Compat
  if not tab.treesMatch() then return "|cffa89a7eCompared on WoW: Forever only|r" end
  local ranks, src = C.talentRanks()
  if not ranks then return "|cffa89a7eCan't read talents here (" .. tostring(src) .. ")|r" end
  local st = ns.Kit.talentStatus(m, ranks, level)
  local parts = { "In game: " .. st.spent .. "/" .. st.available .. " points spent" }
  if #st.off > 0 then
    local n = {}
    for i, o in ipairs(st.off) do if i <= 2 then n[#n + 1] = o.name .. " " .. o.have .. "/" .. o.plan end end
    parts[#parts + 1] = "|cfff0b43cOff plan: " .. table.concat(n, ", ") .. (#st.off > 2 and ", …" or "") .. "|r"
  elseif st.spent > 0 then parts[#parts + 1] = "|cff8fbf6aOn the plan|r" end
  if st.next and st.spent < st.available then parts[#parts + 1] = "Take next: |cffffd100" .. st.next.name .. "|r (rank " .. st.next.rank .. ")" end
  return table.concat(parts, "\n")
end

UI.RegisterTab(tab)
