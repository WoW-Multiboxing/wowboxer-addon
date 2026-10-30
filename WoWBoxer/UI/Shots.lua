--[[ WoWBoxer – screenshots of every page for the website, CurseForge and the redesign checks (docs/ui-redesign.md §4).
  /wbx shots (typed by the player) opens the window and visits each page and dialog in turn; on each it calls the
  game's own Screenshot() and notes the window's place on the screen in WoWBoxerDB.shots, so tools/screens.py can
  crop the files in <client>\Screenshots into docs/screens/. Read-only: it only switches pages and opens dialogs that
  write nothing until clicked; they are closed again. Out of combat only. ]]
local _, ns = ...
local SH = {}
ns.Shots = SH

local UI = ns.UI
local function Core() return ns.Core end

--- {name, show(), hide()} in the order they are taken.
local function plan()
  local A = ns.Advanced
  local list = {}
  local order = {}
  for i, t in ipairs(UI.tabs) do order[i] = t end
  table.sort(order, function(x, y) return (UI.ORDER[x.key] or 99) < (UI.ORDER[y.key] or 99) end)
  for _, t in ipairs(order) do list[#list + 1] = { "page-" .. t.key, function() UI.Select(t.key) end } end
  if A then
    list[#list + 1] = { "dialog-macro-editor", function()
      UI.Select("keys")
      local kp = UI.panels.keys
      for _, b in ipairs(kp.cells or {}) do
        if b:IsShown() and b.cell and b.cell.name then A.openTargeting(kp, b.cell.name, b.cell.label); return end
      end
    end, function() if A.ef then A.ef:Hide() end end }
    list[#list + 1] = { "dialog-reset", function() A.openReset() end, function() if A.rf then A.rf:Hide() end end }
    -- both states of the Advanced confirm (§2: off vs on); the tick changes nothing until "Turn on Advanced"
    list[#list + 1] = { "dialog-advanced-off", function() if not A.on() then A.confirm() end end }
    list[#list + 1] = { "dialog-advanced-on", function() local c = A.confirmFrame; if c and c:IsShown() then c.tick:Click() end end,
      function() if A.confirmFrame then A.confirmFrame:Hide() end end }
  end
  -- hover states (§2): a rail row and a dropdown item, drawn by our own enter handlers (the tooltip shows too)
  local function enter(f) local fn = f and f:GetScript("OnEnter"); if fn then fn(f) end end
  local function leave(f) local fn = f and f:GetScript("OnLeave"); if fn then fn(f) end end
  list[#list + 1] = { "hover-nav", function() UI.Select("keys"); enter(UI.tabButtons.spells) end, function() leave(UI.tabButtons.spells) end }
  list[#list + 1] = { "hover-dropdown", function()
    UI.Select("keys")
    local dd = UI.panels.keys.role
    if dd and dd.open then dd.open() end
    local L = ns.Widgets.listFrame
    if L and L.rows[2] then enter(L.rows[2]) end
  end, function() local L = ns.Widgets.listFrame; if L then if L.rows[2] then leave(L.rows[2]) end L:Hide() end end }
  return list
end

--- The window's box in screen pixels (top-left origin) and the screen size, for cropping.
local function box()
  local f = UI.frame
  local s = f:GetEffectiveScale() or 1
  local l, r, b, t = f:GetLeft(), f:GetRight(), f:GetBottom(), f:GetTop()
  local pw, ph
  if _G.GetPhysicalScreenSize then pw, ph = _G.GetPhysicalScreenSize() end
  local uh = 768 -- the game's virtual screen height (UI units at effective scale 1)
  local k = ph and (ph / uh) or 1
  return { l = (l or 0) * s * k, r = (r or 0) * s * k, top = ph and (ph - (t or 0) * s * k) or 0, bottom = ph and (ph - (b or 0) * s * k) or 0,
    w = pw, h = ph }
end

function SH.run()
  if not _G.Screenshot or not (_G.C_Timer and _G.C_Timer.After) then Core().print("Screenshots are not available on this client."); return end
  if _G.InCombatLockdown and _G.InCombatLockdown() then Core().print("Not in combat – try again after the fight."); return end
  UI.Open("keys")
  local db = Core().db
  local list = plan()
  local was = UI.current
  db.shots = { at = time(), client = ns.Compat.game(), char = Core().charKey, list = {} }
  local i = 0
  local function step()
    local prev = list[i]
    if prev and prev[3] then pcall(prev[3]) end
    i = i + 1
    local it = list[i]
    if not it or (_G.InCombatLockdown and _G.InCombatLockdown()) then
      UI.Select(was)
      Core().print(#db.shots.list .. " screenshots taken. /reload, then tell Claude \"shots done\".")
      Core().log("info", "shots: " .. #db.shots.list)
      return
    end
    pcall(it[2])
    _G.C_Timer.After(0.6, function()
      local rec = box()
      rec.name, rec.at = it[1], time()
      local ok = pcall(_G.Screenshot)
      if ok then db.shots.list[#db.shots.list + 1] = rec end
      _G.C_Timer.After(1.2, step)
    end)
  end
  Core().print("Taking " .. #list .. " screenshots of WoWBoxer – please wait about " .. math.ceil(#list * 1.8) .. " seconds.")
  step()
end
