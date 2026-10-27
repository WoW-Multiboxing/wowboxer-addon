# Squad overhaul + dropdowns + sequence icons (the owner, 2026-10-27 22:16)

Supersedes `docs/squad-spec.md` where they differ. The owner: "It hasn't done the drop-down versions whatsoever, and I
can't find any upgrades to the squad system … it has to be drop-down, the squad as well … create a giant overhaul …
best practice and your own ideas … all the sequences are just the standard icon, so it's weird … ideally the sequences
have multiple icons."

Status found by the cloud session at 22:20: **no commits after 20:36** and a clean checkout on the PC – the squad
prompt was never worked on. Start here.

---------------------------------------------------------------------------------------------------------------------

## 1. Why sequence keys show the "?" icon – and the fix

**Cause [C, Wowpedia `#showtooltip`].** WoWBoxer creates every macro with the "?" icon (134400) so `#showtooltip`
decides the icon. Single-spell keys say `#showtooltip <Spell>`, so they always show that spell. Sequence and priority
keys say a bare `#showtooltip`; the client then takes the icon from the `/castsequence`/`/cast` line **whose
conditions match right now**. Every condition is `[@mouseover,harm…][@party1target,harm…][harm,nodead]`, so with no
hostile target nothing matches and the button shows "?" – which is what the owner sees out of combat. A macro with a
chosen (non-"?") icon never changes its icon [C].

**Fix (do all three):**
1. **Never a "?" again:** sequence/priority keys get a real icon – the *main* spell's icon file ID (the filler for
   a castsequence, the top line for a priority key), set via `CreateMacro/EditMacro` icon argument
   (`C_Spell.GetSpellTexture(name)` / `GetSpellTexture`). Single-spell keys stay as they are. Changing an icon is an
   EditMacro – only when the player updates keys, out of combat.
