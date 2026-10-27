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
  -- first run: the 3-step guide
  local guide = UI.panels.keys.guide
  H.ok(guide:IsShown(), tag .. "guide on a fresh character")
  H.ok(anyText(W, "^Step 1 of 3") ~= nil, tag .. "guide step 1")
  findButton(W, "Next"):Click()
  H.ok(anyText(W, "^Step 2 of 3") ~= nil, tag .. "guide step 2")
  H.ok(anyText(W, "Place all puts your %d+ keys on Action Bar 1") ~= nil, tag .. "step 2 says where the keys go")
  H.eq(W.calls.CreateMacro, nil, tag .. "the guide writes nothing before the click")
  findButton(W, "Place all"):Click()
  H.eq(Core.compute().macros.changes, 0, tag .. "Place all creates everything")
  local onBar = 0
  for slot = 1, 12 do if (W.slotMacroName(slot) or ""):sub(1, 3) == "WBX" then onBar = onBar + 1 end end
  H.ok(onBar > 0, tag .. "keys on action bar 1")
  H.ok(anyText(W, "^Step 3 of 3") ~= nil, tag .. "guide step 3")
  findButton(W, "Close"):Click()
  H.ok(not guide:IsShown(), tag .. "guide closed")
  H.ok(anyText(W, "All keys are on your bars") ~= nil, tag .. "next step: all done")
  -- plain words: no internal macro names or status codes on the page
  H.ok(anyText(W, "WBX K%d") == nil and anyText(W, "noslot") == nil, tag .. "plain words on the page")
  -- every visible button has a tooltip
  local bare = {}
  for _, f in ipairs(W.frames) do
    if f._kind == "Button" and f._text and f:IsVisible() and not f._scripts.OnEnter then bare[#bare + 1] = f._text end
  end
  H.eq(table.concat(bare, ", "), "", tag .. "every button has a tooltip")
  -- the same on every tab: plain words, a tooltip on every button
  for _, t in ipairs(UI.tabs) do
    UI.Select(t.key)
    local words, noTip = {}, {}
    for _, f in ipairs(W.frames) do
      if f:IsVisible() and type(f._text) == "string" then
        if f._text:find("WBX [KSC]%d") or f._text:find("noslot") or f._text:find("skipped") then words[#words + 1] = f._text:sub(1, 40) end
        if f._kind == "Button" and not f._scripts.OnEnter then noTip[#noTip + 1] = f._text end
      end
    end
    H.eq(table.concat(words, " | "), "", tag .. t.key .. ": plain words")
    H.eq(table.concat(noTip, ", "), "", tag .. t.key .. ": every button has a tooltip")
  end
  UI.Select("keys")
  -- sequence tier (paladin/priest)
  if ns.Engine.seqSupported(scenario.class:lower()) then
    local p = UI.panels.keys
    p.seq.check:Click()
    H.ok(select(2, Core.me()).seq == "simple", tag .. "sequence keys on (Simple)")
    p.seq.tier.select("advanced")
    H.eq(select(2, Core.me()).seq, "advanced", tag .. "sequence tier from the dropdown")
    p.seq.check:Click()
    H.eq(select(2, Core.me()).seq, "off", tag .. "sequence keys off")
    p.seq.check:Click()
    H.eq(select(2, Core.me()).seq, "advanced", tag .. "ticking again keeps the tier")
  end
  -- squad tab: add a character
  UI.Select("squad")
  local panel = UI.panels.squad
  H.ok(panel.frames.home:IsShown(), tag .. "squad home first")
  ns.SquadPages.select(panel, "edit")
  findButton(W, "Add character"):Click()
  local s = Core.me()
  local row = panel.frames.edit.pool.rows[#s.members]
  row.name:SetText("Kirra"); row.name._scripts.OnEnterPressed(row.name)
  H.eq(s.members[#s.members].name, "Kirra", tag .. "character added")
  -- every squad page: plain words, a tooltip on every button
  for _, def in ipairs(ns.SquadPages.pages) do
    ns.SquadPages.select(panel, def.key)
    local noTip = {}
    for _, f in ipairs(W.frames) do
      if f._kind == "Button" and f._text and f:IsVisible() and not f._scripts.OnEnter then noTip[#noTip + 1] = f._text end
    end
    H.eq(table.concat(noTip, ", "), "", tag .. "squad " .. def.key .. ": every button has a tooltip")
  end
  ns.SquadPages.select(panel, "home")
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
  H.ok(anyText(W, "In combat") ~= nil, tag .. "combat explained in the next step")
  UI.panels.keys.cells[1]:Click("LeftButton")
  H.ok(not findButton(W, "Bind key"):IsEnabled(), tag .. "Bind key disabled in combat")
  W.combat = false
  -- slash commands
  W.env.SlashCmdList.WOWBOXER("help"); W.env.SlashCmdList.WOWBOXER("show"); W.env.SlashCmdList.WOWBOXER("log 3"); W.env.SlashCmdList.WOWBOXER("selftest")
  W.env.SlashCmdList.WOWBOXER("")
  H.ok(not UI.frame:IsShown(), tag .. "/wbx toggles the window")
  local errs = uiErrors(ns)
  H.eq(#errs, 0, tag .. "no errors logged: " .. table.concat(errs, " | "))
end


-- ------------------------------------------------------------------ layout at every resolution and UI scale
-- docs/ui-spec-v2.md §3: no text may overlap a button or another text, run out of its window or be cut off, and no
-- window may leave the screen – on every screen in Layout.MATRIX, in every state of the window.
local Layout = dofile(dir .. "/layout.lua")
local function layoutPass(screen, opts)
  opts = opts or {}
  local W, ns = boot({ name = opts.name or "Dorin", class = opts.class or "PALADIN", race = "Scourge", level = opts.level or 24,
    toc = opts.toc, spellbookStyle = opts.toc and "classic" or nil, screen = { w = screen.w, h = screen.h }, fontFactor = opts.fontFactor })
  for _, s in ipairs(ns.Data.spells[(opts.class or "PALADIN"):lower()]) do if s.level <= (opts.level or 24) then W.known[s.name] = true end end
  local UI, Core = ns.UI, ns.Core
  if opts.scale then Core.db.settings.scale = opts.scale end
  local problems = {}
  local function check(what, extra)
    for _, msg in ipairs(Layout.check(W, extra or { UI.frame })) do problems[#problems + 1] = what .. ": " .. msg end
  end
  UI.Open("keys")
  check("guide step 1")
  UI.panels.keys.guide.next:Click()
  check("guide step 2")
  findButton(W, "I'll drag them myself"):Click()
  check("guide step 3")
  findButton(W, "Close"):Click()
  for _, t in ipairs(UI.tabs) do UI.Select(t.key); check("tab " .. t.key) end
  -- a squad of three, every squad page
  local s = Core.me()
  for _, x in ipairs({ { "Wowtwo-Longname", "priest" }, { "Kirrathedestroyer", "warlock" } }) do
    table.insert(s.members, ns.State.newMember({ name = x[1], cls = x[2], race = "undead", unit = "party1", level = 24 }))
  end
  UI.Select("squad")
  for _, def in ipairs(ns.SquadPages.pages) do ns.SquadPages.select(UI.panels.squad, def.key); check("squad " .. def.key) end
  ns.SquadPages.select(UI.panels.squad, "keymap")
  ns.SquadPages.showCheatSheet(UI.panels.squad.frames.keymap)
  check("cheat sheet")
  UI.panels.squad.frames.keymap.sheet:Hide()
  ns.SquadPages.select(UI.panels.squad, "home")
  UI.Select("keys")
  local p = UI.panels.keys
  p.cells[3]:Click("LeftButton")
  check("key selected")
  p.capture:Start(p.selected, "Some key")
  check("key capture")
  p.capture:Stop()
  findButton(W, "Place all"):Click()
  check("after Place all")
  UI.Select("custom")
  UI.panels.custom.cells[1]:Click("LeftButton")
  check("key editor", { UI.frame })
  W.player.level = W.player.level + 4
  for _, s in ipairs(ns.Data.spells[(opts.class or "PALADIN"):lower()]) do if s.level <= W.player.level then W.known[s.name] = true end end
  W.fire("PLAYER_LEVEL_UP", W.player.level); W.fire("SPELLS_CHANGED"); W.flush()
  if UI.offer and UI.offer:IsShown() then check("level-up toast", { UI.offer }) end
  -- offer cards from another client (squad, preset) and the session card
  ns.Sync.offer({ kind = "squad", from = "Dorinverylongname", name = "The undead trio of doom", count = 3, str = "" })
  check("squad offer card", { ns.Sync.frame })
  ns.Sync.dismiss()
  ns.Sync.offer({ kind = "preset", from = "Wowtwo", name = "Dungeon – Wowtwo heals", leader = "Dorinverylongname", squadId = "x", presetId = "y" })
  check("preset offer card", { ns.Sync.frame })
  ns.Sync.dismiss()
  ns.Sync.offer({ kind = "session", from = "", text = "Squad The undead trio of doom · 3/3 online · keys OK on 1/3 · Wowtwo, Kirrathedestroyer need Update keys" })
  check("session card", { ns.Sync.frame })
  ns.Sync.dismiss()
  UI.Select("keys")
  check("keys after level-up")
  return problems
end
local total, shown = 0, 0
for _, screen in ipairs(Layout.MATRIX) do
  local probs = layoutPass(screen)
  total = total + #probs
  for _, m in ipairs(probs) do if shown < 12 then shown = shown + 1; print("  " .. screen.name .. " " .. m) end end
end
H.eq(total, 0, "layout: no overlaps on " .. #Layout.MATRIX .. " screens")
-- the worst case: long names, Classic Era, a wider real font, the biggest window scale on the smallest screen
for _, o in ipairs({
  { name = "Pellucidarian", class = "WARLOCK", level = 40, toc = 11509, fontFactor = 0.62 },
  { name = "Shadowpriest", class = "PRIEST", level = 30, fontFactor = 0.62, scale = 1.3 },
  { name = "Hunty", class = "HUNTER", level = 50, fontFactor = 0.62 },
}) do
  local probs = layoutPass({ w = 835, h = 668 }, o)
  for i, m in ipairs(probs) do if i <= 8 then print("  stress " .. o.class .. " " .. m) end end
  H.eq(#probs, 0, "layout stress " .. o.class .. " (font x" .. o.fontFactor .. ")")
end

os.exit(H.report("ui") and 0 or 1)
