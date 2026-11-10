--[[ WoWBoxer – macros.
  desired(m)  -> the WBX macros this character should have at its level (names are stable: WBX K1.., S1/S2, C1.., helpers)
  plan(list)  -> diff against the character's existing WBX macros: create / update / same / noslot / invalid
  apply(plan) -> CreateMacro / EditMacro, out of combat only (the caller queues it otherwise)
  Never touches a macro whose name does not start with WBX. ]]
local _, ns = ...
local M = {}
ns.Macros = M

local E, K, R, C = ns.Engine, ns.Kit, ns.Rules, ns.Compat
local function Core() return ns.Core end

M.ICON = 134400 -- the "?" icon: #showtooltip then shows the spell
M.ORDER = { "K1", "K2", "K3", "K4", "K5", "K6", "K7", "K8", "S1", "S2", "C1", "C2", "C3", "C4", "C5", "C6", "C7", "C8",
  "Invite", "Invite2", "Follow", "FollowLead", "Assist", "Target", "Focus", "PetBack", "Wand" }
local SEQ_KEY = { dps = "S1", heal = "S2" }
--- Helper keys run no spell, so #showtooltip cannot pick an icon: each gets a picture that says what it does.
M.HELPER_ICON = { Follow = "Ability_Tracking", Assist = "Ability_Hunter_SniperShot", Focus = "Spell_Holy_MindVision",
  PetBack = "Ability_Seal", Invite = "INV_Letter_01", Invite2 = "INV_Letter_01", Target = "Ability_TownWatch",
  FollowLead = "Ability_Rogue_Sprint", Wand = "INV_Wand_01" }

