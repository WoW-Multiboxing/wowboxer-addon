--[[ WoWBoxer – "fly to the bar" (docs/ui-spec-v2.md §5). When WoWBoxer places or updates keys after a click, each key's
  icon flies from the WoWBoxer window (or the screen centre) to its action button, then the button flashes – like the
  game's new-spell animation. Purely visual: it only reads where Blizzard's action buttons are (GetCenter, IsVisible)
  and draws its own textures on UIParent; it never touches, anchors to or clicks those buttons.
  Blizzard's IconIntroTracker is not reused: it is driven by the SPELL_PUSHED_TO_ACTIONBAR event and calling into it
  from addon code would taint the action bar code. No visible button (bar addons, hidden bar) = no flight. ]]
local _, ns = ...
local Fly = {}
ns.Fly = Fly

Fly.DURATION, Fly.STAGGER, Fly.SIZE = 0.7, 0.12, 36

function Fly.enabled()
  local st = ns.Core.db and ns.Core.db.settings
  return not (st and st.animations == false)
end

local BARS = {
  { 25, "MultiBarRightButton" }, { 37, "MultiBarLeftButton" }, { 49, "MultiBarBottomRightButton" }, { 61, "MultiBarBottomLeftButton" },
  { 145, "MultiBar5Button" }, { 157, "MultiBar6Button" }, { 169, "MultiBar7Button" },
}
local function visible(b) return type(b) == "table" and b.IsVisible and b:IsVisible() and b.GetCenter and b:GetCenter() ~= nil end

--- The visible Blizzard action button that shows action slot `slot` right now, or nil.
function Fly.buttonForSlot(slot)
  if type(slot) ~= "number" then return nil end
  local name, index
  if slot <= 24 then
    local page = (_G.GetActionBarPage and _G.GetActionBarPage()) or 1
    local bonus = ns.Compat.bonusBarOffset()
    if bonus == 0 and page == math.floor((slot - 1) / 12) + 1 then name, index = "ActionButton", (slot - 1) % 12 + 1 end
  elseif slot >= 73 and slot <= 120 then
    local bonus = ns.Compat.bonusBarOffset()
    if bonus > 0 and math.floor((slot - 73) / 12) + 1 == bonus then name, index = "ActionButton", (slot - 73) % 12 + 1 end
  else
    for _, b in ipairs(BARS) do if slot >= b[1] and slot < b[1] + 12 then name, index = b[2], slot - b[1] + 1 end end
  end
  if not name then return nil end
  local btn = _G[name .. index]
  if not visible(btn) then return nil end
  local action = rawget(btn, "action")
  if type(action) == "number" and action ~= slot then return nil end
  return btn
end

--- Centre of a frame in UIParent coordinates.
local function centre(f)
  local x, y = f:GetCenter()
  if not x then return nil end
  local s = (f:GetEffectiveScale() or 1) / (UIParent:GetEffectiveScale() or 1)
  return x * s, y * s
end
Fly.centre = centre

