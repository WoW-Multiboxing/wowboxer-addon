--[[ WoWBoxer – the spellbook: My keys, All spells and Custom keys as a two-page spread (docs/ui-spec-v3-book.md).
  My keys: LEFT page = the next step (banner) + your spells (Spells, then Sequences); RIGHT page = role / plays as /
  sequence keys, the helpers (Party helpers or Pet) and the selected key. Section headers are full-width rules on
  one page; nothing crosses the spine. Status is a colour (new = glow, changed = orange dot, not on a bar = dimmed),
  the words are in the tooltip. Drag a button onto an action bar: the WBX macro is created/updated first (out of
  combat), then picked up; the player drops it. Right-click or Shift-click opens a menu. A 3-step guide on a fresh
  character. ]]
local _, ns = ...
local UI, W = ns.UI, ns.Widgets
local Book = {}
ns.Book = Book

local PAGE_GAP = 16                       -- spine + margins between the two pages
local CELL_W, CELL_H, PITCH = 158, 40, 44 -- spell buttons (37 px icon)
local HELP_W, HELP_H, HELP_PITCH = 160, 30, 32
local RULE_H = 20
local TOP_H, BOTTOM_H = 36, 30
local function Core() return ns.Core end

--- Width of one page, x of the right page, panel height (design units).
function Book.pageGeom()
  local pw, ph = UI.PanelSize()
  local w = math.floor((pw - PAGE_GAP) / 2)
  return w, pw - w, ph
end

-- ------------------------------------------------------------------ plain words
local KIND = { S1 = "Damage sequence", S2 = "Heal sequence" }
--- "Key 3", "Own key 2", "Damage sequence", "Helper", "Extra key"
function Book.kindName(it)
  local k = it.key or ""
  if k:match("^K%d$") then return "Key " .. k:sub(2) end
  if k:match("^C%d$") then return "Own key " .. k:sub(2) end
  if KIND[k] then return KIND[k] end
  if it.group == "helper" then return "Helper" end
  if it.group == "extra" then return "Extra key" end
  return k
end
--- Short helper names (the spec: no truncated names).
Book.HELPER_NAME = { Follow = "Follow (line)", FollowLead = "Follow leader", Assist = "Assist", Focus = "Focus", Pet = "Pet attack", PetBack = "Pet back", Invite = "Invite squad",
  Invite2 = "Invite squad 2", Target = "Target leader" }
function Book.shortLabel(it)
  if it.group == "helper" then return Book.HELPER_NAME[it.key] or it.label end
  return it.label
end
--- Status words (tooltips only; the page shows colours).
Book.STATUS = {
  create = { "New key", W.BLUE }, update = { "Changed", W.ORANGE }, noslot = { "No macro slot", W.RED },
  invalid = { "Blocked", W.RED }, skipped = { "Left out", W.MUTED },
}
--- How a key looks: {glow, dot = colour?, dim (not on a bar), off (left out), word, color}.
function Book.statusOf(it, b)
  local st = Book.barStatus(it, b)
  if b and b.status == "off" then -- "Keep off my bars": not dimmed, not counted
    st.dim = nil
    if st.word == "Not on a bar" then st.word, st.color = "Kept off your bars", W.MUTED end
  end
  return st
end
function Book.barStatus(it, b)
  local placed = b and b.status == "placed"
  local st = Book.STATUS[it.status]
  if it.status == "skipped" then return { off = true, word = st[1], color = st[2] } end
  if it.status == "noslot" or it.status == "invalid" then return { dot = W.RED, word = st[1], color = st[2] } end
  if it.status == "create" then return { glow = true, dim = not placed, word = st[1], color = st[2] } end
  if it.status == "update" then return { dot = W.ORANGE, dim = not placed, word = st[1], color = st[2] } end
  if not placed then return { dim = true, word = "Not on a bar", color = W.ORANGE } end
  return { word = "Up to date", color = W.GREEN }
end

--- The leader's name as this member sees it ("the leader" when unknown or self).
local function leaderName(mem)
  local s, me = Core().me()
  mem = mem or me
  local L = s and ns.State.leaderOf(s)
  return (L and L ~= mem and L.name) or "the leader"
end
--- What a key does: ONE plain sentence (details page, tooltip).
function Book.describe(d, mem)
  if not d then return "" end
  if d.seq and d.seq.base == "priority" then return "Each press casts the first ready spell." end
  if d.group == "sequence" or (d.group == "custom" and d.seq) then return "Each press casts the next spell." end
  if d.group == "helper" then return Book.helperShort(d.key, mem) end
  local body = d.body or ""
  local follows = body:match("@party%dtarget") or body:match("@focustarget")
  if body:find("help", 1, true) then
    return "Casts on your mouseover, else " .. (body:match("@party%d") and leaderName(mem) or "your target") .. ", else you."
  elseif body:find("harm", 1, true) then
    return "Casts on your mouseover, else " .. (follows and (leaderName(mem) .. "'s target") or "your target") .. "."
  end
  return "Casts " .. (d.label or "the spell") .. "."
end
--- One short sentence per helper key.
function Book.helperShort(key, mem)
  local _, me = Core().me()
  mem = mem or me
  local L = leaderName(mem)
  local s = Core().me()
  local _, ahead = ns.Squad.lineFor(s, mem)
  local T = { Follow = "Follows " .. ((ahead and ahead.name) or L) .. ", the one ahead of you in the line.", FollowLead = "Follows " .. L .. ".",
    Assist = "Takes " .. L .. "'s target.", Focus = "Sets your target as focus.",
    Pet = "Sends your pet at " .. ((mem and mem.leader) and "your target." or (L .. "'s target.")), PetBack = "Calls your pet back, passive.",
    Invite = "Invites the others in your squad.", Invite2 = "Invites the rest of your squad.", Target = "Targets " .. L .. "." }
  return T[key] or "A helper key."
end
--- The longer helper text for tooltips: what it does and why WoWBoxer made it.
function Book.helperText(key, mem)
  local _, me = Core().me()
  mem = mem or me
  local u = mem and mem.unit or "party1"
  local why = (key == "Invite" or key == "Invite2") and "Built from your squad's names; it changes when the squad does. They still accept by hand."
    or (key == "Pet" or key == "PetBack") and "You have a pet; untick it under Squad keys if you don't want it."
    or ("Uses " .. leaderName(mem) .. " through " .. u .. "; untick it under Squad keys if you don't want it.")
  return Book.helperShort(key, mem) .. " One press, one action, this character only. " .. why
end

