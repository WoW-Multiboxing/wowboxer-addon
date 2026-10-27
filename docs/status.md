# Status and handover (updated 2026-10-27 evening, local Claude Code session – owner of the code)

Plan: `02_Spec/Addon-plan.md` in the project folder. Work list: `docs/backlog.md` (top: "Needs the owner in game").
Look: `docs/ui-spec.md`. Research: `docs/research/`.

## Files (WoWBoxer/, TOC order)
| File | What |
|---|---|
| `Data/*.lua` | Generated from the companion (`tools/build_data.js`), never edited by hand |
| `Engine.lua`, `Kit.lua` | Port of the companion's engine + kit (`tests/parity.lua`: 139,404 cases identical to the JS). `Kit.talentStatus` compares spent talents with the plan |
| `Json.lua`, `Share.lua` | `!WBX:1!` share string (byte-identical with `share/wbx-string.js`) |
| `Rules.lua` | Macro whitelist and limits, CVar allow-list, recommended addons |
| `Compat.lua` | Every WoW API behind probes: spellbook (cached until `SPELLS_CHANGED`), macros, action slots, bars visible / bonus page, talents read-back (`C_Traits` on Forever), Blizzard key bindings, secrets (`C.safe`) |
| `State.lua` | Squads/members in the companion's schema; per-character DB (`primaryBar` nil until `Core.defaultBars`) |
| `Macros.lua`, `Bars.lua`, `Binds.lua` | Desired WBX macros (unique names) → diff → apply; bar layout + placement; keys per macro and per-character binding |
| `Checklist.lua` | Setup checklist (with "Use partyN" fix) |
| `Core.lua` | SavedVariables, events, combat queue (`whenSafe`), `compute` (+ `batch` memo), sync, `pickup`/`pickupSpell` (drag), `scanBars` (remembers where keys are), `setPlaysAs`, CVars, import/export, level-up offer, login diagnose + bridge for WS-C, slash commands |
| `Team.lua` | Display-only team status over addon messages (prefix `WBX1`) |
| `UI/*` | Widgets, Main (header, tabs, window position/scale, error note), Minimap (button, menu, compartment, square minimaps, level-up dot), Keys / Squad / Talents / Setup / Share tabs, KeyEditor (own keys C1–C8), TeamFrame, Audit (layout measurements) |

## Tests (all in the simulator, `tests/wowmock.lua`; plus parity against the companion's JS)
core 82 · diag 28 · features 177 · ui 84 · share 72 (+20 JS) · parity 139,404 · lint51 (5.2+ syntax, forbidden API,
invalid string escapes) · luacheck. `bash tools/check.sh` runs everything; `bash tools/ship.sh` rebases, checks, pushes,
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
- Release workflow on tags only, GitHub Release; CurseForge/Wago when the repo is public (the owner's call).
