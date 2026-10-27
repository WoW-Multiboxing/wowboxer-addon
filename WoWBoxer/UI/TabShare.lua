--[[ WoWBoxer – Share tab: import a squad string (validated preview, then a click) and export yours. ]]
local _, ns = ...
local UI, W = ns.UI, ns.Widgets
local tab = { key = "share", label = "Share" }

local function preview(p)
  local txt = p.importBox:GetText() or ""
  p.pending = nil
  if txt:match("^%s*$") then p.result:SetText("|cffa89a7ePaste a string that starts with !WBX:1! (Ctrl+V).|r"); p.importBtn:Disable(); return end
  local res, err, warn = ns.Core.importString(txt)
  if not res then p.result:SetText("|cffff8a80" .. err .. "|r"); p.importBtn:Disable(); return end
  p.pending = res
  local me = (ns.Compat.playerName() or ""):lower()
  local lines = { "|cffb7f07aValid:|r squad \"" .. res.squad.name .. "\" (" .. #res.squad.members .. " characters, " .. res.game .. ")" }
  local found = false
  for _, m in ipairs(res.squad.members) do
    local isMe = m.name:lower() == me
    found = found or isMe
    lines[#lines + 1] = (isMe and "|cffffd100" or "") .. m.name .. " – " .. ns.Data.classes[m.cls].n .. " " .. ns.State.ROLE_NAME[m.role]:lower() ..
      (m.leader and ", leader" or (", assists via " .. m.unit)) .. (isMe and " (this character)|r" or "")
  end
  if not found then lines[#lines + 1] = "|cffd9b36cThis character is not in it: pick yourself on the Squad tab after importing.|r" end
  local n = 0; for _ in pairs(res.cvars) do n = n + 1 end
  if n > 0 or #res.addons > 0 then lines[#lines + 1] = "Brings " .. n .. " setting(s) and " .. #res.addons .. " recommended addon(s)." end
  for _, w in ipairs(warn or {}) do lines[#lines + 1] = "|cffd9b36c" .. w .. "|r" end
  local exists = ns.State.squad(ns.Core.db, res.squad.id)
  lines[#lines + 1] = "|cffa89a7e" .. (exists and ("Replaces your squad \"" .. exists.name .. "\". ") or "Adds a new squad. ") ..
    "Nothing changes in the game until you press Create & place keys.|r"
  p.result:SetText(table.concat(lines, "\n"))
  p.importBtn:Enable()
end

function tab.build(p)
  local h1 = W.text(p, "GameFontNormal", nil, W.GOLD)
  h1:SetPoint("TOPLEFT", 0, -4)
  h1:SetText("Import")
  local n1 = W.text(p, "GameFontHighlightSmall", nil, W.MUTED)
  n1:SetPoint("TOPLEFT", 0, -22)
  n1:SetWidth(296)
  n1:SetText("Paste a string from the WoWBoxer website, the companion or another character.")
  local isf
  p.importBox, isf = W.editBox(p, 286, 80)
  isf:SetPoint("TOPLEFT", 4, -50)
  p.importBox:SetScript("OnTextChanged", function(_, user) if user then preview(p) end end)
  p.result = W.text(p, "GameFontHighlightSmall", nil, W.TEXT)
  p.result:SetPoint("TOPLEFT", 0, -142)
  p.result:SetWidth(296)
  p.result:SetJustifyV("TOP")
  p.importBtn = W.button(p, "Import squad", 120, 22, function()
    if not p.pending then return end
    local m = ns.Core.applyImport(p.pending)
    p.pending = nil
    p.importBox:SetText("")
    ns.Core.print("Squad imported" .. (m and (" – you are " .. m.name) or " – pick yourself on the Squad tab") .. ".")
    UI.Select(m and "keys" or "squad")
  end)
  p.importBtn:SetPoint("BOTTOMLEFT", 176, 4)
  p.importBtn:Disable()
  p.clear = W.button(p, "Clear", 70, 22, function() p.importBox:SetText(""); preview(p) end)
  p.clear:SetPoint("RIGHT", p.importBtn, "LEFT", -6, 0)

  local h2 = W.text(p, "GameFontNormal", nil, W.GOLD)
  h2:SetPoint("TOPLEFT", 316, -4)
  h2:SetText("Export")
  local n2 = W.text(p, "GameFontHighlightSmall", nil, W.MUTED)
  n2:SetPoint("TOPLEFT", 316, -22)
  n2:SetWidth(296)
  n2:SetText("Your squad as a string: Select all, Ctrl+C, then paste it on your other characters or on the website.")
  local esf
  p.exportBox, esf = W.editBox(p, 286, 190)
  esf:SetPoint("TOPLEFT", 320, -50)
  p.exportBox:SetScript("OnTextChanged", function(self, user) if user and p.exportText then self:SetText(p.exportText); self:HighlightText() end end)
  p.exportBox:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
  local note = W.text(p, "GameFontHighlightSmall", nil, W.MUTED)
  note:SetPoint("TOPLEFT", 316, -250)
  note:SetWidth(296)
  note:SetText("It holds your squad: characters, roles, units, talent plans, sequence choices and custom keys. Never macro text or code – every client builds its own macros.")
  p.selectAll = W.button(p, "Select all", 100, 22, function() p.exportBox:SetFocus(); p.exportBox:HighlightText() end)
  p.selectAll:SetPoint("BOTTOMRIGHT", 0, 4)
end

function tab.refresh(p)
  local str = ns.Core.exportString()
  p.exportText = str or ""
  p.exportBox:SetText(str or "No squad yet.")
  p.selectAll:SetEnabled(str ~= nil)
end

UI.RegisterTab(tab)
