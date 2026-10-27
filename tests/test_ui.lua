-- UI smoke test in the simulated client: build the window, render every tab in several states, press the main buttons.
local dir = (arg[0]:match("^(.*)/[^/]+$") or ".")
local H = dofile(dir .. "/harness.lua")
local Mock = dofile(dir .. "/wowmock.lua")

local function boot(opts)
  local W = Mock.new(H, opts)
  local ns = H.loadAddon({ env = W.env })
  W.fire("ADDON_LOADED", "WoWBoxer"); W.fire("PLAYER_LOGIN")
  return W, ns
end
local function uiErrors(ns)
  local n = {}
  for _, e in ipairs(ns.Core.db.log) do if e.l == "error" then n[#n + 1] = e.m end end
  return n
end
local function findButton(W, text)
  for _, f in ipairs(W.frames) do if f._kind == "Button" and f._text == text and f:IsVisible() then return f end end
end
local function anyText(W, pat)
  for _, f in ipairs(W.frames) do if f._text and type(f._text) == "string" and f._text:find(pat) and f:IsVisible() then return f._text end end
end

for _, scenario in ipairs({
  { name = "Dorin", class = "PALADIN", race = "Scourge", level = 3 },
  { name = "Wowtwo", class = "PRIEST", race = "Scourge", level = 24, party = { party1 = "Dorin" } },
  { name = "Hunty", class = "HUNTER", race = "Orc", level = 40, toc = 11509, spellbookStyle = "classic" },
}) do
  local W, ns = boot(scenario)
  for _, s in ipairs(ns.Data.spells[scenario.class:lower()]) do if s.level <= scenario.level then W.known[s.name] = true end end
  local UI, Core = ns.UI, ns.Core
  local tag = scenario.class .. ": "
  UI.Toggle()
  H.ok(UI.frame:IsShown(), tag .. "window opens")
  -- no squad yet: opening the window sets this character up solo (leader), nothing written to the game
  H.ok(select(2, Core.me()) ~= nil, tag .. "opening the window sets up this character")
  H.ok(select(2, Core.me()).leader, tag .. "solo character leads")
  H.eq(W.calls.CreateMacro, nil, tag .. "opening writes no macros")
  for _, t in ipairs(UI.tabs) do UI.Select(t.key) end
  UI.Select("keys")
  if scenario.party then
    -- add the leader and make him leader
    local s = Core.me()
    table.insert(s.members, 1, ns.State.newMember({ name = "Dorin", cls = "paladin", race = "undead", role = "tank", leader = true }))
    for _, m in ipairs(s.members) do m.leader = m.name == "Dorin" end
    Core.changed()
  end
  for _, t in ipairs(UI.tabs) do UI.Select(t.key); H.ok(UI.panels[t.key]:IsShown(), tag .. "tab " .. t.key .. " shows") end
  UI.Select("keys")
  H.ok(anyText(W, "Create your %d+ WBX key") ~= nil, tag .. "banner invites to create the keys")
  local apply = findButton(W, "Create & place keys")
  H.ok(apply ~= nil, tag .. "apply button")
  apply:Click()
  H.eq(Core.compute().macros.changes, 0, tag .. "apply creates everything")
  local onBar = 0
  for slot = 1, 12 do if (W.slotMacroName(slot) or ""):sub(1, 3) == "WBX" then onBar = onBar + 1 end end
  H.ok(onBar > 0, tag .. "keys on action bar 1")
  -- sequence tier buttons (paladin/priest)
  if ns.Engine.seqSupported(scenario.class:lower()) then
    local adv = findButton(W, "Advanced")
    H.ok(adv ~= nil, tag .. "tier buttons")
    adv:Click()
    H.eq(select(2, Core.me()).seq, "advanced", tag .. "tier set")
  end
  -- squad tab: add a character
  UI.Select("squad")
  local panel = UI.panels.squad
  findButton(W, "Add character"):Click()
  H.ok(panel.editor:IsShown(), tag .. "editor opens")
  panel.editor.name:SetText("Kirra")
  findButton(W, "Add"):Click()
  H.ok(not panel.editor:IsShown(), tag .. "editor closes after Add")
  local s = Core.me()
  H.eq(s.members[#s.members].name, "Kirra", tag .. "character added")
  -- share: export then import back
  UI.Select("share")
  local share = UI.panels.share
  local str = share.exportText
  H.ok(str and str:sub(1, 7) == "!WBX:1!", tag .. "export string shown")
  share.importBox:SetText("garbage")
  share.importBox._scripts.OnTextChanged(share.importBox, true)
  H.ok(share.result._text:find("Not a WoWBoxer string") ~= nil, tag .. "bad import explained")
  share.importBox:SetText(str)
  share.importBox._scripts.OnTextChanged(share.importBox, true)
  H.ok(share.result._text:find("Valid") ~= nil, tag .. "valid import previewed")
  findButton(W, "Import squad"):Click()
  H.ok(select(2, Core.me()) ~= nil, tag .. "still me after re-import")
  -- setup: apply settings
  UI.Select("setup")
  local applyCv
  for _, f in ipairs(W.frames) do if f._kind == "Button" and f._text and f._text:find("^Apply %d") and f:IsVisible() then applyCv = f end end
  H.ok(applyCv ~= nil, tag .. "apply settings button")
  if applyCv then applyCv:Click() end
  H.eq(W.cvars.autoLootDefault, "1", tag .. "settings applied")
  -- talents tab renders a plan
  UI.Select("talents")
  H.ok(UI.panels.talents.pool.used > 0 or scenario.level < 10, tag .. "talent order listed")
  -- level-up toast
  W.player.level = scenario.level + 6
  W.fire("PLAYER_LEVEL_UP", W.player.level)
  W.flush()
  if UI.offer and UI.offer:IsShown() then
    findButton(W, "Update keys"):Click()
    H.eq(Core.compute().macros.changes, 0, tag .. "toast updates keys")
  end
  -- combat: buttons disabled, nothing written
  W.combat = true
  UI.Select("keys")
  H.ok(not findButton(W, "Create & place keys"):IsEnabled(), tag .. "apply disabled in combat")
  W.combat = false
  -- slash commands
  W.env.SlashCmdList.WOWBOXER("help"); W.env.SlashCmdList.WOWBOXER("show"); W.env.SlashCmdList.WOWBOXER("log 3"); W.env.SlashCmdList.WOWBOXER("selftest")
  W.env.SlashCmdList.WOWBOXER("")
  H.ok(not UI.frame:IsShown(), tag .. "/wbx toggles the window")
  local errs = uiErrors(ns)
  H.eq(#errs, 0, tag .. "no errors logged: " .. table.concat(errs, " | "))
end

os.exit(H.report("ui") and 0 or 1)
