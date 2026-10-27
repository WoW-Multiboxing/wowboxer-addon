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

--- Problems on the tab currently shown: {{kind, text, need, have}}
function AU.scan(frame, tabKey)
  local out = {}
  local fl, fr, fb = num(call(frame, "GetLeft")), num(call(frame, "GetRight")), num(call(frame, "GetBottom"))
  local seen = {}
  walk(frame, function(obj, kind)
    if seen[obj] or #out >= AU.MAX then return end
    seen[obj] = true
    if kind == "text" then
      local txt = call(obj, "GetText")
      if type(txt) ~= "string" or txt == "" then return end
      local w, sw = num(call(obj, "GetWidth")), num(call(obj, "GetStringWidth"))
      local wraps = call(obj, "CanWordWrap")
      if w and sw and w > 0 and wraps == false and sw > w + 2 then
        out[#out + 1] = { tab = tabKey, kind = "cut", text = txt:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):sub(1, 50), need = math.floor(sw), have = math.floor(w) }
      end
    else
      if call(obj, "GetObjectType") == "Button" then
        local fs = call(obj, "GetFontString")
        local bw = num(call(obj, "GetWidth"))
        local sw = fs and num(call(fs, "GetStringWidth"))
        local txt = fs and call(fs, "GetText")
        if bw and sw and type(txt) == "string" and txt ~= "" and sw > bw - 6 then
          out[#out + 1] = { tab = tabKey, kind = "button", text = txt:sub(1, 40), need = math.floor(sw + 8), have = math.floor(bw) }
        end
      end
      local l, r, b = num(call(obj, "GetLeft")), num(call(obj, "GetRight")), num(call(obj, "GetBottom"))
      if obj ~= frame and fl and fr and fb and l and r and b and (l < fl - 2 or r > fr + 2 or b < fb - 2) then
        local name = call(obj, "GetName") or call(obj, "GetObjectType") or "?"
        out[#out + 1] = { tab = tabKey, kind = "outside", text = tostring(name), need = math.floor(math.max(fl - l, r - fr, fb - b)), have = 0 }
      end
    end
  end)
  return out
end

--- Visit every tab once, collect problems, restore the tab the player had. Returns the list.
function AU.run()
  local f = UI.frame
  if not f or not f:IsShown() then return nil end
  local keep = UI.current
  local all = {}
  for _, tab in ipairs(UI.tabs) do
    UI.Select(tab.key)
    for _, p in ipairs(AU.scan(f, tab.key)) do if #all < AU.MAX then all[#all + 1] = p end end
  end
  UI.Select(keep)
  local Core = ns.Core
  local key = Core.charKey or "?"
  Core.db.diag[key] = Core.db.diag[key] or {}
  local scale = num(call(f, "GetEffectiveScale"))
  Core.db.diag[key].layout = { at = time and time() or 0, count = #all, items = all, scale = scale, game = ns.Compat.game() }
  Core.log("info", "layout audit: " .. #all .. " finding(s)")
  return all
end

--- Once per session, shortly after the window first opens.
function AU.onFirstOpen()
  if AU.done then return end
  AU.done = true
  local function go() local ok, err = pcall(AU.run); if not ok then ns.Core.log("error", "audit: " .. tostring(err)) end end
  if _G.C_Timer and _G.C_Timer.After then _G.C_Timer.After(0.5, go) else go() end
end

return AU
