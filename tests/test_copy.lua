-- Copy rules (docs/ui-spec-v3-book.md): walk every visible text in every tab and state and check the word budgets
-- (labels ≤ 3 words, buttons ≤ 2 (a page's big action ≤ 5), status ≤ 2, hints ≤ 8 per line, sentences only in tooltips/guides), no truncated
-- spell or helper names, no section header in a grid cell, nothing across the book's spine, a 255-character macro
-- fully visible in the key editor, and a "?" with a tooltip and 3–5 callouts on every page.
local dir = (arg[0]:match("^(.*)/[^/]+$") or ".")
local H = dofile(dir .. "/harness.lua")
local Mock = dofile(dir .. "/wowmock.lua")
local Layout = dofile(dir .. "/layout.lua")

local BUDGET = { label = 3, status = 2, hint = 8, warn = 12, sentence = 14, guide = 24 }

local function boot(opts)
  local W = Mock.new(H, opts)
  local ns = H.loadAddon({ env = W.env })
  W.fire("ADDON_LOADED", "WoWBoxer"); W.fire("PLAYER_LOGIN")
  for _, s in ipairs(ns.Data.spells[(opts.class or "PALADIN"):lower()]) do if s.level <= (opts.level or 10) then W.known[s.name] = true end end
  if ns.Help then ns.Help.forceOwn = true end
  return W, ns
end
local function plain(W, t) return (W.plain(t):gsub("^%s+", ""):gsub("%s+$", "")) end
--- Words that count: tokens with a letter (numbers, "·", "–", "›", "×4" do not).
local function words(line)
  local n = 0
  for tok in line:gmatch("%S+") do if tok:find("%a") then n = n + 1 end end
  return n
end
local function sentences(line)
  local n = 0
  for _ in (line .. " "):gmatch("[%.!?]%s") do n = n + 1 end
  return n
end
local function ancestorOf(a, f) local p = f._parent; while p do if p == a then return true end p = p._parent end return false end
local function isDropdownLabel(f) local p = f._parent; return p and rawget(p, "opts") ~= nil and rawget(p, "label") == f end

--- Budget problems of everything visible under root.
local function copyProblems(W, root, what)
  local out = {}
  for _, f in ipairs(W.frames) do
    if (f == root or ancestorOf(root, f)) and f:IsVisible() and type(rawget(f, "_text")) == "string" then
      local text = plain(W, f._text)
      if text ~= "" then
        if f._kind == "Button" then
          -- the one big action of a page (b.wbxBig: "Send to my other characters", docs/squad-v2-simple.md) may use 5
          local max = rawget(f, "wbxBig") and 5 or 2
          if words(text) > max then out[#out + 1] = what .. ": button over " .. max .. " words: \"" .. text .. "\"" end
        elseif f._kind == "FontString" and not isDropdownLabel(f) then
          local cls = rawget(f, "wbxCopy") or "hint"
          local max = BUDGET[cls]
          if max then
            for line in (text .. "\n"):gmatch("([^\n]*)\n") do
              if words(line) > max then out[#out + 1] = what .. ": " .. cls .. " over " .. max .. " words: \"" .. line:sub(1, 70) .. "\"" end
              if (cls == "label" or cls == "status" or cls == "hint") and sentences(line) > 1 then
                out[#out + 1] = what .. ": more than one sentence in a " .. cls .. ": \"" .. line:sub(1, 70) .. "\""
              end
              if (cls == "sentence" or cls == "guide") and sentences(line) > 1 then
                out[#out + 1] = what .. ": " .. cls .. " has more than one sentence: \"" .. line:sub(1, 70) .. "\""
              end
            end
          end
          -- names are never cut: they fit their lines
          if rawget(f, "wbxName") then
            local r = W.rect(f)
            local width = r and (r[3] - r[1]) / W.factor(f) or nil
            local need = W.textLines(f._text, f._fontSize or 12, width)
            local room = rawget(f, "_maxLines") or 1
            if f._wrap == false then room = 1 end
            if text:find("…", 1, true) or text:find("%.%.%.") or need > room then out[#out + 1] = what .. ": name cut off: \"" .. text .. "\"" end
          end
        end
      end
    end
  end
  return out
end

--- Book pages: no header in a grid cell, nothing across the spine.
local function bookProblems(W, ns, key, what)
  local out = {}
  local UI = ns.UI
  local p = UI.panels[key]
  for _, b in ipairs(p.cells or {}) do
    if b:IsShown() and b.cell and (b.cell.kind == "header" or b.cell.kind == "pad" or rawget(b, "wbxRule")) then out[#out + 1] = what .. ": header in a grid cell" end
  end
  local sp = W.rect(UI.spine)
  local modals = {}
  for _, f in ipairs(W.frames) do if f:IsVisible() and rawget(f, "wbxModal") and ancestorOf(p, f) then modals[#modals + 1] = f end end
  for _, f in ipairs(W.frames) do
    if (f._kind == "FontString" or f._kind == "Button") and f:IsVisible() and ancestorOf(p, f) then
      local covered = false
      for _, m in ipairs(modals) do if f == m or ancestorOf(m, f) then covered = true end end
      local r = not covered and W.rect(f)
      if r and (f._kind == "Button" or plain(W, f._text) ~= "") and r[1] < sp[3] - 0.5 and r[3] > sp[1] + 0.5 then
        out[#out + 1] = what .. ": crosses the spine: " .. f._kind .. " \"" .. plain(W, f._text or ""):sub(1, 30) .. "\""
      end
    end
  end
  return out
end

local problems = {}
local function add(list) for _, m in ipairs(list) do problems[#problems + 1] = m end end

-- ------------------------------------------------------------------ every tab in several states
for _, sc in ipairs({
  { name = "Fresh", class = "WARLOCK", level = 4, fresh = true },
  { name = "Warlocker", class = "WARLOCK", level = 20, party = { party1 = "Leadername" }, follower = true },
  { name = "Hunty", class = "HUNTER", level = 30 },
  { name = "Dorin", class = "PALADIN", level = 24, seq = "medium" },
  { name = "Wowtwo", class = "PRIEST", level = 10, levelUp = true, fontFactor = 0.62 },
}) do
  local W, ns = boot(sc)
  local UI, Core = ns.UI, ns.Core
  local tag = sc.class .. " " .. sc.name
  UI.Open("keys")
  local p = UI.panels.keys
  if sc.fresh then
    add(copyProblems(W, UI.frame, tag .. " guide 1"))
    p.guide.next:Click(); add(copyProblems(W, UI.frame, tag .. " guide 2"))
    p.guide.drag:Click(); add(copyProblems(W, UI.frame, tag .. " guide 3"))
    p.guide.done:Click()
  else
    Core.cdb.guide = "done"
  end
  if sc.follower then
    local s = Core.me()
    table.insert(s.members, 1, ns.State.newMember({ name = "Leadername", cls = "paladin", race = "undead", role = "tank", leader = true }))
    for _, m in ipairs(s.members) do m.leader = m.name == "Leadername" end
    Core.changed()
  end
  if sc.seq then local _, m = Core.me(); m.seq = sc.seq; Core.changed() end
  Core.sync({})
  if sc.levelUp then
    W.player.level = W.player.level + 10
    for _, s in ipairs(ns.Data.spells[sc.class:lower()]) do if s.level <= W.player.level then W.known[s.name] = true end end
    W.fire("PLAYER_LEVEL_UP", W.player.level); W.fire("SPELLS_CHANGED"); W.flush()
    H.ok(UI.offer and UI.offer:IsShown(), tag .. ": level-up toast")
    if UI.offer and UI.offer:IsShown() then add(copyProblems(W, UI.offer, tag .. " toast")) end
    H.ok((p.stepText:GetText() or ""):find("macros? changed") ~= nil, tag .. ": banner \"N keys changed\": " .. tostring(p.stepText:GetText()))
  end
  UI.Refresh()
  -- header and footer
  local who = plain(W, UI.who:GetText())
  H.ok(who:match("^[^·]+ · %a+ %d+ · %a+$") ~= nil, tag .. ": header \"Name · Class N · Leader/Follower\": " .. who)
  H.ok((p.slots:GetText() or ""):match("^%d+/%d+ macros$") ~= nil, tag .. ": footer \"N/M macros\": " .. tostring(p.slots:GetText()))
  -- helpers: the right section, short names, small buttons
  local helpers = {}
  for _, b in ipairs(p.helperPool or {}) do if b:IsVisible() then helpers[#helpers + 1] = b.name:GetText() end end
  if sc.follower then
    H.ok(table.concat(helpers, ","):find("Follow (line),Follow leader,Assist", 1, true) ~= nil, tag .. ": follower helpers: " .. table.concat(helpers, ","))
  end
  if sc.class == "HUNTER" then
    local title
    for _, r in ipairs(p.rules) do if r:IsVisible() and r._parent == p.right then title = r.text:GetText() end end
    H.eq(title, "Squad macros", tag .. ": a leader with a pet sees the Squad macros section")
  end
  if sc.class == "PALADIN" and sc.name == "Dorin" then
    local seq
    for _, b in ipairs(p.cells) do if b:IsVisible() and b.cell and b.cell.badge then seq = b end end
    H.ok(seq ~= nil and seq.sub:GetText():find("›", 1, true) ~= nil, tag .. ": sequence shows its steps short: " .. tostring(seq and seq.sub:GetText()))
  end
  for _, t in ipairs(UI.tabs) do
    UI.Select(t.key)
    add(copyProblems(W, UI.frame, tag .. " " .. t.key))
    if t.book then add(bookProblems(W, ns, t.key, tag .. " " .. t.key)) end
    if t.key == "squad" then
      for _, def in ipairs(ns.SquadPages.pages) do
        ns.SquadPages.select(UI.panels.squad, def.key)
        add(copyProblems(W, UI.frame, tag .. " squad " .. def.key))
      end
      ns.SquadPages.select(UI.panels.squad, "main")
    end
  end
  -- the key editor
  UI.Select("custom")
  UI.panels.custom.cells[1]:Click("LeftButton")
  ns.KeyEditor.addStep(ns.KeyEditor.spellChoices(select(2, Core.me()), W.player.level)[1].name)
  add(copyProblems(W, UI.frame, tag .. " key editor"))
  ns.KeyEditor.Close()
  -- Advanced mode windows (copy budgets)
  do
    local A = ns.Advanced
    UI.Select("keys")
    A.confirm(); add(copyProblems(W, A.confirmFrame, tag .. " advanced confirm")); A.confirmFrame:Hide()
    A.setMode(true)
    local kc
    for _, b in ipairs(UI.panels.keys.cells) do if not kc and b:IsShown() and b.cell and b.cell.name then kc = b.cell end end
    if kc then
      A.openTargeting(UI.panels.keys, kc.name, kc.label); add(copyProblems(W, A.ef, tag .. " targeting")); A.ef:Hide()
      A.openText(UI.panels.keys, kc.name, kc.label); add(copyProblems(W, A.xf, tag .. " macro text")); A.xf:Hide()
    end
    ns.AutomationPage.Open(); add(copyProblems(W, ns.AutomationPage.frame, tag .. " automation")); ns.AutomationPage.frame:Hide()
    A.openReset(); add(copyProblems(W, A.rf, tag .. " reset 1")); A.rf.next:Click(); add(copyProblems(W, A.rf, tag .. " reset 2")); A.rf:Hide()
    A.setMode(false)
  end
  -- offer cards
  ns.Sync.offer({ kind = "squad", from = "Dorinverylongname", name = "The undead trio of doom", count = 3, str = "" })
  add(copyProblems(W, ns.Sync.frame, tag .. " squad card")); ns.Sync.dismiss()
  ns.Sync.offer({ kind = "preset", from = "Wowtwo", name = "Dungeon", leader = "Dorin", squadId = "x", presetId = "y" })
  add(copyProblems(W, ns.Sync.frame, tag .. " preset card")); ns.Sync.dismiss()
end

-- ------------------------------------------------------------------ the key editor shows a whole 255-character macro
local LONG = "#showtooltip\n/petattack [@mouseover,harm,nodead][@party1target,harm,nodead][]\n" ..
  "/castsequence [@mouseover,harm,nodead][@party1target,harm,nodead][] reset=combat Immolate, Corruption, Shadow Bolt, Curse of Agony, Shadow Bolt"
LONG = LONG .. string.rep("x", 255 - #LONG)
--- Problems with the long macro in the editor (shared with the resolution matrix in test_ui).
local function longMacro(W, ns, what)
  local out = {}
  local KE = ns.KeyEditor
  local orig = KE.preview
  KE.preview = function() return { kind = "sequence", macro = LONG }, {} end
  KE.Refresh()
  KE.preview = orig
  local f = KE.frame
  local b, sf = W.rect(f.body), W.rect(f.macroSf)
  if not (b and sf) then return { what .. ": macro box not placed" } end
  if b[3] > sf[3] + 0.5 then out[#out + 1] = what .. ": macro text runs off to the right" end
  if b[2] < sf[2] - 0.5 then out[#out + 1] = what .. string.format(": 255 characters need scrolling (%d > %d)", b[4] - b[2], sf[4] - sf[2]) end
  if not (f.info:GetText() or ""):find("255/255", 1, true) then out[#out + 1] = what .. ": counter shows " .. tostring(f.info:GetText()) end
  return out
end
for _, ff in ipairs({ 0.55, 0.62 }) do
  local W, ns = boot({ name = "Lock", class = "WARLOCK", level = 20, fontFactor = ff })
  ns.UI.Open("custom")
  ns.UI.panels.custom.cells[1]:Click("LeftButton")
  local before = #problems
  add(longMacro(W, ns, "font x" .. ff))
  H.eq(#problems - before, 0, "a 255-character macro is fully visible in the key editor (font x" .. ff .. ")")
  add(Layout.check(W, { ns.UI.frame }))
end

-- ------------------------------------------------------------------ a "?" on every page: tooltip + 3–5 callouts
do
  local W, ns = boot({ name = "Warlocker", class = "WARLOCK", level = 20, party = { party1 = "Dorin" } })
  local UI, Help, Core = ns.UI, ns.Help, ns.Core
  UI.Open("keys")
  Core.cdb.guide = "done"
  local s = Core.me()
  table.insert(s.members, 1, ns.State.newMember({ name = "Dorin", cls = "paladin", race = "undead", role = "tank", leader = true }))
  for _, m in ipairs(s.members) do m.leader = m.name == "Dorin" end
  Core.changed()
  local seen = {}
  local function visit(key, go)
    go()
    seen[key] = true
    H.eq(Help.pageKey(), key, "page key " .. key)
    H.ok(UI.helpBtn:IsVisible(), key .. ": ? shown")
    local lines = {}
    local GT = W.env.GameTooltip
    local old = GT.AddLine
    GT.AddLine = function(_, t) lines[#lines + 1] = t end
    UI.helpBtn._scripts.OnEnter(UI.helpBtn)
    GT.AddLine = old
    H.ok(#lines >= 3 and #lines <= 5, key .. ": tooltip has 2–4 short lines (" .. #lines .. ")")
    for _, l in ipairs(lines) do if words(l) > 12 then problems[#problems + 1] = key .. ": tooltip line too long: " .. l end end
    local list = Help.callouts(key)
    H.ok(#list >= 3 and #list <= 5, key .. ": 3–5 callouts (" .. #list .. ")")
    for _, c in ipairs(list) do
      if words(c[2]) > 8 then problems[#problems + 1] = key .. ": callout over 8 words: " .. c[2] end
      if not c[1]:IsVisible() then problems[#problems + 1] = key .. ": callout on a hidden control" end
    end
    UI.helpBtn:Click()
    H.ok(Help.IsShown(), key .. ": click shows the help overlay")
    local o = Help.overlay
    local orr = W.rect(o)
    for i = 1, #list do
      local r = W.rect(o.badges[i])
      if not (r and r[1] >= orr[1] - 0.5 and r[3] <= orr[3] + 0.5 and r[2] >= orr[2] - 0.5 and r[4] <= orr[4] + 0.5) then
        problems[#problems + 1] = key .. ": callout " .. i .. " outside the window"
      end
    end
    add(copyProblems(W, o, key .. " overlay"))
    for _, m in ipairs(Layout.check(W, { UI.frame })) do problems[#problems + 1] = key .. " overlay: " .. m end
    o._scripts.OnClick(o)
    H.ok(not Help.IsShown(), key .. ": a click closes it")
  end
  for _, t in ipairs(UI.tabs) do
    if t.key == "squad" then
      for _, def in ipairs(ns.SquadPages.pages) do
        visit("squad:" .. def.key, function() UI.Select("squad"); ns.SquadPages.select(UI.panels.squad, def.key) end)
      end
    else
      visit(t.key, function() UI.Select(t.key) end)
    end
  end
  visit("editor", function() UI.Select("custom"); UI.panels.custom.cells[1]:Click("LeftButton") end)
  ns.KeyEditor.Close()
  for key in pairs(Help.PAGES) do H.ok(seen[key], "help page visited: " .. key) end
  -- first visit pulses once
  local st = Core.db.settings.helpSeen
  H.ok(st and st.keys and st.share, "pages remember the first visit")
  local n = #W.playing
  UI.Select("share")
  H.eq(#W.playing, n, "no second pulse on a page already seen")
  -- the squad guide: 3 steps, a button each, progress dots
  W.env.SlashCmdList.WOWBOXER("show")
  Help.ShowSquadGuide()
  local g = Help.guide
  H.ok(g:IsVisible(), "squad guide open")
  local titles = {}
  for i = 1, 3 do
    titles[#titles + 1] = g.step:GetText()
    H.ok(g.act:IsVisible() and words(g.act:GetText()) <= 2, "step " .. i .. " has its button: " .. tostring(g.act:GetText()))
    add(copyProblems(W, g, "squad guide " .. i))
    for _, m in ipairs(Layout.check(W, { UI.frame })) do problems[#problems + 1] = "squad guide " .. i .. ": " .. m end
    g.next:Click()
  end
  H.eq(table.concat(titles, "|"), "1. Add your characters|2. Pick the leader|3. Send to your other characters", "the three steps")
  H.ok(not g:IsVisible(), "Done closes the guide")
  -- offered once when a second character joins the party
  Core.db.settings.squadGuideOffered = nil
  H.ok(Help.checkOffer(), "offered when a second character is in the party")
  H.ok(ns.Sync.frame:IsShown() and ns.Sync.frame.go:GetText() == "Open guide", "as a card with Open guide")
  H.ok(not Help.checkOffer(), "only once")
  ns.Sync.frame.go:Click()
  H.ok(g:IsVisible(), "Open guide opens it")
  H.eq(W.calls.CreateMacro, nil, "help and guide write nothing to the game")
end

for i, m in ipairs(problems) do if i <= 40 then print("  " .. m) end end
H.eq(#problems, 0, "copy rules, names, spine, callouts")
os.exit(H.report("copy") and 0 or 1)