-- ------------------------------------------------------------------ squad keys (docs/squad-v2-simple.md §3)
-- The player ticks which ones this character gets (cdb.squadKeys, per character); unticked ones are not created.
-- Only Invite uses names; Follow, Assist, Target and Focus use the leader's party unit, exactly like the spell keys.
local function follower(m) return not m.leader end
local function petClass(m) return m.cls == "warlock" or m.cls == "hunter" end
local function wandClass(m) return E.WAND_CLASSES[m.cls] == true end
M.SQUAD_KEYS = {
  { key = "Invite", label = "Invite squad", applies = function(m, s) return s ~= nil and #s.members > 1 end, default = function(m) return m.leader end },
  { key = "Follow", label = "Follow (line)", applies = follower, default = function() return true end },
  { key = "FollowLead", label = "Follow leader", applies = follower, default = function() return true end },
  { key = "Assist", label = "Assist", applies = follower, default = function() return true end },
  { key = "Target", label = "Target leader", applies = follower, default = function() return false end },
  { key = "Focus", label = "Focus leader", applies = function(m) return follower(m) and m.unit == "focus" end, default = function() return true end },
  -- Pet passive + follow: opt-in, off by default (owner, 9 Nov 2026). "Pet attack" is gone: damage macros send the pet.
  { key = "PetBack", label = "Pet back", applies = petClass, default = function() return false end },
  { key = "Wand", label = "Wand", applies = wandClass, default = function() return true end },
}
--- Is squad key `key` ticked for member m? choices = cdb.squadKeys ({[key] = true/false}); nil = the default.
function M.squadKeyOn(m, key, choices)
  local v = choices and choices[key]
  if v ~= nil then return v and true or false end
  for _, d in ipairs(M.SQUAD_KEYS) do if d.key == key then return d.default(m) end end
  return true
end
--- The squad keys this member can have: {{key, label, on}} (in the order of M.SQUAD_KEYS).
function M.squadKeyList(m, choices, s)
  local out = {}
  for _, d in ipairs(M.SQUAD_KEYS) do
    if d.applies(m, s) then out[#out + 1] = { key = d.key, label = d.label, on = M.squadKeyOn(m, d.key, choices) } end
  end
  return out
end
--- "Name" or "Name-Realm" for /invite. Forever two-part names keep their space ("/invite Rip And"): /invite takes
--- the rest of the line as the name. Inner spaces are collapsed and the ends trimmed (Compat.baseName).
function M.inviteName(m)
  local n = (ns.Compat.baseName and ns.Compat.baseName(m.name)) or m.name
  return m.realm and (n .. "-" .. m.realm) or n
end
--- /invite lines for every other member, split into bodies of at most 255 characters.
function M.inviteBodies(s, me)
  local bodies, cur = {}, ""
  for _, x in ipairs(s and s.members or {}) do
    if x ~= me then
      local line = "/invite " .. M.inviteName(x)
      if cur ~= "" and #cur + 1 + #line > R.MACRO_LIMIT then bodies[#bodies + 1] = cur; cur = "" end
      cur = cur == "" and line or (cur .. "\n" .. line)
    end
  end
  if cur ~= "" then bodies[#bodies + 1] = cur end
  return bodies
end
--- The squad keys member m gets: {{key, label, body}} – K.helpers filtered by the ticks, plus Target and Invite.
--- Follow (line) follows the member ahead (opts.lineUnit on this client, else m.lineUnit, else the leader's unit);
--- Follow leader is the old Follow. Both use party units, never names (docs/follow-line.md).
function M.squadKeys(m, opts)
  local choices, s = opts.squadKeys, opts.squad
  local out = {}
  if s and M.squadKeyOn(m, "Invite", choices) then
    for i, body in ipairs(M.inviteBodies(s, m)) do
      if i <= 2 then out[#out + 1] = { key = i == 1 and "Invite" or "Invite2", label = i == 1 and "Invite squad" or "Invite squad 2", body = body } end
    end
  end
  local u = E.units(m.unit)
  for _, h in ipairs(K.helpers(m)) do
    if h.key == "Follow" then
      if M.squadKeyOn(m, "Follow", choices) then
        out[#out + 1] = { key = "Follow", label = "Follow the one ahead in the line", body = "/follow " .. (opts.lineUnit or m.lineUnit or u.main) }
      end
      if M.squadKeyOn(m, "FollowLead", choices) then out[#out + 1] = { key = "FollowLead", label = "Follow the leader", body = h.body } end
    elseif M.squadKeyOn(m, h.key, choices) then out[#out + 1] = h end
    if h.key == "Assist" and M.squadKeyOn(m, "Target", choices) then
      out[#out + 1] = { key = "Target", label = "Target the leader", body = "/target " .. u.main }
    end
  end
  return out
end
-- ------------------------------------------------------------------ extra lines (Talex, #help 10 Nov; owner 10 Nov)
-- Lines WoWBoxer adds that the player did not pick. One switch each for ALL macros of this character (cdb.lines,
-- nil = on = today's macros; "Take the leader's target" is the member's own m.assist), and a per-macro choice
-- (cdb.keyLines[name]) that beats the switch, survives updates and level-ups and is cleared by "WoWBoxer's version".
-- The Wand squad macro and Shoot in All spells are separate choices and never change here.
M.LINES = {
  { key = "wand", label = "Wand in damage macros", short = "Wand", icon = "INV_Wand_01",
    about = "Ends caster damage macros with /cast !Shoot: when the spell can't be cast, the press shoots your wand.",
    applies = function(m) return E.WAND_CLASSES[m.cls] == true end },
  { key = "autoshot", label = "Auto Shot", short = "Auto Shot", icon = "Ability_Whirlwind",
    about = "Ends hunter priority macros with /cast !Auto Shot, so the hunter keeps shooting.",
    applies = function(m) return m.cls == "hunter" end },
  { key = "startattack", label = "Start attack", short = "Start attack", icon = "Ability_MeleeDamage",
    about = "Adds /startattack to melee macros, so auto attack starts with the ability.",
    applies = function(m) return not E.WAND_CLASSES[m.cls] end },
  { key = "petattack", label = "Pet attack", short = "Pet attack", icon = "Ability_Hunter_BeastTaming",
    about = "Adds /petattack to damage macros, so your pet attacks the same target.",
    applies = function(m) return m.cls == "hunter" or m.cls == "warlock" end },
  { key = "assist", label = "Take the leader's target", short = "Leader's target", icon = "Ability_Hunter_SniperShot",
    about = "Starts a follower's damage macros with /assist <leader>, so it really targets the leader's target.",
    applies = function(m) return not m.leader end },
}
M.LINE_BY = {}
for _, x in ipairs(M.LINES) do M.LINE_BY[x.key] = x end
--- This character's switch for extra line `key` (true = on). lines = cdb.lines; m = the member (for assist).
function M.lineOn(key, lines, m)
  if key == "assist" then return m ~= nil and m.assist ~= false end
  return not (lines and lines[key] == false)
end
--- The extra lines key d really has, with their state for this key: {{key, label, on, own}} (own = its own choice).
--- Found by building the key with everything on and with one line off: only lines that change the macro count.
local linesCache = setmetatable({}, { __mode = "k" })
function M.linesOf(d, keyLines)
  if not (d and d.rebuild and d.lineCtx) then return {} end
  local cached = linesCache[d]
  if cached then return cached end
  local base = d.lineCtx
  local function with(no, assist)
    return { leader = base.leader, unit = base.unit, wand = base.wand, assist = assist, no = no }
  end
  local follower = not base.leader
  local full = d.rebuild(with({}, follower))
  local per = keyLines and keyLines[d.name] or {}
  local out = {}
  for _, x in ipairs(M.LINES) do
    local no, assist = {}, follower
    if x.key == "assist" then assist = false else no[x.key] = true end
    if d.rebuild(with(no, assist)) ~= full then
      local on
      if x.key == "assist" then on = base.assist and true or false else on = not base.no[x.key] end
      out[#out + 1] = { key = x.key, label = x.label, short = x.short, on = on, own = per[x.key] ~= nil }
    end
  end
  linesCache[d] = out
  return out
end

--- The icon argument for CreateMacro/EditMacro: the file ID when the client can look it up, else the icon name.
function M.namedIcon(slug)
  local f = _G.GetFileIDFromPath
  if f then
    local ok, id = pcall(f, "Interface\\Icons\\" .. slug)
    if ok and type(id) == "number" and id > 0 then return id end
  end
  return slug
end

--- live(name, spell) from the spellbook: true if the character really knows the spell. nil when no spellbook API.
function M.liveCheck()
  local names = C.knownSpellNames()
  if not names then return nil end
  return function(name, spell) return names[name] == true or C.knowsAnyRank(spell) end
end

local function shortName(name) local s = R.PREFIX .. " " .. name; if #s > R.NAME_LIMIT then s = s:sub(1, R.NAME_LIMIT) end return s end
M.shortName = shortName

-- ------------------------------------------------------------------ non-English clients
-- The data (and so every macro) uses English spell names. On other locales /cast needs the client's own names: they come
-- from the spell IDs in the data (C_Spell.GetSpellName / GetSpellInfo). Only whole tokens are replaced – the name after
-- #showtooltip, after the conditions of /cast (optionally "!"), and each entry of a /castsequence – never substrings,
-- so "Heal" inside "Greater Heal" stays intact. English clients skip all of this.
local nameMaps = {}
function M.nameMap(m)
  if not C.needsLocalNames() then return nil end
  local key = m.cls .. ":" .. tostring(m.race)
  if nameMaps[key] ~= nil then return nameMaps[key] or nil end
  local map, n = {}, 0
  for _, s in ipairs(K.customSpellsOf(m)) do -- incl. Shoot (5019): wand lines in the client's language
    local id = s.ranks and s.ranks[1] and s.ranks[1].id
    local loc = id and C.spellName(id)
    if loc and loc ~= s.name then map[s.name] = loc; n = n + 1 end
  end
  nameMaps[key] = n > 0 and map or false
  return n > 0 and map or nil
end
local function locName(map, name)
  local bang, base = name:match("^(!?)(.*)$")
  return bang .. (map[base] or base)
end
--- Translate the spell names in a macro body with `map` (English -> client name). Pure function.
function M.localize(body, map)
  if not map then return body end
  local out = {}
  for line in (body .. "\n"):gmatch("([^\n]*)\n") do
    local tip = line:match("^#showtooltip (.+)$")
    if tip then line = "#showtooltip " .. locName(map, tip)
    else
      local cmd, rest = line:match("^(/castsequence )(.*)$")
      if not cmd then cmd, rest = line:match("^(/cast )(.*)$") end
      if cmd then
        local conds, i = "", 1
        while rest:sub(i, i) == "[" do
          local j = rest:find("]", i, true)
          if not j then break end
          conds = conds .. rest:sub(i, j); i = j + 1
        end
        local tail = rest:sub(i):gsub("^%s+", "")
        local reset, list = tail:match("^(reset=%S+ )(.*)$")
        if not reset then reset, list = "", tail end
        local parts = {}
        for item in (list .. ", "):gmatch("(.-), ") do parts[#parts + 1] = locName(map, item) end
        line = cmd .. conds .. ((conds ~= "" and #parts > 0) and " " or "") .. reset .. table.concat(parts, ", ")
      end
    end
    out[#out + 1] = line
  end
  return table.concat(out, "\n")
end

--- The highest level any spell in the data unlocks at (the game's max level: 60, TBC 70).
function M.cap() return E.maxLevel() end

--- Whether spell s is usable by member m at level L: nil = known now, "trainer" = learnable now but not in the
--- spellbook, a number = the level it unlocks at, false = never (a talent outside the plan, or past the cap).
function M.pendingOf(m, s, L, live)
  local known = live and live(s.name, s)
  if known then return nil end
  if K.learned(m, s, L) then return live and "trainer" or nil end
  if s.gate ~= "talent" then return s.level <= M.cap() and s.level or false end
  for lv = math.max(L + 1, s.level), M.cap() do if K.learned(m, s, lv) then return lv end end -- when the plan takes the talent
  return false
end

--- The macros member m should have at level L. opts: {live=fn|nil, extras={spellIds}, squad=s, squadKeys=ticks}
--- Each item: {name, key, group, label, body, spell?, icon}
function M.desired(m, L, opts)
  opts = opts or {}
  L = L or m.level
  local live = opts.live
  local ctx = K.memberCtx(m)
  -- extra lines (Talex, #help 10 Nov): this character's switches (opts.lines) and each key's own choice (opts.keyLines)
  local lines, keyLines = opts.lines or m.lines or {}, opts.keyLines or {}
  local function ctxFor(name) return K.keyCtx(m, lines, name and keyLines[name]) end
  local out = {}
  for _, x in ipairs(K.kitSlots(m, L, live)) do
    local name = R.PREFIX .. " K" .. x.slot
    local kctx = ctxFor(name)
    local body = E.makeMacro(x.spell, kctx)
    if body ~= "" then
      local sp = x.spell
      out[#out + 1] = { key = "K" .. x.slot, name = name, group = "kit", label = sp.name, item = x.item, body = body, spell = sp,
        plain = E.isPlain(sp, kctx) or nil, lineCtx = kctx, rebuild = function(c) return E.makeMacro(sp, c) end }
    end
  end
  local customIndex = {}
  for i, c in ipairs(m.customSeq or {}) do customIndex["c" .. c.id] = i end
  local function seqKey(id) return customIndex[id] and ("C" .. customIndex[id]) or SEQ_KEY[id] end
  local function seqCtx(id) local k = seqKey(id); return ctxFor(k and (R.PREFIX .. " " .. k) or nil) end
  for _, x in ipairs(K.seqOf(m, L, live, seqCtx)) do
    local key = x.custom and customIndex[x.id] and ("C" .. customIndex[x.id]) or SEQ_KEY[x.id]
    if key and x.macro ~= "" then
      local id = x.id
      local function rebuild(c)
        local r = K.seqOf(m, L, live, function(i) return i == id and c or seqCtx(i) end, id)[1]
        return r and r.macro or ""
      end
      out[#out + 1] = { key = key, name = R.PREFIX .. " " .. key, group = x.custom and "custom" or "sequence", label = x.label, body = x.macro, seq = x,
        lineCtx = seqCtx(id), rebuild = rebuild }
    end
  end
  for _, h in ipairs(M.squadKeys(m, opts)) do
    out[#out + 1] = { key = h.key, name = R.PREFIX .. " " .. h.key, group = "helper", label = h.label, body = h.body }
  end
  -- extra single-spell keys the player added from the spell list
  local all = K.customSpellsOf(m) -- + the wand's Shoot (All spells → drag)
  -- names are cut to 16 characters, so two spells can share one ("Shadow Word: Pain"/"Death"): the later one gets a
  -- digit instead of its last character. Taken in the order of the extras list, so a name never changes by level.
  local taken = {}
  for _, d in ipairs(out) do taken[d.name] = true end
  local function unique(name)
    if not taken[name] then return name end
    for i = 2, 9 do
      local n = name:sub(1, R.NAME_LIMIT - 1) .. i
      if not taken[n] then return n end
    end
    return nil
  end
  -- A spell not learned yet (trainer, or a later level) still gets its macro: /cast does nothing until the spell is
  -- learned, then the same macro just works. pending = "trainer" or the unlock level.
  for _, id in ipairs(opts.extras or {}) do
    for _, s in ipairs(all) do
      if s.id == id and s.action ~= "passive" then
        local name = unique(shortName(s.name)) -- reserved even when not learned yet, so it never moves
        if name then
          taken[name] = true
          local pending = M.pendingOf(m, s, L, live)
          if pending ~= false then
            local xctx, sp = ctxFor(name), s
            out[#out + 1] = { key = "X:" .. s.id, name = name, group = "extra", label = s.name, body = E.makeMacro(s, xctx), spell = s,
              pending = pending, plain = E.isPlain(s, xctx) or nil, lineCtx = xctx, rebuild = function(c) return E.makeMacro(sp, c) end }
          end
        end
      end
    end
  end
  local map = M.nameMap(m)
  local byName = {}
  for _, s in ipairs(all) do byName[s.name] = s end
  for _, d in ipairs(out) do
    -- the player's own targeting (Advanced mode) on a plain spell's key makes it a macro again
    if d.plain and opts.overrides and opts.overrides[d.name] then d.plain = nil end
    if d.plain then d.body = "" end
    if map then d.body = M.localize(d.body, map) end
    d.icon = M.ICON
    -- a "?" macro of an unknown spell stays a "?" on the bar: give it the spell's own picture
    if d.pending and d.spell.icon then d.icon = M.namedIcon(d.spell.icon) end
    if d.seq then M.seqIcon(d, byName) end
    if d.group == "helper" and M.HELPER_ICON[d.key] then d.iconName = M.HELPER_ICON[d.key]; d.icon = M.namedIcon(d.iconName) end
    if d.plain then
      -- the spell itself on the bar: its own icon, nothing to validate (no macro is written)
      d.icon = (d.spell.icon and M.namedIcon(d.spell.icon)) or M.ICON
      d.ok, d.why = true, nil
    else
      d.ok, d.why = R.validateMacro(d.name, d.body)
      if not d.ok and map and #d.body > R.MACRO_LIMIT then d.why = "too long with your client's spell names (" .. #d.body .. "/255)" end
    end
  end
  -- Advanced mode: the player's own targeting / text (Override.lua), checked by the same rules as every key
  if opts.overrides and ns.Override then
    ns.Override.applyAll(out, opts.overrides, opts.ovCtx or {})
    for _, d in ipairs(out) do
      if d.override then
        d.ok, d.why = R.validateMacro(d.name, d.body)
        if not d.ok and #d.body > R.MACRO_LIMIT then d.why = "Too long with your targeting (" .. #d.body .. "/255): remove a target or untick Skip if dead" end
      end
    end
  end
  return out
end

--- Sequence and priority keys: their steps as spell objects and a real icon. A bare #showtooltip shows "?" whenever no
--- line's conditions match (no hostile target, docs/squad-overhaul.md §1), so these macros get the main spell's icon:
--- the filler of a castsequence, the first line of a priority key. d.steps = spells in cast order, d.main = that spell.
function M.seqIcon(d, byName)
  local x = d.seq
  local steps = {}
  for _, n in ipairs(x.spells or {}) do if byName[n] then steps[#steps + 1] = byName[n] end end
  if x.base == "sequence" and x.filler and byName[x.filler] then
    -- cast order: the steps, then the filler (fills) times
    steps = {}
    for _, n in ipairs(x.spells) do if n ~= x.filler and byName[n] then steps[#steps + 1] = byName[n] end end
    for _ = 1, math.max(1, x.fills or 1) do steps[#steps + 1] = byName[x.filler] end
  end
  d.steps = steps
  d.main = (x.base == "sequence" and x.filler and byName[x.filler]) or steps[1]
  d.icon = C.spellTexture(d.main) or M.ICON
end

--- Spells the character should know at level L (data) but the spellbook does not have: visit the trainer.
function M.missingFromBook(m, L, live)
  if not live then return {} end
  local out = {}
  for _, s in ipairs(K.spellsOf(m)) do
    if K.learned(m, s, L) and s.gate ~= "racial" and s.action ~= "passive" and not live(s.name, s) then out[#out + 1] = s end
  end
  return out
end

--- True when an existing macro needs a new icon: it still has the "?" while we want a real one, or another real one.
function M.iconChanged(have, want)
  if want == nil or want == M.ICON then return false end
  if type(have) == "string" and not tonumber(have) then return have:lower():find("questionmark", 1, true) ~= nil end
  -- an icon given by name: the client stores some file ID for it, so only the "?" counts as a change
  if type(want) == "string" then return have == nil or tonumber(have) == M.ICON end
  have = tonumber(have)
  return have == nil or have == M.ICON or have ~= want
end

-- ------------------------------------------------------------------ general (account) macro slots
-- When the character's 18 slots are full, a macro goes into the account's general macros (120, shared by every
-- character on this WoW account). There it gets a name of its own per character: "WBX" + this character's tag +
-- " " + the key ("WBXRi K1", "WBXRi Shadow W3k"), so two characters never use or change each other's macros.
-- The tag is handed out by Core.macroTag (unique per character in the account-wide SavedVariables).
-- Inside WoWBoxer a key keeps its usual name ("WBX K1": skip, bars, overrides); M.gameName gives the macro's name in
-- the game. Nil tag = character slots only.
M.tag = nil
function M.setTag(tag) M.tag = tag end
--- Two characters 0-9a-z from a text (stable): keeps a shortened name unique.
local function hash2(s)
  local h = 0
  for i = 1, #s do h = (h * 31 + s:byte(i)) % 1296 end
  local A = "0123456789abcdefghijklmnopqrstuvwxyz"
  local a, b = math.floor(h / 36) + 1, h % 36 + 1
  return A:sub(a, a) .. A:sub(b, b)
end
--- The general-slot name of key `name` for character tag `tag` (≤ 16 characters, WBX prefix).
function M.accountName(name, tag)
  tag = tag or M.tag
  if not tag then return nil end
  local suffix = name:sub(1, #R.PREFIX + 1) == R.PREFIX .. " " and name:sub(#R.PREFIX + 2) or name:sub(#R.PREFIX + 1)
  local head = R.PREFIX .. tag .. " "
  local room = R.NAME_LIMIT - #head
  if #suffix > room then suffix = suffix:sub(1, room - 2) .. hash2(suffix) end
  return head .. suffix
end
--- Is general macro `name` this character's (its tag)?
function M.isMineAccount(name, tag)
  tag = tag or M.tag
  if not (tag and type(name) == "string") then return false end
  local head = R.PREFIX .. tag .. " "
  return name:sub(1, #head) == head
end
--- Key name -> the macro's name in the game (the general-slot name when the last plan put it there), and back.
M.gameNames, M.keyNames = {}, {}
function M.gameName(name) return M.gameNames[name] or name end
function M.keyName(gameName) return M.keyNames[gameName] or gameName end
--- True when the game macro called `gameName` is WoWBoxer key `name` (its own name, or its general-slot name).
function M.isMacro(gameName, name)
  if gameName == nil or name == nil then return false end
  return gameName == name or (M.tag ~= nil and gameName == M.accountName(name)) or false
end

--- Diff desired against existing macros. skip = {[name]=true} to leave out. tag (optional, default M.tag): this
--- character's general-slot tag; without one only character slots are used.
--- Item status: create | update | same | noslot | invalid | skipped | spell (a plain spell: no macro at all).
--- it.account = the macro is (or will be) in a general slot, it.gameName = its name in the game.
function M.plan(desired, skip, tag)
  skip = skip or {}
  tag = tag or M.tag
  local existing, accList = C.characterMacros(), C.accountMacros()
  local byName, accBy = {}, {}
  for _, x in ipairs(existing) do if R.isOurs(x.name) and not byName[x.name] then byName[x.name] = x end end
  for _, x in ipairs(accList) do if M.isMineAccount(x.name, tag) and not accBy[x.name] then accBy[x.name] = x end end
  local accMax, charMax = C.macroLimits()
  local free, accFree = charMax - #existing, accMax - #accList
  local items, wanted = {}, {}
  local counts = { create = 0, update = 0, same = 0, noslot = 0, invalid = 0, skipped = 0, spell = 0, account = 0 }
  M.gameNames, M.keyNames = {}, {}
  for _, d in ipairs(desired) do
    local it = { name = d.name, key = d.key, label = d.label, body = d.body, icon = d.icon, group = d.group, seq = d.seq ~= nil, gameName = d.name }
    local an = tag and M.accountName(d.name, tag) or nil
    local cur, inAcc = byName[d.name], false
    if not cur and an and accBy[an] then cur, inAcc = accBy[an], true end
    if d.plain then
      it.status, it.plain = "spell", true -- no macro: an old WBX macro of this name is offered for removal (unused)
    else
      wanted[d.name] = true
      if an then wanted[an] = true end
      if skip[d.name] then it.status = "skipped"
      elseif not d.ok then it.status = "invalid"; it.why = d.why
      elseif cur and cur.body == d.body and not M.iconChanged(cur.icon, d.icon) then it.status = "same"; it.index = cur.index
      elseif cur then it.status = "update"; it.index = cur.index; it.old = cur.body
      elseif free > 0 then it.status = "create"; free = free - 1
      elseif an and accFree > 0 then it.status = "create"; inAcc = true; accFree = accFree - 1
      else it.status = "noslot" end
      if inAcc then
        it.account, it.gameName = true, an
        M.gameNames[d.name], M.keyNames[an] = an, d.name
        counts.account = counts.account + 1
      end
    end
    counts[it.status] = counts[it.status] + 1
    items[#items + 1] = it
  end
  local unused = {}
  for _, x in ipairs(existing) do if R.isOurs(x.name) and not wanted[x.name] then unused[#unused + 1] = x.name end end
  for _, x in ipairs(accList) do if M.isMineAccount(x.name, tag) and not wanted[x.name] then unused[#unused + 1] = x.name end end
  local accountOurs = {}
  for _, x in ipairs(accList) do if R.isOurs(x.name) then accountOurs[#accountOurs + 1] = x.name end end
  local noslot = {}
  for _, it in ipairs(items) do if it.status == "noslot" then noslot[#noslot + 1] = it.label or it.name end end
  return { items = items, counts = counts, unused = unused, accountOurs = accountOurs, free = free, charMax = charMax, accMax = accMax,
    accFree = accFree, charUsed = #existing, accUsed = #accList, noslotNames = noslot, tag = tag,
    changes = counts.create + counts.update }
end

--- Index of our macro with this name (re-read every time: indices move when macros are sorted): a character macro,
--- else this character's general macro of that name or of that key.
function M.findIndex(name)
  for _, x in ipairs(C.characterMacros()) do if x.name == name then return x.index end end
  if not R.isOurs(name) then return nil end
  local an = M.isMineAccount(name) and name or M.accountName(name)
  if an then for _, x in ipairs(C.accountMacros()) do if x.name == an then return x.index end end end
  return nil
end

--- Apply create/update items. Must be called out of combat. Returns {done, failed={{name, err}}}
function M.apply(plan)
  local res = { created = 0, updated = 0, failed = {}, changed = {} }
  if C.inCombat() then res.failed[1] = { name = "*", err = "in combat" }; return res end
  for _, it in ipairs(plan.items) do
    if it.status == "create" or it.status == "update" then
      local ok, why = R.validateMacro(it.name, it.body)
      if not ok then
        res.failed[#res.failed + 1] = { name = it.name, err = why }
      elseif it.status == "create" then
        local gname = it.gameName or it.name
        if M.findIndex(it.name) then -- created meanwhile: edit instead
          local idx = M.findIndex(it.name)
          local okc, err = pcall(EditMacro, idx, M.nameAt(idx, gname), it.icon, it.body)
          if okc then res.updated = res.updated + 1; res.changed[#res.changed + 1] = it.name else res.failed[#res.failed + 1] = { name = it.name, err = tostring(err) } end
        else
          -- perCharacter: true = a character slot; nil = a general slot (named for this character, M.accountName)
          local okc, err = pcall(CreateMacro, gname, it.icon, it.body, (not it.account) or nil)
          if okc and err and it.account then
            if Core() and Core().macroTag then Core().macroTag(true) end -- from now on this tag is this character's
            Core().log("info", "macro " .. it.name .. " created in a general slot as " .. gname)
          end
          if okc and err then res.created = res.created + 1; res.changed[#res.changed + 1] = it.name else res.failed[#res.failed + 1] = { name = it.name, err = tostring(err or "no free macro slot") } end
        end
      else
        local idx = M.findIndex(it.name)
        if not idx then res.failed[#res.failed + 1] = { name = it.name, err = "macro disappeared" }
        else
          local okc, err = pcall(EditMacro, idx, M.nameAt(idx, it.gameName or it.name), it.icon, it.body)
          if okc then res.updated = res.updated + 1; res.changed[#res.changed + 1] = it.name else res.failed[#res.failed + 1] = { name = it.name, err = tostring(err) } end
        end
      end
    end
  end
  return res
end
--- The name to keep when editing macro #idx: the name it has now (a general macro keeps its per-character name).
function M.nameAt(idx, fallback)
  local n = C.macroInfo(idx)
  return (type(n) == "string" and R.isOurs(n)) and n or fallback
end

--- Delete unused WBX macros (only on an explicit click): this character's macros and its own general macros (its
--- tag), never another character's general macro and never a macro without the WBX prefix.
function M.deleteUnused(names)
  local n = 0
  if C.inCombat() then return 0 end
  for _, name in ipairs(names) do
    if R.isOurs(name) then
      local idx = M.findIndex(name)
      local real = idx and C.macroInfo(idx)
      local mine = real ~= nil and R.isOurs(real) and (idx > select(1, C.macroLimits()) or M.isMineAccount(real))
      if mine and pcall(DeleteMacro, idx) then n = n + 1 end
    end
  end
  return n
end
