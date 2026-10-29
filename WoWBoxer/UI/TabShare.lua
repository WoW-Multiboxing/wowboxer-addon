--[[ WoWBoxer – Share tab: import a squad string (validated preview, then a click) and export yours. ]]
local _, ns = ...
local UI, W = ns.UI, ns.Widgets
local tab = { key = "share", label = "Share", icon = "INV_Letter_15", tip = "Copy your squad to your other characters as a text string, or import one from another client." }

local function preview(p)
  local txt = p.importBox:GetText() or ""
  p.pending = nil
  if txt:match("^%s*$") then p.result:SetText("|cffa89a7ePaste a !WBX:1! string (Ctrl+V)|r"); p.importBtn:Disable(); return end
  local res, err, warn = ns.Core.importString(txt)
  if not res then p.result:SetText("|cffff8a80" .. err .. "|r"); p.importBtn:Disable(); return end
  p.pending = res
  local me = (ns.Compat.playerName() or ""):lower()
  local lines = { "|cffb7f07aValid:|r \"" .. res.squad.name .. "\" (" .. #res.squad.members .. ")" }
  local found = false
  for _, m in ipairs(res.squad.members) do
    local isMe = m.name:lower() == me
    found = found or isMe
    lines[#lines + 1] = (isMe and "|cffffd100" or "") .. m.name .. " – " .. ns.Data.classes[m.cls].n .. " " .. ns.State.ROLE_NAME[m.role]:lower() ..
      (m.leader and ", leader" or (", " .. m.unit)) .. (isMe and " (you)|r" or "")
  end
  if not found then lines[#lines + 1] = "|cffd9b36cYou are not in it – pick yourself later|r" end
  local n = 0; for _ in pairs(res.cvars) do n = n + 1 end
  if n > 0 or #res.addons > 0 then lines[#lines + 1] = "Brings " .. n .. " settings, " .. #res.addons .. " addons" end
  for _, w in ipairs(warn or {}) do lines[#lines + 1] = "|cffd9b36c" .. w .. "|r" end
  local exists = ns.State.squad(ns.Core.db, res.squad.id)
  lines[#lines + 1] = "|cffa89a7e" .. (exists and ("Replaces \"" .. exists.name .. "\"") or "Adds a new squad") .. "|r"
  p.result:SetText(table.concat(lines, "\n"))
  p.importBtn:Enable()
end

function tab.build(p)
  local h1 = W.text(p, "GameFontNormal", nil, W.GOLD)
  h1:SetPoint("TOPLEFT", 0, -4)
  h1:SetText("Import")
  local n1 = W.text(p, "GameFontHighlightSmall", nil, W.MUTED)
  n1:SetPoint("TOPLEFT", 0, -22)
  n1:SetWidth(316)
  n1:SetText("From another character or client")
  local isf
  p.importBox, isf = W.editBox(p, 306, 80)
  isf:SetPoint("TOPLEFT", 4, -50)
  p.importSf = isf
  p.importBox:SetScript("OnTextChanged", function(_, user) if user then preview(p) end end)
  p.result = W.text(p, "GameFontHighlightSmall", nil, W.TEXT)
  p.result:SetPoint("TOPLEFT", 0, -142)
  p.result:SetWidth(316)
  p.result:SetJustifyV("TOP")
  if p.result.SetMaxLines then p.result:SetMaxLines(4) end
  p.importBtn = W.button(p, "Import squad", 120, 22, function()
    if not p.pending then return end
    local m = ns.Core.applyImport(p.pending)
    p.pending = nil
    p.importBox:SetText("")
    ns.Core.print("Squad imported" .. (m and (" – you are " .. m.name) or " – pick yourself on the Squad tab") .. ".")
    UI.Select(m and "keys" or "squad")
  end, "Replaces this squad in WoWBoxer with the one in the string and picks you by name. Nothing changes in the game until you place or update macros.")
  p.importBtn:SetPoint("TOPRIGHT", p, "TOPLEFT", 320, -200)
  p.importBtn:Disable()
  p.clear = W.button(p, "Clear", 70, 22, function() p.importBox:SetText(""); preview(p) end, "Empties the box.")
  p.clear:SetPoint("RIGHT", p.importBtn, "LEFT", -6, 0)

  local h2 = W.text(p, "GameFontNormal", nil, W.GOLD)
  h2:SetPoint("TOPLEFT", 336, -4)
  h2:SetText("Export")
  local n2 = W.text(p, "GameFontHighlightSmall", nil, W.MUTED)
  n2:SetPoint("TOPLEFT", 336, -22)
  n2:SetWidth(316)
  n2:SetText("Select all, Ctrl+C, paste on your other clients")
  local esf
  p.exportBox, esf = W.editBox(p, 306, 190)
  esf:SetPoint("TOPLEFT", 340, -50)
  p.exportSf = esf
  p.exportBox:SetScript("OnTextChanged", function(self, user) if user and p.exportText then self:SetText(p.exportText); self:HighlightText() end end)
  p.exportBox:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
  local note = W.text(p, "GameFontHighlightSmall", nil, W.MUTED)
  note:SetPoint("TOPLEFT", 336, -252)
  note:SetWidth(316)
  note:SetText("No macro text, no code")
  local noteHit = CreateFrame("Frame", nil, p)
  noteHit:SetAllPoints(note)
  W.tip(noteHit, "What the string holds", "Your squad: characters, roles, units, talent plans, sequence choices and own macros. Never macro text or code – every client builds its own macros.")
  p.selectAll = W.button(p, "Select all", 100, 22, function() p.exportBox:SetFocus(); p.exportBox:HighlightText() end,
    "Selects the whole string, so Ctrl+C copies it.")
  p.selectAll:SetPoint("TOPRIGHT", p, "TOPLEFT", 652, -320)
end

function tab.refresh(p)
  local str = ns.Core.exportString()
  p.exportText = str or ""
  p.exportBox:SetText(str or "No squad yet")
  p.selectAll:SetEnabled(str ~= nil)
end

UI.RegisterTab(tab)
