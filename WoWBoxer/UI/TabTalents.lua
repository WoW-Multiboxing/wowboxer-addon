--[[ WoWBoxer – Talents tab: the character's guide (picked from a list that shows each guide's source and type) or
  own build, what to take at this level, "plan ahead" to a chosen level, and the whole point order by level. Forever talent data; on other clients it is shown with a warning. ]]
local _, ns = ...
local UI, W = ns.UI, ns.Widgets
local tab = { key = "talents", label = "Talents", icon = "Ability_Marksmanship", tip = "The talent order of your guide and the next point to take." }
local ROW_H = 20
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
      for _, g in ipairs(ns.Kit.guidesOf(m.cls)) do v[#v + 1] = { g.id, g.label .. (g.default and " *" or ""), tab.guideTip(g) } end
      return v
    end,
    get = function() local _, m = ns.Core.me(); return m and m.guide end,
    set = function(v) local _, m = ns.Core.me(); if m then m.guide = v; ns.Core.changed() end end })
  p.guide:SetPoint("LEFT", lg, "RIGHT", 6, 0)
  W.ddTip(p.guide, "Guide", "The talent guide WoWBoxer follows for this character. * = recommended for your role. Each guide shows its source and type when you hover it in the list.")
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
      for _, x in ipairs({ L + 1, L + 2, L + 5, L + 10 }) do if x <= 60 then v[#v + 1] = { x, "Plan to " .. x } end end
      if L < 60 then v[#v + 1] = { 60, "Plan to 60" } end
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

local KIND_SHORT = { ["exact-order"] = "Exact order", ["final-derived"] = "Final build, order by WoWBoxer", priorities = "Priorities only",
  adaptation = "Adaptation" }
--- A guide's source and type in one tooltip text.
function tab.guideTip(g)
  local src = g.source or {}
  local parts = { (KIND_SHORT[g.kind] or g.kind or "?") .. "." }
  parts[#parts + 1] = "Source: " .. (src.site or "?") .. (src.author and (", " .. src.author) or "") .. (src.updated and (" (" .. src.updated .. ")") or "") .. "."
  if src.scope then parts[#parts + 1] = "Levels " .. src.scope .. "." end
  if g.note and g.note ~= "" then parts[#parts + 1] = g.note end
  return table.concat(parts, " ")
end
--- The level "Plan ahead" looks to (default: 5 levels on, at most 60).
function tab.planTo()
  local L = ns.Compat.playerLevel()
  local v = tonumber(ns.Core.cdb.planTo)
  if not v or v <= L then v = math.min(60, L + 5) end
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
  local warn = ns.Compat.isForever() and "" or "|cffd9b36c(WoW: Forever talents – this client differs)|r "
  if kind == "build" then p.kind:SetText(warn .. "Your own build (" .. #order .. " points)")
  else p.kind:SetText(warn .. (g and (KIND[g.kind] or g.kind) or "No guide")) end
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
      "\nTalent data: Zephras (zephras.com), CC BY 4.0, changed by WoWBoxer; The Forever Era")
  else p.source:SetText("Talent data: Zephras (zephras.com), CC BY 4.0, changed by WoWBoxer; The Forever Era") end
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
  if not C.isForever() then return "|cffa89a7eCompared on WoW: Forever only|r" end
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
