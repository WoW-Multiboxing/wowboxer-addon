--[[ A small World of Warcraft API simulator for the addon tests.
  Simulates what WoWBoxer touches: macros (account 120 / character N slots, kept sorted by name like the client, with
  action buttons that follow their macro), action slots and the cursor, combat lockdown, CVars, addons, spellbook,
  units, events, timers, chat, slash commands and generic frames for UI smoke tests. ]]
local Mock = {}

local function lowerLess(a, b) local la, lb = a.name:lower(), b.name:lower(); if la ~= lb then return la < lb end return a.seq < b.seq end

function Mock.new(H, opts)
  opts = opts or {}
  local W = { chat = {}, events = {}, frames = {}, timers = {}, errors = {}, calls = {} }
  W.combat = false
  W.toc = opts.toc or 16001
  W.player = { name = opts.name or "Dorin", class = opts.class or "PALADIN", race = opts.race or "Scourge", level = opts.level or 10, faction = opts.faction or "Horde" }
  W.party = opts.party or {}
  W.focus = opts.focus
  W.known = opts.known or {}          -- spell names in the spellbook
  W.spellbookStyle = opts.spellbookStyle or "modern" -- modern | classic | none
  W.maxChar = opts.maxChar or 18
  W.acc, W.char = {}, {}
  W.actions, W.cursor = {}, nil
  W.cvars = opts.cvars or { autoLootDefault = "0", deselectOnClick = "1", autoSelfCast = "1", maxfpsbk = "8", Sound_EnableSoundWhenGameIsInBG = "1",
    Sound_EnableErrorSpeech = "1", showTargetOfTarget = "0", ActionButtonUseKeyDown = "1", autoClearAFK = "1" }
  W.addons = opts.addons or { Questie = "loaded", Leatrix_Plus = "installed" }
  local seq = 0

  local env = H.env51()
  W.env = env
  local function protected(name) if W.combat then error("Interface action failed because of an AddOn (" .. name .. ")", 2) end end
  local function call(name) W.calls[name] = (W.calls[name] or 0) + 1 end

  -- ---------------------------------------------------------------- macros
  local function sortAll() table.sort(W.acc, lowerLess); table.sort(W.char, lowerLess) end
  local function byIndex(i)
    if i >= 1 and i <= 120 then return W.acc[i], W.acc, i end
    if i > 120 and i <= 120 + W.maxChar then return W.char[i - 120], W.char, i - 120 end
  end
  local function indexOf(m)
    for i, x in ipairs(W.acc) do if x == m then return i end end
    for i, x in ipairs(W.char) do if x == m then return 120 + i end end
  end
  W.indexOf = indexOf
  env.MAX_ACCOUNT_MACROS, env.MAX_CHARACTER_MACROS = 120, W.maxChar
  env.GetNumMacros = function() return #W.acc, #W.char end
  env.GetMacroInfo = function(i) local m = byIndex(i); if m then return m.name, m.icon, m.body end end
  env.CreateMacro = function(name, icon, body, perChar)
    protected("CreateMacro"); call("CreateMacro")
    local list = perChar and W.char or W.acc
    if #list >= (perChar and W.maxChar or 120) then error("Macro limit reached", 2) end
    seq = seq + 1
    local m = { name = name:sub(1, 16), icon = icon, body = body:sub(1, 255), seq = seq }
    list[#list + 1] = m; sortAll()
    return indexOf(m)
  end
  env.EditMacro = function(i, name, icon, body)
    protected("EditMacro"); call("EditMacro")
    local m = byIndex(i); if not m then error("bad macro index", 2) end
    if name then m.name = name:sub(1, 16) end
    if icon then m.icon = icon end
    if body then m.body = body:sub(1, 255) end
    sortAll(); return indexOf(m)
  end
  env.DeleteMacro = function(i)
    protected("DeleteMacro"); call("DeleteMacro")
    local m, list, k = byIndex(i); if not m then return end
    table.remove(list, k)
    for slot, a in pairs(W.actions) do if a.ref == m then W.actions[slot] = nil end end
  end
  function W.addMacro(name, body, perChar) local was = W.combat; W.combat = false; env.CreateMacro(name, 134400, body, perChar); W.combat = was end

  -- ---------------------------------------------------------------- action bars + cursor
  env.GetActionInfo = function(slot)
    local a = W.actions[slot]; if not a then return nil end
    if a.kind == "macro" then return "macro", indexOf(a.ref) end
    return a.kind, a.id
  end
  env.HasAction = function(slot) return W.actions[slot] ~= nil end
  env.PickupMacro = function(i) protected("PickupMacro"); local m = byIndex(i); if m then W.cursor = { kind = "macro", ref = m } end end
  env.PlaceAction = function(slot) protected("PlaceAction"); call("PlaceAction"); local old = W.actions[slot]; W.actions[slot] = W.cursor; W.cursor = old end
  env.PickupAction = function(slot) protected("PickupAction"); local old = W.actions[slot]; W.actions[slot] = W.cursor; W.cursor = old end
  env.ClearCursor = function() W.cursor = nil end
  env.GetCursorInfo = function() return W.cursor and W.cursor.kind or nil end
  function W.slotMacroName(slot) local a = W.actions[slot]; return a and a.kind == "macro" and a.ref.name or nil end

  -- ---------------------------------------------------------------- game, units, combat
  env.GetBuildInfo = function() return W.toc >= 16000 and "1.60.1" or "1.15.9", W.toc >= 16000 and "70532" or "70576", "Oct 1 2026", W.toc end
  env.GetLocale = function() return "enUS" end
  env.GetRealmName = function() return "Realm" end
  env.InCombatLockdown = function() return W.combat end
  env.UnitName = function(u)
    if u == "player" then return W.player.name end
    if u == "focus" then return W.focus end
    return W.party[u]
  end
  env.UnitExists = function(u) if u == "target" then return W.targetGUID ~= nil end return env.UnitName(u) ~= nil end
  env.UnitClass = function(u) local c = W.player.class; return c:sub(1, 1) .. c:sub(2):lower(), c end
  env.UnitRace = function(u) return W.player.race, W.player.race end
  env.UnitLevel = function(u) return W.player.level end
  env.UnitFactionGroup = function(u) return W.player.faction end
  env.IsInGroup = function() return next(W.party) ~= nil end
  env.GetNumGroupMembers = function() local n = 0; for _ in pairs(W.party) do n = n + 1 end; return n > 0 and n + 1 or 0 end
  if opts.secrets then env.issecretvalue = function(v) return v == "SECRET" end end

  -- ---------------------------------------------------------------- spellbook
  local function knownList() local l = {}; for n in pairs(W.known) do l[#l + 1] = n end; table.sort(l); return l end
  if W.spellbookStyle == "modern" then
    env.Enum = { SpellBookSpellBank = { Player = 0, Pet = 1 } }
    env.C_SpellBook = {
      GetNumSpellBookSkillLines = function() return 1 end,
      GetSpellBookSkillLineInfo = function(i) return { itemIndexOffset = 0, numSpellBookItems = #knownList() } end,
      GetSpellBookItemName = function(i, bank) return knownList()[i] end,
    }
    env.C_Spell = { GetSpellName = function(id) return "Spell" .. tostring(id) end }
  elseif W.spellbookStyle == "classic" then
    env.GetNumSpellTabs = function() return 1 end
    env.GetSpellTabInfo = function(i) return "General", nil, 0, #knownList() end
    env.GetSpellBookItemName = function(i) return knownList()[i], "" end
    env.BOOKTYPE_SPELL = "spell"
    env.GetSpellInfo = function(id) return "Spell" .. tostring(id) end
  end
  env.IsPlayerSpell = function(id) return false end

  -- ---------------------------------------------------------------- cvars, addons
  env.C_CVar = { GetCVar = function(n) return W.cvars[n] end, SetCVar = function(n, v) protected("SetCVar"); if W.cvars[n] == nil then error("unknown cvar") end W.cvars[n] = tostring(v); return true end }
  env.C_AddOns = {
    IsAddOnLoaded = function(n) return W.addons[n] == "loaded" end,
    GetAddOnInfo = function(n) if W.addons[n] then return n, n, "", true, nil end return nil, nil, nil, false, "MISSING" end,
  }

  -- ---------------------------------------------------------------- timers, time
  local clock = 1793100000
  env.time = function() clock = clock + 1; return clock end
  env.date = function(f, t) return os.date(f, t) end
  env.GetTime = function() return W.now or clock end
  -- addon messages, target, power (for the team status)
  W.sent, W.prefixes = {}, {}
  W.targetGUID, W.mana, W.manaMax, W.inCombatUnit = nil, 500, 1000, false
  env.C_ChatInfo = { SendAddonMessage = function(prefix, msg, chan) W.sent[#W.sent + 1] = { prefix = prefix, msg = msg, chan = chan }; return true end,
    RegisterAddonMessagePrefix = function(p) W.prefixes[p] = true; return true end }
  env.UnitGUID = function(u) if u == "target" then return W.targetGUID end return nil end
  env.UnitPower = function(u) return W.mana end
  env.UnitPowerMax = function(u) return W.manaMax end
  env.UnitAffectingCombat = function(u) return W.inCombatUnit end
  env.IsInRaid = function() return false end
  env.C_Timer = { After = function(sec, fn) W.timers[#W.timers + 1] = fn end, NewTicker = function() return { Cancel = function() end } end }
  function W.flush() local t = W.timers; W.timers = {}; for _, fn in ipairs(t) do fn() end end

  -- ---------------------------------------------------------------- frames
  local FrameMT = {}
  local function newFrame(kind, name, parent)
    local f = { _kind = kind, _name = name, _parent = parent, _scripts = {}, _events = {}, _shown = kind ~= "Frame" or true, _text = nil, _children = {},
      _w = 100, _h = 20, _checked = false, _value = 0 }
    setmetatable(f, FrameMT)
    W.frames[#W.frames + 1] = f
    if name then env[name] = f end
    if parent and parent._children then parent._children[#parent._children + 1] = f end
    return f
  end
  local methods = {}
  function methods:SetScript(s, fn) self._scripts[s] = fn end
  function methods:GetScript(s) return self._scripts[s] end
  function methods:HookScript(s, fn) local old = self._scripts[s]; self._scripts[s] = function(...) if old then old(...) end fn(...) end end
  function methods:RegisterEvent(e) self._events[e] = true; W.events[e] = W.events[e] or {}; W.events[e][self] = true end
  function methods:UnregisterEvent(e) self._events[e] = nil; if W.events[e] then W.events[e][self] = nil end end
  function methods:Show() self._shown = true; if self._scripts.OnShow then self._scripts.OnShow(self) end end
  function methods:Hide() local was = self._shown; self._shown = false; if was and self._scripts.OnHide then self._scripts.OnHide(self) end end
  function methods:SetShown(v) if v then self:Show() else self:Hide() end end
  function methods:IsShown() return self._shown end
  function methods:IsVisible() local f = self; while f do if not f._shown then return false end f = f._parent end return true end
  function methods:SetText(t) self._text = t end
  function methods:GetText() return self._text end
  function methods:SetFormattedText(fmt, ...) self._text = string.format(fmt, ...) end
  function methods:CreateFontString(name, _, template)
    local fs = newFrame("FontString", name, self)
    fs._fontSize = W.FONT_SIZE[template or "GameFontNormal"] or 12
    return fs
  end
  function methods:CreateTexture(name) return newFrame("Texture", name, self) end
  function methods:GetName() return self._name end
  function methods:GetParent() return self._parent end
  function methods:SetParent(p) self._parent = p end
  function methods:SetWidth(w) self._w = w; self._wSet = true end
  function methods:SetHeight(h) self._h = h; self._hSet = true end
  function methods:SetSize(w, h) self._w, self._h = w, h; self._wSet, self._hSet = true, true end
  -- ---------------------------------------------------------------- geometry (anchors, scale, text metrics)
  -- Text is measured like the spec says: width = characters x font size x W.fontFactor (0.55), line height = size + 2.
  -- Rects are computed from the anchors in UIParent units (y up), so tests can find overlaps (tests/layout.lua).
  W.fontFactor = opts.fontFactor or 0.55
  local FONT_SIZE = { GameFontHighlightSmall = 10, GameFontNormalSmall = 10, GameFontDisableSmall = 10, GameFontNormal = 12,
    GameFontHighlight = 12, GameFontDisable = 12, GameFontNormalLarge = 16, GameFontNormalHuge = 20, ChatFontNormal = 14,
    GameFontHighlightLarge = 16, GameFontNormalMed3 = 14, NumberFontNormal = 12, GameFontWhite = 12 }
  W.FONT_SIZE = FONT_SIZE
  function W.plain(t)
    t = tostring(t or "")
    t = t:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "##"):gsub("|n", "\n")
    return t
  end
  local function chars(s) local n = 0; for _ in s:gmatch("[^\128-\191]") do n = n + 1 end return n end
  function W.textWidth(t, size)
    local w = 0
    for line in (W.plain(t) .. "\n"):gmatch("([^\n]*)\n") do w = math.max(w, chars(line) * size * W.fontFactor) end
    return w
  end
  --- Lines a text needs at `width` (word wrap like the client: break at spaces, long words are split).
  function W.textLines(t, size, width)
    local n = 0
    for line in (W.plain(t) .. "\n"):gmatch("([^\n]*)\n") do
      if not width or width <= 0 then n = n + 1
      else
        local cur, count = 0, 1
        local space = size * W.fontFactor
        for word in line:gmatch("%S+") do
          local ww = chars(word) * size * W.fontFactor
          if cur > 0 and cur + space + ww > width + 0.5 then count = count + 1; cur = 0 end
          if cur == 0 then
            while ww > width + 0.5 do count = count + 1; ww = ww - width end
            cur = ww
          else cur = cur + space + ww end
        end
        n = n + count
      end
    end
    return n
  end
  local function fontSize(f) return f._fontSize or 12 end
  function methods:GetFont() return "Fonts\\FRIZQT__.TTF", fontSize(self), "" end
  function methods:SetFont(_, size) if size then self._fontSize = size end return true end
  function methods:SetFontObject(o) if type(o) == "table" and o._name and FONT_SIZE[o._name] then self._fontSize = FONT_SIZE[o._name] end end
  function methods:SetMaxLines(n) self._maxLines = n end
  function methods:GetStringWidth() return W.textWidth(self._text, fontSize(self)) end
  function methods:GetUnboundedStringWidth() return W.textWidth(self._text, fontSize(self)) end
  function methods:GetTextWidth() return W.textWidth(self._text, self._kind == "FontString" and fontSize(self) or 12) end
  function methods:GetLineHeight() return fontSize(self) + 2 end
  function methods:SetPoint(point, a, b, c, d)
    self._points = self._points or {}
    local rel, rp, x, y
    if type(a) == "number" or a == nil then rel, rp, x, y = nil, point, a or 0, b or 0
    elseif type(b) == "number" then rel, rp, x, y = a, point, b, c or 0
    else rel, rp, x, y = a, b or point, c or 0, d or 0 end
    if type(rel) == "string" then rel = env[rel] end
    for i = #self._points, 1, -1 do if self._points[i][1] == point then table.remove(self._points, i) end end
    self._points[#self._points + 1] = { point, rel or self._parent, rp, x, y }
  end
  function methods:SetAllPoints(rel)
    self._points = {}
    self:SetPoint("TOPLEFT", rel or self._parent, "TOPLEFT", 0, 0)
    self:SetPoint("BOTTOMRIGHT", rel or self._parent, "BOTTOMRIGHT", 0, 0)
  end
  function methods:ClearAllPoints() self._points = {} end
  function methods:GetNumPoints() return #(self._points or {}) end
  function methods:GetPoint(i)
    local p = (self._points or {})[i or 1]
    if p then return p[1], p[2], p[3], p[4], p[5] end
  end
  function methods:SetScale(s) self._scale = s end
  function methods:GetScale() return self._scale or 1 end
  function methods:GetEffectiveScale()
    local s, f = 1, self
    while f do s = s * (f._scale or 1); f = f._parent end
    return s
  end
  function methods:SetScrollChild(c) self._scrollChild = c; c._scrollParent = self end
  function methods:GetScrollChild() return self._scrollChild end
  --- {l, b, r, t} in UIParent units, or nil when the frame is not placed.
  local function factor(f) return f:GetEffectiveScale() / env.UIParent:GetEffectiveScale() end
  local POS = { TOPLEFT = { 0, 1 }, TOP = { 0.5, 1 }, TOPRIGHT = { 1, 1 }, LEFT = { 0, 0.5 }, CENTER = { 0.5, 0.5 }, RIGHT = { 1, 0.5 },
    BOTTOMLEFT = { 0, 0 }, BOTTOM = { 0.5, 0 }, BOTTOMRIGHT = { 1, 0 } }
  W.POS = POS
  local rectOf
  local function intrinsic(f, k, width)
    if f._kind == "FontString" then
      local size = fontSize(f) * k
      local natural = W.textWidth(f._text, fontSize(f)) * k
      local w = width or ((f._wSet and f._w > 0) and f._w * k) or natural
      local lines = 1
      if f._wrap ~= false and (width or (f._wSet and f._w > 0)) then lines = W.textLines(f._text, fontSize(f), w / k) end
      if f._maxLines and f._maxLines > 0 then lines = math.min(lines, f._maxLines) end
      local h = (f._hSet and f._h > 0) and f._h * k or lines * (size + 2 * k)
      return w, h, lines
    end
    return (f._w or 0) * k, (f._h or 0) * k
  end
  rectOf = function(f, seen)
    if f == env.UIParent then return { 0, 0, W.screen.w, W.screen.h } end
    seen = seen or {}
    if seen[f] then return nil end
    seen[f] = true
    local k = factor(f)
    local pts = f._points
    if (not pts or #pts == 0) and f._scrollParent then
      local pr = rectOf(f._scrollParent, seen)
      seen[f] = nil
      if not pr then return nil end
      return { pr[1], pr[4] - f._h * k, pr[1] + f._w * k, pr[4] }
    end
    if not pts or #pts == 0 then seen[f] = nil; return nil end
    local L, R, CX, T, B, CY
    for _, p in ipairs(pts) do
      local rr = p[2] and rectOf(p[2], seen)
      if not rr then seen[f] = nil; return nil end
      local rp, mp = POS[p[3]], POS[p[1]]
      local ax = rr[1] + (rr[3] - rr[1]) * rp[1] + p[4] * k
      local ay = rr[2] + (rr[4] - rr[2]) * rp[2] + p[5] * k
      if mp[1] == 0 then L = ax elseif mp[1] == 1 then R = ax else CX = ax end
      if mp[2] == 0 then B = ay elseif mp[2] == 1 then T = ay else CY = ay end
    end
    -- two points on one axis set the size, like the client (TOP + CENTER gives height 2 x (top - centre))
    local width = (L and R) and (R - L) or (L and CX) and 2 * (CX - L) or (R and CX) and 2 * (R - CX) or nil
    if width and not (L and R) then L = L or (R - width) end
    local iw, ih = intrinsic(f, k, width)
    local w = width or iw
    if not L then L = R and (R - w) or ((CX or 0) - w / 2) end
    R = L + w
    local h = (T and B) and (T - B) or (T and CY) and 2 * (T - CY) or (B and CY) and 2 * (CY - B) or nil
    if h and not (T and B) then B = B or (T - h) end
    if not h then h = ih end
    if not B then B = T and (T - h) or ((CY or 0) - h / 2) end
    T = B + h
    seen[f] = nil
    return { L, B, R, T }
  end
  W.rect = rectOf
  W.factor = factor
  function methods:GetLeft() local r = rectOf(self); return r and r[1] / factor(self) end
  function methods:GetRight() local r = rectOf(self); return r and r[3] / factor(self) end
  function methods:GetBottom() local r = rectOf(self); return r and r[2] / factor(self) end
  function methods:GetTop() local r = rectOf(self); return r and r[4] / factor(self) end
  function methods:GetCenter() local r = rectOf(self); if r then local k = factor(self); return (r[1] + r[3]) / 2 / k, (r[2] + r[4]) / 2 / k end end
  local function placed(f) return f._points and #f._points > 0 end
  function methods:GetWidth()
    if self._kind == "FontString" or (placed(self) and not self._wSet) then
      local r = rectOf(self); if r then return (r[3] - r[1]) / factor(self) end
      if self._kind == "FontString" then return W.textWidth(self._text, fontSize(self)) end
    end
    return self._w
  end
  function methods:GetHeight()
    if self._kind == "FontString" or (placed(self) and not self._hSet) then
      local r = rectOf(self); if r then return (r[4] - r[2]) / factor(self) end
      if self._kind == "FontString" then return fontSize(self) + 2 end
    end
    return self._h
  end
  function methods:GetStringHeight()
    local r = rectOf(self)
    local w = r and (r[3] - r[1]) / factor(self) or nil
    local lines = W.textLines(self._text, fontSize(self), (self._wrap ~= false) and w or nil)
    if self._maxLines and self._maxLines > 0 then lines = math.min(lines, self._maxLines) end
    return lines * (fontSize(self) + 2)
  end
  function methods:IsTruncated()
    local r = rectOf(self)
    if not r then return false end
    local k = factor(self)
    local w = (r[3] - r[1]) / k
    if W.textWidth(self._text, fontSize(self)) <= w + 0.5 then return false end
    if self._wrap == false then return true end
    local need = W.textLines(self._text, fontSize(self), w) * (fontSize(self) + 2)
    return need > (r[4] - r[2]) / k + 0.5
  end
  function methods:SetChecked(v) self._checked = not not v end
  function methods:GetChecked() return self._checked end
  function methods:SetValue(v) self._value = v end
  function methods:GetValue() return self._value end
  function methods:SetMinMaxValues(a, b) self._min, self._max = a, b end
  function methods:GetMinMaxValues() return self._min or 0, self._max or 0 end
  function methods:GetVerticalScroll() return 0 end
  function methods:GetVerticalScrollRange() return 0 end
  function methods:GetChildren() return unpack(self._children) end
  function methods:GetNumChildren() return #self._children end
  function methods:IsEnabled() return not self._disabled end
  function methods:Enable() self._disabled = false end
  function methods:Disable() self._disabled = true end
  function methods:SetEnabled(v) self._disabled = not v end
  function methods:Click(button) if not self._disabled and self._scripts.OnClick then self._scripts.OnClick(self, button or "LeftButton") end end
  function methods:GetFontString() self._fs = self._fs or newFrame("FontString", nil, self); return self._fs end
  function methods:HasFocus() return false end
  function methods:GetObjectType() return self._kind end
  function methods:GetCursorPosition() return 0 end
  function methods:SetWordWrap(v) self._wrap = v and true or false end
  function methods:CanWordWrap() return rawget(self, "_wrap") ~= false end
  function methods:GetRegions()
    local out = {}
    for _, c in ipairs(self._children) do if c._kind == "FontString" or c._kind == "Texture" then out[#out + 1] = c end end
    return unpack(out)
  end
  function methods:GetNumLetters() return #(self._text or "") end
  -- unknown API methods (CamelCase) are no-ops; unknown fields (_x, lowercase) are nil, like on a real frame
  FrameMT.__index = function(t, k)
    if methods[k] then return methods[k] end
    if type(k) == "string" and k:match("^%u") then return function() end end
    return nil
  end
  W.newFrame = newFrame
  env.CreateFrame = function(kind, name, parent, template) local f = newFrame(kind, name, parent); f._template = template; return f end
  env.UIParent = newFrame("Frame", "UIParent")
  W.screen = opts.screen or { w = 1365, h = 768 }
  env.UIParent._w, env.UIParent._h = W.screen.w, W.screen.h
  env.GetScreenWidth = function() return W.screen.w end
  env.GetScreenHeight = function() return W.screen.h end
  env.GameTooltip = newFrame("GameTooltip", "GameTooltip", env.UIParent)
  env.UISpecialFrames = {}
  env.StaticPopupDialogs = {}
  env.StaticPopup_Show = function(which, a, b, data) W.popup = { which = which, data = data } end
  env.StaticPopup_Hide = function() W.popup = nil end
  env.PlaySound = function() end
  env.SOUNDKIT = { IG_MAINMENU_OPEN = 1, IG_MAINMENU_CLOSE = 2, U_CHAT_SCROLL_BUTTON = 3 }
  env.RAID_CLASS_COLORS = {}
  for _, c in ipairs({ "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }) do
    env.RAID_CLASS_COLORS[c] = { r = 1, g = 1, b = 1, colorStr = "ffffffff" }
  end
  for _, fnt in ipairs({ "GameFontNormal", "GameFontHighlight", "GameFontHighlightSmall", "GameFontNormalSmall", "GameFontNormalLarge", "GameFontDisable", "GameFontDisableSmall", "ChatFontNormal", "GameFontNormalHuge" }) do
    env[fnt] = newFrame("Font", fnt)
  end
  env.DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) W.chat[#W.chat + 1] = msg end }
  env.SlashCmdList = {}
  env.hooksecurefunc = function() end
  env.ACCEPT, env.CANCEL, env.OKAY, env.CLOSE, env.YES, env.NO = "Accept", "Cancel", "Okay", "Close", "Yes", "No"
  env.GetCurrentBindingSet = function() return W.bindingSet or 1 end
  -- key bindings: W.bindings[key] = command
  W.bindings = opts.bindings or { ["1"] = "ACTIONBUTTON1", ["2"] = "ACTIONBUTTON2", ["3"] = "ACTIONBUTTON3", ["F"] = "ASSISTTARGET" }
  env.GetBindingKey = function(cmd)
    local keys = {}
    for k, c in pairs(W.bindings) do if c == cmd then keys[#keys + 1] = k end end
    table.sort(keys)
    return unpack(keys)
  end
  env.GetBindingAction = function(key) return W.bindings[key] or "" end
  env.SetBindingMacro = function(key, name) protected("SetBindingMacro"); call("SetBindingMacro"); W.bindings[key] = "MACRO " .. name; return true end
  env.SetBinding = function(key, cmd) protected("SetBinding"); call("SetBinding"); W.bindings[key] = cmd; return true end
  env.SaveBindings = function(set) protected("SaveBindings"); W.bindingSet = set end
  env.CHARACTER_BINDINGS = 2
  W.mods = {}
  env.IsShiftKeyDown = function() return W.mods.shift end
  env.IsControlKeyDown = function() return W.mods.ctrl end
  env.IsAltKeyDown = function() return W.mods.alt end
  W.cursorPos = { 0, 0 }
  env.GetCursorPosition = function() return W.cursorPos[1], W.cursorPos[2] end
  env.Minimap = newFrame("Frame", "Minimap", env.UIParent)
  env.Minimap.GetCenter = function() return 500, 500 end
  env.Minimap.GetEffectiveScale = function() return 1 end
  env.Minimap._w = 140
  env.ReloadUI = function() W.reloaded = true end
  env.IsLoggedIn = function() return true end

  -- ---------------------------------------------------------------- events
  function W.fire(event, ...)
    for f in pairs(W.events[event] or {}) do if f._scripts.OnEvent then f._scripts.OnEvent(f, event, ...) end end
  end
  function W.lastChat() return W.chat[#W.chat] end
  function W.chatHas(pat) for _, m in ipairs(W.chat) do if m:find(pat) then return true end end return false end
  return W
end

return Mock
