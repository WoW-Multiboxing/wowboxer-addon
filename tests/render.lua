-- Dump every page of the simulated window as draw lists for tools/render.py (docs/ui-redesign.md: compare with the
-- mockup without the game). Run: python tools/lua.py tests/render.lua <outdir> [era]
-- One JSON file per shot: {name, screen = {w, h}, items = [{k = "tex"|"text", rect, ...}]} in draw order.
local dir = (arg[0]:match("^(.*)/[^/]+$") or ".")
local H = dofile(dir .. "/harness.lua")
local Mock = dofile(dir .. "/wowmock.lua")
local out = arg[1] or "."
local era = arg[2] == "era"

local function json(v)
  local t = type(v)
  if t == "nil" then return "null" end
  if t == "boolean" or t == "number" then return tostring(v) end
  if t == "string" then return '"' .. v:gsub('[%c"\\]', function(c) return string.format("\\u%04x", c:byte()) end) .. '"' end
  local out2 = {}
  if #v > 0 or next(v) == nil then
    for _, x in ipairs(v) do out2[#out2 + 1] = json(x) end
    return "[" .. table.concat(out2, ",") .. "]"
  end
  for k, x in pairs(v) do out2[#out2 + 1] = json(tostring(k)) .. ":" .. json(x) end
  return "{" .. table.concat(out2, ",") .. "}"
end

local STRATA = { BACKGROUND = 1, LOW = 2, MEDIUM = 3, HIGH = 4, DIALOG = 5, FULLSCREEN = 6, FULLSCREEN_DIALOG = 7, TOOLTIP = 8 }
local LAYER = { BACKGROUND = 1, BORDER = 2, ARTWORK = 3, OVERLAY = 4, HIGHLIGHT = 5 }

local W = Mock.new(H, { name = "Dorin", class = "PALADIN", race = "Scourge", level = 24, toc = era and 11509 or nil,
  spellbookStyle = era and "classic" or nil, screen = { w = 940, h = 600 } })
local ns = H.loadAddon({ env = W.env })
W.fire("ADDON_LOADED", "WoWBoxer"); W.fire("PLAYER_LOGIN")
for _, s in ipairs(ns.Data.spells.paladin) do if s.level <= 24 then W.known[s.name] = true end end
W.env.RAID_CLASS_COLORS = { PALADIN = { r = 0.96, g = 0.55, b = 0.73 }, PRIEST = { r = 1, g = 1, b = 1 }, WARLOCK = { r = 0.53, g = 0.53, b = 0.93 } }
local UI, Core = ns.UI, ns.Core
Core.ensureMe()
local s = Core.me()
for _, x in ipairs({ { "Anna", "priest" }, { "Warlocker", "warlock" } }) do
  table.insert(s.members, ns.State.newMember({ name = x[1], cls = x[2], race = "undead", unit = "party1", level = 24 }))
end

local function dump(name, roots)
  local items = {}
  local inRoot = {}
  for _, f in ipairs(W.frames) do
    local p, ok = f, false
    while p do for _, r in ipairs(roots) do if p == r then ok = true end end p = p._parent end
    if ok and f:IsVisible() and (f._kind == "Texture" or f._kind == "FontString") and f._layer ~= "HIGHLIGHT" then
      local r = W.rect(f)
      if r and r[3] > r[1] and r[4] > r[2] then
        local owner = f._parent
        local clip
        local q = owner
        while q do if q._kind == "ScrollFrame" then clip = W.rect(q); break end q = q._parent end
        local it = { rect = r, clip = clip, alpha = f._alpha or 1,
          order = { STRATA[owner:GetFrameStrata()] or 3, owner:GetFrameLevel(), LAYER[f._layer or "ARTWORK"] or 3, f._sub or 0, #items } }
        if f._kind == "Texture" then
          it.k, it.color, it.file, it.tint, it.coords = "tex", f._color, type(f._file) == "number" and ("id:" .. f._file) or f._file, f._tint, f._coords
        else
          if f._text and f._text ~= "" then
            it.k, it.text, it.size, it.font, it.color = "text", f._text, f._fontSize or 12, f._fontFile or "game", f._textColor
            it.justify, it.wrap, it.justifyV = f._justifyH or "CENTER", f._wrap ~= false, f._justifyV or "MIDDLE"
            -- a one-line text with a fixed width is cut with "…" in the game (W.line)
            it.trunc = rawget(f, "wbxTrunc") and (f._wSet or #(f._points or {}) > 1) or nil
          end
        end
        if it.k then items[#items + 1] = it end
      end
    elseif ok and f:IsVisible() and (f._kind == "Button" or f._kind == "CheckButton") and f._text and f._text ~= "" then
      -- a button's own label (Button:SetText): drawn centred in its font object
      local r, o = W.rect(f), f._fontObject
      if r then
        items[#items + 1] = { k = "text", rect = r, alpha = 1, text = f._text, size = o and o._fontSize or 12,
          font = o and o._fontFile or "game", color = o and o._textColor or { 1, 0.82, 0, 1 }, justify = "CENTER", wrap = false,
          order = { STRATA[f:GetFrameStrata()] or 3, f:GetFrameLevel(), 4, 7, #items } }
      end
    end
  end
  table.sort(items, function(a, b)
    for i = 1, 5 do if a.order[i] ~= b.order[i] then return a.order[i] < b.order[i] end end
    return false
  end)
  local fh = assert(io.open(out .. "/" .. name .. ".json", "w"))
  fh:write(json({ name = name, screen = { w = W.screen.w, h = W.screen.h }, items = items }))
  fh:close()
  print("dumped " .. name .. " (" .. #items .. " items)")
end

Core.cdb.guide = "done"
UI.Open("keys")
for _, t in ipairs(UI.tabs) do UI.Select(t.key); dump("page-" .. t.key, { UI.frame }) end
UI.Select("keys")
local A = ns.Advanced
A.confirm(); dump("dialog-advanced", { UI.frame }); A.confirmFrame:Hide()
A.openReset(); dump("dialog-reset", { UI.frame }); A.rf:Hide()
local kp = UI.panels.keys
for _, b in ipairs(kp.cells or {}) do
  if b:IsShown() and b.cell and b.cell.name then A.openTargeting(kp, b.cell.name, b.cell.label); dump("dialog-macro-editor", { UI.frame }); if A.ef then A.ef:Hide() end break end
end
