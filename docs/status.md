# Status and handover (updated 2026-10-28 morning, local Claude Code session – owner of the code)

Plan: `02_Spec/Addon-plan.md` in the project folder. Work list: `docs/backlog.md` (top: "Needs the owner in game").
Look: `docs/ui-spec-v3-book.md` (book spread, status by colour, copy rules, help on every page) over
`docs/ui-spec-v2.md` (spellbook, guide, any resolution, fly to the bar) over `docs/ui-spec.md`; squad, dropdowns
and sequence icons: `docs/squad-overhaul.md` (over `docs/squad-spec.md`). Research: `docs/research/`.

## Files (WoWBoxer/, TOC order)
| File | What |
|---|---|
| `Data/*.lua` | Generated from the companion (`tools/build_data.js`), never edited by hand |
| `Engine.lua`, `Kit.lua` | Port of the companion's engine + kit (`tests/parity.lua`: 139,404 cases identical to the JS). `Kit.talentStatus` compares spent talents with the plan |
| `Json.lua`, `Share.lua` | `!WBX:1!` share string (byte-identical with `share/wbx-string.js`) |
| `Rules.lua` | Macro whitelist and limits, CVar allow-list, recommended addons |
| `Compat.lua` | Every WoW API behind probes: spellbook (cached until `SPELLS_CHANGED`), macros, action slots, bars visible / bonus page, talents read-back (`C_Traits` on Forever), Blizzard key bindings, secrets (`C.safe`) |
| `State.lua` | Squads/members in the companion's schema + slot order, tags, leader presets, notes, templates, party import; per-character DB (`primaryBar` nil until `Core.defaultBars`) |
| `Macros.lua`, `Bars.lua`, `Binds.lua` | Desired WBX macros (unique names) → diff → apply; bar layout + placement; keys per macro and per-character binding |
| `Checklist.lua` | Setup checklist (with "Use partyN" fix) |
| `Core.lua` | SavedVariables, events, combat queue (`whenSafe`), `compute` (+ `batch` memo), sync, `pickup`/`pickupSpell` (drag), `scanBars` (remembers where keys are), `setPlaysAs`, CVars, import/export, level-up offer, login diagnose + bridge for WS-C, slash commands |
| `Team.lua` | Display-only team status over addon messages (prefix `WBX1`): `S|` state, `R|` readiness + version |
| `Squad.lua` | Live party (Add my party), "Dorin is party2 here", readiness per member, key map + cheat sheet, levelling plan |
| `Sync.lua` | Offers between your clients: Send squad (`Q|` chunks of the share string → Review / Ignore → Import), preset switch (`P|` → Apply / Ignore), session card |
| `UI/*` | Widgets (auto-sized buttons with tooltips, truncating lines, menu, composite icons), Dropdown (Blizzard menu or our own list; sequence control), SeqStrip (step icons on the action buttons), TabSquad + SquadPages (Home, Edit squad, Readiness, Key map, Plan), Main (the book: cover, pages, bookmark tabs, character line, fit-to-screen scale, position per character, level-up toast), Book (My keys spread: spells left, helpers + selected key right; All spells / Custom keys; next-step banner, 3-step guide, key capture, right-click menu), Help ("?" per page: tooltip + numbered overlay, squad guide), Fly (icons fly to the action buttons), Minimap, Talents / Setup / Squad / Share tabs, KeyEditor (own keys C1–C8), TeamFrame, Audit (in-game layout measurements incl. overlaps) |

## Tests (all in the simulator, `tests/wowmock.lua`; plus parity against the companion's JS)
core 82 · diag 35 · dropdown 51 · features 212 · seqicons 45 · squad 93 · sync 45 (three clients in one party) · ui 179 (incl. the layout matrix: 18 screens/UI scales + 3 stress runs, every tab
and state; `tests/layout.lua`) · locale 9 · share 72 (+20 JS) · parity 139,404 · lint51 · luacheck. The simulator
computes frame boxes from anchors and text metrics (`tests/wowmock.lua`); `python tools/lua.py tests/probe_layout.lua`
prints the problems per tab while developing. `bash tools/check.sh` runs everything; `bash tools/ship.sh` rebases, checks, pushes,
installs into both clients and waits for CI.

## Verified in the real client so far
Classic Era 1.15.9 (2026-10-27): loads without errors, diagnose written; `MAX_CHARACTER_MACROS` = 30; spellbook via
`GetSpellTabInfo`; `C_ClassTalents` missing. Nothing else has been seen on screen yet – see "Needs the owner in game".

## Decisions taken by the code session (also in LOG.md)
- Own minimap button instead of LibDBIcon (no libraries; square minimaps handled with `GetMinimapShape`).
- Warrior/Druid/Rogue keys default to Bottom Left / Bottom Right (bar 1 shows their stance page).
- A solo character that plays as follower gets a placeholder "Leader" member.
- Talent read-back only on Forever (Era trees differ). Never purchases or commits talents.
- Team status on by default while a squad of 2+ is grouped; display only; `/wbx team off` silences it.
- Classic Era dataset not built here (data job for the companion pipeline).
- Main view is a spellbook with bookmarks; bar choices, Replace, window size and Animations live in Setup.
- Window keeps its design size (760 x 500) and is scaled to fit the screen; the player's size option comes on top.
- Fly-to-bar uses own AnimationGroups; Blizzard's IconIntroTracker is not reused (taint risk on the action bars).
- Release workflow on tags only, GitHub Release; CurseForge/Wago when the repo is public (the owner's call).
- Dropdowns: Blizzard's menu dropdown only when `MenuUtil` exists and `DropdownButton` + `WowStyle1DropdownTemplate`
  create; otherwise our own list. Same API, so the UI code never knows which.
- Sequence/priority macros carry the main spell's icon (the "?" disappears); the live "next step" lives in the strip.
- The step strip only draws textures on our own frames anchored to Blizzard's buttons; it re-anchors only out of combat.
- Squad sync is offer-only: no auto-accept and no setting for one; offers only from the own party.
