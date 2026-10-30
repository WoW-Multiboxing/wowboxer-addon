--[[ WoWBoxer – the look in one place (docs/ui-redesign.md §2): colour tokens, fonts and the flat rounded skin.
  No colour is written anywhere else; widgets ask for a token by name. Everything here is optional: a client without
  a piece of API (mask textures, custom fonts) keeps the plain version of that piece. ]]
local _, ns = ...
local T = {}
ns.Theme = T

local MEDIA = "Interface\\AddOns\\WoWBoxer\\Media\\"
T.MEDIA = MEDIA
T.TEX = MEDIA .. "Theme\\"

local function hex(h, a)
  return { tonumber(h:sub(2, 3), 16) / 255, tonumber(h:sub(4, 5), 16) / 255, tonumber(h:sub(6, 7), 16) / 255, a or 1 }
end
--- The tokens (§2). line / line-soft are gold at 32 % / 16 %.
T.C = {
  night = hex("#0b0e14"), night2 = hex("#0f131c"), panel = hex("#151a24"), panel2 = hex("#1c2333"), panel3 = hex("#232b3e"),
  gold = hex("#c9a24a"), goldHi = hex("#e8c66a"), goldLo = hex("#8c6b26"),
  line = hex("#c9a24a", 0.32), lineSoft = hex("#c9a24a", 0.16),
  uiGold = hex("#ffd100"), parchment = hex("#e9dfc4"), text = hex("#d6cdb6"), muted = hex("#a79f8a"),
  ok = hex("#8ccb7a"), warn = hex("#e6b455"), no = hex("#e37a7e"), horde = hex("#b3262b"),
  ttBg = hex("#090b16"), ttEdge = hex("#8e8e8e"), black = hex("#000000"), none = { 0, 0, 0, 0 },
  hp = hex("#3fae49"), mana = hex("#2f6bd8"), test = hex("#ff8019"),
}
function T.rgb(name) local c = T.C[name] or T.C.text; return c[1], c[2], c[3], c[4] end
--- "|cffxxxxxx" for a token (inline colour in a text).
function T.code(name) local c = T.C[name] or T.C.text; return string.format("|cff%02x%02x%02x", c[1] * 255, c[2] * 255, c[3] * 255) end

-- ------------------------------------------------------------------ fonts
-- Cinzel for the title, headings and primary buttons; Inter for everything else. Names, spell names and chat-like
-- text keep the game font (T.font(fs, "game")). Locales the two fonts do not cover keep the game font throughout.
T.FONT = {
  heading = MEDIA .. "Fonts\\Cinzel-Bold.ttf",
  body = MEDIA .. "Fonts\\Inter-Regular.ttf",
  bold = MEDIA .. "Fonts\\Inter-SemiBold.ttf",
}
local NO_LATIN = { koKR = true, zhCN = true, zhTW = true }
local NO_CINZEL = { ruRU = true }
function T.fontsOn()
  local loc = _G.GetLocale and _G.GetLocale() or "enUS"
  return not NO_LATIN[loc], not NO_CINZEL[loc] and not NO_LATIN[loc]
end
--- Blizzard font template -> our role + size (a size given by the caller wins).
T.TEMPLATE = {
  GameFontNormalHuge = { "heading", 18 }, GameFontNormalLarge = { "heading", 15 }, GameFontHighlightLarge = { "heading", 15 },
  GameFontNormalMed3 = { "bold", 13 }, GameFontNormal = { "bold", 12 }, GameFontHighlight = { "body", 12 },
  GameFontWhite = { "body", 12 }, GameFontDisable = { "body", 12 }, GameFontNormalSmall = { "bold", 11 },
  GameFontHighlightSmall = { "body", 11 }, GameFontDisableSmall = { "body", 11 },
}
--- The font file for a role on this client, or nil (= keep the game font).
function T.fontFile(role)
  if role == "game" then return nil end
  local latin, cinzel = T.fontsOn()
  if not latin then return nil end
  if role == "heading" and not cinzel then role = "bold" end
  return T.FONT[role] or T.FONT.body
end
--- Put a role on a font string (keeps the game font where the role has no file on this client).
function T.font(fs, role, size)
  if not (fs and fs.SetFont) then return fs end
  local file = T.fontFile(role)
  local cur, curSize, flags = fs:GetFont()
  if role == "game" then
    local base = _G.STANDARD_TEXT_FONT or cur
    if base and size then fs:SetFont(base, size, flags or "") end
    fs.wbxRole = "game"
    return fs
  end
  if file then
    if not fs:SetFont(file, size or curSize or 12, "") and cur then fs:SetFont(cur, size or curSize or 12, flags or "") end
    if fs.SetShadowOffset then fs:SetShadowOffset(0, -1) end
    if fs.SetShadowColor then fs:SetShadowColor(0, 0, 0, 0.6) end
  elseif size and cur then fs:SetFont(cur, size, flags or "") end
  fs.wbxRole = role
  return fs
end
--- A shared font object (for buttons and edit boxes): role, size, colour token. Nil without CreateFont.
local objects, nObj = {}, 0
function T.fontObject(role, size, color)
  local key = role .. size .. color
  if objects[key] then return objects[key] end
  if not _G.CreateFont then return nil end
  nObj = nObj + 1
  local o = _G.CreateFont("WoWBoxerFont" .. nObj)
  local file = T.fontFile(role) or _G.STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
  o:SetFont(file, size, "")
  o:SetTextColor(T.rgb(color))
  if o.SetShadowOffset then o:SetShadowOffset(0, -1); o:SetShadowColor(0, 0, 0, 0.6) end
  objects[key] = o
  return o
