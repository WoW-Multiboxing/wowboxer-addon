-- Helper keys (icons, the Helpers section, what they do), copy / paste of keys, and the warnings for buffs and
-- summons in an enemy key (the owner's warlock key, 2026-10-28).
local dir = (arg[0]:match("^(.*)/[^/]+$") or ".")
local H = dofile(dir .. "/harness.lua")
local Mock = dofile(dir .. "/wowmock.lua")
local Layout = dofile(dir .. "/layout.lua")

local function boot(opts)
  local W = Mock.new(H, opts)
  local ns = H.loadAddon({ env = W.env })
  W.fire("ADDON_LOADED", "WoWBoxer"); W.fire("PLAYER_LOGIN")
  ns.Core.cdb.guide = "done"
  for _, s in ipairs(ns.Data.spells[(opts.class or "PALADIN"):lower()]) do if s.level <= (opts.level or 10) and s.gate ~= "talent" then W.known[s.name] = true end end
  return W, ns
end
local function macro(W, name) for _, m in ipairs(W.char) do if m.name == name then return m end end end
local function errors(ns)
  local n = {}
  for _, e in ipairs(ns.Core.db.log) do if e.l == "error" then n[#n + 1] = e.m end end
  return table.concat(n, " | ")
end
local JAKOB = [[#showtooltip
/petattack [@mouseover,harm,nodead][@party1target,harm,nodead][harm,nodead]
/castsequence [@mouseover,harm,nodead][@party1target,harm,nodead][harm,nodead] reset=combat Demon Skin, Summon Imp, Immolate, Shadow Bolt, Shadow Bolt, Shadow Bolt]]

-- ------------------------------------------------------------------ helper keys
for _, fileIds in ipairs({ false, true }) do
  local W, ns = boot({ name = "Lock", class = "WARLOCK", race = "Scourge", level = 10 })
  if fileIds then W.env.GetFileIDFromPath = function(path) return 900000 + #path end end
  local Core, UI = ns.Core, ns.UI
  local tag = fileIds and "file IDs: " or "icon names: "
  UI.Open("keys")
  Core.setPlaysAs("party1")
  local ctx = Core.computeFresh()
  local names = {}
  for _, d in ipairs(ctx.desired) do if d.group == "helper" then names[d.key] = d end end
  -- owner, 9 Nov 2026: no Pet attack key (damage macros send the pet); Pet passive + follow is opt-in
  H.ok(names.Follow and names.Assist and not names.Pet and not names.PetBack, tag .. "follower warlock: Follow, Assist; no Pet, no PetBack by default")
  for key, d in pairs(names) do H.ok(d.icon ~= ns.Macros.ICON, tag .. key .. " gets its own icon, not the ?") end
  H.eq(names.Follow.iconName, "Ability_Tracking", tag .. "Follow icon")
  Core.sync({})
  local fm = macro(W, "WBX Follow")
  H.ok(fm and fm.icon ~= 134400, tag .. "the macro in the game has the icon")
  local again = Core.computeFresh().macros
  local upd = {}
  for _, it in ipairs(again.items) do if it.status ~= "same" and it.status ~= "spell" then upd[#upd + 1] = it.name .. "=" .. it.status end end
  H.eq(table.concat(upd, ","), "", tag .. "no endless updates after the icon is set")
  -- an old ? helper gets the icon with the next Update macros
  fm.icon = 134400
  local st
  for _, it in ipairs(Core.computeFresh().macros.items) do if it.name == "WBX Follow" then st = it.status end end
  H.eq(st, "update", tag .. "an old ? helper counts as a change")
  -- the book: sections and plain explanations
  UI.Select("keys")
  local heads, helperCell = {}, nil
  for _, r in ipairs(UI.panels.keys.rules) do if r:IsVisible() then heads[#heads + 1] = r.text:GetText() end end
  for _, b in ipairs(UI.panels.keys.cells) do
    if b:IsShown() and b.cell and b.cell.name == "WBX Follow" then helperCell = b end
  end
  H.ok(table.concat(heads, ","):find("Spells", 1, true) and table.concat(heads, ","):find("Squad macros", 1, true), tag .. "sections: " .. table.concat(heads, ","))
  H.eq(helperCell and helperCell.name:GetText(), "Follow (line)", tag .. "short helper name")
  H.ok(helperCell and helperCell.small, tag .. "helpers are the small buttons")
  H.ok(helperCell ~= nil, tag .. "Follow is in the book")
  local lines = {}
  W.env.GameTooltip.AddLine = function(_, t) lines[#lines + 1] = t end
  helperCell._scripts.OnEnter(helperCell)
  local all = table.concat(lines, "\n")
  H.ok(all:find("Follows", 1, true) and all:find("One press, one action", 1, true) and all:find("untick it under Squad macros", 1, true),
    tag .. "hover explains what Follow does and why it is there")
  H.ok(all:find("/follow party1", 1, true) ~= nil, tag .. "and shows the macro text")
  -- a header is a rule, never a key button
  local bad = 0
  for _, b in ipairs(UI.panels.keys.cells) do if b.cell and (b.cell.kind == "header" or b.wbxRule) then bad = bad + 1 end end
  H.eq(bad, 0, tag .. "no section header among the key buttons")
  H.eq(errors(ns), "", tag .. "no errors")
end

-- ------------------------------------------------------------------ paste: macro text and key strings (data only)
do
  local _, ns = boot({})
  local Sh = ns.Share
  local d = Sh.parseMacro(JAKOB)
  H.ok(d ~= nil, "The owner's macro parses")
  H.eq(d.kind, "sequence", "a castsequence")
  H.eq(table.concat(d.steps, ","), "Demon Skin,Summon Imp,Immolate", "the steps")
  H.eq(d.filler, "Shadow Bolt", "the repeated last spell is the filler")
  H.eq(d.fills, 3, "three times")
  H.eq(d.aim, "harm", "enemy key")
  H.eq(d.reset, "combat", "reset after combat")
  local pr = Sh.parseMacro("#showtooltip\n/cast [@mouseover,help,nodead][help] Flash of Light\n/cast [help] Holy Light(Rank 3)\n/cast [help] !Flash of Light")
  H.eq(pr.kind, "priority", "/cast lines = a priority list")
  H.eq(table.concat(pr.steps, ","), "Flash of Light,Holy Light", "names without ranks, no duplicates")
  H.eq(pr.aim, "help", "friendly key")
  local t = Sh.parseMacro("/castsequence reset=target Corruption, Shadow Bolt")
  H.eq(t.reset, "target/combat", "reset=target")
  H.eq(table.concat(t.steps, ","), "Corruption,Shadow Bolt", "no filler when the last spell is not repeated")
  H.ok(Sh.parseMacro("/run DoSomething()") == nil, "no /cast lines: nothing")
  H.ok(Sh.parseMacro(string.rep("x", 3000)) == nil, "too long: nothing")
  -- key strings
  local key = { name = "Lock dps", kind = "sequence", aim = "harm", steps = { "Immolate", "Corruption" }, filler = "Shadow Bolt", fills = 3, reset = "combat" }
  local str = Sh.encodeKey(key, "warlock")
  H.ok(str:sub(1, 8) == "!WBXK:1!", "key string")
  H.ok(not str:find("castsequence", 1, true), "no macro text in the key string")
  local back, cls = Sh.decodeKey(str)
  H.eq(cls, "warlock", "class travels")
  H.eq(back.name .. "|" .. table.concat(back.steps, ",") .. "|" .. back.filler .. "|" .. back.fills, "Lock dps|Immolate,Corruption|Shadow Bolt|3", "key round trip")
  local bad = str:sub(1, -3) .. (str:sub(-2) == "00" and "11" or "00")
  H.ok(Sh.decodeKey(bad) == nil, "damaged key refused")
end

-- ------------------------------------------------------------------ the editor: paste, warnings, copy
do
  local W, ns = boot({ name = "Lock", class = "WARLOCK", race = "Scourge", level = 4 })
  local UI, KE, CB = ns.UI, ns.KeyEditor, ns.CopyBox
  UI.Open("custom")
  UI.panels.custom.cells[1]:Click("LeftButton")
  H.ok(KE.IsOpen(), "editor open")
  local f = KE.frame
  f.paste:Click()
  local box = CB.frame
  H.ok(box:IsShown() and box.mode == "paste", "Paste… opens the paste box")
  H.ok(not box.use:IsEnabled(), "nothing to use yet")
  box.e1:SetText(JAKOB); box.e1._scripts.OnTextChanged(box.e1, true)
  H.ok(box.result:GetText():find("Demon Skin", 1, true) and box.result:GetText():find("Shadow Bolt ×3", 1, true), "the box shows what it read")
  H.eq(table.concat(Layout.check(W, { box }), " | "), "", "paste box: no overlaps")
  box.use:Click()
  H.ok(not box:IsShown(), "Use it closes the box")
  H.eq(table.concat(f.draft.steps, ","), "Demon Skin,Summon Imp,Immolate", "the editor got the steps")
  H.eq(f.draft.filler, "Shadow Bolt", "and the filler")
  local warn = f.warnFull
  H.ok((f.warn:GetText() or ""):find("buffs – put them on their own macro", 1, true) ~= nil, "short warning line: " .. tostring(f.warn:GetText()))
  H.ok(warn:find("Demon Skin, Summon Imp are buffs or summons", 1, true) ~= nil, "warns about buffs and summons in an enemy key: " .. warn)
  H.ok(warn:find("Summon Imp (10 s)", 1, true) ~= nil, "warns about the 10 s summon")
  H.eq(W.calls.CreateMacro, nil, "pasting writes nothing to the game")
  -- copy
  f.copy:Click()
  H.ok(box:IsShown() and box.mode == "copy", "Copy… shows the copy box")
  H.ok(box.e1:GetText():find("/castsequence", 1, true) ~= nil, "macro text to copy")
  H.ok(box.e2:GetText():sub(1, 8) == "!WBXK:1!", "WoWBoxer key to copy")
  box.e1:SetText("changed"); box.e1._scripts.OnTextChanged(box.e1, true)
  H.ok(box.e1:GetText():find("/castsequence", 1, true) ~= nil, "the copy text cannot be typed over")
  H.eq(table.concat(Layout.check(W, { box }), " | "), "", "copy box: no overlaps")
  box.close:Click()
  -- a pasted key from another class: unknown spells are left out and named
  f.paste:Click()
  box.e1:SetText(ns.Share.encodeKey({ name = "Holy", kind = "sequence", aim = "harm", steps = { "Smite", "Immolate" }, filler = "", fills = 1, reset = "combat" }, "priest"))
  box.e1._scripts.OnTextChanged(box.e1, true)
  box.use:Click()
  H.eq(table.concat(f.draft.steps, ","), "Immolate", "only this class's spells")
  H.ok(W.chatHas("Left out"), "the left-out spell is named")
  H.eq(f.name:GetText(), "Holy", "the key's name came along")
  -- the book's right-click menu offers Copy… for every key
  f.cancel:Click()
  UI.Select("keys")
  local cell
  for _, b in ipairs(UI.panels.keys.cells) do if b:IsShown() and b.cell and b.cell.name == "WBX K1" then cell = b end end
  cell:Click("RightButton")
  local m = ns.Widgets.menuFrame
  local copyRow
  for _, b in ipairs(m.rows) do if b:IsShown() and b.label._text == "Copy…" then copyRow = b end end
  H.ok(copyRow ~= nil, "Copy… in the right-click menu")
  copyRow:Click()
  H.ok(box:IsShown() and box.e1:GetText():find("Shadow Bolt", 1, true) ~= nil, "copy a spell key's macro text")
  H.ok(not box.s2:IsShown(), "no WoWBoxer key string for a spell key")
  H.eq(errors(ns), "", "no errors (editor)")
end

-- the boxes fit small and big screens
for _, screen in ipairs({ { w = 835, h = 668 }, { w = 1024, h = 768 }, { w = 2240, h = 960 } }) do
  local W, ns = boot({ class = "WARLOCK", level = 10, screen = screen, fontFactor = 0.62 })
  ns.CopyBox.ShowCopy("Copy \"A rather long key name\"", JAKOB, ns.Share.encodeKey({ name = "x", steps = { "Immolate" } }, "warlock"))
  H.eq(table.concat(Layout.check(W, { ns.CopyBox.frame }), " | "), "", "copy box fits " .. screen.w .. "x" .. screen.h)
end

os.exit(H.report("keys") and 0 or 1)
