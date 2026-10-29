--[[ WoWBoxer – copy and paste keys (addons cannot use the clipboard, so the text is shown selected: Ctrl+C / Ctrl+V).
  Copy: the macro text (works in /macro on any character, with or without WoWBoxer) and, for own keys, a WoWBoxer key
  string (!WBXK:1!…) that another WoWBoxer pastes into the key editor. Paste: a key string or plain macro text; only
  the spell names are taken over and WoWBoxer builds the macro itself (Share.parseMacro / Share.decodeKey). ]]
local _, ns = ...
local W = ns.Widgets
local CB = {}
ns.CopyBox = CB

local WIDTH, HEIGHT = 470, 330

local function frame()
  if CB.frame then return CB.frame end
  local f = W.box(UIParent, 0.09, 0.07, 0.045, 0.98)
  f:SetSize(WIDTH, HEIGHT)
  f:SetFrameStrata("DIALOG")
  f:SetClampedToScreen(true)
  f:SetPoint("CENTER", 0, 60)
  f:EnableMouse(true)
  f.title = W.text(f, "GameFontNormal", nil, W.GOLD)
  f.title:SetPoint("TOPLEFT", 12, -10)
  f.title:SetPoint("TOPRIGHT", -12, -10)
  f.sel1 = W.button(f, "Select", 70, 20, function() f.e1:SetFocus(); f.e1:HighlightText() end, "Selects this text, so Ctrl+C copies it.")
  f.sel1:SetPoint("TOPRIGHT", -12, -30)
  f.sel2 = W.button(f, "Select", 70, 20, function() f.e2:SetFocus(); f.e2:HighlightText() end, "Selects this text, so Ctrl+C copies it.")
  f.sel2:SetPoint("TOPRIGHT", -12, -162)
  f.l1 = W.text(f, "GameFontHighlightSmall", nil, W.MUTED)
  f.l1:SetPoint("TOPLEFT", 12, -30)
  f.l1:SetWidth(WIDTH - 24 - 82)
  if f.l1.SetMaxLines then f.l1:SetMaxLines(2) end
  local s1, s2
  f.e1, s1 = W.editBox(f, WIDTH - 48, 90)
  s1:SetPoint("TOPLEFT", 16, -60)
  f.l2 = W.text(f, "GameFontHighlightSmall", nil, W.MUTED)
  f.l2:SetPoint("TOPLEFT", 12, -162)
  f.l2:SetWidth(WIDTH - 24 - 82)
  if f.l2.SetMaxLines then f.l2:SetMaxLines(2) end
  f.e2, s2 = W.editBox(f, WIDTH - 48, 36)
  s2:SetPoint("TOPLEFT", 16, -192)
  f.s2 = s2
  f.result = W.text(f, "GameFontHighlightSmall", nil, W.TEXT)
  f.result:SetPoint("TOPLEFT", 12, -238)
  f.result:SetPoint("TOPRIGHT", -12, -238)
  if f.result.SetMaxLines then f.result:SetMaxLines(4) end
  f.close = W.button(f, "Close", 80, 22, function() f:Hide() end, "Closes this box. Nothing changes.")
  f.close:SetPoint("BOTTOMRIGHT", -10, 10)
  f.use = W.button(f, "Use it", 80, 22, function() if f.parsed and f.onUse then local d = f.parsed; f:Hide(); f.onUse(d) end end,
    "Puts the spells into the macro editor. Nothing is saved until you press Save macro.")
  f.use:SetPoint("RIGHT", f.close, "LEFT", -6, 0)
  -- copy mode: the text cannot be changed by typing
  local function keep(self, user) if user and f.mode == "copy" and self.fixed then self:SetText(self.fixed); self:HighlightText() end end
  f.e1:SetScript("OnTextChanged", function(self, user) if f.mode == "paste" then if user then CB.parse(self:GetText()) end else keep(self, user) end end)
  f.e2:SetScript("OnTextChanged", keep)
  f:Hide()
  _G.WoWBoxerCopyFrame = f
  table.insert(UISpecialFrames, "WoWBoxerCopyFrame")
  CB.frame = f
  return f
end

--- Show a key's macro text (and its WoWBoxer key string, for own keys) to copy.
function CB.ShowCopy(title, macroText, keyString)
  local f = frame()
  f.mode = "copy"
  f.title:SetText(title)
  f.l1:SetText("Macro text – paste it into /macro on any character (also without WoWBoxer):")
  f.e1.fixed = macroText or ""
  f.e1:SetText(f.e1.fixed)
  local hasKey = keyString ~= nil
  f.l2:SetShown(hasKey); f.s2:SetShown(hasKey); f.sel2:SetShown(hasKey)
  f.l2:SetText("WoWBoxer macro – on another character: My own macros → New macro → Paste:")
  f.e2.fixed = keyString or ""
  f.e2:SetText(f.e2.fixed)
  f.result:SetText("Select the text, then Ctrl+C. Nothing in the game changes.")
  f.sel1:Show(); f.use:Hide()
  f:Show()
  f.e1:SetFocus(); f.e1:HighlightText()
  return f
end

--- Paste a key string or macro text; onUse(draft) gets the parsed key (spell names only).
function CB.ShowPaste(onUse)
  local f = frame()
  f.mode, f.onUse, f.parsed = "paste", onUse, nil
  f.title:SetText("Paste a macro")
  f.l1:SetText("Paste a WoWBoxer macro (!WBXK:1!…) or a macro with /castsequence or /cast lines (Ctrl+V):")
  f.e1.fixed = nil
  f.e1:SetText("")
  f.l2:Hide(); f.s2:Hide(); f.sel2:Hide(); f.sel1:Hide()
  f.result:SetText("|cffa89a7eOnly the spell names are used – WoWBoxer writes the macro itself.|r")
  f.use:Show(); f.use:SetEnabled(false)
  f:Show()
  f.e1:SetFocus()
  return f
end

--- Read the pasted text (data only): a key string first, else macro text.
function CB.parse(text)
  local f = frame()
  local d, err
  if (text or ""):find("!WBXK:", 1, true) then d, err = ns.Share.decodeKey(text) else d, err = ns.Share.parseMacro(text) end
  f.parsed = d
  if not d then
    f.result:SetText((text or ""):match("^%s*$") and "" or ("|cffff8a80" .. tostring(err) .. "|r"))
    f.use:SetEnabled(false)
    return nil, err
  end
  local parts = {}
  for _, n in ipairs(d.steps) do parts[#parts + 1] = n end
  if d.filler and d.filler ~= "" then parts[#parts + 1] = d.filler .. " ×" .. d.fills end
  f.result:SetText("|cffb7f07a" .. (d.kind == "priority" and "Priority list" or "Sequence") .. ":|r " .. table.concat(parts, " → ") ..
    " (" .. (d.aim == "help" and "friendly" or "enemy") .. ")")
  f.use:SetEnabled(true)
  return d
end

return CB
