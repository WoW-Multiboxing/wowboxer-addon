--[[ WoWBoxer – layout audit (read-only). The first time the window opens in a session it visits every tab once and
  measures, with the game's real fonts: text cut off in a one-line label, button labels wider than their button, and
  elements that stick out of the window. The findings go to WoWBoxerDB.diag[char].layout (read after /reload with
  tools/read_log.py), so layout bugs can be fixed without screenshots. /wbx audit runs it again. Nothing is changed. ]]
local _, ns = ...
local UI = ns.UI
local AU = {}
ns.Audit = AU

AU.MAX = 60
local function num(v) return type(v) == "number" and v or nil end
local function call(obj, method, ...)
  local f = obj and obj[method]
  if type(f) ~= "function" then return nil end
  local ok, a, b = pcall(f, obj, ...)
  if ok then return a, b end
  return nil
end

--- Every value an API returns (GetRegions / GetChildren return many), or {}.
local function all(obj, method)
  local f = obj and obj[method]
  if type(f) ~= "function" then return {} end
  local res = { pcall(f, obj) }
  if not res[1] then return {} end
  table.remove(res, 1)
  return res
end

--- All font strings and frames below `root` (visible only).
local function walk(root, visit, depth)
  depth = depth or 0
  if depth > 12 or not call(root, "IsVisible") then return end
  visit(root, "frame")
  for _, r in ipairs(all(root, "GetRegions")) do
    if type(r) == "table" and call(r, "GetObjectType") == "FontString" and call(r, "IsVisible") then visit(r, "text") end
  end
  for _, k in ipairs(all(root, "GetChildren")) do if type(k) == "table" then walk(k, visit, depth + 1) end end
end

--- The box of obj as the player sees it: clipped to every scroll frame above it (bug sweep 9 Nov 2026: rows of the
--- talents point order list that were scrolled out of view were reported as "overlap" with the buttons above).
--- nil when it is scrolled out of view completely.
local function rect(obj)
  local l, r, b, t = num(call(obj, "GetLeft")), num(call(obj, "GetRight")), num(call(obj, "GetBottom")), num(call(obj, "GetTop"))
  if not (l and r and b and t) then return nil end
  local p = call(obj, "GetParent")
  local depth = 0
  while p and depth < 20 do
    if call(p, "GetObjectType") == "ScrollFrame" then
      local cl, cr, cb, ct = num(call(p, "GetLeft")), num(call(p, "GetRight")), num(call(p, "GetBottom")), num(call(p, "GetTop"))
      if cl and cr and cb and ct then
        l, r, b, t = math.max(l, cl), math.min(r, cr), math.max(b, cb), math.min(t, ct)
        if r - l <= 1.5 or t - b <= 1.5 then return nil end
      end
    end
    p = call(p, "GetParent"); depth = depth + 1
  end
  return { l, b, r, t }
end
--- True when obj is inside a scroll frame (its own box may lie outside the window: scrolled, not sticking out).
local function scrolled(obj)
  local p = call(obj, "GetParent")
  local depth = 0
  while p and depth < 20 do
    if call(p, "GetObjectType") == "ScrollFrame" then return true end
    p = call(p, "GetParent"); depth = depth + 1
  end
  return false
end
local function inter(a, b)
  return math.min(a[3], b[3]) - math.max(a[1], b[1]) > 1.5 and math.min(a[4], b[4]) - math.max(a[2], b[2]) > 1.5
end
local function inside(a, obj)
  local p = call(obj, "GetParent")
  while p do if p == a then return true end p = call(p, "GetParent") end
  return false
end
local function plain(txt) return (txt:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("\n", " ")) end