2. **Multiple icons on the bar – the WoWBoxer sequence strip (visual overlay):** on every visible action button that
   holds a WBX sequence/priority key, draw a thin strip of mini icons (10–12 px) of its steps along the bottom edge
   ("Imm › SB SB SB SB"), and a gold frame around the **next** step. Next step = `QueryCastSequence(<sequence text>)`
   if the client has it [AFKLAR – exists in Classic; probe], else `GetMacroSpell(macroIndex)` when conditions resolve,
   else just the strip without highlight. Update on `UNIT_SPELLCAST_SUCCEEDED` (player), `PLAYER_REGEN_ENABLED`,
   `PLAYER_TARGET_CHANGED`, `ACTIONBAR_SLOT_CHANGED` – throttled, never per frame. Plus a small purple "SEQ"/"PRI"
   badge in the top corner. Textures only, parented to our own frame anchored to the button (never change the
   button's scripts/attributes); hide for bar addons we don't know; setting "Sequence strip on action bars" (on).
   Check for taint with `taintLog` in Era.
3. **Composite icons in WoWBoxer's own window:** 2 spells = diagonal split, 3–4 = 2×2 quadrants (`SetTexCoord`),
   the filler gets the biggest part; the same picture in tooltips, the guide and the squad views.

## 2. Real dropdowns everywhere

Replace **every** "‹ value ›" cycle control with a dropdown: role, plays-as (Leader / Follower via party1–4 / focus),
sequence tier, class, race, guide, bars, squad selector, templates.
- Forever (12.x menu system): `CreateFrame("DropdownButton", nil, parent, "WowStyle1DropdownTemplate")` +
  `:SetupMenu(generator)` with `rootDescription:CreateRadio(...)` [C, warcraft.wiki.gg Blizzard Menu guide].
- Classic Era: probe for the same template; if missing, our own `Widgets.dropdown` (button with arrow, click opens a
  list frame with radio rows, closes on choice / ESC / click outside, keyboard-free). Same API for both so the UI code
  calls one function. Never use `UIDropDownMenu` (deprecated, taint-prone).
- **Sequence control:** `[x] Use sequence keys` + dropdown **Simple / Medium / Advanced** (disabled when unticked);
  on the My-keys page header, in guide step 1 and in every member's editor. Unsupported classes: checkbox disabled +
  "Built-in sequences: Paladin, Priest, Warlock – make your own under Custom keys".

## 3. Squad overhaul – what the squad is for

Best practice from multibox tools (EMA/Jamba "teams" with a master, order and tags; ISBoxer "character sets" with
slots; BoxTrack's team panel), translated to WoWBoxer's rules (nothing acts for you, each client clicks itself):
**the squad is the shared plan of who plays what, so every client builds the right keys, shows the team, and stays
in sync – set up once, used every session.**

### 3.1 Concepts (data model, extends the companion squad schema; keep it importable/exportable)
- **Squad**: name, faction, members (ordered = window/slot order 1–N, matching the window layout app), active leader
  preset, notes.
- **Member**: name, class, race, role, leader/follower, unit (partyN/focus), sequence on/off + tier, guide, custom keys,
  pins, *slot number* (1 = main window). Optional **tags** ("healer", "caster", "melee", "pet") for filtering views.
- **Leader presets**: e.g. "Questing – Dorin leads", "Dungeon – Dorin leads, Wow2 heals". Switching preset recomputes
  every member's leader/unit; each other client gets an offer to apply it (one click there).

### 3.2 Screens (spellbook look, bookmark "Squad" with sub-pages)
1. **Squad home** – party-frame style cards (class icon, name, role icon, crown, level, "keys OK / 3 to update",
   follow ✓, same target ✓, mana bar) from display-only team messages; "THIS CHARACTER" highlighted; buttons:
   Edit squad, Send to party, Leader preset dropdown, Readiness.
2. **Edit squad** – table: drag to reorder; per row dropdowns (class, race, role, plays-as, sequence tier), name box,
   remove; "Add character"; "Add my party"; templates dropdown (Duo, Trio, Quad, 5-man; and "Undead trio").
3. **Readiness** – one row per member × checks (in party, unit matches, keys current, Follow/Assist on bars, settings
   applied, team signal); each client can only fix itself; one-click fixes on this client.
4. **Key map** – "same key, same job": member × key table (key 1 = main attack/heal … 11 Follow, 12 Assist) with each
   member's actual spell icon in the cell; highlights gaps; "Copy cheat sheet" text.
5. **Plan** – levelling together: everyone's level (team status), next trainer visit per member, next talent point per
   member from their guide, "followers use leader's level" toggle.

### 3.3 Sync between clients (offers only)
- **Send squad to my party**: chunked addon messages (prefix `WBX1`, checksum, throttled like Team.lua), payload = the
  share-string JSON. Receivers show "Dorin shares squad 'Undead trio' (3) – Review / Ignore"; Review = the Share
  import preview; **Import** on that client applies it. No auto-accept, no setting for it. Logged on both sides.
- **Leader preset switch**: same mechanism ("Dorin switched to 'Dungeon' – apply here?").
- **Version check**: show when another client has an older WoWBoxer (display only).

### 3.4 Smart helpers (own ideas, all display or one-click-on-this-client)
- **Create squad from my party** (names/classes from party1–4, leader = group leader), then edit.
- **Auto-detect my unit**: "Dorin is party2 here – use party2?" in the next-step line.
- **Composition hints**: "No healer in this squad" / "Two tanks" (info only).
- **Follow chain view**: who follows whom (all → leader) and a warning if a follower's unit points at a non-leader.
- **Squad-wide sequence tier**: set all members' tier in one dropdown (each client then updates its own keys).
- **Session start card** on login when grouped: "Squad Undead trio · 3/3 online · keys OK on 2/3 · Wow2 needs Update".

### 3.5 Hard rules (unchanged)
No message ever makes another client target, follow, cast, accept, invite or change keys by itself. Offers need a click
on the receiving client. WBX macros only, writes out of combat after a click, no loadstring.

## 4. Order of work
1. Dropdown widget (both clients) and replace every cycle control; sequence checkbox + tier dropdown. (small, visible)
2. Sequence icons: real icon (fix the "?"), composite icons in the window, then the bar strip overlay.
3. Squad data model (slots, tags, presets) + Edit squad + Add my party + templates.
4. Squad home cards + Readiness + Key map + Plan.
5. Send to party / preset offers / version check (3-client simulator test).
6. Polish, layout matrix green, install, one in-game checklist for 2–3 clients.
