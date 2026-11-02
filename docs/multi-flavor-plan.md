# One addon, three games: Forever, Classic Era, TBC Anniversary (plan, 2 Nov 2026)

A Discord user asked for a TBC Anniversary version. The owner's PC already has the TBC Anniversary client: the
`_anniversary_` folder, build 2.5.6.70577, so interface **20506**.

## Best practice: one repo, one download, files per game

- **One repository and one CurseForge/Wago project.** The same zip is uploaded and tagged for all three game versions.
  This is how the big multi-version addons work: engine fixes reach every game at once, and players find one page.
  Separate repos would mean fixing every bug two or three times.
- **The TOC** (warcraft.wiki.gg "TOC format"):
  - one TOC with `## Interface: 16001, 11509, 20506`;
  - game-specific files are chosen per line with inline directives, e.g.
    `Data\TBC\Class_mage.lua [AllowLoadGameType tbc]`, or the `[Game]` path variable;
  - the wiki prefers this over separate `_TBC.toc` / `_Vanilla.toc` files.
  - Note: TBC Classic and TBC Anniversary share the game type/suffix `tbc`. Forever is `forever` (older builds:
    `camelot`).
  - Pair every `AllowLoadGameType` with an `ExcludeLoadGameType`: an unknown game type would otherwise load everything.
- **Code stays shared:**
  - Engine, macro rules, UI, squad, automation and keybinds stay as they are.
  - Differences go through `Compat.lua` capability probes, as today.
  - **Only the data differs per game:** spells by level, talent trees, guides, sequence tables, races.

## What differs per game

| | Forever | Classic Era | TBC Anniversary |
|---|---|---|---|
| Max level / talent points | 60 / 51 | 60 / 51 | 70 / 61 |
| Talent trees | Forever's own (companion data) | vanilla (differ from Forever) | TBC |
| Spells | Forever data (Zephras) | vanilla | TBC (new ranks to 70, new spells e.g. Steady Shot, Mangle, Mana Tide …) |
| Races | Forever (incl. Skyborne) | vanilla 8 | + Draenei, Blood Elf (Shaman for Alliance, Paladin for Horde) |
| Wowhead links | `/forever/` | `/classic/` | `/tbc/` |
| Data today | full | **Forever data filtered by the real spellbook (partial)** | none |

## Where the data comes from (licence-clean)

1. **From the client itself**, with a dev command on the owner's PC that writes a dump to SavedVariables:
   - talent trees (`GetTalentInfo`: names, positions, ranks);
   - the spellbook;
   - races.
   `tools/` turns the dump into `Data/<game>/*.lua`.
2. **Spells by level** (the trainer lists) come from Blizzard's game tables, as published per build on
   wago.tools (DB2 exports, the usual source for addon authors). They are filtered to class spells with their
   required level.
3. **Macro rules per spell** (enemy/friend/melee/pet etc.) reuse the companion's action types by spell name where the
   spell exists. New TBC spells get a short hand-made table.
4. **Talent guides:**
   - one default build per spec, written as Wowhead TBC links and converted by the existing importer;
   - players can import their own (the importer gets the `/tbc/` and `/classic/` token tables).

Hard rule 6 (the companion is the source of truth) stays for **Forever**. For Era and TBC the addon's own data
pipeline is the source. Record that decision in `02_Spec/Decisions.md` (G).

## Work estimate (Claude Code sessions plus the owner's test time)

| Step | Size | What players get |
|---|---|---|
| 1. Groundwork: TOC with 20506, per-game data folders, Compat probes for 2.5.6, CI + CurseForge/Wago tagging for TBC Anniversary, install to `_anniversary_` | small (½–1 session) | WoWBoxer loads on TBC without errors |
| 2. "Basic TBC": macros built from the live spellbook (no future spells), squad, follow line, automation, keybinds, settings; talents read from the client; the Wowhead TBC import | small–medium (1 session) | Usable on TBC: everything except guides and future-spell planning |
| 3. Data pipeline (client dump + wago.tools trainer levels) for **TBC and real Classic Era data** | medium (1–2 sessions) | Future spells, trainer to-do and level-up offers on both |
| 4. TBC tuning: sequences per class (Steady Shot, Mangle, Shaman shocks …), default guides per spec, new races | medium (2–3 sessions + testing) | Same quality as Forever |

Steps 1+2 are enough to answer the Discord question within days. Steps 3–4 can follow while Forever is the priority.
