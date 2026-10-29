# Companion → add-on parity (2026-10-29)

The owner's decision (29 Oct 2026): the Squad Companion web page is parked; the WoWBoxer add-on is the one tool. Source
of data and macro rules stays `vendor/companion` (snapshot of `wowboxer-site/companion/`), `tests/parity.lua` at 0
failures. Compared: `wowboxer-site/companion/src/app.js` + `engine.js` + `template.html` against `WoWBoxer/`.

Status: **in** = in the add-on · **partly** · **missing** · **n/a** = does not fit the game (or breaks a hard rule).
Effort: S ≈ hours, M ≈ a day, L ≈ several days. "0.9.4" = built in this round.

| # | Companion feature (app.js) | Add-on | Where / what is missing | Effort |
|---|---|---|---|---|
| 1 | Squads, several, 2–10 characters, class/race/role/level (`newSquad`, `renderSquad`) | in | Squad page (one screen), squad dropdown with New/Delete | – |
| 2 | Leader / follower unit, crown (`fixLeader`) | in | Crown per row; Plays as in the row editor | – |
| 3 | Mixed-faction / over-5 warnings | missing | One status-line hint on the Squad page | S |
| 4 | Link levels (`applyLink`) | partly | Plan page "Leader's level"; real levels come from the game | – |
| 5 | +1 level all / sync levels (`levelAll`, `syncLevels`) | n/a | Levels come from the game; Plan ahead covers planning | – |
| 6 | To-do strip: talent points to spend, trainer now, sequence changed (`todoStrip`) | in (0.9.4) | Book top line: "N talent points to spend", "Visit your trainer", "trainer at 12: …"; Plan page per member | – |
| 7 | Kit summary tiles (new at level, next trainer, points, targeting) | partly (0.9.4) | Top line + "New at <level>" in All spells; no tile row | S |
| 8 | Everyday Kit: primary + situational keys with macros (`coreList`, `kitLists`) | in | My keys (keys 1–8) + All spells; macro text in the tooltip and Selected | – |
| 9 | Pins (`m.pins`) | partly | Data and import keep pins; in the game you drag any spell as an extra key instead | S |
| 10 | Targeting explanation (`ruleText`) | partly | One sentence per key (`Book.describe`, helper texts); no per-character paragraph | S |
| 11 | Sequence keys Off/Simple/Medium/Advanced (`renderSeq`, `seqOf`) | in | Tick + tier on My keys, row editor, guide | – |
| 12 | Sequence level plan / "changes at level N" (`seqPlan`) | partly | Logic in `K.seqPlan`; shown as "changed" after the level-up only | S |
| 13 | Custom keys editor (`openSeqDlg`) | in | Custom keys + key editor, paste, copy | – |
| 14 | Spellbook, every rank, filters (`bookRows`) | partly (0.9.4) | All spells: learned + future, ranks in the tooltip; no category/source filter chips | M |
| 15 | Spell search (`bookSearch`) | in (0.9.4) | All spells: search by name or kind | – |
| 16 | Rich spell tooltip: cost, range, cast, cooldown, rank (`spellTip`) | partly (0.9.4) | Rank line, macro, status, unlock level; the game's own tooltip has cost/range | S |
| 17 | Spell details dialog with a rank table (`openDetails`) | missing | Not needed in game (the spellbook shows it) | M |
| 18 | Guide picker per spec, recommended mark (`renderGuidePanel`) | in | Talents: dropdown, * = recommended | – |
| 19 | Guide type, source, credits (`KIND`, sources) | in (0.9.4) | Hover a guide: type, site/author/date, levels, note; full credit line. `key`, `trio`, `adaptedFrom` not exported by build_data | S |
| 20 | Talent trees, 3-tree grid with arrows (`renderTalents`) | missing | Point list only; the game's talent window is next to it | L |
| 21 | Spend next point / follow to level / apply full (`nextGuide`, `applyGuide`) | partly | "Next at level N" + "Then:"; the player spends in the game (no automation) | – |
| 22 | Plan ahead to level 60 (`planAhead`) | in (0.9.4) | Talents: "Plan to N" – highlighted points + summary | – |
| 23 | Undo/redo, saved builds | missing | Own builds come in by import only | M |
| 24 | Progress table guide vs plan | partly | Point order + "In game: x/y spent, off plan" (Forever) | S |
| 25 | Compare guides | missing | | M |
| 26 | Build code copy/paste (WF7) | partly | Encoder in `Engine.lua`, no UI | S |
| 27 | Legacy "Talented" setting | in | `m.talented` | – |
| 28 | Copy all / export kit as text (`kitText`, `squadSheet`) | partly | Key map cheat sheet; Copy… per key | S |
| 29 | Import/export JSON, all squads | in | `!WBX:1!` share string (Share tab), Send to my other characters | – |
| 30 | Setup helper macros (check party order, mark target) | partly | Follow/Assist/Target/Focus/Pet/Invite squad keys; the `/run` ones are forbidden (hard rule 3) | n/a |
| 31 | Sources and credits page | partly | Credit on Talents + README; no "reviewed but not included" list | S |
| 32 | Data self-check (`renderDiag`) | partly | Selftest in SavedVariables (`WoWBoxerDB.diag`) | – |
| 33 | Command palette, shortcuts, deep links | n/a | Browser only | – |
| – | Add-on only: drag to bars, Place all, level-up update, bars/CVars/addon checks, key bindings, team status, readiness, key map, sync offers between clients | – | – | – |

## Launch order (Forever, 4 Nov)
Done in 0.9.4: trainer to-do and talent points on the top line (6), guide picker with source/type + credits (19),
Plan ahead (22), spell search + "New at <level>" + ranks (14–16). Next, if time allows before launch: targeting
paragraph per character (10), mixed-faction hint (3), export `key`/`trio`/`adaptedFrom` from build_data (19), kit as
text (28). After launch: talent trees (20), compare guides (25), saved builds (23).
