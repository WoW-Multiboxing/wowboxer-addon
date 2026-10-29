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
  H.ok(anyText(W, "Place all puts your %d+ macros on Action Bar 1") ~= nil, tag .. "step 2 says where the keys go")
  H.eq(W.calls.CreateMacro, nil, tag .. "the guide writes nothing before the click")
  findButton(W, "Place all"):Click()
  H.eq(Core.compute().macros.changes, 0, tag .. "Place all creates everything")
  local onBar = 0
  for slot = 1, 12 do if (W.slotMacroName(slot) or ""):sub(1, 3) == "WBX" then onBar = onBar + 1 end end
  H.ok(onBar > 0, tag .. "keys on action bar 1")
  H.ok(anyText(W, "^Step 3 of 3") ~= nil, tag .. "guide step 3")
  findButton(W, "Close"):Click()
  H.ok(not guide:IsShown(), tag .. "guide closed")
  H.ok(anyText(W, "All macros on your bars") ~= nil or anyText(W, "All set") ~= nil, tag .. "next step: all done")
  local tl = ns.Squad.nextTrainer(select(2, Core.me()))
  if tl and tl <= scenario.level + 4 then
    H.ok(anyText(W, "trainer at " .. tl .. ": ") ~= nil, tag .. "the trainer to-do on the top line (level " .. tl .. ")")
  end
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
  H.ok(panel.frames.main:IsShown(), tag .. "the squad page first")
  local main = panel.frames.main
  if main.empty:IsShown() then main.empty.byName:Click() end
  main.add.name:SetText("Kirra"); main.add.cls.select("warlock"); main.add.go:Click()
  local s = Core.me()
  H.eq(s.members[#s.members].name, "Kirra", tag .. "character added by name")
  -- every squad page: plain words, a tooltip on every button
  for _, def in ipairs(ns.SquadPages.pages) do
    ns.SquadPages.select(panel, def.key)
    local noTip = {}
    for _, f in ipairs(W.frames) do
      if f._kind == "Button" and f._text and f:IsVisible() and not f._scripts.OnEnter then noTip[#noTip + 1] = f._text end
    end
    H.eq(table.concat(noTip, ", "), "", tag .. "squad " .. def.key .. ": every button has a tooltip")
  end
  ns.SquadPages.select(panel, "main")
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
    findButton(W, "Update"):Click()
    H.eq(Core.compute().macros.changes, 0, tag .. "toast updates keys")
  end
  -- combat: buttons disabled, nothing written
  W.combat = true
  UI.Select("keys")
  H.ok(anyText(W, "In combat") ~= nil, tag .. "combat explained in the next step")
  UI.panels.keys.cells[1]:Click("LeftButton")
  H.ok(not findButton(W, "Set keybind"):IsEnabled(), tag .. "Bind key disabled in combat")
  W.combat = false
  -- the "?" is a quest-style badge that stays inside its box and inside the window border
  do
    local hb, fr = W.rect(UI.helpBtn), W.rect(UI.frame)
    H.ok(hb and hb[1] >= fr[1] + 6 and hb[3] <= fr[3] - 6 and hb[4] <= fr[4] - 6, tag .. "help button inside the window border")
    for _, k in ipairs({ "rim", "bg", "icon", "glow" }) do
      local r = W.rect(UI.helpBtn[k])
      H.ok(r and r[1] >= hb[1] - 0.5 and r[3] <= hb[3] + 0.5 and r[2] >= hb[2] - 0.5 and r[4] <= hb[4] + 0.5, tag .. "help " .. k .. " inside its box")
    end
  end
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
  findButton(W, "Drag myself"):Click()
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
  -- the main page's states: the inline editor, Removed … Undo, the add line's reason, the delete confirm
  local SPm, sq = ns.SquadPages, UI.panels.squad
  SPm.select(sq, "main")
  sq.frames.main.pool.rows[2]:Click(); check("squad: inline editor")
  sq.frames.main.add.name:SetText("Kirrathedestroyer"); sq.frames.main.add.go:Click(); check("squad: add line refused")
  sq.frames.main.pool.rows[3].remove:Click(); check("squad: removed, undo"); sq.undo:Click()
  sq.squadPick.select("del"); check("squad: delete confirm"); sq.confirm.no:Click()
  sq.frames.main.pool.rows[2]:Click()
  ns.SquadPages.select(UI.panels.squad, "keymap")
  ns.SquadPages.showCheatSheet(UI.panels.squad.frames.keymap)
  check("cheat sheet")
  UI.panels.squad.frames.keymap.sheet:Hide()
  ns.SquadPages.select(UI.panels.squad, "main")
  UI.Select("keys")
  local p = UI.panels.keys
  p.cells[3]:Click("LeftButton")
  check("key selected")
  p.capture:Start(p.selected, "Some key")
  check("key capture")
  ns.Book.onBindKey(p.capture, "F"); check("key capture: question")
  p.capture:Stop()
  findButton(W, "Place all"):Click()
  check("after Place all")
  UI.Select("custom")
  UI.panels.custom.cells[1]:Click("LeftButton")
  check("key editor", { UI.frame })
  -- a full 255-character macro: wraps inside the box and needs no scrolling
  local KE = ns.KeyEditor
  local long = "#showtooltip\n/petattack [@mouseover,harm,nodead][@party1target,harm,nodead][]\n/castsequence [@mouseover,harm,nodead][@party1target,harm,nodead][] reset=combat Immolate, Corruption, Shadow Bolt"
  long = long .. string.rep("x", 255 - #long)
  local orig = KE.preview
  KE.preview = function() return { kind = "sequence", macro = long }, {} end
  KE.Refresh()
  KE.preview = orig
  local b, sf = W.rect(KE.frame.body), W.rect(KE.frame.macroSf)
  if b[3] > sf[3] + 0.5 or b[2] < sf[2] - 0.5 then problems[#problems + 1] = "key editor: 255-character macro not fully visible" end
  check("key editor, 255 characters")
  -- help on the editor, then close it
  UI.helpBtn:Click(); check("help overlay (editor)"); ns.Help.Hide()
  KE.Close()
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
  ns.Sync.offer({ kind = "session", from = "", text = "Squad The undead trio of doom · 3/3 online · keys OK on 1/3 · Wowtwo, Kirrathedestroyer need Update macros" })
  check("session card", { ns.Sync.frame })
  ns.Sync.dismiss()
  UI.Select("keys")
  check("keys after level-up")
  -- the talent import window with a link and warnings
  UI.Select("talents")
  for _, t in ipairs(UI.tabs) do if t.key == "talents" then t.openImport(UI.panels.talents) end end
  local imp = UI.panels.talents.imp
  imp.link:SetText("https://www.wowhead.com/forever/talent-calc/druid/v2410222-4_t3"); imp.link._scripts.OnTextChanged(imp.link)
  check("talent import window")
  imp:Hide()
  -- Advanced mode: the confirm, the Targeting and text windows, Reset to default (every step)
  local A = ns.Advanced
  UI.Select("keys")
  A.confirm(); check("advanced confirm"); A.confirmFrame.tick:Click(); A.confirmFrame.go:Click()
  local kp = UI.panels.keys
  local kc
  for _, b in ipairs(kp.cells) do if not kc and b:IsShown() and b.cell and b.cell.name then kc = b.cell end end
  if kc then
    A.openTargeting(kp, kc.name, kc.label)
    for i = 1, 4 do A.ef.tiles[i]:Click() end
    check("targeting window"); A.ef:Hide()
    A.openText(kp, kc.name, kc.label); check("macro text window"); A.xf:Hide()
  end
  A.openReset(); check("reset step 1")
  A.rf.next:Click(); check("reset step 2")
  A.rf:Hide()
  A.setMode(false)
  -- help overlays and the squad guide stay inside the window
  for _, key in ipairs({ "keys", "setup", "share" }) do
    UI.Select(key); UI.helpBtn:Click(); check("help overlay " .. key); ns.Help.Hide()
  end
  UI.Select("squad")
  for _, def in ipairs(ns.SquadPages.pages) do
    ns.SquadPages.select(UI.panels.squad, def.key); UI.helpBtn:Click(); check("help overlay squad " .. def.key); ns.Help.Hide()
  end
  ns.Help.ShowSquadGuide()
  for i = 1, 3 do check("squad guide " .. i); ns.Help.guide.next:Click() end
  -- the empty state of a new squad (one character), with a party to use
  ns.SquadPages.newSquad(); check("squad: empty state")
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
