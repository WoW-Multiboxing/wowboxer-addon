-- The theme's rules that a screenshot cannot prove for every state (docs/ui-redesign.md §2):
-- every label is readable on its own background in every state (>= 4.5:1), control edges stand out (>= 3:1),
-- and no hover draws a HIGHLIGHT-layer wash or an additive glow over our window. Run: lua tests/test_theme.lua
local dir = (arg[0]:match("^(.*)/[^/]+$") or ".")
local H = dofile(dir .. "/harness.lua")
local Mock = dofile(dir .. "/wowmock.lua")

local W = Mock.new(H, { name = "Dorin", class = "PALADIN", race = "Scourge", level = 24 })
local ns = H.loadAddon({ env = W.env })
W.fire("ADDON_LOADED", "WoWBoxer"); W.fire("PLAYER_LOGIN")
local T = ns.Theme

-- every state pair: label >= 4.5:1 on its background
local n = 0
for kind, states in pairs(T.STATES) do
  for state, pair in pairs(states) do
    n = n + 1
    local c = T.contrast(pair[1], pair[2])
    H.ok(c >= 4.5, string.format("%s.%s: %s on %s = %.2f:1", kind, state, pair[2], pair[1], c))
  end
end
H.ok(n >= 30, "state pairs checked: " .. n)
for _, kind in ipairs({ "secondary", "primary", "raised", "segment" }) do
  for _, st in ipairs({ "normal", "hover", "pressed", "disabled", "selected" }) do H.ok(T.STATES[kind][st] ~= nil, kind .. " has " .. st) end
end
-- control edges (alpha blended onto the panel) >= 3:1; the disabled edge is exempt (not a control you can use)
local function blendOn(tok, bg)
  local c, b = T.C[tok], T.C[bg]
  local a = c[4] or 1
  T.C._probe = { a * c[1] + (1 - a) * b[1], a * c[2] + (1 - a) * b[2], a * c[3] + (1 - a) * b[3], 1 }
  return "_probe"
end
for _, e in ipairs({ { "ctrlEdge", "panel" }, { "ctrlEdge", "panel2" }, { "goldHi", "panel2" }, { "offEdge", "panel" }, { "onEdge", "panel3" }, { "goldLo", "panel" } }) do
  local c = T.contrast(blendOn(e[1], e[2]), e[2])
  H.ok(c >= 3, string.format("edge %s on %s = %.2f:1", e[1], e[2], c))
end

-- no HIGHLIGHT-layer texture and no ADD blend on our window (hover is a flat background under the label)
local UI = ns.UI
ns.Core.cdb.guide = "done"
UI.Open("keys")
local bad = {}
local function scan(what)
  for _, f in ipairs(W.frames) do
    if f._kind == "Texture" then
      local p, inWin = f._parent, false
      while p do if p == UI.frame then inWin = true end p = p._parent end
      if inWin and f:IsVisible() and (f._layer == "HIGHLIGHT" or f._blend == "ADD") then bad[#bad + 1] = what .. ": " .. tostring(f._layer) .. "/" .. tostring(f._blend) .. " " .. tostring(f._file or "") end
    end
  end
end
for _, t in ipairs(UI.tabs) do UI.Select(t.key); scan(t.key) end
H.eq(#bad, 0, "no highlight wash or additive glow on our window: " .. table.concat(bad, "; "))

-- hover paints a lighter background under the label: a rail row, a button, a dropdown pill
local row = UI.tabButtons.spells
row._scripts.OnEnter(row)
H.eq(row.wbxBox.fillName, "hover", "rail hover: #2b3550")
H.eq(string.format("%.2f", select(1, row.label:GetTextColor())), string.format("%.2f", T.C.parchment[1]), "rail hover: parchment label")
row._scripts.OnLeave(row)
H.eq(row.wbxBox.fillName, "none", "rail: flat again")
UI.Select("keys")
local sel = UI.tabButtons.keys
sel._scripts.OnEnter(sel)
H.ok(sel.wbxBox.fillName == "hover" and sel.sel:IsShown(), "selected + hover: #2b3550, marker stays")
H.eq(string.format("%.2f", select(2, sel.label:GetTextColor())), string.format("%.2f", T.C.uiGold[2]), "selected + hover: ui-gold label")
local b = ns.UI.resetBtn
b._scripts.OnEnter(b); H.eq(b.wbxBox.fillName, "panel3", "secondary hover: one step lighter")
b:Disable(); H.eq(b.wbxBox.borderName, "disEdge", "disabled: grey edge"); H.eq(b.wbxBox.fillName, "panel3", "disabled: panel-3")
b:Enable(); b._scripts.OnLeave(b); H.eq(b.wbxBox.fillName, "panel2", "secondary normal")
local dd = UI.panels.keys.role
dd._scripts.OnEnter(dd); H.eq(dd.wbxBox.fillName, "panel3", "dropdown hover lifts"); dd._scripts.OnLeave(dd)

os.exit(H.report("theme") and 0 or 1)
