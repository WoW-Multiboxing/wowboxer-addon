--[[ Layout checker for the simulated client (tests/wowmock.lua computes every frame's box from its anchors).
  Layout.check(W, roots) -> list of problems (strings):
  - a visible text overlaps a button or another text (not its own button/row),
  - a text needs more lines than its box has (cut off) or runs outside its window,
  - a button's label is wider than the button,
  - two buttons overlap, a window leaves the screen.
  Boxes inside a scroll frame are clipped to it (the client clips them too). ]]
local Layout = {}

local TOL = 1.5

local function plain(W, t) return W.plain(t):gsub("^%s+", ""):gsub("%s+$", "") end
local function isButton(f) return f._kind == "Button" or f._kind == "CheckButton" end
local function ancestorOf(a, f) local p = f._parent; while p do if p == a then return true end p = p._parent end return false end
local function inter(a, b)
  local w = math.min(a[3], b[3]) - math.max(a[1], b[1])
  local h = math.min(a[4], b[4]) - math.max(a[2], b[2])
  return w > TOL and h > TOL
end
local function clip(W, f, r)
  local p = f._parent
  while p do
    if p._kind == "ScrollFrame" then
      local c = W.rect(p)
      if c then
        r = { math.max(r[1], c[1]), math.max(r[2], c[2]), math.min(r[3], c[3]), math.min(r[4], c[4]) }
        if r[3] - r[1] <= TOL or r[4] - r[2] <= TOL then return nil end
      end
    end
    p = p._parent
  end
  return r
end
local function fmt(r) return string.format("[%d,%d %dx%d]", r[1], r[2], r[3] - r[1], r[4] - r[2]) end
local function label(W, f)
  if f._kind == "FontString" then return '"' .. plain(W, f._text):sub(1, 40) .. '"' end
  return f._kind .. (f._text and (' "' .. plain(W, f._text):sub(1, 30) .. '"') or "") .. (f._name and (" " .. f._name) or "")
end

--- Visible descendants of root (including root).
local function members(W, root)
  local out = {}
  for _, f in ipairs(W.frames) do
    if (f == root or ancestorOf(root, f)) and f:IsVisible() then out[#out + 1] = f end
  end
  return out
end

function Layout.check(W, roots, opts)
  opts = opts or {}
  local problems, seen = {}, {}
  local function add(msg) if not seen[msg] then seen[msg] = true; problems[#problems + 1] = msg end end
  local screen = { 0, 0, W.screen.w, W.screen.h }
  for _, root in ipairs(roots) do
    if root:IsVisible() then
      local rr = W.rect(root)
      if not rr then add("window not placed: " .. label(W, root))
      else
        if rr[1] < -TOL or rr[2] < -TOL or rr[3] > screen[3] + TOL or rr[4] > screen[4] + TOL then
          add("window leaves the screen " .. fmt(rr) .. " on " .. screen[3] .. "x" .. screen[4] .. ": " .. label(W, root))
        end
        local texts, buttons = {}, {}
        local all = members(W, root)
        -- an opaque overlay (fs.wbxModal: key capture, key editor) hides what lies under it
        local modals = {}
        for _, f in ipairs(all) do if rawget(f, "wbxModal") then local r = W.rect(f); if r then modals[#modals + 1] = { f = f, r = r } end end end
        local function covered(f, r)
          for _, m in ipairs(modals) do if f ~= m.f and not ancestorOf(m.f, f) and inter(r, m.r) then return true end end
          return false
        end
        for _, f in ipairs(all) do
          local r = W.rect(f)
          if r and covered(f, r) then r = nil end
          if r then
            if f._kind == "FontString" and plain(W, f._text) ~= "" then
              local k = W.factor(f)
              local size = (f._fontSize or 12)
              local width = (r[3] - r[1]) / k
              local need = W.textLines(f._text, size, f._wrap ~= false and width or nil, f._ratio)
              local room = math.floor(((r[4] - r[2]) / k + 0.5) / (size + 2) + 0.01)
              if f._wrap ~= false and need > room and (not f._maxLines or f._maxLines == 0 or f._maxLines > room) then
                add("text cut off (" .. need .. " lines, room for " .. room .. "): " .. label(W, f))
              end
              if f._wrap == false and not rawget(f, "wbxTrunc") and W.textWidth(f._text, size, f._ratio) > width + TOL then
                -- single line wider than its box: the client cuts it with "...". Allowed only when marked (fs.wbxTrunc = full text in a tooltip).
                add("text truncated without a tooltip: " .. label(W, f))
              end
              local c = clip(W, f, r)
              if c then
                if r[1] < rr[1] - TOL or r[3] > rr[3] + TOL or r[2] < rr[2] - TOL or r[4] > rr[4] + TOL then
                  add("text runs outside its window " .. fmt(r) .. ": " .. label(W, f))
                end
                texts[#texts + 1] = { f = f, r = c }
              end
            elseif isButton(f) and not f._noHit then
              local c = clip(W, f, r)
              if c then buttons[#buttons + 1] = { f = f, r = c } end
              if f._kind == "Button" and f._text and plain(W, f._text) ~= "" then
                local o = f._fontObject
                local tw = W.textWidth(f._text, o and o._fontSize or 12, o and o._ratio) * W.factor(f)
                if tw + 8 > r[3] - r[1] + TOL then add(string.format("button label wider than the button (%d > %d): %s", tw + 8, r[3] - r[1], label(W, f))) end
              end
            end
          end
        end
        for _, t in ipairs(texts) do
          for _, b in ipairs(buttons) do
            if not ancestorOf(b.f, t.f) and inter(t.r, b.r) then add("text overlaps a button: " .. label(W, t.f) .. " " .. fmt(t.r) .. " x " .. label(W, b.f) .. " " .. fmt(b.r)) end
          end
        end
        for i = 1, #texts do
          for j = i + 1, #texts do
            local a, b = texts[i], texts[j]
            if inter(a.r, b.r) then add("texts overlap: " .. label(W, a.f) .. " " .. fmt(a.r) .. " x " .. label(W, b.f) .. " " .. fmt(b.r)) end
          end
        end
        for i = 1, #buttons do
          for j = i + 1, #buttons do
            local a, b = buttons[i], buttons[j]
            if not ancestorOf(a.f, b.f) and not ancestorOf(b.f, a.f) and inter(a.r, b.r) then
              add("buttons overlap: " .. label(W, a.f) .. " " .. fmt(a.r) .. " x " .. label(W, b.f) .. " " .. fmt(b.r))
            end
          end
        end
      end
    end
  end
  return problems
end

--- Screens to test, in UIParent units: height 768 / UI scale, width from the aspect ratio.
Layout.MATRIX = {}
for _, res in ipairs({ { 1024, 768 }, { 1920, 1080 }, { 2560, 1080 }, { 3440, 1440 }, { 1280, 1024 }, { 870, 696 } }) do
  for _, scale in ipairs({ 1, 0.64, 1.15 }) do
    local h = 768 / scale
    Layout.MATRIX[#Layout.MATRIX + 1] = { name = res[1] .. "x" .. res[2] .. " @" .. scale, w = math.floor(h * res[1] / res[2]), h = math.floor(h) }
  end
end

return Layout
