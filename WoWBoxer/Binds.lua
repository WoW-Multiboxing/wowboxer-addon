--[[ WoWBoxer – key bindings: which key presses each WBX macro, and an optional per-character "bind to key".
  A WBX macro is reached either through the action button it sits on (ACTIONBUTTON3, MULTIACTIONBAR1BUTTON5, ...) or
  through a direct macro binding ("MACRO WBX K1"). Binding is a player's choice made with a click and a key press,
  written only out of combat, into the character-specific binding set. One key = one macro = one action. ]]
local _, ns = ...
local KB = {}
ns.Binds = KB

local G = _G
-- first action slot of a bar -> binding command prefix of its buttons
local BAR_CMD = { [1] = "ACTIONBUTTON", [61] = "MULTIACTIONBAR1BUTTON", [49] = "MULTIACTIONBAR2BUTTON",
  [25] = "MULTIACTIONBAR3BUTTON", [37] = "MULTIACTIONBAR4BUTTON" }
KB.MODIFIERS = { LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true, LALT = true, RALT = true, LMETA = true, RMETA = true }
KB.CHARACTER_SET = 2 -- CHARACTER_BINDINGS

--- Binding command of the action button that shows `slot` (nil for slots without a fixed button, e.g. bar pages 2-6).
function KB.commandForSlot(slot)
  if type(slot) ~= "number" or slot < 1 then return nil end
  local first = slot - (slot - 1) % 12
  local prefix = BAR_CMD[first]
  return prefix and (prefix .. ((slot - 1) % 12 + 1)) or nil
end

