# Status and handover (2026-10-27, cloud session)

Written by the Cowork/cloud session that built M0–M3 so the session that owns workstream E (see CLAUDE.md) can
continue without re-reading the conversation. Plan: `02_Spec/Addon-plan.md` in the project folder.

## Done and tested
| Area | Files | Tests |
|---|---|---|
| Data generated from the companion (`vendor/companion`, v8.4.0) | `WoWBoxer/Data/*.lua`, `tools/build_data.js` | `--check` in CI |
| Engine port (talent rules, macros, sequences, custom keys, warnings) + kit (`coreList`, `kitLists`, `seqOf`, `seqPlan`, guides) | `Engine.lua`, `Kit.lua` | `tests/parity.lua`: 139,404 cases identical to the JS (vectors from `tools/export_vectors.js`, kit functions extracted verbatim from `app.js`) |
| JSON/base64/CRC32, share string `!WBX:1!<b64 canonical JSON>!<crc32>` | `Json.lua`, `Share.lua`, `share/wbx-string.js` | `share/test.js`, `tests/test_share.lua` (byte-identical JS↔Lua, same error texts, hostile imports) |
| Rules: macro whitelist/limits, CVar allow-list, addon list | `Rules.lua` | `tests/test_core.lua` |
| Squad state (companion schema + sanitising), "this is me", quick start | `State.lua` | core + ui tests |
| Compat probes (spellbook incl. future-spell skip, macros, actions, CVars, addons, secrets) | `Compat.lua` | mock |
| Macro sync: stable names `WBX K1–K8` (kit slot = companion kit item), `S1/S2`, `C1–C8`, `Follow/Assist/Focus/Pet/PetBack`, extras; diff create/update/same/noslot/invalid; never touches non-WBX | `Macros.lua` | core tests |
| Bars: fixed layout (primary: K1–8, S1–2, Follow, Assist; secondary: C1–8, Focus, Pet, PetBack); only empty/own slots unless Replace | `Bars.lua` | core + ui tests |
| Core: SavedVariables, combat queue (`whenSafe` → `PLAYER_REGEN_ENABLED`), level-up/spells offer (chat + toast, never auto-applied), CVars apply/backup/restore, import/export, `/wbx` commands, debug log, `/wbx selftest` → `WoWBoxerDB.diag[char-realm]` | `Core.lua`, `Checklist.lua` | core + ui tests |
| UI (follows the Design mockup "WoWBoxer addon window"): Keys, Squad, Talents, Setup, Share + level-up toast | `UI/*.lua` | `tests/test_ui.lua` (simulator) |
| Lint | `tools/lint51.py` (5.2+ syntax, forbidden API), luacheck in CI | CI on Lua 5.1 + LuaJIT |

`has(spell)` in game = companion rule (level + talent plan) AND the spellbook knows the name (or any rank ID via
`IsPlayerSpell`). So untrained spells (and Forever-only spells on Classic Era) never enter a macro; the Keys tab lists
them as "Visit your trainer".

## Not yet verified in a real client (do this first)
1. Install into `_classic_era_` and `_forever_` `Interface\AddOns` (package: `tools/package.sh <ver>` → `dist/WoWBoxer`).
2. Log in (Classic Era), `/wbx selftest`, `/reload`; read `WTF/Account/<ACC>/SavedVariables/WoWBoxer.lua`
   (`WoWBoxerDB.diag`, `.log`). Check: probes, spellbook source, `MAX_CHARACTER_MACROS`, planned macros/bar slots.
3. Open `/wbx`, press "Start a squad", "Create & place keys"; `/reload`; verify macros in `WTF/.../macros-cache.txt`
   and the log. Screenshot the window to compare with the mockup (layout values are first guesses).
4. Things that may differ in the client: `UIPanelButtonTemplate:SetEnabled`, `UICheckButtonTemplate`, scroll frames,
   `CreateMacro` icon 134400 on Era, `GetActionInfo` id for macros, `PlaceAction` restrictions.

## Open / AFKLAR
- [AFKLAR: Forever launch interface number (16001 → 16002?), per-character macro slots (18 or 30), `PlaceAction` from
  addons, secret unit names, Skyborne `UnitRace` file names (`Compat.playerRace` guesses by faction).]
- Companion bug seen while porting (WS A): `kitLists` builds racial spell objects twice, so a pinned racial would
  appear in both primary and "others". Vectors avoid pinned racials; the Lua port does not have the bug.
- An auto-diagnose a few seconds after login (mentioned in CLAUDE.md) is not implemented yet; today it is `/wbx selftest`.
- Later (plan §3): Classic Era dataset, talent read-back via `C_ClassTalents/C_Traits`, keybind helper, display-only
  team status, compressed `!WBX:2!`, companion/website buttons using `share/wbx-string.js` (WS A/D).
