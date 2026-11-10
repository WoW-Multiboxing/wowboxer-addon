-- Discord #help batch (10 Nov 2026, WS-H -> WS-E): extra lines optional (A), auto greed (B) and bugs 1–8.
-- Every class, role and game for the macro rules; the UI fixes in the simulated client.
local dir = (arg[0]:match("^(.*)/[^/]+$") or ".")
local H = dofile(dir .. "/harness.lua")
local Mock = dofile(dir .. "/wowmock.lua")

local GAMES = { { "forever", 16001, "camelot" }, { "era", 11509 }, { "tbc", 20506 } }
local CLASSES = { "warrior", "rogue", "druid", "mage", "priest", "warlock", "hunter", "paladin", "shaman" }

--- /cast and /castsequence lines of a body: {{cmd, conds, names = {…}}}
local function castLines(body)
  local out = {}
  for line in (body .. "\n"):gmatch("([^\n]*)\n") do
    local cmd, rest = line:match("^(/castsequence) (.*)$")
    if not cmd then cmd, rest = line:match("^(/cast) (.*)$") end
    if cmd then
      local conds, i = "", 1
      while rest:sub(i, i) == "[" do local j = rest:find("]", i, true); if not j then break end conds = conds .. rest:sub(i, j); i = j + 1 end
      local tail = rest:sub(i):gsub("^%s+", ""):gsub("^reset=%S+%s+", "")
      local names = {}
      for item in (tail .. ", "):gmatch("(.-), ") do names[#names + 1] = (item:gsub("^!", "")) end
      out[#out + 1] = { cmd = cmd, conds = conds, names = names }
    end
  end
  return out
end

-- ------------------------------------------------------------------ bug 1 + A: every class, role, game
for _, game in ipairs(GAMES) do
  local W = Mock.new(H, { toc = game[2] })
  local ns = H.loadAddon({ env = W.env, gameType = game[3] })
  local E, M, K, S = ns.Engine, ns.Macros, ns.Kit, ns.State
  local tag = game[1] .. ": "
  local function member(o)
    local m = { id = "a", name = "A", race = "human", level = 1, unit = "party1", seq = "advanced" }
    for k, v in pairs(o) do m[k] = v end
    return S.newMember(m)
  end
  local bad, wrongAim, extraOff, longs, checked = {}, {}, {}, {}, 0
  for _, cls in ipairs(CLASSES) do
    for _, role in ipairs((ns.Data.classes[cls] or {}).roles or {}) do
      for _, lead in ipairs({ true, false }) do
        for _, L in ipairs({ 10, 30, E.maxLevel() }) do
          local who = cls .. " " .. role .. (lead and " leader" or " follower") .. " L" .. L
          local m = member({ cls = cls, role = role, leader = lead, level = L })
          local byName = {}
          for _, s in ipairs(K.customSpellsOf(m)) do byName[s.name] = s end
          -- every friendly and every hostile spell also as an own single-spell macro with the WRONG aim (Kerafyrm)
          local custom, n = {}, 0
          for _, s in ipairs(K.spellsOf(m)) do
            local own = E.ownAim(s)
            if own and K.learned(m, s, L) and n < 8 then
              n = n + 1
              custom[#custom + 1] = { id = n, name = "T" .. n, kind = "priority", aim = own == "help" and "harm" or "help", steps = { s.name } }
            end
          end
          m.customSeq = S.cleanCustom(custom)
          local function check(list, off)
            for _, d in ipairs(list) do
              if d.body ~= "" and d.group ~= "helper" then
                checked = checked + 1
                if #d.body > 255 then longs[#longs + 1] = who .. " " .. d.key end
                local lines = castLines(d.body)
                local allHelp = #lines > 0
                for _, l in ipairs(lines) do
                  local harm, help = l.conds:find("harm", 1, true) ~= nil, l.conds:find("help", 1, true) ~= nil
                  if not help then allHelp = false end
                  for _, nm in ipairs(l.names) do
                    local s = byName[nm]
                    local own = s and E.ownAim(s)
                    if s and s.action ~= "dual" then
                      if own == "help" and harm and not help then wrongAim[#wrongAim + 1] = who .. " " .. d.key .. ": friendly " .. nm .. " in a harm chain" end
                      if own == "harm" and help and not harm then wrongAim[#wrongAim + 1] = who .. " " .. d.key .. ": hostile " .. nm .. " in a help chain" end
                    end
                  end
                end
                if allHelp and (d.body:find("/assist", 1, true) or d.body:find("!Shoot", 1, true) or d.body:find("/petattack", 1, true)) then
                  bad[#bad + 1] = who .. " " .. d.key .. ": a friendly key with an extra line"
                end
                if off then
                  local own = d.spell and d.spell.action
                  local engage = own == "engage" or (d.seq and d.seq.kind == "engage")
                  if d.body:find("!Shoot", 1, true) and not (d.spell and d.spell.gate == "wand") then extraOff[#extraOff + 1] = who .. " " .. d.key .. ": wand line" end
                  if d.body:find("!Auto Shot", 1, true) and own ~= "autoshot" and not engage then extraOff[#extraOff + 1] = who .. " " .. d.key .. ": Auto Shot line" end
                  if d.body:find("/startattack", 1, true) and not engage then extraOff[#extraOff + 1] = who .. " " .. d.key .. ": start attack" end
                  if d.body:find("/petattack", 1, true) then extraOff[#extraOff + 1] = who .. " " .. d.key .. ": pet attack" end
                  if d.body:find("/assist", 1, true) then extraOff[#extraOff + 1] = who .. " " .. d.key .. ": assist" end
                end
              end
            end
          end
          check(M.desired(m, L, {}), false)
          -- A: every switch off = none of those lines in any macro or sequence step
          m.lines = S.cleanLines({ wand = false, autoshot = false, startattack = false, petattack = false })
          m.assist = false
          check(M.desired(m, L, {}), true)
        end
      end
    end
  end
  H.ok(checked > 500, tag .. "checked " .. checked .. " macros")
  H.eq(#wrongAim, 0, tag .. "bug 1: no friendly spell in a harm key, no hostile spell in a help key" .. (wrongAim[1] and (" – " .. wrongAim[1]) or ""))
  H.eq(#bad, 0, tag .. "bug 1: friendly keys never get a wand, pet or /assist line" .. (bad[1] and (" – " .. bad[1]) or ""))
  H.eq(#extraOff, 0, tag .. "A: switches off = no extra line anywhere" .. (extraOff[1] and (" – " .. extraOff[1]) or ""))
  H.eq(#longs, 0, tag .. "every macro fits 255" .. (longs[1] and (" – " .. longs[1]) or ""))

  -- Kerafyrm's macro: a damage priest's own single-spell Power Word: Shield (enemy aim) is a friendly key now
  local pri = member({ cls = "priest", role = "ranged", level = 30 })
  pri.customSeq = S.cleanCustom({ { id = 1, name = "Shield", kind = "priority", aim = "harm", steps = { "Power Word: Shield" } } })
  local c1
  for _, d in ipairs(M.desired(pri, 30, {})) do if d.key == "C1" then c1 = d end end
  H.ok(c1 and c1.body:find("[@mouseover,help,nodead][@party1,help,nodead][@player] Power Word: Shield", 1, true) ~= nil,
    tag .. "PW:S own macro: the friendly chain: " .. tostring(c1 and c1.body))
  H.ok(c1 and not c1.body:find("!Shoot", 1, true) and not c1.body:find("harm", 1, true), tag .. "PW:S own macro: no wand, no enemy chain")
  -- a mixed priority key: each spell on its own kind of target
  pri.customSeq = S.cleanCustom({ { id = 1, name = "Mix", kind = "priority", aim = "harm", steps = { "Smite", "Flash Heal" } } })
  for _, d in ipairs(M.desired(pri, 30, {})) do if d.key == "C1" then c1 = d end end
  if c1 and c1.body:find("Flash Heal", 1, true) then
    H.ok(c1.body:find("harm,nodead] Smite", 1, true) and c1.body:find("help,nodead][@player] Flash Heal", 1, true), tag .. "mixed key: Smite harm, Flash Heal help")
  end

  -- A: per macro beats the switch, survives level-ups; the key shows which extra lines it has
  local mage = member({ cls = "mage", role = "ranged", level = 30 })
  local function bodies(m2, L, keyLines) local t = {}; for _, d in ipairs(M.desired(m2, L, { keyLines = keyLines })) do t[d.key] = d end return t end
  local on = bodies(mage, 30)
  H.ok(on.K1 and on.K1.body:find("!Shoot", 1, true), tag .. "mage K1 has the wand line by default")
  local ls = M.linesOf(on.K1, nil)
  local keys = {}
  for _, x in ipairs(ls) do keys[#keys + 1] = x.key .. "=" .. tostring(x.on) end
  H.eq(table.concat(keys, ","), "wand=true,assist=true", tag .. "K1's extra lines: " .. table.concat(keys, ","))
  local per = { ["WBX K1"] = { wand = false } }
  local t = bodies(mage, 30, per)
  H.ok(not t.K1.body:find("!Shoot", 1, true), tag .. "per macro: wand off in K1")
  H.ok(t.K2 and t.K2.body:find("!Shoot", 1, true), tag .. "the others keep it")
  H.ok(not bodies(mage, 60, per).K1.body:find("!Shoot", 1, true), tag .. "and it survives a level-up")
  mage.lines = { wand = false }
  t = bodies(mage, 30, { ["WBX K1"] = { wand = true } })
  H.ok(t.K1.body:find("!Shoot", 1, true), tag .. "per macro on beats the switch off")
  H.ok(not t.K2.body:find("!Shoot", 1, true), tag .. "the switch turns it off in the others")
  -- the Wand squad macro and Shoot in All spells stay
  local w
  for _, d in ipairs(M.desired(mage, 30, { squadKeys = {}, extras = { "wand" } })) do if d.key == "Wand" then w = d end end
  H.ok(w and w.body:find("!Shoot", 1, true), tag .. "the Wand squad macro stays with the switch off")
end

-- ------------------------------------------------------------------ the simulated client
local function boot(opts)
  local W = Mock.new(H, opts)
  local ns = H.loadAddon({ env = W.env, gameType = opts.gameType })
  W.fire("ADDON_LOADED", "WoWBoxer"); W.fire("PLAYER_LOGIN")
  ns.Core.cdb.guide = "done"
  ns.Core.ensureMe()
  for _, s in ipairs(ns.Data.spells[(opts.class or "PALADIN"):lower()] or {}) do if s.level <= (opts.level or 10) and s.gate ~= "talent" then W.known[s.name] = true end end
  return W, ns
end
local function errors(ns)
  local n = {}
  for _, e in ipairs(ns.Core.db.log) do if e.l == "error" then n[#n + 1] = e.m end end
  return n
end
local function byKey(ns) local t = {}; for _, d in ipairs(ns.Core.compute().desired) do t[d.key] = d end return t end

-- A in the client: switches on Setup and the Squad page, card icons, the menu, the editor, Copy settings
do
  local W, ns = boot({ name = "Wowtwo", class = "MAGE", race = "Human", level = 30, party = { party1 = "Dorin" },
    partyInfo = { party1 = { class = "PALADIN", race = "Human", level = 30, leader = true } } })
  local Core, UI = ns.Core, ns.UI
  Core.setPlaysAs("party1")
  local s, me = Core.me()
  s.members[1].name = "Dorin"
  H.ok(byKey(ns).K1.body:find("!Shoot", 1, true), "client: the wand line by default")
  UI.Open("setup")
  local wandCheck
  for _, c in ipairs(UI.panels.setup.lineChecks) do if c.def.key == "wand" then wandCheck = c end end
  H.ok(wandCheck and wandCheck:IsShown() and wandCheck:GetChecked(), "Setup: Wand in damage macros, ticked")
  wandCheck:Click()
  H.eq(me.lines and me.lines.wand, false, "Setup: off for this character (on the member)")
  H.ok(not byKey(ns).K1.body:find("!Shoot", 1, true), "no wand line in K1 now")
  H.eq(W.calls.CreateMacro, nil, "a switch writes no macro (Update does)")
  -- Copy settings carries it, and Advanced mode (bug 8)
  ns.Core.db.settings.advanced = true
  local enc = ns.Settings.encode()
  H.ok(enc:find("ln=wand", 1, true) ~= nil, "Copy settings sends the extra lines: " .. enc)
  H.ok(enc:find("adv=1", 1, true) ~= nil, "and Advanced mode (bug 8)")
  me.lines = nil
  ns.Settings.apply(ns.Settings.decode(enc), "Rip")
  H.eq(me.lines and me.lines.wand, false, "a character that takes them gets the same switch")
  me.lines = nil
  -- the Squad page: the member's own switches
  H.eq(ns.Settings.diff(ns.Settings.decode("ln="))[1] == nil, true, "all on = nothing to change")
  -- card icons on My macros: one click turns the wand off in this macro only
  UI.Open("keys")
  local p = UI.panels.keys
  local card
  for _, b in ipairs(p.cells or {}) do if b:IsShown() and b.cell and b.cell.name == "WBX K1" then card = b end end
  H.ok(card ~= nil, "K1's card")
  local icon
  for _, lb in ipairs(card and card.lineBtns or {}) do if lb:IsShown() and lb.key == "wand" then icon = lb end end
  H.ok(icon ~= nil and icon.on, "K1's card has a Wand icon, on")
  icon:Click()
  H.eq(Core.cdb.keyLines and Core.cdb.keyLines["WBX K1"] and Core.cdb.keyLines["WBX K1"].wand, false, "one click: wand off in K1 only")
  local k = byKey(ns)
  H.ok(not k.K1.body:find("!Shoot", 1, true) and k.K2.body:find("!Shoot", 1, true), "K1 without, K2 with")
  -- the right-click menu says the same and can turn it on again
  local items = ns.Advanced.menuItems(p, { name = "WBX K1", kind = "key", d = k.K1 })
  local found, back
  for _, it in ipairs(items) do
    if it[1] == "Turn on Wand in this macro" then found = it end
    if it[1] == "Back to WoWBoxer's version" then back = it end
  end
  H.ok(found ~= nil, "menu: Turn on Wand in this macro")
  H.ok(back ~= nil, "menu: WoWBoxer's version (an own extra-line choice)")
  back[2]()
  H.eq(Core.cdb.keyLines, nil, "WoWBoxer's version clears the per-macro choice")
  -- the Macro editor's Options: the same ticks, with the preview
  ns.Core.db.settings.advanced = true
  ns.Advanced.openEditor(p, "WBX K1", "K1")
  local ef = ns.Advanced.ef
  local tick
  for _, c in ipairs(ef.lineChecks) do if c:IsShown() and c.key == "wand" then tick = c end end
  H.ok(tick ~= nil and tick:GetChecked(), "editor Options: Wand ticked")
  tick:Click()
  H.ok(not ef.body:find("!Shoot", 1, true), "editor preview without the wand line")
  ef.save:Click()
  H.eq(Core.cdb.keyLines and Core.cdb.keyLines["WBX K1"].wand, false, "Save keeps it for K1")
  H.eq(#errors(ns), 0, "no errors (A) " .. table.concat(errors(ns), " | "))
end

-- Squad page: the switches of the selected member
do
  local W, ns = boot({ name = "Hunty", class = "HUNTER", race = "Orc", level = 30 })
  local Core, UI = ns.Core, ns.UI
  Core.setPlaysAs("party1") -- a squad of two (one character shows the empty state)
  local _, me = Core.me()
  UI.Open("squad")
  ns.SquadPages.editing = me.id
  ns.SquadPages.select(UI.panels.squad, "main")
  UI.Refresh()
  local shown = {}
  for _, f in ipairs(W.frames) do
    if f._kind == "CheckButton" and f.def and f:IsVisible() and f.label and f.label:GetText() == "Pet attack" then shown[#shown + 1] = f end
  end
  if #shown > 0 then
    shown[1]:Click()
    H.eq(me.lines and me.lines.petattack, false, "Squad page: Pet attack off for this member")
    for _, d in ipairs(Core.compute().desired) do
      if d.group ~= "helper" then H.ok(not d.body:find("/petattack", 1, true), "no /petattack in " .. d.key) end
    end
  end
  H.eq(#shown, 1, "Squad page: the member editor shows Pet attack for a hunter")
  local wandShown = false
  for _, f in ipairs(W.frames) do if f._kind == "CheckButton" and f.def and f:IsVisible() and f.def.key == "wand" then wandShown = true end end
  H.ok(not wandShown, "and no Wand switch (hunters have no wand line)")
end

-- ------------------------------------------------------------------ bug 2: Edit text opens for every kind
do
  local W, ns = boot({ name = "Retik", class = "PRIEST", race = "Human", level = 30 })
  local Core, UI = ns.Core, ns.UI
  local _, me = Core.me()
  me.seq = "medium"
  ns.Core.db.settings.advanced = true
  me.customSeq = ns.State.cleanCustom({ { id = 7, name = "Mine", kind = "sequence", aim = "harm", steps = { "Shadow Word: Pain" }, filler = "Smite", fills = 2 } })
  UI.Open("keys")
  local p = UI.panels.keys
  for _, name in ipairs({ "WBX S1", "WBX K1", "WBX C1" }) do
    if ns.Advanced.xf then ns.Advanced.xf:Hide() end
    local ok = ns.Advanced.openEditor(p, name, name)
    H.ok(ok, "bug 2: the editor opens " .. name)
    local ef = ns.Advanced.ef
    ef.text:Click()
    H.ok(ns.Advanced.xf and ns.Advanced.xf:IsVisible(), "bug 2: Edit text opens the text window for " .. name)
    H.ok((ns.Advanced.xf.edit:GetText() or "") ~= "", "with the macro's text")
    H.ok(not ef:IsShown(), "and the editor closes")
  end
  -- bug 4: one character counter on the Spells tab of an own macro
  ns.Advanced.xf:Hide()
  ns.Advanced.openEditor(p, "WBX C1", "Mine")
  ns.Advanced.showSection("spells")
  H.ok(not ns.Advanced.ef.info:IsShown(), "bug 4: the editor's own counter is hidden on the Spells tab")
  ns.Advanced.showSection("target")
  H.ok(ns.Advanced.ef.info:IsShown(), "and back on Targeting")
  H.eq(#errors(ns), 0, "no errors (bug 2/4) " .. table.concat(errors(ns), " | "))
end

-- bug 4: pasted lines that are left out are named
do
  local W, ns = boot({ name = "Retik", class = "PRIEST", race = "Human", level = 30 })
  local d = ns.Share.parseMacro("#showtooltip\n/assist party1\n/targetenemy [noharm]\n/cast [harm] Smite\n/cast Mind Blast")
  H.ok(d ~= nil, "bug 4: parsed")
  H.eq(table.concat(d.dropped or {}, ","), "/assist,/targetenemy", "the left-out lines are named")
  ns.CopyBox.ShowPaste(function() end)
  ns.CopyBox.parse("/assist party1\n/cast Smite")
  local txt = ns.CopyBox.frame.result:GetText()
  H.ok(txt:find("Only /cast and /castsequence lines are kept", 1, true) ~= nil, "the paste box says so: " .. txt)
end

-- ------------------------------------------------------------------ bug 5: bar names of the running client
do
  local W, ns = boot({ name = "Bo", class = "MAGE", race = "Human", level = 10 })
  local B = ns.Bars
  H.eq(B.barLabel(61), "Bottom Left Bar", "classic options: Bottom Left Bar")
  W.env.SHOW_MULTIBAR1_TEXT = "Bottom Left ActionBar"
  H.eq(B.barLabel(61), "Bottom Left ActionBar", "the client's own options string when it has one")
  W.env.EditModeManagerFrame = {}
  W.env.HUD_EDIT_MODE_ACTION_BAR_LABEL = "Action Bar %d"
  local want = { [1] = "Action Bar 1", [61] = "Action Bar 2", [49] = "Action Bar 3", [25] = "Action Bar 4", [37] = "Action Bar 5" }
  for first, name in pairs(want) do H.eq(B.barLabel(first), name, "Edit Mode client: " .. name) end
  H.eq(B.slotLabel(62), "Bar 2 · 2", "short label with the number")
  ns.UI.Open("setup")
  local vals = {}
  for _, v in ipairs(ns.Bars.BARS) do vals[#vals + 1] = ns.Bars.barLabel(v.first) end
  H.eq(table.concat(vals, ","), "Action Bar 1,Action Bar 2,Action Bar 3,Action Bar 4,Action Bar 5", "the dropdown values")
end

-- ------------------------------------------------------------------ bug 6: /wbx team off, then on
do
  local W, ns = boot({ name = "Talex", class = "MAGE", race = "Human", level = 20, party = { party1 = "Dorin" },
    partyInfo = { party1 = { class = "PALADIN", race = "Human", level = 20, leader = true } } })
  ns.Core.setPlaysAs("party1")
  local s = ns.Core.me()
  s.members[1].name = "Dorin"
  ns.TeamFrame.Refresh()
  H.ok(ns.TeamFrame.frame and ns.TeamFrame.frame:IsShown(), "bug 6: the team box shows while grouped")
  W.env.SlashCmdList.WOWBOXER("team off")
  H.eq(ns.Core.db.settings.team, false, "team off: off")
  H.ok(not ns.TeamFrame.frame:IsShown(), "team off hides it")
  W.env.SlashCmdList.WOWBOXER("team on")
  H.eq(ns.Core.db.settings.team, nil, "team on: on again (one switch)")
  H.ok(ns.TeamFrame.frame:IsShown(), "team on brings the box back")
  W.env.SlashCmdList.WOWBOXER("team")
  H.ok(not ns.TeamFrame.frame:IsShown(), "team toggles off")
  W.env.SlashCmdList.WOWBOXER("team")
  H.ok(ns.TeamFrame.frame:IsShown(), "and on")
  -- not grouped: it says why nothing shows
  W.party = {}
  W.chat = {}
  W.env.SlashCmdList.WOWBOXER("team on")
  H.ok(W.chatHas("once your squad is in a party together"), "solo: says it shows once the squad is grouped")
end

-- ------------------------------------------------------------------ bug 7: the leader in every party slot
for slot = 1, 4 do
  local party, info = {}, {}
  for i = 1, 4 do
    local u = "party" .. i
    party[u] = i == slot and "Dorin" or ("Alt" .. i)
    info[u] = { class = i == slot and "PALADIN" or "WARRIOR", race = "Human", level = 30, leader = i == slot }
  end
  local W, ns = boot({ name = "Salami", class = "HUNTER", race = "Dwarf", level = 30, party = party, partyInfo = info })
  ns.Core.setPlaysAs("party1")
  local s, me = ns.Core.me()
  s.members[1].name = "Dorin"
  local k = byKey(ns)
  H.eq(me.unit, "party" .. slot, "bug 7: the leader in party" .. slot .. ": the unit follows")
  H.eq(k.Assist and k.Assist.body, "/assist party" .. slot, "bug 7: the hunter's Assist macro points at the leader (party" .. slot .. ")")
  -- an import from another character (its own party numbers) keeps this character's unit
  local str = ns.Core.exportString()
  me.unit = "party" .. slot
  local res = ns.Core.importString(str)
  for _, x in ipairs(res.squad.members) do if x.name == me.name then x.unit = (slot == 1) and "party3" or "party1" end end
  ns.Core.applyImport(res)
  local _, me2 = ns.Core.me()
  H.eq(me2.unit, "party" .. slot, "bug 7: an import keeps this character's own leader unit")
end

-- ------------------------------------------------------------------ B: auto greed
do
  local W, ns = boot({ name = "Altsy", class = "MAGE", race = "Human", level = 30, party = { party1 = "Dorin" } })
  local LG, AU = ns.Loot, ns.Auto
  -- the decision
  H.eq(LG.decide({ quality = 0, canGreed = true }), "greed", "B: grey: greed")
  H.eq(LG.decide({ quality = 1, canGreed = true }), "greed", "B: white: greed")
  H.eq(select(2, LG.decide({ quality = 3, bop = true, canGreed = true })), "binds when picked up", "B: bind on pickup: the player rolls")
  local plate = { quality = 2, canGreed = true, info = { equipLoc = "INVTYPE_CHEST" }, lines = { { "Helm", 1, 1, 1 }, { "Plate", 1, 0.1, 0.1 } } }
  H.eq(table.concat({ LG.decide(plate) }, " "), "greed can't use", "B: a green the mage can't wear: greed")
  local lvl = { quality = 2, canGreed = true, info = { equipLoc = "INVTYPE_CHEST" }, lines = { { "Robe", 1, 1, 1 }, { "Requires Level 40", 1, 0.1, 0.1 } },
    verdict = { why = "not usable", wait = true } }
  H.eq(LG.decide(lvl), nil, "B: only too high a level: not sure, the player rolls")
  local up = { quality = 2, canGreed = true, info = { equipLoc = "INVTYPE_CHEST" }, lines = {}, verdict = { act = "equip", why = "better" } }
  H.eq(select(2, LG.decide(up)), "could be an upgrade", "B: an upgrade: the player rolls")
  local worse = { quality = 3, canGreed = true, info = { equipLoc = "INVTYPE_CHEST" }, lines = {}, verdict = { why = "worse" } }
  H.eq(table.concat({ LG.decide(worse) }, " "), "greed not an upgrade", "B: not an upgrade for the class and role: greed")
  H.eq(LG.decide({ quality = 2, canGreed = true, info = { equipLoc = "" } }), nil, "B: a green that is not gear: the player rolls")
  H.eq(LG.decide({ quality = 1, canGreed = false }), nil, "B: no greed button: nothing")
  -- in the game: off by default, only in a 5-player dungeon, never Need, one chat line per roll
  local rolled = {}
  W.env.RollOnLoot = function(id, kind) rolled[#rolled + 1] = { id, kind } end
  local items = { [1] = { "Linen Cloth", 1, false }, [2] = { "Plate Helm", 2, false }, [3] = { "Epic Sword", 4, true } }
  W.env.GetLootRollItemInfo = function(id) local x = items[id]; return 132, x[1], 1, x[2], x[3], true, true, false end
  W.env.GetLootRollItemLink = function(id) return "|cff|Hitem:" .. (1000 + id) .. "|h[" .. items[id][1] .. "]|h|r" end
  W.env.GetLootRollTimeLeft = function() return 30000 end
  local where = { true, "party" }
  W.env.IsInInstance = function() return where[1], where[2] end
  W.fire("START_LOOT_ROLL", 1, 60000)
  H.eq(#rolled, 0, "B: off by default: no roll")
  AU.set("greed", true)
  W.chat = {}
  W.fire("START_LOOT_ROLL", 1, 60000)
  H.eq(#rolled, 1, "B: on, in a dungeon: one roll")
  H.eq(rolled[1][2], 2, "B: Greed (2), never Need")
  H.ok(W.chatHas("Greed: .*Linen Cloth.* – white"), "B: one chat line: " .. tostring(W.lastChat()))
  W.fire("START_LOOT_ROLL", 3, 60000)
  H.eq(#rolled, 1, "B: bind on pickup: no roll")
  H.ok(W.chatHas("Roll yourself: .*Epic Sword.* – binds when picked up"), "B: and a chat line that says why")
  where = { false, "none" }
  W.fire("START_LOOT_ROLL", 1, 60000)
  H.eq(#rolled, 1, "B: open world: nothing")
  where = { true, "raid" }
  W.fire("START_LOOT_ROLL", 1, 60000)
  H.eq(#rolled, 1, "B: raid: nothing")
  where = { true, "party" }
  W.combat = true
  W.fire("START_LOOT_ROLL", 1, 60000)
  H.eq(#rolled, 1, "B: in combat: waits")
  W.combat = false
  W.fire("PLAYER_REGEN_ENABLED")
  H.eq(#rolled, 2, "B: rolls when the fight ends")
  W.mods.shift = true
  W.fire("START_LOOT_ROLL", 1, 60000)
  H.eq(#rolled, 2, "B: Shift held: skipped")
  W.mods.shift = false
  H.eq(#errors(ns), 0, "no errors (B) " .. table.concat(errors(ns), " | "))
end

H.report("help-nov10")
