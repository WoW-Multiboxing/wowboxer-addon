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
  env.UnitExists = function(u) return env.UnitName(u) ~= nil end
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
  env.GetTime = function() return clock end
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
  function methods:CreateFontString(name) return newFrame("FontString", name, self) end
  function methods:CreateTexture(name) return newFrame("Texture", name, self) end
  function methods:GetName() return self._name end
  function methods:GetParent() return self._parent end
  function methods:SetParent(p) self._parent = p end
  function methods:GetWidth() return self._w end
  function methods:GetHeight() return self._h end
  function methods:SetWidth(w) self._w = w end
  function methods:SetHeight(h) self._h = h end
  function methods:SetSize(w, h) self._w, self._h = w, h end
  function methods:GetStringWidth() return #(self._text or "") * 6 end
  function methods:GetStringHeight() return 12 end
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
  function methods:GetNumLetters() return #(self._text or "") end
  FrameMT.__index = function(t, k) return methods[k] or function() end end
  W.newFrame = newFrame
  env.CreateFrame = function(kind, name, parent, template) local f = newFrame(kind, name, parent); f._template = template; return f end
  env.UIParent = newFrame("Frame", "UIParent")
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
  env.GetCurrentBindingSet = function() return 2 end
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