end

-- ------------------------------------------------------------------ the rounded box (9-slice of our own textures)
-- A box = a fill and a 1-unit ring, each 9 textures cut from Media/Theme/Fill<r>.tga / Ring<r>.tga and tinted with a
-- token. Radius 3, 4, 6, 8 or 10 (buttons 4, cards 6, window 10, toggles/chips 8).
local RADII = { 3, 4, 6, 8, 10 }
local function radius(r)
  local best = RADII[1]
  for _, v in ipairs(RADII) do if v <= (r or 6) then best = v end end
  return best
end
local function slice(frame, file, r, layer, sub)
  local u = r * 4 / 64
  local parts = {}
  local function piece(l, rr, tp, b)
    local t = frame:CreateTexture(nil, layer, nil, sub)
    t:SetTexture(file)
    t:SetTexCoord(l, rr, tp, b)
    t.wbxSkin = true
    parts[#parts + 1] = t
    return t
  end
  local TL, TR = piece(0, u, 0, u), piece(1 - u, 1, 0, u)
  local BL, BR = piece(0, u, 1 - u, 1), piece(1 - u, 1, 1 - u, 1)
  for _, c in ipairs({ { TL, "TOPLEFT" }, { TR, "TOPRIGHT" }, { BL, "BOTTOMLEFT" }, { BR, "BOTTOMRIGHT" } }) do
    c[1]:SetSize(r, r)
    c[1]:SetPoint(c[2], frame, c[2], 0, 0)
  end
  local function between(t, a, ap, b, bp) t:SetPoint("TOPLEFT", a, ap); t:SetPoint("BOTTOMRIGHT", b, bp) end
  between(piece(u, 1 - u, 0, u), TL, "TOPRIGHT", TR, "BOTTOMLEFT")          -- top edge
  between(piece(u, 1 - u, 1 - u, 1), BL, "TOPRIGHT", BR, "BOTTOMLEFT")      -- bottom edge
  between(piece(0, u, u, 1 - u), TL, "BOTTOMLEFT", BL, "TOPRIGHT")          -- left edge
  between(piece(1 - u, 1, u, 1 - u), TR, "BOTTOMLEFT", BR, "TOPRIGHT")      -- right edge
  between(piece(u, 1 - u, u, 1 - u), TL, "BOTTOMRIGHT", BR, "TOPLEFT")      -- centre
  return parts
end
T.slice = slice
local function tint(parts, name, alpha)
  local r, g, b, a = T.rgb(name)
  for _, t in ipairs(parts) do t:SetVertexColor(r, g, b, (alpha or 1) * (a or 1)); t:SetShown(name ~= "none") end
end
--- Skin a frame as a rounded box: fill + border tokens ("none" = not drawn), radius, fill alpha (optional).
--- Again on the same frame = recolour (hover, selected). Returns the skin.
function T.box(frame, fill, border, r, alpha)
  local s = frame.wbxBox
  if not s then
    r = radius(r)
    s = { r = r, fill = slice(frame, T.TEX .. "Fill" .. r, r, "BACKGROUND", -8), ring = slice(frame, T.TEX .. "Ring" .. r, r, "BACKGROUND", -7) }
    frame.wbxBox = s
  end
  s.fillName, s.borderName, s.alpha = fill or "panel2", border or "lineSoft", alpha
  tint(s.fill, s.fillName, alpha)
  tint(s.ring, s.borderName)
  return s
end
function T.paint(frame, fill, border)
  local s = frame.wbxBox
  if not s then return T.box(frame, fill, border) end
  if fill then s.fillName = fill; tint(s.fill, fill, s.alpha) end
  if border then s.borderName = border; tint(s.ring, border) end
  return s
end
--- A flat 1-unit line (divider) of a token.
function T.line(parent, name, layer)
  local t = parent:CreateTexture(nil, layer or "ARTWORK")
  t:SetColorTexture(T.rgb(name or "lineSoft"))
  return t
end
--- A plain colour texture of a token.
function T.fill(parent, name, layer, sub)
  local t = parent:CreateTexture(nil, layer or "BACKGROUND", nil, sub)
  t:SetColorTexture(T.rgb(name))
  return t
end
--- A glyph texture (Check, Chevron, Close) tinted with a token.
function T.glyph(parent, file, size, name, layer)
  local t = parent:CreateTexture(nil, layer or "ARTWORK")
  t:SetTexture(T.TEX .. file)
  t:SetSize(size, size)
  t:SetVertexColor(T.rgb(name or "gold"))
  return t
end
--- Round the corners of an icon texture (mask; a client without masks keeps square corners).
function T.roundIcon(tex, parent)
  parent = parent or tex:GetParent()
  if not (parent and parent.CreateMaskTexture and tex.AddMaskTexture) then return tex end
  local ok, m = pcall(parent.CreateMaskTexture, parent)
  if not ok or not m then return tex end
  m:SetTexture(T.TEX .. "IconMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
  m:SetAllPoints(tex)
  tex:AddMaskTexture(m)
  tex.wbxMask = m
  return tex
end
