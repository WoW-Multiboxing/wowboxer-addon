--[[ WoWBoxer – small team panel (display only): one line per squad character with mana and problems from
  ns.Team ("not following", "other target", "low mana", "bags full", "away", "no signal") and each character's gold
  and free bag slots. Shown while in a group with a squad of 2+
  characters; movable (position saved); /wbx team on|off. It has no buttons that act on other characters. ]]
local _, ns = ...
local W = ns.Widgets
local TF = {}
ns.TeamFrame = TF

local ROW_H = 16
TF.WIDTH = 300
local COLORS = { warn = W.ORANGE, bad = W.RED, muted = W.MUTED }

local function settings() return ns.Core.db and ns.Core.db.settings or {} end

function TF.Build()
  if TF.frame then return TF.frame end
  local f = W.box(UIParent, 0.07, 0.055, 0.035, 0.85)
  f:SetSize(TF.WIDTH, 30)
  f:SetFrameStrata("MEDIUM")
  f:SetClampedToScreen(true)
  f:EnableMouse(true)
  f:SetMovable(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function(self) self:StartMoving() end)
  f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, rel, x, y = self:GetPoint()
    if point then settings().teamPos = { point, rel or point, math.floor((x or 0) + 0.5), math.floor((y or 0) + 0.5) } end
  end)
  local p = settings().teamPos
  if type(p) == "table" and type(p[1]) == "string" then f:SetPoint(p[1], UIParent, p[2], tonumber(p[3]) or 0, tonumber(p[4]) or 0)
  else f:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -200, -220) end
  f.title = W.text(f, "GameFontNormalSmall", nil, W.GOLD)
  f.title:SetPoint("TOPLEFT", 8, -6)
  f.title:SetText("WoWBoxer team")
  W.tooltip(f, function(GT)
    GT:AddLine("WoWBoxer team", 1, 0.82, 0)
    GT:AddLine("What your other clients report: mana, gold and free bag slots, and problems. Display only: it never acts for you. Drag to move; /wbx team off hides it.", 1, 1, 1, true)
  end)
  f.rows = {}
  f:Hide()
  TF.frame = f
  return f
end

local function row(f, i)
  local r = f.rows[i]
  if r then return r end
  r = CreateFrame("Frame", nil, f)
  r:SetSize(TF.WIDTH - 16, ROW_H)
  r:SetPoint("TOPLEFT", 8, -22 - (i - 1) * ROW_H)
  r.name = W.text(r, "GameFontHighlightSmall")
  r.name:SetPoint("LEFT", 0, 0)
  r.name:SetWidth(80)
  if r.name.SetWordWrap then r.name:SetWordWrap(false) end
  r.mana = W.text(r, "GameFontHighlightSmall", nil, W.BLUE, "RIGHT")
  r.mana:SetPoint("LEFT", 80, 0)
  r.mana:SetWidth(34)
  r.bags = W.text(r, "GameFontHighlightSmall", nil, W.TEXT, "RIGHT")
  r.bags:SetPoint("LEFT", 116, 0)
  r.bags:SetWidth(66)
  r.flags = W.text(r, "GameFontHighlightSmall", nil, W.MUTED)
  r.flags:SetPoint("LEFT", 188, 0)
  r.flags:SetWidth(96)
  if r.flags.SetWordWrap then r.flags:SetWordWrap(false) end
  f.rows[i] = r
  return r
end

--- "123g · 8" = gold and free bag slots (empty when unknown).
function TF.bagsText(x)
  if not x then return "" end
  local g = "|cffffd100" .. (x.gold or 0) .. "g|r"
  if (x.free or -1) < 0 then return g end
  return g .. " · " .. x.free
end

function TF.Refresh()
  local TM = ns.Team
  if not TM or not ns.Core.db then return end
  local show = TM.active() and settings().teamFrame ~= false
  if not show then if TF.frame then TF.frame:Hide() end return end
  local f = TF.Build()
  local rows = TM.rows()
  for i, x in ipairs(rows) do
    local r = row(f, i)
    r:Show()
    r.name:SetText(W.hex(W.classColor(x.cls)) .. x.name .. "|r" .. (x.leader and " |cffffd100*|r" or ""))
    r.mana:SetText(x.st and x.st.mana >= 0 and (x.st.mana .. "%") or "")
    r.bags:SetText(TF.bagsText(x.extra))
    local parts = {}
    for _, fl in ipairs(x.flags) do parts[#parts + 1] = W.hex(COLORS[fl[2]] or W.TEXT) .. fl[1] .. "|r" end
    r.flags:SetText(#parts > 0 and table.concat(parts, ", ") or "|cff8fbf6aok|r")
  end
  for i = #rows + 1, #f.rows do f.rows[i]:Hide() end
  f:SetHeight(28 + #rows * ROW_H)
  f:Show()
end

function TF.SetShown(on)
  settings().teamFrame = on and true or false
  if not on and TF.frame then TF.frame:Hide() end
  TF.Refresh()
end

return TF
