-- Reminders that respect the player (docs/squad-v2-simple.md §4): only real changes, "Keep off my bars", "Don't show
-- again" per character across a reload, a new change shows again, "Level-up reminders" off, at most one chat line.
local dir = (arg[0]:match("^(.*)/[^/]+$") or ".")
local H = dofile(dir .. "/harness.lua")
local Mock = dofile(dir .. "/wowmock.lua")

local function learn(W, ns, cls, level)
  for _, s in ipairs(ns.Data.spells[cls]) do if s.level <= level and s.gate ~= "talent" then W.known[s.name] = true end end
end
local function boot(opts)
  local W = Mock.new(H, opts)
  local ns = H.loadAddon({ env = W.env })
  W.fire("ADDON_LOADED", "WoWBoxer"); W.fire("PLAYER_LOGIN")
  learn(W, ns, (opts.class or "PALADIN"):lower(), opts.level or 10)
  ns.Core.cdb.guide = "done"
  return W, ns
end
--- /reload: the same game (macros, bars, SavedVariables), a fresh addon.
local function reload(W)
  W.events, W.timers, W.chat = {}, {}, {}
  local ns = H.loadAddon({ env = W.env })
  W.fire("ADDON_LOADED", "WoWBoxer"); W.fire("PLAYER_LOGIN")
  W.flush()
  return ns
end
local function chatCount(W, pat) local n = 0; for _, m in ipairs(W.chat) do if m:find(pat) then n = n + 1 end end return n end
local function levelUp(W, ns, to)
  W.player.level = to
  learn(W, ns, W.player.class:lower(), to)
  W.chat = {}
  W.fire("PLAYER_LEVEL_UP", to); W.fire("SPELLS_CHANGED"); W.flush()