--- Dropdown values: the roles of the member's class, and Leader / Follower via a unit.
function Book.roleValues(mem)
  local v = {}
  if mem then for _, r in ipairs(ns.Data.classes[mem.cls].roles) do v[#v + 1] = { r, ns.State.ROLE_NAME[r] } end end
  return v
end
function Book.playsAsValues()
  local v = { { "leader", "Leader", "This character leads: its keys use its own target." } }
  for _, u in ipairs(ns.Engine.UNITS) do
    -- the unit is where THIS client sees the leader – not the place in the follow line (that is the squad order)
    v[#v + 1] = { u, "Follower – leader is " .. u, "The leader is " .. u .. " on this character's client: Assist, Follow leader and the spell keys use it. The place in the follow line is the squad order (Up / Down on the Squad page)." }
  end
  return v
end
function Book.setRole(mem, v)
  if not mem then return end
  mem.role = v; mem.guide = ns.Kit.defaultGuideFor(mem.cls, v)
  Core().log("info", "role " .. v); Core().changed()
end

-- ------------------------------------------------------------------ data per page
local function iconFor(d, it)
  if d and d.spell and d.spell.icon then return d.spell.icon end
  if it and it.group == "helper" then return ns.Macros.HELPER_ICON[it.key] or "INV_Misc_QuestionMark" end
  if d and d.main then return d.main.icon end
  return nil
end
Book.iconFor = iconFor
--- The pictures of a sequence/priority key for a composite icon: the main spell first, then the others (max 4).
function Book.iconsFor(d)
  if not (d and d.steps and #d.steps > 1) then return nil end
  local out, seen = {}, {}
  local function add(s) if s and not seen[s] and #out < 4 then seen[s] = true; out[#out + 1] = s.icon end end
  add(d.main)
  for _, s in ipairs(d.steps) do add(s) end
  return #out > 1 and out or nil
end
--- "SEQ" for a castsequence key, "PRI" for a priority key, nil otherwise.
function Book.badge(d)
  if not (d and d.seq) or d.seq.kind == "single" then return nil end
  return d.seq.base == "priority" and "PRI" or "SEQ"
end
--- "Imm", "SB", "SWP": a step's short name.
function Book.abbrev(name)
  local words = {}
  for w in (name or ""):gmatch("[%a']+") do
    local l = w:lower()
    if l ~= "of" and l ~= "the" then words[#words + 1] = w end
  end
  if #words >= 2 then
    local s = ""
    for _, w in ipairs(words) do s = s .. w:sub(1, 1):upper() end
    return s
  end
  return (words[1] or name or "?"):sub(1, 3)
end
--- "Imm › SB ×4": the steps of a sequence, short.
function Book.stepsShort(steps)
  local out, i = {}, 1
  while steps and i <= #steps do
    local s, n = steps[i], 1
    while steps[i + n] == s do n = n + 1 end
    out[#out + 1] = Book.abbrev(s.name) .. (n > 1 and (" ×" .. n) or "")
    i = i + n
  end
  return table.concat(out, " › ")
end

--- The visible book button of key `name` (where its flight starts), or nil.
function Book.cellFrame(name)
  local p = UI.panels and UI.panels[UI.current]
  if not (p and p.cells and p:IsVisible()) then return nil end
  for _, b in ipairs(p.cells) do if b:IsShown() and b.cell and b.cell.name == name then return b end end
end

-- three looks for a spell: learned (normal), at your trainer now (greyed, gold note), a later level (greyed, dark,
-- a lock, a blue-grey note). Future spells follow the learned ones under a "Future spells" rule, by unlock level.
Book.TRAINER = { 0.9, 0.75, 0.4 }
Book.FUTURE = { 0.62, 0.68, 0.86 }
--- "At your trainer" / "Unlocks at 32" for M.pendingOf's value; nil when the spell is known.
function Book.unlockText(pending)
  if pending == "trainer" then return "At your trainer" end
  if type(pending) == "number" then return "Unlocks at " .. pending end
  return nil
end
local function pendingSt(pending, base)
  local future = type(pending) == "number"
  local st = { off = true, locked = future or nil, subColor = future and Book.FUTURE or Book.TRAINER,
    word = future and ("Unlocks at level " .. pending) or "Learn it at your trainer", color = future and Book.FUTURE or Book.TRAINER }
  if base then st.dot, st.dim = base.dot, base.dim end
  return st
end

--- One key cell: {kind="key", name, label, sub, hot, icon, icons, badge, item, d, st, group}
local function keyCell(ctx, it, d, b)
  local st = Book.statusOf(it, b)
  if d and d.pending and it.status ~= "skipped" then st = pendingSt(d.pending, st) end
  local placed = b and b.status == "placed"
  local keys = ns.Binds.keysFor(it.name, placed and b.slot or nil)
  local direct = {}
  for _, k in ipairs(keys) do if k.via == "macro" then direct[#direct + 1] = ns.Binds.short(k.key) end end
  local sub = ""
  if d and d.steps and #d.steps > 1 then sub = Book.stepsShort(d.steps)
  elseif d and d.pending then sub = Book.unlockText(d.pending)
  elseif placed and it.group ~= "helper" then sub = ns.Bars.slotLabel(b.slot) .. (direct[1] and (" · " .. direct[1]) or "") end
  local hot = keys[1] and ns.Binds.short(keys[1].key) or nil
  return { kind = "key", name = it.name, label = Book.shortLabel(it), sub = sub, hot = hot, icon = iconFor(d, it), item = it, d = d, st = st,
    icons = Book.iconsFor(d), badge = Book.badge(d), group = it.group, keys = keys, bar = b }
end

--- My keys: {sections = {{title, cells}}, helpers = {title, cells}} – the left page's sections and the right page's helpers.
function Book.spread(ctx)
  local out = { sections = { { title = "Spells", cells = {} }, { title = "Sequences", cells = {} } }, helpers = { title = "Squad keys", cells = {} } }
  if not ctx then return out end
  local desiredBy, barOf = {}, {}
  for _, d in ipairs(ctx.desired) do desiredBy[d.name] = d end
  for _, b in ipairs(ctx.bars.items) do barOf[b.name] = b end
  local helperCell = {}
  for _, it in ipairs(ctx.macros.items) do
    local c = keyCell(ctx, it, desiredBy[it.name], barOf[it.name])
    if it.group == "kit" or it.group == "extra" then table.insert(out.sections[1].cells, c)
    elseif it.group == "sequence" then table.insert(out.sections[2].cells, c)
    elseif it.group == "helper" then helperCell[it.key] = c end
  end
  -- squad keys in a fixed order, each with its tick; unticked ones are shown off (nothing is created for them)
  for _, k in ipairs(Book.squadKeyList(ctx)) do
    local c = helperCell[k.key]
    if c then c.squadKey, c.on = k.key, true; out.helpers.cells[#out.helpers.cells + 1] = c
    elseif not k.on then
      out.helpers.cells[#out.helpers.cells + 1] = { kind = "squadkey", squadKey = k.key, on = false, label = k.label, name = false, group = "helper",
        icon = ns.Macros.HELPER_ICON[k.key], st = { off = true, word = "Off – tick it to make the key", color = W.MUTED } }
    end
    if k.key == "Invite" and helperCell.Invite2 then
      local c2 = helperCell.Invite2
      c2.squadKey, c2.on = "Invite", true
      out.helpers.cells[#out.helpers.cells + 1] = c2
    end
  end
  return out
end

--- This character's squad keys with their ticks: {{key, label, on}}.
function Book.squadKeyList(ctx)
  return ns.Macros.squadKeyList(ctx.member, Core().cdb.squadKeys, ctx.squad)
end
--- Tick or untick a squad key for this character (WoWBoxer's own setting; the macro follows on Update keys).
function Book.setSquadKey(key, on)
  Core().cdb.squadKeys[key] = on and true or false
  Core().log("info", "squad key " .. key .. (on and " on" or " off"))
  Core().changed()
end

--- "Rank 3 of 7 · next rank at 30" for a spell with ranks (nil without).
function Book.rankLine(s, level)
  local ranks = s.ranks or {}
  if #ranks < 2 then return nil end
  local now, nx = ns.Kit.rankAt(s, level), ns.Kit.nextRank(s, level)
  local t = now and ("Rank " .. (now.r or "?") .. " of " .. #ranks) or ("Rank 1 at level " .. (ranks[1].l or s.level))
  if now and nx then t = t .. " · next rank at " .. nx.l elseif now then t = t .. " · highest rank" end
  return t
end
--- True when spell s (or one of its ranks) is learned exactly at `level`.
function Book.newAt(s, level)
  if s.level == level then return true end
  for _, r in ipairs(s.ranks or {}) do if r.l == level then return true end end
  return false
end
--- Does spell s match the search text (name or category, any case)?
function Book.matches(s, q)
  if not q or q == "" then return true end
  q = q:lower()
  return (s.name or ""):lower():find(q, 1, true) ~= nil or (type(s.category) == "string" and s.category:lower():find(q, 1, true) ~= nil)
end
--- All spells as two sections: {learned (incl. at your trainer), future = later levels, by unlock level}. q = search.
function Book.spellSections(ctx, q)
  local learned, future = { cells = {} }, { title = "Future spells", cells = {}, future = true }
  if not ctx then return { learned, future } end
  local keyOf = {}
  for _, d in ipairs(ctx.desired) do if d.spell then keyOf[d.spell.id] = d end end
  local m, M = ctx.member, ns.Macros
  local function cell(s, pending)
    local d = keyOf[s.id]
    local key = d and d.name
    local sub, col, word
    if pending ~= nil then
      local st = pendingSt(pending)
      if key then st.word = st.word .. " · already a key" end
      return { kind = "spell", label = s.name, sub = Book.unlockText(pending), icon = s.icon, spell = s, name = key or false, d = d, st = st, pending = pending }
    end
    if key then
      local it
      for _, x in ipairs(ctx.macros.items) do if x.name == key then it = x end end
      sub, col, word = Book.kindName(it or { key = "" }), W.GREEN, "Already a key"
    else sub, col, word = "", W.BLUE, "Drag to your bar" end
    if Book.newAt(s, ctx.level) then
      sub = "|cffb7f07aNew at " .. ctx.level .. "|r" .. (sub ~= "" and (" · " .. sub) or "")
      word = "New at level " .. ctx.level .. " · " .. word
    end
    return { kind = "spell", label = s.name, sub = sub, color = col, icon = s.icon, spell = s, name = key or false, st = { word = word, color = col } }
  end
  local lists = ns.Kit.kitLists(m)
  local shown = {}
  for _, l in ipairs({ lists.primary, lists.others }) do
    for _, s in ipairs(l) do shown[s] = true; if Book.matches(s, q) then learned.cells[#learned.cells + 1] = cell(s, M.pendingOf(m, s, ctx.level, ctx.live)) end end
  end
  local later = {}
  for i, s in ipairs(ns.Kit.spellsOf(m)) do
    if not shown[s] and s.action ~= "passive" and Book.matches(s, q) then
      local p = M.pendingOf(m, s, ctx.level, ctx.live)
      if p == nil then learned.cells[#learned.cells + 1] = cell(s, nil) -- known already (the data says later)
      elseif type(p) == "number" then later[#later + 1] = { s = s, p = p, i = i } end
    end
  end
  table.sort(later, function(a, b)
    if a.p ~= b.p then return a.p < b.p end
    local ca, cb = ns.Kit.catOrder(a.s), ns.Kit.catOrder(b.s)
    if ca ~= cb then return ca < cb end
    return a.i < b.i
  end)
  for _, x in ipairs(later) do local c = cell(x.s, x.p); c.future = true; future.cells[#future.cells + 1] = c end
  return { learned, future }
end

--- Cells for a mode (flat): keys = every key on My keys; spells = every spell; custom = own keys + "New key".
function Book.cells(mode, ctx)
  local out = {}
  if not ctx then return out end
  if mode == "keys" then
    local sp = Book.spread(ctx)
    for _, sec in ipairs(sp.sections) do for _, c in ipairs(sec.cells) do out[#out + 1] = c end end
    for _, c in ipairs(sp.helpers.cells) do out[#out + 1] = c end
    return out
  end
  local desiredBy, barOf = {}, {}
  for _, d in ipairs(ctx.desired) do desiredBy[d.name] = d end
  for _, b in ipairs(ctx.bars.items) do barOf[b.name] = b end
  if mode == "spells" then
    for _, sec in ipairs(Book.spellSections(ctx)) do for _, c in ipairs(sec.cells) do out[#out + 1] = c end end
    return out
  end
  for _, it in ipairs(ctx.macros.items) do
    if it.group == "custom" then out[#out + 1] = keyCell(ctx, it, desiredBy[it.name], barOf[it.name]) end
  end
  if #(ctx.member.customSeq or {}) < ns.State.CUSTOM_MAX then
    out[#out + 1] = { kind = "new", label = "New key", sub = "", icon = "Spell_ChargePositive", name = false, st = { word = "Build your own key", color = W.BLUE } }
  end
  return out
end

--- How many keys of a page ("spells" | "squad") Place would create, update or put on a bar.
function Book.pageWork(ctx, page)
  if not ctx then return 0 end
  local groups = Core().PAGE_GROUPS[page]
  local n, seen = 0, {}
  for _, it in ipairs(Core().onlyGroups(ctx.macros.items, ctx.desired, groups)) do
    if it.status == "create" or it.status == "update" then n = n + 1; seen[it.name] = true end
  end
  local replace = Core().cdb.replace
  for _, b in ipairs(Core().onlyGroups(ctx.bars.items, ctx.desired, groups)) do
    if not seen[b.name] and (b.status == "empty" or b.status == "ours" or b.status == "missing" or (replace and b.status == "occupied")) then n = n + 1 end
  end
  return n
end

-- ------------------------------------------------------------------ the next step (banner)
--- {text (≤ 8 words), tip (sentence), button={label, tip, fn}?} – the one thing to do now on this page.
function Book.nextStep(ctx, mode)
  local cdb = Core().cdb
  local C, B = ns.Compat, ns.Bars
  if not ctx then return { text = "No setup yet", tip = "This character has no WoWBoxer setup yet.",
    button = { "Set up", "Sets up this character (only WoWBoxer's own settings change).", function() Core().ensureMe(); Core().changed() end } } end
  if C.inCombat() then return { text = "|cffff8a80In combat|r", tip = "WoWBoxer changes nothing until the fight is over." } end
  for _, first in ipairs({ cdb.primaryBar or 1, cdb.secondaryBar or 61 }) do
    if not C.barVisible(first) then
      return { text = "|cfff0b43c" .. B.barLabel(first) .. " is hidden|r", tip = "Turn it on in " .. (C.game() == "forever" and "Edit Mode" or "Interface > Action Bars") ..
        ", or choose another bar in Setup.", button = { "Choose bars", "Opens Setup, where you pick the bars WoWBoxer uses.", function() UI.Select("setup") end } }
    end
  end
  if (cdb.primaryBar or 1) == 1 and C.bonusBarOffset() > 0 then
    return { text = "|cfff0b43cBar 1 shows your stance|r", tip = "Bar 1 is showing your stance or form page, so keys on Bar 1 are hidden there.",
      button = { "Move keys", "Moves your main keys to the Bottom Left Bar (placed there when you press Place all).", function()
        cdb.primaryBar, cdb.secondaryBar, cdb.slots = 61, 49, {}; Core().changed() end } }
  end
  local hu, L = ns.Squad.unitHint()
  if hu then
    return { text = "|cfff0b43c" .. L.name .. " is " .. hu .. " here|r", tip = "Your keys follow " .. ctx.member.unit .. ". Use " .. hu .. " instead?",
      button = { "Use " .. hu, "Your keys will use " .. L.name .. " through " .. hu .. " (WoWBoxer's setting; then Update keys).", function() Core().setPlaysAs(hu) end } }
  end
  local lu, ahead = ns.Squad.lineHint()
  if lu then
    return { text = "|cfff0b43c" .. ahead.name .. " is " .. lu .. " here|r", tip = "Follow (line) follows " .. ahead.name .. ". Use " .. lu .. ", then update your keys.",
      button = { "Use " .. lu, "Follow (line) will follow " .. ahead.name .. " through " .. lu .. " (WoWBoxer's setting; then Update keys).", function() Core().setLineUnit(lu) end } }
  end
  local m = ctx.macros
  if m.counts.noslot > 0 then
    return { text = "|cffff8a80No free macro slot|r", tip = m.counts.noslot .. (m.counts.noslot == 1 and " key needs" or " keys need") ..
      " a macro slot. Delete a macro you don't need in the game's macro window (/macro)." }
  end
  local n = m.changes
  if n > 0 then
    if not cdb.lastSync then
      return { text = n .. (n == 1 and " key ready" or " keys ready"), tip = "Drag your keys onto your action bar, or press Place all and WoWBoxer puts them there.",
        button = { "Place all", "Creates your " .. n .. " WoWBoxer macros and puts them on your action bars. Buttons that hold something else are kept (see Setup).", function() Core().sync({ replace = cdb.replace }) end } }
    end
    local names = {}
    for _, it in ipairs(m.items) do if it.status == "create" or it.status == "update" then names[#names + 1] = Book.shortLabel(it) end end
    local lvl = (cdb.lastSync.level or 0) < ctx.level and ("|cffb7f07aLevel " .. ctx.level .. ":|r ") or ""
    return { text = lvl .. n .. (n == 1 and " key changed" or " keys changed"), tip = table.concat(names, ", ") .. ". They stay on the same buttons and keys.",
      button = { "Update keys", "Updates the changed macros. They stay on the same action buttons and keys.", function() Core().sync({ replace = cdb.replace }) end } }
  end
  if ctx.bars.changes > 0 then
    local k = ctx.bars.changes
    return { text = k .. (k == 1 and " key not on a bar" or " keys not on a bar"), tip = "Drag them from the book, or press Place all.",
      button = { "Place all", "Puts the keys that are not on a bar onto your action bars. Buttons that hold something else are kept.", function() Core().sync({ replace = cdb.replace }) end } }
  end
  if #ctx.missing > 0 then
    local names = {}
    for _, s in ipairs(ctx.missing) do names[#names + 1] = s.name end
    return { text = "Visit your trainer", tip = table.concat(names, ", ") .. ". They join your keys when you have learned them." }
  end
  -- talent points to spend (display only: the player spends them in the game's talent window)
  local free = C.unspentTalentPoints(ctx.member, ctx.level)
  if free and free > 0 then
    local nt = ns.Squad.nextTalent(ctx.member)
    return { text = free .. (free == 1 and " talent point to spend" or " talent points to spend"),
      tip = (nt and ("Your guide takes " .. nt.name .. " next. ") or "") .. "Spend it in the game's talent window (N).",
      button = { "Talents", "Opens WoWBoxer's Talents page: your guide's next points.", function() UI.Select("talents") end } }
  end
  if mode == "spells" then return { text = "Drag a spell to your bar", tip = "Any spell you drag becomes a WoWBoxer key for this character." } end
  if mode == "custom" then return { text = "Build your own keys", tip = "A sequence of your spells. One press is still one spell." } end
  -- the trainer to-do: the next level that brings something new (display only)
  local tl, names = ns.Squad.nextTrainer(ctx.member)
  if tl and tl <= ctx.level + 4 then
    return { text = "|cff8fbf6aAll set|r · trainer at " .. tl .. ": " .. names[1] .. (#names > 1 and (" +" .. (#names - 1)) or ""),
      tip = "At level " .. tl .. " your trainer has " .. table.concat(names, ", ") .. ". Your keys update after you learn them.",
      button = { "Key bindings", "Opens the game's key bindings, so you can choose which keys press your action buttons.", function() Core().openKeyBindings() end } }
  end
  return { text = "|cff8fbf6aAll keys on your bars|r", tip = "Hover a key to see what it does; drag it to move it.",
    button = { "Key bindings", "Opens the game's key bindings, so you can choose which keys press your action buttons.", function() Core().openKeyBindings() end } }
end

-- ------------------------------------------------------------------ key capture (bind a key to one WBX macro)
local function buildCapture(p)
  local c = W.box(p, 0.12, 0.09, 0.04, 0.98)
  c:SetPoint("TOPLEFT", 120, -110)
  c:SetPoint("BOTTOMRIGHT", -120, 110)
  c:SetFrameLevel((p:GetFrameLevel() or 1) + 30)
  c:EnableMouse(true)
  c.wbxModal = true
  c.text = W.text(c, "GameFontHighlight", nil, W.TEXT, "CENTER")
  c.text:SetPoint("TOPLEFT", 12, -14)
  c.text:SetPoint("TOPRIGHT", -12, -14)
  c.text.wbxCopy = "guide"
  c.cancel = W.button(c, "Cancel", 80, 22, function() c:Stop() end, "Stops waiting for a key. Nothing changes.")
  c.cancel:SetPoint("BOTTOM", 0, 10)
  -- a question: Yes (do it) / No (wait for another key)
  c.yes = W.button(c, "Yes", 90, 22, function() if c.onYes then local f = c.onYes; c:Stop(); f() end end, "Does what the question says.")
  c.yes:SetPoint("BOTTOMRIGHT", c, "BOTTOM", -4, 38)
  c.no = W.button(c, "No", 90, 22, function() c:Wait() end, "Nothing changes; press another key.")
  c.no:SetPoint("BOTTOMLEFT", c, "BOTTOM", 4, 38)
  c:Hide()
  function c:Wait()
    self.pending, self.onYes = nil, nil
    self.yes:Hide(); self.no:Hide(); W.setLabel(self.cancel, "Cancel")
    self.text:SetText("Press a key for |cffffd100" .. self.label .. "|r.\n\nEsc cancels.")
  end
  --- Ask a plain question; yes runs fn (pressing the same key again also counts as yes).
  function c:Ask(text, yes, no, fn, key)
    self.pending, self.onYes = key, fn
    self.text:SetText(text)
    W.setLabel(self.yes, yes); W.setLabel(self.no, no)
    self.yes:Show(); self.no:Show()
  end
  function c:Start(name, label)
    self.name, self.label = name, label or name
    self:Wait()
    self:Show()
    if self.EnableKeyboard then self:EnableKeyboard(true) end
    if self.SetPropagateKeyboardInput then self:SetPropagateKeyboardInput(false) end
  end
  function c:Stop()
    if self.EnableKeyboard then self:EnableKeyboard(false) end
    self:Hide()
  end
  c:SetScript("OnKeyDown", function(self, key)
    if key == "ESCAPE" then self:Stop(); return end
    local full = ns.Binds.compose(key, _G.IsAltKeyDown and _G.IsAltKeyDown(), _G.IsControlKeyDown and _G.IsControlKeyDown(),
      _G.IsShiftKeyDown and _G.IsShiftKeyDown())
    if not full then return end -- a modifier on its own: wait for the real key
    Book.onBindKey(self, full)
  end)
  return c
end

--- What a pressed key means for the key being bound (docs/feedback-2026-10-29-evening.md §3). A key that presses an
--- action button is not a conflict: an empty button gets the key placed on it, the same key there is "Already on",
--- a button with something else asks first. Other game bindings ask in plain words. Never shows command names.
function Book.onBindKey(c, full)
  local name, KB = c.name, ns.Binds
  if c.pending == full and c.onYes then local f = c.onYes; c:Stop(); f(); return end -- the same key again = Yes
  local k = KB.classify(name, full)
  if k.kind == "free" then c:Stop(); Core().bindKey(name, full); return end
  if k.kind == "same" then
    c.yes:Hide(); c.no:Hide(); c.pending, c.onYes = nil, nil
    c.text:SetText("Already on |cffffd100" .. full .. "|r.\n\nPress another key, or Close.")
    W.setLabel(c.cancel, "Close")
    return
  end
  if k.kind == "button" then
    if k.empty then c:Stop(); Core().placeOn(name, k.slot, full); return end
    c:Ask("|cffffd100" .. full .. "|r is " .. KB.buttonName(k.slot) .. " (" .. k.what .. ").\nPut this key there?", "Put it there", "Another key",
      function() Core().placeOn(name, k.slot, full) end, full)
    return
  end
  c:Ask("|cffffd100" .. full .. "|r is " .. k.text .. " now.\nUse it for " .. c.label .. " anyway?", "Yes", "No",
    function() Core().bindKey(name, full) end, full)
end

-- ------------------------------------------------------------------ actions on one key
local function pickupResult(ok, why) if not ok and why then Core().print("|cffff8a80" .. why .. "|r") end end
local function pickupCell(c)
  if not c then return end
  if c.kind == "spell" and not c.name then pickupResult(Core().pickupSpell(c.spell.id))
  elseif c.name then pickupResult(Core().pickup(c.name)) end
end
local function setSkip(name, skip) Core().cdb.skip[name] = skip or nil; Core().changed() end
local function directBound(c)
  for _, k in ipairs(c.keys or {}) do if k.via == "macro" then return true end end
  return false
end

--- Menu entries for a cell (right-click, Shift-click).
function Book.menuFor(p, c)
  local items = {}
  if ns.Compat.inCombat() then return { { "Not in combat – try again after the fight", function() end } } end
  if c.kind == "new" then return { { "New own key", function() ns.KeyEditor.Open(p, nil) end } } end
  if c.kind == "squadkey" then return { { "Make this key", function() Book.setSquadKey(c.squadKey, true) end } } end
  if c.kind == "spell" and not c.name then
    items[#items + 1] = { c.pending and "Pick up (key works once learned)" or "Pick up (make a key)", function() pickupCell(c) end }
    return items
  end
  items[#items + 1] = { "Pick up", function() pickupCell(c) end }
  items[#items + 1] = { "Bind key…", function() p.capture:Start(c.name, c.label) end }
  if c.item and c.item.status == "skipped" then items[#items + 1] = { "Use again", function() setSkip(c.name, false) end }
  elseif c.item then items[#items + 1] = { "Leave out", function() setSkip(c.name, true) end } end
  if c.item and c.item.status ~= "skipped" then
    if c.bar and c.bar.status == "off" then
      items[#items + 1] = { "Allow on my bars", function() Core().setKeptOff(c.name, false) end, "Place all puts this key on your bars again, and WoWBoxer reminds you when it is not on a bar." }
    elseif not (c.bar and c.bar.status == "placed") then
      items[#items + 1] = { "Keep off my bars", function() Core().setKeptOff(c.name, true) end, "Place all leaves this key off your bars and WoWBoxer never reminds you about it. You can still drag it." }
    end
  end
  local i = c.name and tonumber(c.name:match("^WBX C(%d)$"))
  if i then items[#items + 1] = { "Edit", function() ns.KeyEditor.Open(p, i) end } end
  if c.d and c.d.body then items[#items + 1] = { "Copy…", function() Book.copyKey(c) end } end
  if directBound(c) then items[#items + 1] = { "Unbind", function() Core().unbindKey(c.name) end } end
  return items
end

--- Show a key's macro text (and, for own keys, a WoWBoxer key string) to copy and give to others.
function Book.copyKey(c)
  local _, m = Core().me()
  local i = c.name and tonumber(c.name:match("^WBX C(%d)$"))
  local own = i and m and m.customSeq and m.customSeq[i]
  ns.CopyBox.ShowCopy("Copy \"" .. (c.label or "key") .. "\"", c.d.body, own and ns.Share.encodeKey(own, m.cls) or nil)
end

--- Tooltip of a book button: name, status word, one sentence, steps, macro text, how to use it.
local function cellTooltip(GT, c)
  GT:AddLine(c.label, 1, 0.82, 0)
  if c.st and c.st.word then GT:AddLine(c.st.word, c.st.color[1], c.st.color[2], c.st.color[3]) end
  if c.kind == "new" then GT:AddLine("Click to build your own key: a sequence of your spells, one spell per press.", 1, 1, 1, true); return end
  if c.kind == "squadkey" then GT:AddLine(Book.helperShort(c.squadKey) .. " Tick the box to make this key.", 1, 1, 1, true); return end
  local d = c.d
  if c.kind == "spell" and not d then
    d = { group = "extra", label = c.spell.name, body = ns.Engine.makeMacro(c.spell, ns.Kit.memberCtx(ns.Core.compute().member)) }
  end
  if c.group == "helper" then GT:AddLine(Book.helperText(c.item.key), 1, 1, 1, true)
  else GT:AddLine(Book.describe(d, nil), 1, 1, 1, true) end
  if d and d.steps and #d.steps > 1 then GT:AddLine(W.stepsText(d.steps), 0.85, 0.72, 1, true) end
  if d and d.seq and d.seq.label == "Combo" then
    local _, me = Core().me()
    if me and not me.leader then
      -- [AFKLAR: do combo points add up on [@party1target] when your own target is something else?]
      GT:AddLine("Combo points stay on your own target: if they don't add up, press Assist first (one press).", 1, 0.82, 0.4, true)
    end
  end
  local sp = c.spell or (d and d.spell)
  if sp then local rl = Book.rankLine(sp, ns.Compat.playerLevel()); if rl then GT:AddLine(rl, 0.8, 0.8, 0.8, true) end end
  if d and d.body then for line in (d.body .. "\n"):gmatch("([^\n]*)\n") do if line ~= "" then GT:AddLine(line, 0.56, 0.85, 0.45) end end end
  if c.item and c.item.why then GT:AddLine(c.item.why, 1, 0.54, 0.5, true) end
  local pending = c.pending or (c.d and c.d.pending)
  if pending then
    GT:AddLine((type(pending) == "number" and ("You learn this at level " .. pending .. ".") or "Learn it at your trainer.") ..
      " Place it now: the key does nothing until you know the spell, then it just works.", Book.FUTURE[1], Book.FUTURE[2], Book.FUTURE[3], true)
  end
  GT:AddLine("Drag to your bar · Right-click: more", 0.66, 0.6, 0.49)
end

-- ------------------------------------------------------------------ build
--- A spellbook button. small = a helper (28 px, silver, desaturated, grey name, no second line).
local function makeCell(p, parent, small)
  local b = CreateFrame("Button", nil, parent)
  local S = small and 26 or 35
  b:SetSize(small and HELP_W or CELL_W, small and HELP_H or CELL_H)
  b.small = small
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:RegisterForDrag("LeftButton")
  b.slotBg = b:CreateTexture(nil, "BACKGROUND")
  b.slotBg:SetSize(S + 2, S + 2)
  b.slotBg:SetPoint("LEFT", 2, 0)
  b.slotBg:SetColorTexture(0, 0, 0, 0.55)
  b.icon = W.icon(b, S, small)
  b.icon:SetPoint("CENTER", b.slotBg, "CENTER", 0, 0)
  if small then b.icon.border:SetColorTexture(0.72, 0.74, 0.78, 1) end
  b.multi = W.composite(b, b.icon)
  b.frame = b:CreateTexture(nil, "OVERLAY")
  b.frame:SetSize(S * 1.8, S * 1.8)
  b.frame:SetPoint("CENTER", b.slotBg, "CENTER", 0, 0)
  b.frame:SetTexture("Interface\\Buttons\\UI-Quickslot2")
  if small then b.frame:Hide() end
  -- the key on the icon, like an action bar hotkey (white, top-left)
  b.hot = W.line(b, "NumberFontNormal", small and 9 or 10, { 1, 1, 1 })
  b.hot:SetPoint("TOPLEFT", b.slotBg, "TOPLEFT", 2, -2)
  b.hot:SetPoint("TOPRIGHT", b.slotBg, "TOPRIGHT", -2, -2)
  b.hot.wbxCopy = "data"
  b.badge = W.text(b, "GameFontHighlightSmall", 8, { 0.85, 0.72, 1 })
  b.badge:SetPoint("BOTTOMLEFT", b.slotBg, "BOTTOMLEFT", 2, 2)
  b.badge.wbxCopy = "data"
  b.badgeBg = b:CreateTexture(nil, "OVERLAY")
  b.badgeBg:SetPoint("TOPLEFT", b.badge, "TOPLEFT", -1, 1)
  b.badgeBg:SetPoint("BOTTOMRIGHT", b.badge, "BOTTOMRIGHT", 1, -1)
  b.badgeBg:SetColorTexture(0.32, 0.2, 0.52, 0.85)
  -- status: changed = a dot on the icon corner, new = the new-spell glow
  b.dot = b:CreateTexture(nil, "OVERLAY")
  b.dot:SetSize(small and 9 or 11, small and 9 or 11)
  b.dot:SetPoint("CENTER", b.slotBg, "TOPRIGHT", -2, -2)
  b.dot:SetTexture("Interface\\COMMON\\Indicator-Yellow")
  b.glow = b:CreateTexture(nil, "OVERLAY")
  b.glow:SetSize(S * 1.95, S * 1.95)
  b.glow:SetPoint("CENTER", b.slotBg, "CENTER", 0, 0)
  b.glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
  if b.glow.SetBlendMode then b.glow:SetBlendMode("ADD") end
  b.glow:SetVertexColor(1, 0.9, 0.5, 0.95)
  -- a later-level spell: a padlock on the icon and a cool tint behind the button
  b.lock = b:CreateTexture(nil, "OVERLAY")
  b.lock:SetSize(small and 14 or 18, small and 14 or 18)
  b.lock:SetPoint("BOTTOMRIGHT", b.slotBg, "BOTTOMRIGHT", 3, -3)
  b.lock:SetTexture("Interface\\Buttons\\LockButton-Locked-Up")
  b.lock:Hide()
  b.tint = b:CreateTexture(nil, "BACKGROUND")
  b.tint:SetAllPoints()
  b.tint:SetColorTexture(0.3, 0.36, 0.55, 0.16)
  b.tint:Hide()
  b.sel = b:CreateTexture(nil, "BACKGROUND")
  b.sel:SetAllPoints()
  b.sel:SetColorTexture(1, 0.82, 0, 0.13)
  local hl = b:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints()
  hl:SetColorTexture(1, 1, 1, 0.07)
  if small then
    b.name = W.text(b, "GameFontHighlight", 11, { 0.8, 0.8, 0.8 })
    b.name:SetPoint("LEFT", b.slotBg, "RIGHT", 6, 0)
    b.name:SetPoint("RIGHT", b, "RIGHT", -24, 0)
    -- squad keys: the player ticks which ones this character gets
    b.tick = W.frame("CheckButton", b, "UICheckButtonTemplate")
    b.tick:SetSize(20, 20)
    b.tick:SetPoint("RIGHT", -2, 0)
    b.tick:SetScript("OnClick", function(self) if b.cell and b.cell.squadKey then Book.setSquadKey(b.cell.squadKey, self:GetChecked() and true or false) end end)
    W.tip(b.tick, "Squad key", function() return (b.cell and b.cell.on) and "Ticked: WoWBoxer makes this key. Untick to leave it out." or "Tick to make this key." end)
    if b.name.SetMaxLines then b.name:SetMaxLines(1) end
  else
    b.name = W.text(b, "GameFontNormal", nil, W.GOLD)
    b.name:SetWidth(CELL_W - S - 13)
    if b.name.SetMaxLines then b.name:SetMaxLines(2) end
    b.sub = W.line(b, "GameFontHighlightSmall", nil, W.MUTED)
    b.sub:SetPoint("TOPLEFT", b.name, "BOTTOMLEFT", 0, -3)
    b.sub:SetWidth(CELL_W - S - 13)
    b.sub.wbxCopy = "data"
  end
  b.name.wbxName, b.name.wbxCopy = true, "data"
  b:SetScript("OnClick", function(self, button)
    local c = self.cell
    if not c then return end
    if button == "RightButton" or (_G.IsShiftKeyDown and _G.IsShiftKeyDown()) then W.menu(self, Book.menuFor(p, c)); return end
    if c.kind == "new" then ns.KeyEditor.Open(p, nil); return end
    if p.mode == "custom" then
      local i = c.name and tonumber(c.name:match("^WBX C(%d)$"))
      if i then ns.KeyEditor.Open(p, i) end
      return
    end
    if p.mode ~= "keys" then return end
    p.selected = c.name or nil
    UI.Refresh()
  end)
  b:SetScript("OnDragStart", function(self) if self.cell and self.cell.kind ~= "new" then pickupCell(self.cell) end end)
  W.tooltip(b, function(GT, self) if self.cell then cellTooltip(GT, self.cell) end end)
  return b
end

--- Show cell data c on button b.
local function paintCell(p, b, c)
  b.cell = c
  local st = c.st or {}
  W.setIcon(b.icon, c.icon)
  if c.icons then b.multi.set(c.icons, b.small and 26 or 35); b.icon:SetAlpha(0) else b.multi.Hide() end
  b.badge:SetText(c.badge or ""); b.badge:SetShown(c.badge ~= nil); b.badgeBg:SetShown(c.badge ~= nil)
  b.hot:SetText(c.hot or "")
  b.name:SetText(c.label)
  local grey = b.small or st.off
  if b.icon.SetDesaturated then b.icon:SetDesaturated(grey and true or false) end
  b.multi:SetDesaturated(grey and true or false)
  local a = st.locked and 0.4 or st.off and 0.6 or 1
  if not c.icons then b.icon:SetAlpha(a) end
  b.multi:SetAlpha(a)
  b.lock:SetShown(st.locked and true or false)
  b.tint:SetShown(st.locked and true or false)
  if not b.small then
    if c.badge then b.frame:SetVertexColor(0.72, 0.55, 1) else b.frame:SetVertexColor(1, 1, 1) end
    b.frame:SetAlpha(st.dim and 0.35 or 1)
    -- one line when the name needs two; the second line only when it adds something
    local two = (b.name:GetStringWidth() or 0) > CELL_W - 48 + 0.5
    local showSub = not two and (c.sub or "") ~= ""
    b.sub:SetText(showSub and c.sub or "")
    b.sub:SetShown(showSub)
    local sc = c.badge and { 0.85, 0.72, 1 } or st.subColor or W.MUTED
    b.sub:SetTextColor(sc[1], sc[2], sc[3])
    b.name:ClearAllPoints()
    if showSub then b.name:SetPoint("TOPLEFT", b.slotBg, "TOPRIGHT", 7, -2)
    else b.name:SetPoint("LEFT", b.slotBg, "RIGHT", 7, 0) end
    local nc = st.locked and { 0.55, 0.56, 0.6 } or st.off and W.MUTED or W.GOLD
    b.name:SetTextColor(nc[1], nc[2], nc[3])
  else
    b.icon.border:SetAlpha(st.dim and 0.35 or 1)
    b.tick:SetShown(c.squadKey ~= nil)
    b.tick:SetChecked(c.on and true or false)
    b.tick:SetEnabled(not ns.Compat.inCombat())
  end
  b.dot:SetShown(st.dot ~= nil)
  if st.dot then b.dot:SetVertexColor(st.dot[1], st.dot[2], st.dot[3]) end
  b.glow:SetShown(st.glow and true or false)
  local id = c.name or nil
  b.sel:SetShown(p.mode == "keys" and id ~= nil and id == p.selected)
  b:Show()
end

--- A section header: small gold text + a thin line to the page edge (never a grid cell).
local function makeRule(parent, width)
  local r = CreateFrame("Frame", nil, parent)
  r:SetSize(width, RULE_H - 4)
  r.text = W.text(r, "GameFontNormalSmall", nil, W.GOLD)
  r.text:SetPoint("LEFT", 0, 0)
  r.text.wbxCopy = "label"
  r.line = r:CreateTexture(nil, "ARTWORK")
  r.line:SetHeight(1)
  r.line:SetPoint("LEFT", r.text, "RIGHT", 6, 0)
  r.line:SetPoint("RIGHT", r, "RIGHT", 0, 0)
  r.line:SetColorTexture(1, 0.82, 0, 0.35)
  r.wbxRule = true
  return r
end

--- Page layout: sections → {{rule=title, y} | {cell, y, col}} per page (a rule always has a row under it).
function Book.flow(sections, height, cols, pitch)
  local pages, page, y = {}, {}, 0
  local function newPage() if #page > 0 then pages[#pages + 1] = page end page, y = {}, 0 end
  for _, sec in ipairs(sections) do
    if #sec.cells > 0 then
      if sec.title then
        if y > 0 and y + RULE_H + pitch > height then newPage() end
        page[#page + 1] = { rule = sec.title, y = y }; y = y + RULE_H
      end
      for i = 1, #sec.cells, cols do
        if y + pitch > height then
          newPage()
          if sec.title then page[#page + 1] = { rule = sec.title, y = y }; y = y + RULE_H end
        end
        for j = 0, cols - 1 do
          if sec.cells[i + j] then page[#page + 1] = { cell = sec.cells[i + j], y = y, col = j } end
        end
        y = y + pitch
      end
      y = y + 4
    end
  end
  newPage()
  if #pages == 0 then pages[1] = {} end
  return pages
end

local function build(p, mode)
  p.mode, p.page = mode, 1
  local PW, RX, PH = Book.pageGeom()
  local body = CreateFrame("Frame", nil, p)
  body:SetAllPoints()
  p.body = body
  p.left = CreateFrame("Frame", nil, body)
  p.left:SetPoint("TOPLEFT", 0, 0)
  p.left:SetSize(PW, PH)
  p.right = CreateFrame("Frame", nil, body)
  p.right:SetPoint("TOPLEFT", RX, 0)
  p.right:SetSize(PW, PH)

  -- banner (left page): the next step, ≤ 8 words, the sentence in the tooltip
  p.strip = W.box(p.left, 0.13, 0.17, 0.08, 0.95)
  p.strip:SetPoint("TOPLEFT", 0, 0)
  p.strip:SetSize(PW, 28)
  p.stepBtn = W.button(p.strip, "Place all", 80, 22, function() if p.stepFn then p.stepFn() end end)
  p.stepBtn:SetPoint("RIGHT", -3, 0)
  W.tip(p.stepBtn, function() return p.stepBtn:GetText() end, function() return p.stepBtnTip end)
  p.stepText = W.text(p.strip, "GameFontHighlight", nil, W.TEXT)
  p.stepText:SetPoint("LEFT", 8, 0)
  p.stepText:SetPoint("RIGHT", p.stepBtn, "LEFT", -6, 0)
  if p.stepText.SetMaxLines then p.stepText:SetMaxLines(1) end
  p.stepText.wbxCopy = "hint"
  local stepHit = CreateFrame("Frame", nil, p.strip)
  stepHit:SetAllPoints(p.stepText)
  W.tooltip(stepHit, function(GT) GT:AddLine(p.stepText:GetText() or "", 1, 0.82, 0); if p.stepTip then GT:AddLine(p.stepTip, 1, 1, 1, true) end end)

  p.cells, p.cellPool, p.rules = {}, {}, {}
  p.listH = PH - TOP_H - BOTTOM_H
  if mode == "keys" then
    -- right page: role, plays as, sequence keys
    local function me() local _, mem = Core().me(); return mem end
    p.role = W.dropdown(p.right, { width = 104, values = function() return Book.roleValues(me()) end,
      get = function() local mem = me(); return mem and mem.role end,
      set = function(v) Book.setRole(me(), v) end })
    local rl = W.labelled(p.right, "Role", p.role)
    rl:SetPoint("TOPLEFT", 0, -5)
    W.ddTip(p.role, "Role", "Picks the recommended keys and talent guide for this character. Nothing changes in the game until you place or update keys.")
    p.playsAs = W.dropdown(p.right, { width = 150, values = function() return Book.playsAsValues(me()) end,
      get = function() local mem = me(); return mem and (mem.leader and "leader" or mem.unit) end,
      set = function(v) Core().setPlaysAs(v) end })
    p.playsAs:SetPoint("LEFT", p.role, "RIGHT", 8, 0)
    W.ddTip(p.playsAs, "Plays as", "Leader: your keys use your own target. Follower: where the leader is in your party here (party1–4 or focus) – your keys use the leader's target through it. Your place in the follow line is the squad order. One key press is still one action on this character.")
    p.seq = W.seqControl(p.right, { member = me, width = 96 })
    p.seq:SetPoint("TOPLEFT", 0, -30)
    p.helperPool = {}
    -- the selected key
    p.det = CreateFrame("Frame", nil, p.right)
    p.det:SetPoint("BOTTOMLEFT", 0, 0)
    p.det:SetPoint("BOTTOMRIGHT", 0, 0)
    p.det.rule = makeRule(p.det, PW)
    p.det.rule:SetPoint("TOPLEFT", 0, 0)
    p.det.rule.text:SetText("Selected")
    p.detIconBg = p.det:CreateTexture(nil, "BACKGROUND")
    p.detIconBg:SetSize(37, 37)
    p.detIconBg:SetPoint("TOPLEFT", 0, -RULE_H - 2)
    p.detIconBg:SetColorTexture(0, 0, 0, 0.55)
    p.detIcon = W.icon(p.det, 35, true)
    p.detIcon:SetPoint("CENTER", p.detIconBg, "CENTER", 0, 0)
    p.detName = W.text(p.det, "GameFontNormal", nil, W.GOLD)
    p.detName:SetPoint("TOPLEFT", p.detIconBg, "TOPRIGHT", 8, -2)
    p.detName:SetWidth(PW - 45)
    if p.detName.SetMaxLines then p.detName:SetMaxLines(1) end
    p.detName.wbxName, p.detName.wbxCopy = true, "data"
    p.detSub = W.line(p.det, "GameFontHighlightSmall", nil, W.MUTED)
    p.detSub:SetPoint("TOPLEFT", p.detName, "BOTTOMLEFT", 0, -4)
    p.detSub:SetWidth(PW - 45)
    p.detSub.wbxCopy = "data"
    p.detDesc = W.text(p.det, "GameFontHighlightSmall", nil, W.TEXT)
    p.detDesc:SetPoint("TOPLEFT", p.detIconBg, "BOTTOMLEFT", 0, -6)
    p.detDesc:SetWidth(PW)
    if p.detDesc.SetMaxLines then p.detDesc:SetMaxLines(2) end
    p.detDesc.wbxCopy = "sentence"
    p.detMacro = W.text(p.det, "GameFontHighlightSmall", 9, { 0.6, 0.66, 0.52 })
    p.detMacro:SetPoint("TOPLEFT", p.detDesc, "BOTTOMLEFT", 0, -5)
    p.detMacro:SetPoint("BOTTOMRIGHT", p.det, "BOTTOMRIGHT", 0, 28)
    p.detMacro:SetJustifyV("TOP")
    if p.detMacro.SetNonSpaceWrap then p.detMacro:SetNonSpaceWrap(true) end
    p.detMacro.wbxCopy = "data"
    p.bind = W.button(p.det, "Bind key", 76, 22, function() if p.selected then p.capture:Start(p.selected, p.selLabel) end end,
      "Press a key to run this macro directly, also when it is not on a bar. Saved for this character only. Right-click a key for more.")
    p.bind:SetPoint("BOTTOMLEFT", 0, 0)
    -- one Place button per page: the left page's spells, the right page's squad keys (same rules as Place all)
    p.placeLeft = W.button(p.left, "Place spells", 100, 22, function() Core().sync({ replace = Core().cdb.replace, page = "spells" }) end,
      "Creates or updates your spell and sequence keys and puts them on empty or WoWBoxer buttons (others only with Replace buttons in Setup). Keys you keep off your bars stay off.")
    p.placeLeft:SetPoint("BOTTOMLEFT", 32, 2)
    p.placeLeft.wbxBig = true
    p.placeRight = W.button(p.right, "Place squad keys", 120, 20, function() Core().sync({ replace = Core().cdb.replace, page = "squad" }) end,
      "Creates or updates your squad keys (Invite, Follow, Assist, pet keys …) and puts them on empty or WoWBoxer buttons. Keys you keep off your bars stay off.")
    p.placeRight.wbxBig = true -- the right page's one action (the owner's wording)
    -- footer
    p.slots = W.text(p.right, "GameFontHighlightSmall", nil, W.MUTED, "RIGHT")
    p.slots:SetPoint("BOTTOMRIGHT", 0, 6)
    p.slots.wbxCopy = "status"
    local slotsHit = CreateFrame("Frame", nil, p.right)
    slotsHit:SetAllPoints(p.slots)
    W.tooltip(slotsHit, function(GT) GT:AddLine("Character macros", 1, 0.82, 0); GT:AddLine(p.slotsTip or "", 1, 1, 1, true) end)
  else
    p.hint = W.text(p.right, "GameFontHighlightSmall", nil, W.MUTED)
    p.hint:SetPoint("TOPLEFT", 4, -8)
    p.hint:SetText(mode == "spells" and "Grey: at your trainer · Lock: later levels" or "Up to 8 own keys")
    p.hint.wbxCopy = "hint"
    if mode == "spells" then
      -- search: name or category
      p.search = W.frame("EditBox", p.right, "InputBoxTemplate")
      p.search:SetSize(120, 20)
      p.search:SetAutoFocus(false)
      p.search:SetMaxLetters(30)
      p.search:SetPoint("TOPRIGHT", p.right, "TOPRIGHT", -2, -5)
      p.hint:SetText("Grey: trainer · Lock: later")
      p.hint:SetPoint("RIGHT", p.search, "LEFT", -12, 0)
      p.search:SetScript("OnTextChanged", function(self) local t = self:GetText() or ""; if t ~= (p.query or "") then p.query = t; p.page = 1; UI.Refresh() end end)
      p.search:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)
      p.search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
      W.tip(p.search, "Search spells", "Type part of a spell's name or its kind (Heal, Buff, …). Esc clears it.")
    end
  end
  p.empty = W.text(p.left, "GameFontHighlight", nil, W.MUTED, "CENTER")
  p.empty:SetPoint("TOPLEFT", 10, -TOP_H - 30)
  p.empty:SetPoint("TOPRIGHT", -10, -TOP_H - 30)
  p.empty.wbxCopy = "hint"

  -- pager (left page, bottom)
  p.prev = CreateFrame("Button", nil, p.left)
  p.prev:SetSize(26, 26)
  p.prev:SetPoint("BOTTOMLEFT", 0, 0)
  p.prev:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up")
  p.prev:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Down")
  p.prev:SetDisabledTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Disabled")
  p.prev:SetScript("OnClick", function() p.page = math.max(1, p.page - 1); UI.Refresh() end)
  W.tip(p.prev, "Previous page")
  p.next = CreateFrame("Button", nil, p.left)
  p.next:SetSize(26, 26)
  p.next:SetPoint("BOTTOMRIGHT", 0, 0)
  p.next:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up")
  p.next:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Down")
  p.next:SetDisabledTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Disabled")
  p.next:SetScript("OnClick", function() p.page = p.page + 1; UI.Refresh() end)
  W.tip(p.next, "Next page")
  p.pageText = W.text(p.left, "GameFontNormalSmall", nil, W.GOLD, "CENTER")
  p.pageText:SetPoint("BOTTOM", 0, 8)
  p.pageText.wbxCopy = "status"

  p.capture = buildCapture(p)
  if mode == "keys" then Book.buildGuide(p) end
end

-- ------------------------------------------------------------------ refresh
local function getCell(p, i)
  local b = p.cellPool[i]
  if not b then b = makeCell(p, p.left); p.cellPool[i] = b end
  return b
end
local function getRule(p, i)
  local r = p.rules[i]
  if not r then r = makeRule(p.left, Book.pageGeom()); p.rules[i] = r end
  return r
end
local function getHelper(p, i)
  local b = p.helperPool[i]
  if not b then b = makeCell(p, p.right, true); p.helperPool[i] = b end
  return b
end

--- Place one flowed page on `page` (left/right frame); returns the next free cell/rule index.
local function placePage(p, page, items, ci, ri)
  for _, e in ipairs(items or {}) do
    if e.rule then
      local r = getRule(p, ri); ri = ri + 1
      r:SetParent(page); r:ClearAllPoints()
      r:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -TOP_H - e.y)
      r.text:SetText(e.rule)
      r:Show()
    else
      local b = getCell(p, ci); ci = ci + 1
      b:SetParent(page); b:ClearAllPoints()
      b:SetPoint("TOPLEFT", page, "TOPLEFT", e.col * (CELL_W + 6), -TOP_H - e.y)
      paintCell(p, b, e.cell)
      p.cells[#p.cells + 1] = b
    end
  end
  return ci, ri
end

local function refresh(p, ctx)
  local step = Book.nextStep(ctx, p.mode)
  p.stepText:SetText(step.text)
  p.stepTip = step.tip
  if step.button then
    W.setLabel(p.stepBtn, step.button[1]); p.stepBtnTip, p.stepFn = step.button[2], step.button[3]
    p.stepBtn:Show(); p.stepBtn:SetEnabled(not ns.Compat.inCombat())
  else p.stepBtn:Hide(); p.stepFn = nil end
  p.stepText:SetPoint("RIGHT", step.button and p.stepBtn or p.strip, step.button and "LEFT" or "RIGHT", -6, 0)
  for _, b in ipairs(p.cellPool) do b:Hide(); b.cell = nil end
  for _, r in ipairs(p.rules) do r:Hide() end
  for _, b in ipairs(p.helperPool or {}) do b:Hide(); b.cell = nil end
  p.cells = {}
  if not ctx then if p.det then p.det:Hide() end; return end
  if p.role then p.role.Refresh(); p.playsAs.Refresh(); p.seq.Refresh() end

  local pages, spread
  if p.mode == "keys" then
    spread = Book.spread(ctx)
    pages = Book.flow(spread.sections, p.listH, 2, PITCH)
  elseif p.mode == "spells" then
    -- one flow: the known spells, then a "Future spells" rule (repeated on each page) and the later ones
    pages = Book.flow(Book.spellSections(ctx, p.query), p.listH, 2, PITCH)
  else
    local list = Book.cells(p.mode, ctx)
    local per = math.floor(p.listH / PITCH) * 2
    pages = {}
    for i = 1, math.max(1, math.ceil(#list / per)) do
      local chunk = {}
      for j = (i - 1) * per + 1, math.min(#list, i * per) do chunk[#chunk + 1] = list[j] end
      pages[i] = Book.flow({ { cells = chunk } }, p.listH, 2, PITCH)[1]
    end
  end
  -- My keys: one page of the list per spread (the right page holds helpers + details); the others: two per spread
  local perSpread = p.mode == "keys" and 1 or 2
  local spreads = math.max(1, math.ceil(#pages / perSpread))
  p.page = math.min(p.page or 1, spreads)
  local first = (p.page - 1) * perSpread
  local lead = pages[first + 1] and pages[first + 1][1]
  if p.mode == "spells" and lead and (lead.rule or (lead.cell and lead.cell.future)) then
    -- a spread of only future spells: the banner says what these are (it replaces the next step there)
    p.stepText:SetText("|cff9eaddbFuture spells – place them now|r")
    p.stepTip = "You learn these later: the level is under each spell. Drag one onto your bar now and set it up; the key does nothing until you learn the spell, then it just works."
    p.stepBtn:Hide(); p.stepFn = nil
    p.stepText:SetPoint("RIGHT", p.strip, "RIGHT", -6, 0)
  end
  local ci, ri = placePage(p, p.left, pages[first + 1], 1, 1)
  if perSpread == 2 then placePage(p, p.right, pages[first + 2], ci, ri) end
  local count = 0
  for _, pg in ipairs(pages) do for _, e in ipairs(pg) do if e.cell then count = count + 1 end end end
  p.empty:SetText(count == 0 and (p.mode == "custom" and "No own keys yet" or (p.query and p.query ~= "" and "No spell matches") or "No keys yet – visit your trainer") or "")
  p.pageText:SetText(spreads > 1 and (p.page .. " / " .. spreads) or "")
  p.prev:SetShown(spreads > 1); p.next:SetShown(spreads > 1)
  p.prev:SetEnabled(p.page > 1); p.next:SetEnabled(p.page < spreads)

  if p.mode == "keys" then
    local inCombat = ns.Compat.inCombat()
    p.placeLeft:SetEnabled(not inCombat and Book.pageWork(ctx, "spells") > 0)
    p.placeRight:SetShown(#spread.helpers.cells > 0)
    p.placeRight:SetEnabled(not inCombat and Book.pageWork(ctx, "squad") > 0)
    -- helpers (right page)
    local y = 62
    local hc = spread.helpers.cells
    if #hc > 0 then
      local r = getRule(p, ri)
      r:SetParent(p.right); r:ClearAllPoints()
      r:SetPoint("TOPLEFT", p.right, "TOPLEFT", 0, -y)
      r.text:SetText(spread.helpers.title)
      r:Show()
      p.placeRight:ClearAllPoints()
      p.placeRight:SetPoint("TOPRIGHT", p.right, "TOPRIGHT", 0, -y + 2)
      y = y + RULE_H
      for i, c in ipairs(hc) do
        local b = getHelper(p, i)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", p.right, "TOPLEFT", ((i - 1) % 2) * (HELP_W + 6), -y - math.floor((i - 1) / 2) * HELP_PITCH)
        paintCell(p, b, c)
        p.cells[#p.cells + 1] = b
      end
      y = y + math.ceil(#hc / 2) * HELP_PITCH + 6
    end
    p.det:SetPoint("TOPLEFT", p.right, "TOPLEFT", 0, -y)
    -- the selected key (default: the first one)
    local all, sel = Book.cells("keys", ctx), nil
    for _, c in ipairs(all) do if c.name == p.selected then sel = c end end
    if not sel then sel = all[1]; p.selected = sel and sel.name or nil end
    p.det:SetShown(sel ~= nil)
    if sel then
      for _, b in ipairs(p.cells) do b.sel:SetShown(b.cell and b.cell.name == p.selected) end
      p.selLabel = sel.label
      W.setIcon(p.detIcon, sel.icon)
      p.detName:SetText(sel.label)
      local kt = {}
      for _, k in ipairs(sel.keys or {}) do kt[#kt + 1] = ns.Binds.short(k.key) end
      p.detSub:SetText(Book.kindName(sel.item) .. (#kt > 0 and (" · |cffffd100" .. table.concat(kt, " ") .. "|r") or ""))
      p.detDesc:SetText(sel.group == "helper" and Book.helperShort(sel.item.key) or Book.describe(sel.d, nil))
      p.detMacro:SetText(sel.d and sel.d.body or "")
      local h = p.detMacro:GetHeight() or 0
      if p.detMacro.SetMaxLines then p.detMacro:SetMaxLines(math.max(1, math.floor((h + 0.5) / 11))) end
      p.bind:SetEnabled(not ns.Compat.inCombat())
    end
    -- footer
    local _, charMax = ns.Compat.macroLimits()
    local used = charMax - ctx.macros.free - ctx.macros.counts.create
    p.slots:SetText(used .. "/" .. charMax .. " macros")
    p.slotsTip = used .. " of " .. charMax .. " character macro slots used."
  end
  if ns.KeyEditor.IsOpen() then ns.KeyEditor.Refresh() end
  if p.guide then Book.refreshGuide(p, ctx) end
end

-- ------------------------------------------------------------------ first-run guide (3 steps)
local ROLE_TIP = "Picks the recommended keys and talent guide."
function Book.buildGuide(p)
  local g = W.box(p, 0.11, 0.085, 0.05, 0.99)
  g:SetPoint("TOPLEFT", 0, 0)
  g:SetPoint("BOTTOMRIGHT", 0, 0)
  g:SetFrameLevel((p:GetFrameLevel() or 1) + 20)
  g:EnableMouse(true)
  g.wbxModal = true
  p.guide = g
  g.step = 1
  g.title = W.text(g, "GameFontNormalLarge", 16, W.GOLD)
  g.title:SetPoint("TOPLEFT", 24, -22)
  g.title:SetPoint("TOPRIGHT", -120, -22)
  g.title.wbxCopy = "hint"
  g.skip = W.button(g, "Skip guide", 90, 22, function() Book.closeGuide(p) end,
    "Closes the guide. Open it again from the minimap button menu or Setup.")
  g.skip:SetPoint("TOPRIGHT", -14, -16)
  g.text = W.text(g, "GameFontHighlight", nil, W.TEXT)
  g.text:SetPoint("TOPLEFT", g.title, "BOTTOMLEFT", 0, -14)
  g.text:SetPoint("TOPRIGHT", g, "TOPRIGHT", -24, -54)
  g.text.wbxCopy = "guide"
  -- step 1 choices
  g.roleLabel = W.text(g, "GameFontNormal", nil, W.GOLD)
  g.roleLabel:SetPoint("TOPLEFT", 24, -130)
  g.roleLabel:SetText("Role")
  g.roleLabel.wbxCopy = "label"
  g.roles = {}
  for i = 1, 4 do
    local b = W.button(g, "Role", 100, 28, function(self)
      local _, mem = Core().me()
      if mem and self.value then mem.role = self.value; mem.guide = ns.Kit.defaultGuideFor(mem.cls, self.value); Core().changed() end
    end, { "Role", ROLE_TIP })
    if i == 1 then b:SetPoint("TOPLEFT", 24, -150) else b:SetPoint("LEFT", g.roles[i - 1], "RIGHT", 8, 0) end
    g.roles[i] = b
  end
  g.playLabel = W.text(g, "GameFontNormal", nil, W.GOLD)
  g.playLabel:SetPoint("TOPLEFT", 24, -196)
  g.playLabel:SetText("This character")
  g.playLabel.wbxCopy = "label"
  g.lead = W.button(g, "Leader", 100, 28, function() Core().setPlaysAs("leader") end,
    "This character leads: its keys use its own target.")
  g.lead:SetPoint("TOPLEFT", 24, -216)
  g.follow = W.button(g, "Follower", 100, 28, function()
    local _, mem = Core().me()
    Core().setPlaysAs((mem and not mem.leader and mem.unit) or "party1")
  end, { "Follower", function()
    local _, mem = Core().me()
    return "This character follows " .. leaderName(mem) .. ": its keys use the leader's target through " .. ((mem and not mem.leader and mem.unit) or "party1") ..
      " (change the unit on the My keys page)."
  end })
  g.follow:SetPoint("LEFT", g.lead, "RIGHT", 8, 0)
  g.seq = W.seqControl(g, { member = function() local _, mem = Core().me(); return mem end, width = 110 })
  g.seq:SetPoint("TOPLEFT", 20, -262)
  -- step 2 option
  g.replace = W.check(g, "Replace buttons", function(_, v) Core().cdb.replace = v; Core().changed() end)
  g.replace:SetPoint("TOPLEFT", 20, -186)
  W.tip(g.replace, "Replace buttons", function()
    return "Off: buttons that already hold a spell or item are kept and that key waits for you to drag it. On: WoWBoxer puts its key there." ..
      (g.occupied and g.occupied > 0 and (" " .. g.occupied .. (g.occupied == 1 and " of those buttons holds" or " of those buttons hold") .. " something else now.") or "")
  end)
  -- navigation
  g.next = W.button(g, "Next", 90, 26, function() g.step = g.step + 1; Core().cdb.guideStep = g.step; UI.Refresh() end, "Goes to the next step.")
  g.next:SetPoint("BOTTOMRIGHT", -16, 16)
  g.place = W.button(g, "Place all", 100, 26, function()
    Core().sync({ replace = Core().cdb.replace })
    g.step = 3; Core().cdb.guideStep = 3; UI.Refresh()
  end, "Creates your WoWBoxer macros and puts them on the action buttons shown above.")
  g.place:SetPoint("BOTTOMRIGHT", -16, 16)
  g.drag = W.button(g, "Drag myself", 110, 26, function() g.step = 3; Core().cdb.guideStep = 3; UI.Refresh() end,
    "Closes this step. Drag each key from the book onto any action button.")
  g.drag:SetPoint("RIGHT", g.place, "LEFT", -8, 0)
  g.back = W.button(g, "Back", 70, 26, function() g.step = math.max(1, g.step - 1); Core().cdb.guideStep = g.step; UI.Refresh() end, "Goes back one step.")
  g.back:SetPoint("BOTTOMLEFT", 16, 16)
  g.done = W.button(g, "Close", 90, 26, function() Book.closeGuide(p) end, "Closes the guide and shows your keys.")
  g.done:SetPoint("BOTTOMRIGHT", -16, 16)
  g:Hide()
end

function Book.closeGuide(p)
  Core().cdb.guide = "done"
  if p.guide then p.guide:Hide() end
  UI.Refresh()
end
--- Show the guide again (minimap menu, Setup).
function Book.ShowGuide()
  Core().cdb.guide, Core().cdb.guideStep = nil, 1
  UI.Open("keys")
end

--- "Bar 1 · 1–10 and Bottom Left Bar · 9–11": where Place all puts the keys.
function Book.whereText(ctx)
  local byBar, order = {}, {}
  for _, it in ipairs(ctx.bars.items) do
    local first = it.slot - (it.slot - 1) % 12
    if not byBar[first] then byBar[first] = {}; order[#order + 1] = first end
    table.insert(byBar[first], (it.slot - 1) % 12 + 1)
  end
  local parts = {}
  for _, first in ipairs(order) do
    local l = byBar[first]
    table.sort(l)
    parts[#parts + 1] = ns.Bars.barLabel(first) .. " (" .. (#l > 1 and (l[1] .. "–" .. l[#l]) or tostring(l[1])) .. ")"
  end
  return table.concat(parts, " and ")
end

function Book.refreshGuide(p, ctx)
  local g, cdb = p.guide, Core().cdb
  local want = ctx and cdb.guide ~= "done" and (not cdb.lastSync or (cdb.guideStep or 1) >= 3) and cdb.guide ~= "skip"
  p.body:SetShown(not want)
  if not want then g:Hide(); return end
  g.step = math.max(1, math.min(3, cdb.guideStep or 1))
  g:Show()
  local mem, info = ctx.member, Core().playerInfo()
  local cls = ns.Data.classes[mem.cls]
  for _, x in ipairs({ g.roleLabel, g.playLabel, g.lead, g.follow, g.seq, g.replace, g.next, g.place, g.drag, g.done }) do x:Hide() end
  for _, b in ipairs(g.roles) do b:Hide() end
  g.back:SetShown(g.step > 1 and g.step < 3)
  if g.step == 1 then
    g.title:SetText("Step 1 of 3 – Who is " .. (info.name or "this") .. "?")
    g.text:SetText("Pick a role, leader or follower, and sequence keys.")
    g.roleLabel:Show(); g.playLabel:Show(); g.lead:Show(); g.follow:Show(); g.next:Show()
    g.seq:Show(); g.seq.Refresh()
    for i, r in ipairs(cls and cls.roles or {}) do
      local b = g.roles[i]
      if b then
        b.value = r
        W.setLabel(b, ns.State.ROLE_NAME[r] or r)
        b:Show()
        if mem.role == r then b:LockHighlight() else b:UnlockHighlight() end
      end
    end
    if mem.leader then g.lead:LockHighlight(); g.follow:UnlockHighlight() else g.follow:LockHighlight(); g.lead:UnlockHighlight() end
  elseif g.step == 2 then
    g.title:SetText("Step 2 of 3 – Your action bar")
    g.occupied = ctx.bars.counts.occupied or 0
    g.text:SetText("Place all puts your " .. #ctx.desired .. " keys on " .. Book.whereText(ctx) .. ".")
    g.replace:Show(); g.replace:SetChecked(cdb.replace and true or false)
    g.place:Show(); g.drag:Show()
    g.place:SetEnabled(not ns.Compat.inCombat())
  else
    g.title:SetText("Step 3 of 3 – Done")
    g.text:SetText("WoWBoxer tells you when a level-up changes a key.")
    g.done:Show()
  end
end

-- ------------------------------------------------------------------ register the three book tabs
for _, def in ipairs({
  { key = "keys", label = "My keys", icon = "INV_Misc_Book_09", tip = "Your recommended keys for this level. Drag them onto your action bars." },
  { key = "spells", label = "All spells", icon = "INV_Misc_Book_11", tip = "Every spell you know, then the ones you learn later. Drag one onto a bar to make it a key." },
  { key = "custom", label = "Custom keys", icon = "Spell_ChargePositive", tip = "Your own sequence keys (up to 8)." },
}) do
  UI.RegisterTab({ key = def.key, label = def.label, icon = def.icon, tip = def.tip, book = true,
    build = function(p) build(p, def.key) end, refresh = refresh })
end
