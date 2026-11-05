-- Bar memory (owner, 5 Nov 2026): "it doesn't remember … when you log in and out", "it should find the spells that
-- you've already placed … on the same exact spot", and "if it wants to replace any action bars you need to confirm".
--   1. Forever: GetActionInfo gives a macro button the SPELL id it casts (K2 Lesser Heal read as macro 2053); WBX
--      macros are recognised by the button's text, so where the player put them is remembered across logins.
--   2. A macro goes where the player put it, else where its spell already sits, else the fixed layout.
--   3. A button that holds something (a spell, an item, another WBX macro) is only replaced after "Replace".
local dir = (arg[0]:match("^(.*)/[^/]+$") or ".")
local H = dofile(dir .. "/harness.lua")
local Mock = dofile(dir .. "/wowmock.lua")

local function boot(opts)
  local W = Mock.new(H, opts)
  local ns = H.loadAddon({ env = W.env })
  W.fire("ADDON_LOADED", "WoWBoxer"); W.fire("PLAYER_LOGIN")
  for _, s in ipairs(ns.Data.spells[opts.class:lower()]) do if s.level <= opts.level then W.known[s.name] = true end end
  ns.Core.cdb.guide = "done"
  -- spell buttons carry real names: id -> name from the class data
  local names = {}
  for _, s in ipairs(ns.Data.spells[opts.class:lower()]) do
    if s.id then names[s.id] = s.name end
    for _, r in ipairs(s.ranks or {}) do if r.id then names[r.id] = s.name end end
  end
  local function nameOf(id) return names[id] or ("Spell" .. tostring(id)) end
  if W.env.C_Spell then W.env.C_Spell.GetSpellName = nameOf end
  W.env.GetSpellInfo = function(id) return nameOf(id) end
  W.popups = {}
  ns.UI.Popup = function(text, buttons) W.popups[#W.popups + 1] = { text = text, buttons = buttons } end
  return W, ns, names
end
local function slotOf(W, name) for slot, a in pairs(W.actions) do if a.kind == "macro" and a.ref.name == name then return slot end end end
local function idOf(names, spell) for id, n in pairs(names) do if n == spell then return id end end end
local function click(W, label) local p = W.popups[#W.popups]; for _, b in ipairs(p and p.buttons or {}) do if b[1] == label then b[2]() return true end end return false end

-- ------------------------------------------------------------------ 1. Forever reads macro buttons by their text
do
  local W, ns = boot({ name = "Rup", class = "PRIEST", race = "Human", level = 12 })
  local Core = ns.Core
  ns.State.quickStart(Core.db, Core.cdb, Core.playerInfo())
  Core.sync({})
  local k2 = slotOf(W, "WBX K2")
  H.ok(k2 ~= nil, "K2 is on a button")
  -- the modern client: a macro button reports the spell it casts, not the macro
  local real = W.env.GetActionInfo
  W.env.GetActionInfo = function(slot)
    local a = W.actions[slot]
    if a and a.kind == "macro" then return "macro", 2053, "spell" end
    return real(slot)
  end
  local a = ns.Compat.actionInfo(k2)
  H.eq(a and a.name, "WBX K2", "Forever: the macro button is read by its text")
  -- the player moves K2 to another button; after a /reload it stays there
  local free = 72
  W.actions[free], W.actions[k2] = W.actions[k2], nil
  Core.scanBars()
  H.eq(Core.cdb.slots["WBX K2"], free, "the new spot is remembered")
  W.popups = {}
  Core.sync({})
  H.eq(slotOf(W, "WBX K2"), free, "Update keeps K2 where the player put it")
  H.eq(W.actions[k2], nil, "and does not put it back on its old button")
  H.eq(#W.popups, 0, "nothing to ask")
end

-- ------------------------------------------------------------------ 2. a macro goes where its spell already is (after a yes)
do
  local W, ns, names = boot({ name = "Rup", class = "PRIEST", race = "Human", level = 12 })
  local Core = ns.Core
  ns.State.quickStart(Core.db, Core.cdb, Core.playerInfo())
  local ctx = Core.compute()
  local k1
  for _, d in ipairs(ctx.desired) do if d.key == "K1" then k1 = d end end
  local sid = idOf(names, k1.spell.name)
  W.actions[7] = { kind = "spell", id = sid } -- the player has K1's spell on button 7
  W.actions[1] = { kind = "spell", id = 6603 } -- and something else on button 1
  Core.sync({})
  H.eq(W.actions[7].kind, "spell", "the spell is not replaced without a yes")
  H.eq(slotOf(W, "WBX K1"), nil, "K1 waits")
  H.eq(W.actions[1].kind, "spell", "button 1 is untouched (K1 does not go to the fixed spot)")
  local p = W.popups[#W.popups]
  H.ok(p and p.text:find("WBX K1", 1, true) and p.text:find(k1.spell.name .. " (same spell)", 1, true), "asked: " .. tostring(p and p.text))
  click(W, "Keep")
  H.eq(slotOf(W, "WBX K1"), nil, "Keep: nothing changes")
  Core.sync({})
  click(W, "Replace")
  H.eq(slotOf(W, "WBX K1"), 7, "Replace: K1 takes the spell's own button")
  H.eq(W.actions[1].kind, "spell", "button 1 still untouched")
  -- the next update finds it there
  W.popups = {}
  Core.sync({})
  H.eq(slotOf(W, "WBX K1"), 7, "updates keep it on that button")
end

-- ------------------------------------------------------------------ 3. another WBX macro is never replaced without a yes
do
  local W, ns = boot({ name = "Rup", class = "PRIEST", race = "Human", level = 12 })
  local Core = ns.Core
  ns.State.quickStart(Core.db, Core.cdb, Core.playerInfo())
  Core.sync({})
  local s1, k1 = slotOf(W, "WBX S1"), slotOf(W, "WBX K1")
  if s1 and k1 then
    -- the player drags S1 onto K1's button (K1 goes off the bars)
    W.actions[k1], W.actions[s1] = W.actions[s1], nil
    Core.scanBars()
    W.popups = {}
    Core.sync({})
    H.eq(slotOf(W, "WBX S1"), k1, "S1 stays on the button the player chose")
    H.ok(slotOf(W, "WBX K1") ~= k1, "K1 never replaces it")
  end
  -- Ask to replace off: never asks, never replaces
  Core.cdb.askReplace = false
  W.actions[70] = { kind = "item", id = 4604 }
  Core.cdb.slots = {}
  W.popups = {}
  for slot, a in pairs(W.actions) do if a.kind == "macro" then W.actions[slot] = nil end end
  W.actions[1] = { kind = "spell", id = 6603 }
  Core.sync({})
  H.eq(#W.popups, 0, "Ask to replace off: no question")
  H.eq(W.actions[1].kind, "spell", "and nothing replaced")
  local errs = {}
  for _, e in ipairs(Core.db.log) do if e.l == "error" then errs[#errs + 1] = e.m end end
  H.eq(#errs, 0, "no errors: " .. table.concat(errs, " / "))
end

H.report("barmemory")