local pool, flashes = {}, {}
local function newIcon()
  local f = CreateFrame("Frame", nil, UIParent)
  f:SetFrameStrata("DIALOG")
  f:SetSize(Fly.SIZE, Fly.SIZE)
  f.tex = f:CreateTexture(nil, "ARTWORK")
  f.tex:SetAllPoints()
  if f.tex.SetTexCoord then f.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
  f.border = f:CreateTexture(nil, "OVERLAY")
  f.border:SetPoint("CENTER")
  f.border:SetSize(Fly.SIZE * 1.75, Fly.SIZE * 1.75)
  f.border:SetTexture("Interface\\Buttons\\UI-Quickslot2")
  local ag = f.CreateAnimationGroup and f:CreateAnimationGroup()
  if not ag then return nil end
  f.ag = ag
  f.move = ag:CreateAnimation("Translation")
  f.move:SetDuration(Fly.DURATION)
  if f.move.SetSmoothing then f.move:SetSmoothing("IN_OUT") end
  f.grow = ag:CreateAnimation("Scale")
  f.grow:SetDuration(Fly.DURATION * 0.35)
  if f.grow.SetScale then f.grow:SetScale(1.3, 1.3) end
  f.shrink = ag:CreateAnimation("Scale")
  f.shrink:SetStartDelay(Fly.DURATION * 0.35)
  f.shrink:SetDuration(Fly.DURATION * 0.65)
  if f.shrink.SetScale then f.shrink:SetScale(0.62, 0.62) end
  f.fade = ag:CreateAnimation("Alpha")
  f.fade:SetStartDelay(Fly.DURATION * 0.85)
  f.fade:SetDuration(Fly.DURATION * 0.15)
  if f.fade.SetFromAlpha then f.fade:SetFromAlpha(1); f.fade:SetToAlpha(0) end
  ag:SetScript("OnFinished", function()
    f:Hide()
    pool[#pool + 1] = f
    if f.onDone then f.onDone() end
  end)
  return f
end

--- A short additive glow over the button's position (own frame on UIParent, not a child of the button).
function Fly.flash(btn)
  local x, y = centre(btn)
  if not x then return end
  local f = table.remove(flashes)
  if not f then
    f = CreateFrame("Frame", nil, UIParent)
    f:SetFrameStrata("DIALOG")
    f.tex = f:CreateTexture(nil, "OVERLAY")
    f.tex:SetAllPoints()
    f.tex:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    if f.tex.SetBlendMode then f.tex:SetBlendMode("ADD") end
    f.tex:SetVertexColor(1, 0.9, 0.4, 1)
    local ag = f.CreateAnimationGroup and f:CreateAnimationGroup()
    if ag then
      local a = ag:CreateAnimation("Alpha")
      a:SetDuration(0.6)
      if a.SetFromAlpha then a:SetFromAlpha(1); a:SetToAlpha(0) end
      ag:SetScript("OnFinished", function() f:Hide(); flashes[#flashes + 1] = f end)
      f.ag = ag
    end
  end
  local w = (btn:GetWidth() or 36) * (btn:GetEffectiveScale() or 1) / (UIParent:GetEffectiveScale() or 1)
  f:SetSize(w * 1.9, w * 1.9)
  f:ClearAllPoints()
  f:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
  f:Show()
  Fly.flashes = (Fly.flashes or 0) + 1
  if f.ag then f.ag:Play() else f:Hide() end
end

--- One icon from (sx, sy) to the button.
local function launch(icon, sx, sy, btn)
  local tx, ty = centre(btn)
  if not tx then return false end
  local f = table.remove(pool) or newIcon()
  if not f then return false end
  ns.Widgets.setIcon(f.tex, icon)
  f:ClearAllPoints()
  f:SetPoint("CENTER", UIParent, "BOTTOMLEFT", sx, sy)
  f:SetAlpha(1)
  f.move:SetOffset(tx - sx, ty - sy)
  f.onDone = function() Fly.flash(btn) end
  f:Show()
  f.ag:Play()
  Fly.flights = (Fly.flights or 0) + 1
  return true
end

--- Fly every key in `list` ({icon, slot, from=frame?}) to its button, one after the other. Returns how many fly.
function Fly.play(list)
  if not Fly.enabled() or type(list) ~= "table" then return 0 end
  local n = 0
  for _, it in ipairs(list) do
    local btn = Fly.buttonForSlot(it.slot)
    if btn then
      local sx, sy
      if it.from and it.from.IsVisible and it.from:IsVisible() then sx, sy = centre(it.from) end
      if not sx and ns.UI.frame and ns.UI.frame:IsVisible() then sx, sy = centre(ns.UI.frame) end
      if not sx then sx, sy = (UIParent:GetWidth() or 0) / 2, (UIParent:GetHeight() or 0) / 2 end
      local delay = n * Fly.STAGGER
      n = n + 1
      local icon = it.icon
      if delay > 0 and _G.C_Timer and _G.C_Timer.After then _G.C_Timer.After(delay, function() launch(icon, sx, sy, btn) end)
      else launch(icon, sx, sy, btn) end
    end
  end
  return n
end

return Fly