end
local function errors(ns)
  local n = {}
  for _, e in ipairs(ns.Core.db.log) do if e.l == "error" then n[#n + 1] = e.m end end
  return table.concat(n, " | ")
end

-- ------------------------------------------------------------------ toast, one chat line, reload, Don't show again
do
  local W, ns = boot({ name = "Dorin", class = "PALADIN", level = 10 })
  ns.UI.Open("keys")
  ns.Core.sync({})
  W.flush()
  levelUp(W, ns, 20)
  H.ok(ns.UI.offer and ns.UI.offer:IsShown(), "level-up: the toast")
  H.eq(chatCount(W, "changed at level"), 1, "level-up: exactly one chat line")
  W.fire("SPELLS_CHANGED"); W.flush()
  H.eq(chatCount(W, "changed at level"), 1, "the same change again: no second line")
  -- reload without ticking anything: nothing new, so no chat line and no toast
  ns = reload(W)
  H.eq(chatCount(W, "changed at level"), 0, "after /reload: no chat line for the same change")
  H.ok(not (ns.UI.offer and ns.UI.offer:IsShown()), "after /reload: no toast for the same change")
  H.ok(ns.Core.pending(ns.Core.compute()) ~= "", "the change is still pending (the book shows it)")
  -- a new change shows again, and Don't show again sticks across a reload
  levelUp(W, ns, 30)
  H.ok(ns.UI.offer and ns.UI.offer:IsShown(), "a new level-up shows again")
  H.eq(chatCount(W, "changed at level"), 1, "with one chat line")
  local sig = ns.UI.offer.sig
  H.eq(ns.UI.offer.never.label:GetText(), "Skip these changes", "the tick says it is about these changes (#help 10 Nov)")
  ns.UI.offer.never:Click()
  H.ok(ns.UI.offer:IsShown(), "ticking does not close the toast")
  H.eq(ns.Core.cdb.offerSeen, sig, "stored per character")
  ns.UI.offer.never:Click()
  H.eq(ns.Core.cdb.offerSeen, nil, "unticking takes it back")
  ns.UI.offer.never:Click()
  ns.UI.offer:Hide()
  ns.Core.cdb.offerShown = nil -- even when the login check forgets what it showed, Don't show again holds
  ns = reload(W)
  H.ok(not (ns.UI.offer and ns.UI.offer:IsShown()), "Don't show again survives /reload")
  H.eq(chatCount(W, "changed at level"), 0, "and writes no chat line")
  levelUp(W, ns, 40)
  H.ok(ns.UI.offer and ns.UI.offer:IsShown(), "a NEW change after Don't show again shows again")
  -- "Turn reminders off" on the toast: no more reminders (Setup turns them on again)
  ns.UI.offer.off:Click()
  H.ok(not ns.UI.offer:IsShown(), "Turn reminders off closes the toast")
  H.eq(ns.Core.cdb.reminders, false, "and turns level-up reminders off")
  H.ok(chatCount(W, "reminders are off") == 1, "with one chat line that says where to turn them on")
  ns.Core.cdb.reminders = nil
  -- Level-up reminders off: no toast, no chat; the book still marks the keys
  ns.UI.Open("setup")
  ns.UI.panels.setup.remind:Click()
  H.eq(ns.Core.cdb.reminders, false, "Setup: Level-up reminders off")
  levelUp(W, ns, 50)
  H.ok(not ns.UI.offer:IsShown(), "reminders off: no toast")
  H.eq(chatCount(W, "changed at level"), 0, "reminders off: no chat line")
  ns.UI.Select("keys")
  local dots = 0
  for _, b in ipairs(ns.UI.panels.keys.cells) do local word = b.sub and b.sub:IsShown() and (b.sub:GetText() or "")
    if b:IsShown() and (b.dot:IsShown() or b.glow:IsShown() or word == "New macro" or word == "Changed · update") then dots = dots + 1 end end
  H.ok(dots > 0, "the book still marks the changed keys (" .. dots .. ")")
  ns.UI.Select("setup")
  ns.UI.panels.setup.remind:Click()
  H.ok(ns.Core.remindersOn(), "back on")
  H.eq(errors(ns), "", "no errors (reminders)")
end

-- ------------------------------------------------------------------ login with nothing new: no chat line at all
do
  local W, ns = boot({ name = "Dorin", class = "PALADIN", level = 10 })
  ns.Core.sync({})
  local ns2 = reload(W)
  H.eq(#W.chat, 0, "login with nothing new writes no chat line: " .. table.concat(W.chat, " / "))
  H.eq(errors(ns2), "", "no errors (quiet login)")
end

-- ------------------------------------------------------------------ Keep off my bars
do
  local W, ns = boot({ name = "Lock", class = "WARLOCK", level = 20 })
  local Core, UI = ns.Core, ns.UI
  UI.Open("keys")
  Core.sync({})
  -- an own key and an extra key: kept off the bars by default until placed once
  local _, m = Core.me()
  m.customSeq = ns.State.cleanCustom({ { name = "Dots", steps = { "Corruption", "Immolate" }, filler = "Shadow Bolt" } })
  Core.changed()
  local function bar(name) for _, b in ipairs(Core.compute().bars.items) do if b.name == name then return b end end end
  H.eq(bar("WBX C1").status, "off", "own key: kept off the bars by default")
  H.eq(Core.compute().bars.changes, 0, "and not counted as \"not on a bar\"")
  local _, n = Core.pending(Core.compute())
  H.eq(n, 0, "and never reminded about")
  Core.sync({})
  H.ok(ns.Macros.findIndex("WBX C1") ~= nil, "Place all still creates its macro (to drag)")
  H.eq(bar("WBX C1").status, "off", "but does not put it on a bar")
  -- the player drags it once: from then on it is a normal key
  Core.pickup("WBX C1"); W.env.PlaceAction(30); W.fire("ACTIONBAR_SLOT_CHANGED", 30); W.flush()
  H.ok(Core.cdb.placedOnce["WBX C1"], "placed once is remembered")
  H.eq(bar("WBX C1").status, "placed", "now on a bar")
  W.env.PickupAction(30); W.env.ClearCursor(); W.fire("ACTIONBAR_SLOT_CHANGED", 30); W.flush()
  H.ok(bar("WBX C1").status ~= "off", "taken off again: counted again (it was placed once)")
  -- right-click → Keep off my bars on a normal key
  UI.Refresh()
  local cell
  for _, b in ipairs(UI.panels.keys.cells) do if b:IsShown() and b.cell and b.cell.name == "WBX C1" then cell = b end end
  local menu = ns.Book.menuFor(UI.panels.keys, cell and cell.cell or { kind = "key", name = "WBX C1", item = { status = "same" }, bar = bar("WBX C1") })
  local keep
  for _, it in ipairs(menu) do if it[1] == "Keep off my bars" then keep = it[2] end end
  H.ok(keep ~= nil, "the menu has Keep off my bars")
  keep()
  H.eq(Core.cdb.offBars["WBX C1"], true, "stored per character")
  H.eq(bar("WBX C1").status, "off", "kept off")
  -- a key kept off whose text changes: no reminder
  m.customSeq[1].steps = { "Immolate", "Corruption" }
  Core.changed()
  local sig, n2 = Core.pending(Core.compute())
  H.eq(n2, 0, "a kept-off key's change is not reminded about (" .. sig .. ")")
  -- and a normal key that changes is
  Core.cdb.offBars["WBX C1"] = false
  local _, n3 = Core.pending(Core.compute())
  H.eq(n3, 1, "allowed on the bars again: its change counts")
  H.eq(errors(ns), "", "no errors (keep off)")
end

os.exit(H.report("reminders") and 0 or 1)
