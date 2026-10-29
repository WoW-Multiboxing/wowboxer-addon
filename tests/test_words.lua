-- Words (docs/feedback-2026-10-29-late.md §2): what WoWBoxer makes is a "macro", the key on its button is its
-- "keybind". Scans every string literal of the addon's code (not Engine.lua: its texts are the companion's, parity)
-- for "key"/"keys" used about our macros. Allowed: keybinds, the keyboard (press a key, key bindings, Esc …).
local dir = (arg[0]:match("^(.*)/[^/]+$") or ".")
local H = dofile(dir .. "/harness.lua")

local ALLOW = {
  "keybind", "[Kk]ey [Bb]indings?", "[Pp]ress a key", "[Pp]ress another key", "key press", "[Ee]sc", "Cast on key down",
  "[Ss]ame key, same job", "[Kk]ey map", "Your key per column", "a key that", "WoWBoxer key string", "wowboxer%-key",
  "Quick Keybind", "^/wbx keys", "Unknown key format", "expected key",
  "^My key$", -- the companion's default name of an own macro (data, parity)
  "^Key $", -- the key map: keyboard key 1, 2 … (same key, same job)
}
local function allowed(s)
  for _, a in ipairs(ALLOW) do if s:find(a) then return true end end
  return false
end
local files = {}
for _, f in ipairs(H.tocFiles()) do
  if f:match("%.lua$") and not f:match("^Data/") and f ~= "Engine.lua" then files[#files + 1] = f end
end
local bad = {}
for _, f in ipairs(files) do
  local n = 0
  for line in io.lines(H.root .. "/WoWBoxer/" .. f) do
    n = n + 1
    local code = line:match("^%s*%-%-") and "" or line:gsub("%-%-[^\"]*$", "")
    for lit in code:gmatch('"([^"\\]*)"') do
      -- player text only: has a space or starts with a capital; not a table key, pattern or API name
      local text = lit:find(" ", 1, true) or lit:match("^%u%l")
      if text and (lit:find("%f[%a][Kk]eys?%f[%A]")) and not allowed(lit) then bad[#bad + 1] = f .. ":" .. n .. ": " .. lit end
    end
  end
end
for i, b in ipairs(bad) do if i <= 30 then print("  " .. b) end end
H.eq(#bad, 0, "player texts say macro / keybind, not key (" .. #files .. " files)")
os.exit(H.report("words") and 0 or 1)