local function keysOf(command)
  if not command or not G.GetBindingKey then return {} end
  local out = {}
  for _, k in ipairs({ G.GetBindingKey(command) }) do if type(k) == "string" and k ~= "" then out[#out + 1] = k end end
  return out
end

--- Keys that press macro `name`: its own macro binding first, then the keys of its action button. {{key, via}}
function KB.keysFor(name, slot)
  local out, seen = {}, {}
  for _, k in ipairs(keysOf("MACRO " .. name)) do if not seen[k] then seen[k] = true; out[#out + 1] = { key = k, via = "macro" } end end
  for _, k in ipairs(keysOf(KB.commandForSlot(slot))) do if not seen[k] then seen[k] = true; out[#out + 1] = { key = k, via = "button" } end end
  return out
end

--- Short label for a key: "SHIFT-F" -> "sF", "CTRL-ALT-1" -> "ca1", mouse buttons "M4".
function KB.short(key)
  if not key then return "" end
  local mods, base = "", key
  while true do
    local m, rest = base:match("^(%u+)%-(.+)$")
    if m == "SHIFT" then mods = mods .. "s" elseif m == "CTRL" then mods = mods .. "c" elseif m == "ALT" then mods = mods .. "a"
    elseif m == "META" then mods = mods .. "m" else break end
    base = rest
  end
  base = base:gsub("^BUTTON", "M"):gsub("^NUMPAD", "N"):gsub("^MOUSEWHEELUP", "MwU"):gsub("^MOUSEWHEELDOWN", "MwD")
  return mods .. base
end

--- Key name in WoW's binding format from a key press plus the modifiers held: ALT-CTRL-SHIFT-KEY.
function KB.compose(key, alt, ctrl, shift)
  if not key or KB.MODIFIERS[key] then return nil end
  return (alt and "ALT-" or "") .. (ctrl and "CTRL-" or "") .. (shift and "SHIFT-" or "") .. key
end

--- What a key does now (binding command), or nil.
function KB.actionOf(key)
  if not key or not G.GetBindingAction then return nil end
  local a = G.GetBindingAction(key)
  if a == nil or a == "" then return nil end
  return a
end

--- The action slot an action-button binding command presses (ACTIONBUTTON4 -> 4, MULTIACTIONBAR1BUTTON2 -> 62), or nil.
function KB.slotForCommand(cmd)
  if type(cmd) ~= "string" then return nil end
  for first, prefix in pairs(BAR_CMD) do
    local n = tonumber(cmd:match("^" .. prefix .. "(%d+)$"))
    if n and n >= 1 and n <= 12 then return first + n - 1 end
  end
  return nil
end
--- The game's own name for a binding command ("Open All Bags"); never a raw command name.
function KB.bindingText(cmd)
  if type(cmd) ~= "string" then return "something else" end
  local macro = cmd:match("^MACRO (.+)$")
  if macro then return "the macro \"" .. macro .. "\"" end
  if G.GetBindingText then
    local ok, t = pcall(G.GetBindingText, cmd, "BINDING_NAME_")
    if ok and type(t) == "string" and t ~= "" and t ~= cmd and not t:find("^[%u%d_]+$") then return "\"" .. t .. "\"" end
  end
  return "another game function"
end
--- What the key would mean for macro `name`: {kind = "free" | "same" | "button" | "other", slot, empty, what, text}.
--- A key that presses an action button is not a conflict: the key belongs to that button.
function KB.classify(name, key)
  local used = KB.actionOf(key)
  if not used then return { kind = "free" } end
  if used == "MACRO " .. name then return { kind = "same" } end
  local slot = KB.slotForCommand(used)
  if slot then
    local a = ns.Compat.actionInfo(slot)
    if not a then return { kind = "button", slot = slot, empty = true } end
    if a.kind == "macro" and a.name == name then return { kind = "same", slot = slot } end
    local what = a.name
    if not what and a.kind == "item" and G.GetItemInfo then local ok, n = pcall(G.GetItemInfo, a.id); what = ok and n or nil end
    return { kind = "button", slot = slot, what = what or "something" }
  end
  return { kind = "other", text = KB.bindingText(used) }
end
--- "action button 4" / "Bottom Left Bar button 2" for an action slot.
function KB.buttonName(slot)
  local first = slot - (slot - 1) % 12
  local n = (slot - 1) % 12 + 1
  if first == 1 then return "action button " .. n end
  return ns.Bars.barLabel(first) .. " button " .. n
end

local function save()
  local set = G.CHARACTER_BINDINGS or KB.CHARACTER_SET
  if G.SaveBindings then G.SaveBindings(set) end
end

local function prevStore() local c = ns.Core and ns.Core.cdb; if c then c.bindPrev = c.bindPrev or {} return c.bindPrev end return {} end
--- The game's standard keys of action buttons 1–12 (bar 1): "1"–"9", "0", "-", "=".
KB.DEFAULT_KEYS = { ["1"] = 1, ["2"] = 2, ["3"] = 3, ["4"] = 4, ["5"] = 5, ["6"] = 6, ["7"] = 7, ["8"] = 8, ["9"] = 9, ["0"] = 10, ["-"] = 11, ["="] = 12 }

--- Bind `key` to macro `name` for this character. Must run out of combat (Core.bindKey wraps it).
--- A key that belongs to an action button is NEVER rebound (the macro goes on that button instead: Core.placeOn).
--- The key's previous command is remembered in cdb.bindPrev, so Remove keybind / Reset to default can put it back.
--- Returns true, previousAction or false, reason.
function KB.bind(name, key)
  if not ns.Rules.isOurs(name) then return false, "only WBX macros can be bound" end
  if not key or key == "" then return false, "no key" end
  if ns.Compat.inCombat() then return false, "in combat" end
  if not G.SetBindingMacro then return false, "SetBindingMacro is not available" end
  local before = KB.actionOf(key)
  if KB.slotForCommand(before) then return false, key .. " is the keybind of " .. KB.buttonName(KB.slotForCommand(before)) .. " – put the macro on that button instead" end
  local ok = G.SetBindingMacro(key, name)
  if not ok then return false, "the game refused the key" end
  local prev = prevStore()
  if prev[key] == nil and before ~= "MACRO " .. name then prev[key] = before or "" end -- "" = it did nothing before
  save()
  return true, before
end

--- Put back what `key` did before WoWBoxer bound it (bindPrev), else the standard action-button key for 1–=,
--- else nothing. Returns the command it now has (or nil).
local function restoreKey(key)
  local prev = prevStore()
  local cmd = prev[key]
  if cmd == nil and KB.DEFAULT_KEYS[key] then cmd = "ACTIONBUTTON" .. KB.DEFAULT_KEYS[key] end
  if cmd and cmd ~= "" and not cmd:find("^MACRO WBX") then G.SetBinding(key, cmd) else G.SetBinding(key); cmd = nil end
  prev[key] = nil
  return cmd
end
KB.restoreKey = restoreKey

--- Remove keybind: the direct macro bindings of `name` go back to what the key did before. Returns the number removed.
function KB.unbind(name)
  if not ns.Rules.isOurs(name) or ns.Compat.inCombat() or not G.SetBinding then return 0 end
  local n = 0
  for _, k in ipairs(keysOf("MACRO " .. name)) do restoreKey(k); n = n + 1 end
  if n > 0 then save() end
  return n
end

--- Every key that presses a WBX macro directly: {{key, macro, prev}} (read-only, for the diagnose and the repair).
function KB.directWbx()
  local out, seen = {}, {}
  local names = {}
  for _, x in ipairs(ns.Compat.characterMacros()) do if ns.Rules.isOurs(x.name) then names[#names + 1] = x.name end end
  for _, n in ipairs(names) do
    for _, k in ipairs(keysOf("MACRO " .. n)) do if not seen[k] then seen[k] = true; out[#out + 1] = { key = k, macro = n, prev = prevStore()[k] } end end
  end
  for k in pairs(KB.DEFAULT_KEYS) do
    local a = KB.actionOf(k)
    local m = a and a:match("^MACRO (WBX.*)$")
    if m and not seen[k] then seen[k] = true; out[#out + 1] = { key = k, macro = m, prev = prevStore()[k] } end
  end
  table.sort(out, function(a, b) return a.key < b.key end)
  return out
end
--- Keys 1–= that press a WBX macro directly although they belong to bar 1's buttons (the 0.9.4 bind bug):
--- {{key, slot, macro}}. A key the player bound on purpose from something else (bindPrev not a button) is left alone.
function KB.lostButtons()
  local out = {}
  for _, d in ipairs(KB.directWbx()) do
    local slot = KB.DEFAULT_KEYS[d.key]
    if slot and (d.prev == nil or d.prev == "ACTIONBUTTON" .. slot) then out[#out + 1] = { key = d.key, slot = slot, macro = d.macro } end
  end
  return out
end
--- Give `key` back to its action button (after a click, out of combat).
function KB.giveBack(key)
  if ns.Compat.inCombat() or not G.SetBinding then return false end
  local slot = KB.DEFAULT_KEYS[key]
  if not slot then return false end
  G.SetBinding(key, "ACTIONBUTTON" .. slot)
  prevStore()[key] = nil
  save()
  return true
end
--- Reset to default: every key WoWBoxer bound goes back to what it did before (and 1–= to their buttons).
function KB.restoreAll()
  if ns.Compat.inCombat() or not G.SetBinding then return 0 end
  local n = 0
  for _, d in ipairs(KB.directWbx()) do restoreKey(d.key); n = n + 1 end
  if n > 0 then save() end
  return n
end

return KB