--- Problems on the tab currently shown: {{kind, text, need, have}}. kind: cut (text cut off without a tooltip),
--- button (label wider than the button), overlap (text over a button or another text), outside (sticks out).
function AU.scan(frame, tabKey)
  local out = {}
  local fl, fr, fb = num(call(frame, "GetLeft")), num(call(frame, "GetRight")), num(call(frame, "GetBottom"))
  local seen, texts, buttons, modals = {}, {}, {}, {}
  walk(frame, function(obj, kind)
    if seen[obj] or #out >= AU.MAX then return end
    seen[obj] = true
    if kind == "text" then
      local txt = call(obj, "GetText")
      if type(txt) ~= "string" or txt == "" then return end
      local w, sw = num(call(obj, "GetWidth")), num(call(obj, "GetStringWidth"))
      local wraps = call(obj, "CanWordWrap")
      local cut = (w and sw and w > 0 and wraps == false and sw > w + 2) or (wraps ~= false and call(obj, "IsTruncated") == true)
      if cut and not obj.wbxTrunc and rect(obj) then
        out[#out + 1] = { tab = tabKey, kind = "cut", text = plain(txt):sub(1, 50), need = math.floor(sw or 0), have = math.floor(w or 0) }
      end
      local r = rect(obj)
      if r then texts[#texts + 1] = { obj = obj, r = r, text = plain(txt):sub(1, 30) } end
    else
      if obj.wbxModal then local r = rect(obj); if r then modals[#modals + 1] = { obj = obj, r = r } end end
      local ot = call(obj, "GetObjectType")
      if ot == "Button" or ot == "CheckButton" then
        local r = rect(obj)
        if r then buttons[#buttons + 1] = { obj = obj, r = r } end
      end
      if ot == "Button" then
        local fs = call(obj, "GetFontString")
        local bw = num(call(obj, "GetWidth"))
        local sw = fs and num(call(fs, "GetStringWidth"))
        local txt = fs and call(fs, "GetText")
        if bw and sw and type(txt) == "string" and txt ~= "" and sw > bw - 6 then
          out[#out + 1] = { tab = tabKey, kind = "button", text = txt:sub(1, 40), need = math.floor(sw + 8), have = math.floor(bw) }
        end
      end
      local l, r, b = num(call(obj, "GetLeft")), num(call(obj, "GetRight")), num(call(obj, "GetBottom"))
      if obj ~= frame and fl and fr and fb and l and r and b and (l < fl - 2 or r > fr + 2 or b < fb - 2) and not scrolled(obj) then
        local name = call(obj, "GetName") or call(obj, "GetObjectType") or "?"
        out[#out + 1] = { tab = tabKey, kind = "outside", text = tostring(name), need = math.floor(math.max(fl - l, r - fr, fb - b)), have = 0 }
      end
    end
  end)
  local function covered(obj, r)
    for _, m in ipairs(modals) do if obj ~= m.obj and not inside(m.obj, obj) and inter(r, m.r) then return true end end
    return false
  end
  for _, t in ipairs(texts) do
    if not covered(t.obj, t.r) then
      for _, b in ipairs(buttons) do
        if #out < AU.MAX and not inside(b.obj, t.obj) and not covered(b.obj, b.r) and inter(t.r, b.r) then
          out[#out + 1] = { tab = tabKey, kind = "overlap", text = t.text .. " x button", need = 0, have = 0 }
        end
      end
    end
  end
  for i = 1, #texts do
    for j = i + 1, #texts do
      local a, b = texts[i], texts[j]
      if #out < AU.MAX and not covered(a.obj, a.r) and not covered(b.obj, b.r) and inter(a.r, b.r) then
        out[#out + 1] = { tab = tabKey, kind = "overlap", text = a.text .. " x " .. b.text, need = 0, have = 0 }
      end
    end
  end
  return out
end

--- Visit every tab once, collect problems, restore the tab the player had. Returns the list.
function AU.run()
  local f = UI.frame
  if not f or not f:IsShown() then return nil end
  local keep = UI.current
  local found = {}
  for _, tab in ipairs(UI.tabs) do
    UI.Select(tab.key)
    for _, p in ipairs(AU.scan(f, tab.key)) do if #found < AU.MAX then found[#found + 1] = p end end
  end
  UI.Select(keep)
  local Core = ns.Core
  local key = Core.charKey or "?"
  Core.db.diag[key] = Core.db.diag[key] or {}
  local scale = num(call(f, "GetEffectiveScale"))
  Core.db.diag[key].layout = { at = time and time() or 0, count = #found, items = found, scale = scale, game = ns.Compat.game() }
  Core.log("info", "layout audit: " .. #found .. " finding(s)")
  return found
end

--- Once per session, shortly after the window first opens.
function AU.onFirstOpen()
  if AU.done then return end
  AU.done = true
  local function go() local ok, err = pcall(AU.run); if not ok then ns.Core.log("error", "audit: " .. tostring(err)) end end
  if _G.C_Timer and _G.C_Timer.After then _G.C_Timer.After(0.5, go) else go() end
end

return AU
