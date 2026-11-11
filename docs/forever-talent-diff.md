# WoW Forever talents: pre-launch seed → live client (rerun 11 Nov 2026)

Task: `docs/talents-rerun-2026-11-11.md`. Generated parts (trees, guides, spells) come from `node tools/forever_diff.js`,
the Wowhead check from `node tools/wowhead_forever.js <talents-classic.js>`. Rerun both after a hotfix build.

## 1. Where the live data comes from

- **Client:** WoW Forever build **1.60.1.70888** (product `wowf` in `World of Warcraft\.build.info` on the owner's PC,
  11 Nov 2026). Tables from wago.tools for that build: `python tools/fetch_client.py forever` →
  `datasrc/forever/blizzard-1.60.1.70888.json`.
- **The client's `Talent`/`TalentTab` tables are stale** (Classic Era copies: e.g. no Accelerant, wrong ranks). The
  live talents are **C_Traits** tables, the same ones the game's talent window reads:
  - `SkillLineXTraitTree`: one TraitTree per class (Druid 1089, Hunter 1091, Mage 1112, Paladin 1100, Priest 1114,
    Rogue 1111, Shaman 1082, Warlock 1116, Warrior 1117). Its currency (3820) has SourcedMax 51 = the 51 points.
  - `TraitNode` PosX/PosY: three trees side by side (PosX 1020/5020/9080 = column 1 of tree 1/2/3, 600 per column),
    seven rows (PosY 2130 + 600 per row). Tree names and order: `TalentTab` (OrderIndex, left to right).
  - `TraitNodeEntry.MaxRanks` = ranks; `TraitDefinition.SpellID` = the spell (one spell per node; the rank is the
    node's rank, not a separate spell). `TraitEdge` Type 2/3 = prerequisite (the upper talent at full rank).
  - Row gates: `TraitCond` on the row groups needs 5/10/…/30 points (`SpentAmountRequired`), the rule the engine
    already has. Wowhead's `requiredPoints` agrees for every talent.
  - **Parked nodes:** Hunter Lightning Reflexes 104982 (PosX 102800), Hunter Improved Serpent Sting 105003
    (PosY 39300) and Priest Holy Specialization 105865 (PosY 21300) sit far off the grid. They are older copies; the
    live talents are other nodes on the grid (110859, 110855; Improved Serpent Sting is gone). Left out, as Wowhead does.
- **Spells:** the same rerun. Class skill lines (`SkillLineAbility`, `SpellLevels`) give ranks and trainer levels,
  merged with the seed's macro rules in `tools/forever_data.js`: one ID per level (the seed's, else the lowest; the
  lines also hold effect spells at the same level, e.g. Lightning Shield's proc). A talent's spell gets the first level
  its row can be reached (10 + 5 per row; the client says level 0/1 for talent spells).
  `datasrc/forever/spells-extra.json` still merges on top (talent key and row level now from the live tree).

## 2. Cross-check: Wowhead's calculator

- Data: `nether.wowhead.com/forever/data/talents-classic`, fetched 11 Nov 2026. **Hash version `vkndmh`** (was `v2`).
  Wowhead's talent IDs are the client's C_Traits node IDs, so the check is exact.
- **Result: the client and Wowhead agree on all 467 talents**: name, tree, row, column, max rank, prerequisite and
  points needed. No row needed "the client wins".
- `vendor/wowhead/forever-trees.json` refreshed: `trees` = the live layout, `layouts.v2` = Wowhead's own two older
  layouts, so links made before the change still read (`docs/talent-import.md` §7).
- §5 of `docs/talent-import.md` (the Mage Arcane/Fire mismatches) is settled: the live client matches Wowhead (no
  Arcane Focus; Incineration 5, Critical Mass 3, Accelerant instead of Improved Fireball, Improved Fire Blast row 3).

## 3. In game: diag.talentTree

- The login diagnose dumps the live tree of the character (`Compat.talentTreeDump`: C_Traits node ID, position, max
  rank, points spent, name, spell; read-only) to `WoWBoxerDB.diag[char].talentTree`.
- `python tools/read_log.py --client _forever_` compares it with the data by node ID and prints every difference
  (moved, renamed, re-ranked, missing, extra, a parked node the game shows). Test: `tests/test_read_log.py`.
- [AFKLAR: the first dumps from the owner's Paladin, Priest and Warlock after `/reload`; expected: 0 differences.]

## 4. Trees, guides and spells

### 4.1 Trees: pre-launch seed → live client (build 1.60.1.70888)

Matched by talent name inside the class. "moved" = other row/column (or tree); a name that left one cell while a new
name took the same cell is shown as "replaced by".

- **Warrior Arms** (17 talents): Improved Tactical Mastery: ranks 5 → 3; Bloodthrill: ranks 5 → 2.
- **Warrior Fury** (18 talents): replaced by **Reckless Swings** (1) at row 4 col 2: Raging Blows (1); added: **Improved Whirlwind** (2, row 6 col 1); Enrage: moved row 4 col 3 → row 3 col 4; Gore Drinker: moved row 6 col 3 → row 5 col 3, prerequisite enrage → blood-craze; Flurry: moved row 6 col 2 → row 6 col 3, ranks 5 → 3, prerequisite death-wish → none; Bloodthirst: prerequisite none → death-wish.
- **Paladin Holy** (17 talents): removed: Voice of Truth (1, row 3); added: **Oath of Light** (1, row 4 col 3); added: **Boundless Light** (2, row 5 col 3); Spiritual Focus: moved row 2 col 2 → row 1 col 2, ranks 2 → 5; Divine Strength: moved row 1 col 2 → row 1 col 3; Reverence: moved row 3 col 2 → row 2 col 2, ranks 3 → 2; Improved Seals: ranks 3 → 5; Purifying Power: moved row 3 col 3 → row 2 col 4; Divine Favor: moved row 4 col 3 → row 3 col 1; Illumination: moved row 4 col 2 → row 3 col 2; Holy Conduit: moved from tree Retribution row 2 col 2 → row 3 col 3; Divine Precision: moved row 5 col 1 → row 4 col 1, ranks 3 → 2, prerequisite holy-shock → none; Infusion of Light: moved row 4 col 1 → row 4 col 2; Consecrated Ground: moved row 5 col 3 → row 5 col 1.
- **Paladin Protection** (17 talents): removed: Improved Seal of Fury (1, row 3); removed: One-Handed Weapon Specialization (3, row 4); added: **Stoicism** (2, row 5 col 1); added: **Shieldsworn** (1, row 7 col 2); Divine Intellect: moved from tree Holy row 1 col 3 → row 1 col 2; Sacred Duty: moved row 3 col 4 → row 2 col 4; Templar's Bulwark: moved row 5 col 2 → row 3 col 1; Improved Hammer of Justice: moved row 4 col 3 → row 3 col 2; Shield Specialization: ranks 3 → 2; Toughness: moved row 1 col 2 → row 3 col 4; Swift Judgement: prerequisite improved-seal-of-fury → templars-bulwark; Improved Righteous Fury: moved row 3 col 2 → row 4 col 2; Anticipation: moved row 2 col 4 → row 4 col 3; Holy Shield: moved row 7 col 2 → row 5 col 2, prerequisite templars-bulwark → none; Iron Creed: ranks 5 → 3.
- **Paladin Retribution** (17 talents): removed: Instrument of Law (2, row 6); replaced by **Unsealed Wrath** (1) at row 7 col 2: Twist of Light (1); added: **Turn Evil** (2, row 5 col 1); Conviction: moved row 2 col 3 → row 2 col 2, ranks 5 → 3; Sanctified Judgement: moved row 3 col 2 → row 2 col 3; Unyielding Faith: moved from tree Holy row 2 col 4 → row 3 col 2; Sacred Arbiter: moved row 4 col 3 → row 4 col 2; Two-Handed Weapon Specialization: moved row 5 col 1 → row 4 col 4; Repentance: moved row 5 col 3 → row 5 col 2; Vengeance: moved row 5 col 2 → row 5 col 3, prerequisite sanctified-judgement → seal-of-command; Champion of the Light: moved row 6 col 2 → row 6 col 3, ranks 3 → 5.
- **Hunter Beast Mastery** (16 talents): Improved Revive Pet: moved row 2 col 4 → row 2 col 3; Pathfinding: moved row 2 col 3 → row 3 col 1.
- **Rogue Assassination** (17 talents): removed: Murder (2, row 2); added: **Blood Splatter** (1, row 3 col 2); Improved Expose Armor: moved row 3 col 2 → row 2 col 2; Vigor: moved row 5 col 1 → row 3 col 1; Lethality: ranks 5 → 2; Relentless Strikes: moved row 3 col 1 → row 5 col 1, ranks 1 → 5; Venom: moved row 7 col 2 → row 5 col 2, prerequisite mutilate → none; Seal Fate: ranks 5 → 3; Mutilate: moved row 5 col 2 → row 7 col 2, prerequisite none → venom.
- **Rogue Combat** (19 talents): replaced by **Coup de Grace** (3) at row 1 col 1: Improved Eviscerate (3); replaced by **Efficient Strikes** (2) at row 1 col 2: Improved Sinister Strike (2); added: **Composure** (2, row 3 col 4); added: **Flash of Steel** (5, row 6 col 3); Improved Sprint: moved row 3 col 4 → row 2 col 4; Weapon Expertise: moved row 6 col 2 → row 4 col 3, prerequisite blade-flurry → precision; Aggression: moved row 6 col 3 → row 4 col 4; Dual Wield Specialization: moved row 4 col 3 → row 5 col 1, ranks 5 → 2, prerequisite precision → none; Adrenaline Rush: prerequisite none → blade-flurry.
- **Rogue Subtlety** (18 talents): removed: Improved Distract (2, row 3); removed: Quietus (5, row 6); replaced by **Boot Knife** (5) at row 6 col 3: Cutthroat (5); replaced by **Death Mark** (1) at row 7 col 2: Thousand Cuts (1); added: **Quick Getaway** (2, row 4 col 4); Setup: moved row 2 col 1 → row 1 col 1; Opportunity: ranks 2 → 5; Dirty Deeds: moved row 5 col 1 → row 2 col 1; Camouflage: moved row 1 col 1 → row 2 col 2, ranks 5 → 3; Improved Ambush: moved row 2 col 4 → row 2 col 3; Dirty Tricks: moved row 2 col 3 → row 2 col 4; Premeditation: moved row 4 col 2 → row 3 col 2; Serrated Blades: moved row 4 col 3 → row 3 col 3; Elusiveness: moved row 2 col 2 → row 4 col 1; Ghostly Strike: moved row 3 col 2 → row 4 col 2; Heightened Senses: moved row 4 col 1 → row 5 col 1.
- **Priest Holy** (17 talents): replaced by **Holy Binding** (1) at row 4 col 4: Binding Heal (1).
- **Shaman Elemental** (16 talents): replaced by **Call of Thunder** (1) at row 5 col 2: Lava Burst (1); replaced by **Lightning Mastery** (1) at row 7 col 2: Elemental Mastery (1).
- **Shaman Enhancement** (18 talents): Improved Lightning Shield: moved row 2 col 4 → row 2 col 3; Improved Ghost Wolf: moved row 2 col 3 → row 4 col 4.
- **Mage Arcane** (18 talents): removed: Arcane Focus (5, row 1); Improved Channeling: moved row 1 col 3 → row 1 col 2; Arcane Resilience: moved row 2 col 4 → row 1 col 3, ranks 2 → 3; Missile Barrage: moved row 1 col 4 → row 2 col 4.
- **Mage Fire** (17 talents): replaced by **Accelerant** (5) at row 1 col 3: Improved Fireball (5); Incineration: ranks 3 → 5; Improved Fire Blast: moved row 1 col 1 → row 3 col 4; Critical Mass: ranks 5 → 3.
- **Mage Frost** (18 talents): replaced by **Precision** (3) at row 1 col 3: Elemental Precision (3).
- **Druid Feral Combat** (20 talents): removed: Improved Shifting Power (2, row 5); removed: Berserk (1, row 7); added: **Lacerate** (1, row 4 col 2); added: **Predatory Discipline** (1, row 4 col 3); Furor: moved from tree Restoration row 1 col 3 → row 1 col 3; Predatory Strikes: moved row 4 col 3 → row 4 col 1; Rend and Tear: moved row 6 col 3 → row 6 col 1; Natural Reaction: moved row 6 col 1 → row 6 col 4; Primal Bite: moved row 4 col 2 → row 7 col 2, prerequisite savage-fury → leader-of-the-pack; Shifting Power: moved row 4 col 1 → row 7 col 3, prerequisite shredding-attacks → predatory-discipline.
- **Druid Restoration** (16 talents): replaced by **Bloom** (1) at row 3 col 4: Gift of the Earthmother (1); Heart of the Wild: moved from tree Feral Combat row 1 col 3 → row 1 col 3; Reflection: moved row 3 col 2 → row 2 col 2; Subtlety: moved row 2 col 2 → row 3 col 2.

17 of 27 trees changed, 10 unchanged (same names, cells, ranks and prerequisites).

### 4.2 Guides

| Guide | Class | Status | Points | What changed |
|---|---|---|---|---|
| `war-protection-wowvendor-waspers` | warrior | OK | 21 | every point still legal |
| `war-protection-mobalytics-phaseshifter` | warrior | OK | 21 | every point still legal |
| `war-protection-icy-veins-abide` | warrior | OK | 0 | no point order (tips only) |
| `war-protection-icy-veins-abide-2` | warrior | OK | 0 | no point order (tips only) |
| `war-protection-wowhead-riyani` | warrior | OK | 0 | no point order (tips only) |
| `war-fury-wowhead-drakanthos-user-submitt` (default) | warrior | rebuilt | 51 | old: used raging-blows (not in the live tree) and had Flurry 5/3, Improved Tactical Mastery 5/3; now Icy Veins 2026-11-04 (16/33/2) |
| `war-fury-mobalytics-kargoz` | warrior | moved | 43 | old: used raging-blows (not in the live tree) and had Flurry 5/3, Improved Tactical Mastery 5/3; no current source, 43/51 points kept |
| `war-fury-wowvendor-waspers` | warrior | OK | 21 | every point still legal |
| `war-fury-icy-veins-abide` | warrior | OK | 0 | no point order (tips only) |
| `war-arms-wowvendor-waspers` | warrior | rebuilt | 51 | old: had Improved Tactical Mastery 5/3; now WowVendor 2026-11-10 (31/20/0) |
| `war-arms-mobalytics-mobalytics` | warrior | OK | 21 | every point still legal |
| `war-arms-icy-veins-abide` | warrior | OK | 0 | no point order (tips only) |
| `war-arms-wowhead-shoop` | warrior | OK | 0 | no point order (tips only) |
| `war-arms-method-babyhoof` | warrior | OK | 0 | no point order (tips only) |
| `pal-prot-holyshield` (default) | paladin | rebuilt | 51 | old: used improved-seal-of-fury, one-handed-weapon-specialization (not in the live tree) and had Shield Specialization 3/2, Iron Creed 5/3; now Icy Veins 2026-11-04 (0/35/16) |
| `pal-prot-crowd` | paladin | rebuilt | 51 | old: used improved-seal-of-fury, one-handed-weapon-specialization (not in the live tree) and had Shield Specialization 3/2, Iron Creed 5/3; now Icy Veins 2026-11-04 (0/35/16) |
| `pal-prot-wowhead-tips` | paladin | OK | 0 | no point order (tips only) |
| `pal-ret-twist` | paladin | rebuilt | 51 | old: used instrument-of-law, twist-of-light (not in the live tree) and had Conviction 5/3; now Icy Veins 2026-11-04 (18/0/33) |
| `pal-ret-wowhead30` | paladin | OK | 0 | no point order (tips only) |
| `pal-holy-dungeon` | paladin | rebuilt | 51 | old: used voice-of-truth (not in the live tree) and had Reverence 3/2; now Icy Veins 2026-11-04 (34/5/12) |
| `pal-holy-raid` | paladin | rebuilt | 51 | old: used voice-of-truth (not in the live tree) and had Reverence 3/2; now Icy Veins 2026-11-04 (31/8/12) |
| `hun-beast-mastery-mobalytics-kargoz` | hunter | moved | 28 | old: no longer fit the rows/prerequisites; no current source, 28/51 points kept |
| `hun-beast-mastery-warcraft-tavern-sponge` (default) | hunter | rebuilt | 51 | old: no longer fit the rows/prerequisites; now Warcraft Tavern 2026-11-11 (31/20/0) |
| `hun-beast-mastery-warcraft-tavern-spo-2` | hunter | rebuilt | 51 | old: no longer fit the rows/prerequisites; now Warcraft Tavern 2026-11-09 (31/20/0) |
| `hun-marksmanship-warcraft-tavern-sponge` | hunter | OK | 21 | every point still legal |
| `hun-marksmanship-mobalytics-mobalytics` | hunter | OK | 21 | every point still legal |
| `hun-marksmanship-warcraft-tavern-spon-2` | hunter | OK | 51 | every point still legal |
| `hun-survival-warcraft-tavern-sponge` | hunter | OK | 21 | every point still legal |
| `hun-survival-mobalytics-ff` | hunter | OK | 21 | every point still legal |
| `hun-survival-icy-veins-veramos` | hunter | OK | 0 | no point order (tips only) |
| `rog-combat-mobalytics-rogues-diary` (default) | rogue | rebuilt | 51 | old: used improved-eviscerate, improved-sinister-strike (not in the live tree) and had Dual Wield Specialization 4/2, Lethality 5/2; now Mobalytics 2026-11-10 (16/35/0) |
| `rog-combat-mobalytics-donthecrown` | rogue | rebuilt | 51 | old: used improved-sinister-strike, improved-eviscerate (not in the live tree) and had Dual Wield Specialization 4/2; now Mobalytics 2026-11-04 (16/35/0) |
| `rog-combat-mobalytics-mobalytics-oli` | rogue | rebuilt | 51 | old: used improved-sinister-strike, improved-eviscerate (not in the live tree) and had Dual Wield Specialization 5/2; now Mobalytics 2026-11-05 (16/35/0) |
| `rog-combat-wowvendor-waspers` | rogue | rebuilt | 51 | old: used improved-eviscerate, improved-sinister-strike (not in the live tree) and had Dual Wield Specialization 4/2; now WowVendor 2026-11-10 (14/37/0) |
| `rog-assassination-mobalytics-mobalytics` | rogue | rebuilt | 51 | old: had Lethality 5/2; now Mobalytics 2026-11-05 (34/12/5) |
| `rog-assassination-wowvendor-waspers` | rogue | rebuilt | 51 | old: had Lethality 3/2; now WowVendor 2026-11-10 (41/10/0) |
| `rog-assassination-icy-veins-sellin` | rogue | OK | 0 | no point order (tips only) |
| `rog-subtlety-mobalytics-ff` | rogue | rebuilt | 51 | old: had Camouflage 4/3; now Mobalytics 2026-11-04 (6/14/31) |
| `rog-subtlety-wowvendor-waspers` | rogue | rebuilt | 51 | old: had Camouflage 4/3; now WowVendor 2026-11-10 (15/5/31) |
| `rog-subtlety-mobalytics-rogues-diary` | rogue | rebuilt | 51 | old: used improved-eviscerate (not in the live tree) and had Camouflage 5/3, Dual Wield Specialization 5/2; now Mobalytics 2026-11-10 (17/3/31) |
| `rog-subtlety-icy-veins-seliathan` | rogue | OK | 0 | no point order (tips only) |
| `pri-holy-wh30` (default) | priest | rebuilt | 21 | old: used binding-heal (not in the live tree); now Icy Veins 2026-11-04 (10/6/5) |
| `pri-holy-trio60` | priest | rebuilt | 51 | old: used binding-heal (not in the live tree); now Icy Veins 2026-11-04 (14/32/5) |
| `pri-holy-wv30` | priest | rebuilt | 51 | old: used binding-heal (not in the live tree); now WowVendor 2026-11-10 (14/32/5) |
| `pri-holy-wh20` | priest | OK | 11 | every point still legal |
| `pri-disc-mobalytics` | priest | OK | 21 | every point still legal |
| `pri-disc-wowhead` | priest | OK | 0 | no point order (tips only) |
| `pri-shadow-wh30` | priest | OK | 21 | every point still legal |
| `pri-shadow-wv30` | priest | OK | 21 | every point still legal |
| `sha-enhancement-wowvendor-waspers` (default) | shaman | rebuilt | 51 | old: no longer fit the rows/prerequisites; now WowVendor 2026-11-11 (18/33/0) |
| `sha-enhancement-mobalytics-nicktew` | shaman | moved | 8 | old: no longer fit the rows/prerequisites; no current source, 8/11 points kept |
| `sha-enhancement-wowhead-yebb` | shaman | OK | 0 | no point order (tips only) |
| `sha-elemental-mobalytics-tiqqle` | shaman | rebuilt | 51 | old: used lava-burst (not in the live tree); now Mobalytics 2026-11-08 (31/9/11) |
| `sha-elemental-wowhead-lucenia` | shaman | OK | 0 | no point order (tips only) |
| `sha-restoration-wowvendor-waspers` | shaman | OK | 21 | every point still legal |
| `sha-restoration-mobalytics-mobalytics` | shaman | OK | 21 | every point still legal |
| `sha-restoration-wowhead-woah` | shaman | OK | 0 | no point order (tips only) |
| `mag-frost-warcraft-tavern-nevermore` (default) | mage | rebuilt | 51 | old: used elemental-precision, arcane-focus (not in the live tree); now Warcraft Tavern 2026-11-11 (18/2/31) |
| `mag-frost-method-celz` | mage | OK | 0 | no point order (tips only) |
| `mag-frost-the-forever-era-the-forever-er` | mage | OK | 0 | no point order (tips only) |
| `mag-arcane-mobalytics-mobalytics` | mage | rebuilt | 51 | old: used arcane-focus (not in the live tree); now Mobalytics 2026-11-05 (32/16/3) |
| `mag-arcane-warcraft-tavern-nevermore` | mage | rebuilt | 51 | old: used arcane-focus, elemental-precision (not in the live tree); now Warcraft Tavern 2026-11-11 (31/17/3) |
| `mag-fire-mobalytics-mobalytics` | mage | rebuilt | 51 | old: used improved-fireball (not in the live tree); now Mobalytics 2026-11-06 (16/32/3) |
| `mag-fire-warcraft-tavern-nevermore` | mage | rebuilt | 51 | old: used improved-fireball, elemental-precision, arcane-focus (not in the live tree) and had Critical Mass 5/3; now Warcraft Tavern 2026-11-11 (18/31/2) |
| `wl-destro-mobalytics60` (default) | warlock | OK | 51 | every point still legal |
| `wl-destro-tavern30` | warlock | OK | 25 | every point still legal |
| `wl-destro-wowhead30` | warlock | OK | 0 | no point order (tips only) |
| `wl-aff-mobalytics-level` | warlock | OK | 48 | every point still legal |
| `wl-aff-mobalytics60` | warlock | OK | 51 | every point still legal |
| `wl-aff-icy` | warlock | OK | 0 | no point order (tips only) |
| `wl-demo-mobalytics60` | warlock | OK | 51 | every point still legal |
| `wl-demo-wowhead30` | warlock | OK | 0 | no point order (tips only) |
| `wl-demo-icy` | warlock | OK | 0 | no point order (tips only) |
| `dru-feral-combat-mobalytics-ff` (default) | druid | rebuilt | 51 | old: used berserk, improved-shifting-power, gift-of-the-earthmother (not in the live tree); now Mobalytics 2026-11-06 (9/32/10) |
| `dru-feral-combat-mobalytics-ruse-cruize` | druid | rebuilt | 51 | old: no longer fit the rows/prerequisites; now Mobalytics 2026-11-04 (9/31/11) |
| `dru-feral-combat-wowvendor-waspers` | druid | rebuilt | 51 | old: no longer fit the rows/prerequisites; now WowVendor 2026-11-10 (0/35/16) |
| `dru-feral-combat-wowvendor-waspers-2` | druid | rebuilt | 51 | old: no longer fit the rows/prerequisites; now WowVendor 2026-11-10 (0/46/5) |
| `dru-feral-combat-warcraft-tavern-luxrah` | druid | repaired | 26 | same points, order repaired (first illegal point: Requires 10 points in Feral Combat (you have 7)) |
| `dru-feral-combat-wowhead-lexolas` | druid | OK | 0 | no point order (tips only) |
| `dru-feral-combat-wowhead-l0uki` | druid | OK | 0 | no point order (tips only) |
| `dru-feral-combat-icy-veins-meyra` | druid | OK | 0 | no point order (tips only) |
| `dru-balance-wowvendor-waspers` | druid | OK | 21 | every point still legal |
| `dru-balance-mobalytics-mobalytics` | druid | OK | 21 | every point still legal |
| `dru-balance-warcraft-tavern-luxrah` | druid | OK | 26 | every point still legal |
| `dru-balance-warcraft-tavern-luxrah-2` | druid | OK | 26 | every point still legal |
| `dru-balance-wowhead-drwonder` | druid | OK | 0 | no point order (tips only) |
| `dru-restoration-mobalytics-mobalytics` | druid | rebuilt | 51 | old: used gift-of-the-earthmother (not in the live tree); now Mobalytics 2026-11-04 (11/0/40) |
| `dru-restoration-wowvendor-waspers` | druid | rebuilt | 51 | old: used gift-of-the-earthmother (not in the live tree); now WowVendor 2026-11-10 (11/0/40) |
| `dru-restoration-warcraft-tavern-luxrah` | druid | OK | 26 | every point still legal |
| `dru-restoration-wowhead-frankensteak` | druid | OK | 0 | no point order (tips only) |

52 OK, 34 rebuilt, 3 moved, 1 repaired (90 guides).
Default moved: hunter hun-beast-mastery-mobalytics-kargoz → hun-beast-mastery-warcraft-tavern-sponge (hun-beast-mastery-mobalytics-kargoz kept 28 points only (no current source)).

### 4.3 Guide sources used (all dated after launch, 4 Nov 2026)

| Site | Guides | How it was read |
|---|---|---|
| Icy Veins (Mytholxgy, Meyra, Rainy, Abide), 4 Nov | 8: Paladin ×5, Holy Priest ×2, Fury (drakanthos) | `#tc-` calculator codes decoded with Icy Veins' own talent files, checked legal |
| WowVendor (Waspers), 10–11 Nov | 9: Holy Priest, Arms, Rogue ×3, Enhancement, Druid ×3 | "Talent Progression" tables, one rank per level, 10–60 |
| Warcraft Tavern (Nevermore, Sponge), 9–11 Nov | 5: Mage ×3, Beast Mastery ×2 | calculator hash (A/B/C = tree, one character = row×4+column). Arcane and Fire each take one point a level early: repaired, and the note says so |
| Mobalytics, 4–11 Nov | 12: Rogue ×6, Elemental, Mage ×2, Druid ×3 | the rendered page's talent calculator (leveling path or final ranks). Arcane and Fire give final ranks only (order by WoWBoxer) |

The original Wowhead guides (Paladin ×4, Holy Priest, Fury) are still from October (`v2` links), so Icy Veins replaced
them. Not used, with the reason: Mobalytics Fury (kargoz: still Raging Blows, Flurry 5/3), Mobalytics Beast Mastery
(kargoz: dated 22 Oct), Mobalytics Enhancement (nicktew: two different talents named "Mental Quickness" on the page,
not guessed). Those three keep the points that still fit, leave the rest to place, and say so in their note; none of
them is a default any more.

Players' choices: every guide id is kept, so a saved `m.guide` stays selected. A saved id that is gone falls back to
the default with one chat line ("Your talent guide was updated for WoW Forever's live talents"). Own builds that the
live trees no longer hold are kept as saved (`orig`) with a warning (`stale`, shown in the Guide list and on the
Talents tab), and WoWBoxer plans with the points that still fit (`tests/test_forever_live.lua`).

### 4.4 Spells

- **Paladin**: Seal of Righteousness – ranks undefined@1 20287@10 20288@18 20289@26 20290@34 20291@42 20292@50 20293@58 -> 20154@1 20287@10 20288@18 20289@26 20290@34 20291@42 20292@50 20293@58; Righteous Fury – ranks 25780@16 -> 25780@10; Exorcism – ranks undefined@20 undefined@28 undefined@36 undefined@44 undefined@52 undefined@60 -> 879@20 5614@28 5615@36 10312@44 10313@52 10314@60; Voice of Truth – gate talent -> trainer; Divine Favor – ranks 20216@25 -> 20216@20; Templar's Bulwark – ranks 1311015@30 -> 1311015@20; Holy Shield – ranks 20925@40 20927@50 20928@60 -> 20925@30 20927@40 20928@50 1239570@60.
- **Hunter**: Counterattack – ranks 19306@25 1242634@30 20909@42 20910@54 -> 19306@30 1242634@30 20909@42 20910@54; Lacerate – ranks undefined@30 undefined@40 undefined@50 undefined@60 -> 24118@30 24119@40 24120@50 1299332@60.
- **Rogue**: Ghostly Strike – ranks 14278@20 -> 14278@25; Premeditation – ranks 14183@25 -> 14183@20; Mutilate – ranks 1310705@30 399956@40 1241582@50 1241584@60 -> 399956@40 1241582@50 1241584@60; Venom – ranks 1310703@40 -> 1329328@30.
- **Priest**: Touch of Weakness – ranks 2652@10 19249@20 19251@30 19252@40 undefined@50 undefined@60 -> 2652@10 19249@20 19251@30 19252@40 19253@50 19254@60; Binding Heal – removed: its talent binding-heal is not in the live tree and no class skill line teaches it (Wowhead's Forever class abilities agree); Vampiric Embrace – ranks 15286@25 -> 15286@30; Penance – ranks 402174@30 1240720@40 1240721@50 1316991@60 -> 402174@30 1240720@40 1240721@50 1316995@60.
- **Shaman**: Stormstrike – ranks 17364@25 -> 17364@40; Lava Burst – removed: its talent lava-burst is not in the live tree and no class skill line teaches it (Wowhead's Forever class abilities agree); Elemental Mastery – renamed to Lightning Mastery (same spell 16166, the live talent); Lightning Mastery – talent elemental-mastery -> lightning-mastery.
- **Druid**: Primal Bite – ranks 407995@25 1238069@36 1238070@48 1238073@60 -> 407995@40 1238069@50 1238070@60; Shifting Power – ranks 1322605@25 -> 1322605@40; Ferocious Bite – ranks 22568@32 22827@40 22828@48 22829@56 31018@60 -> 1328618@24 22568@32 22827@40 22828@48 22829@56 31018@60; Berserk – removed: its talent berserk is not in the live tree and no class skill line teaches it (Wowhead's Forever class abilities agree); Lacerate – ranks 414644@42 1235826@50 1235827@58 -> 1328617@25 1328616@34 414644@42 1235826@50 1235827@58; Lacerate – gate trainer -> talent.
- Recommended macros: shaman/ranged Lava Burst left out (not a Forever spell any more).

## 5. Sequences, priority keys and recommended macros

- Every spell named in `WoWBoxer/Games/Forever.lua` (sequences) and in the recommended macros exists in the new data
  (`tests/test_forever_live.lua`), with its talent where it has one, and never before its row's level.
- **Lava Burst is gone** (no talent, no trainer; Wowhead's Forever class abilities agree). The Shaman caster sequence
  (medium and advanced) uses Chain Lightning in its place, and the ranged recommended macros drop it.
- **Elemental Mastery is Lightning Mastery** (the same spell 16166, Elemental row 7): renamed, level 40.
- **Berserk** (Druid) and **Binding Heal** (Priest) are gone; no sequence used them.
- Talented spells checked: Hemorrhage, Stormstrike (row 7 now: level 40, was 25), Penance (rank 4 is 1316995),
  Lightwell, Power Infusion, Shadowform, Holy Shield (row 5: level 30), Mutilate (row 7: 40), Primal Bite (row 7: 40),
  Lacerate (now a Feral talent, row 4: 25), Venom (1329328, row 5: 30), Voice of Truth (no talent: trainer, 20).
- Golden snapshot: the commit body lists the outputs changed per class.

## 6. Website (workstream D): pages that name talents or the talent data

Not edited from here. For the site session:

| Page | What to update |
|---|---|
| `wowboxer-site/content/pages/licences.md` (Credits → Data) | "Talent data: Zephras … Mage tree updated to later hotfixes" → WoW Forever's talent trees now come from Blizzard's client tables (build 1.60.1.70888), checked against Wowhead; Zephras CC BY 4.0 stays for the other seed data. Leveling guides line: the rebuilt guides come from Icy Veins, WowVendor, Warcraft Tavern and Mobalytics (plus the unchanged seed guides: Wowhead, Method, The Forever Era). |
| `wowboxer-site/content/pages/addon.md` (feature "Talents per guide and level", Known limits, Credits line 95) | The credits line as above; the "tested … before launch, we update this page after launch week" box; the Known limits line "On Classic Era the AddOn uses Forever's class data" is out of date since 0.15 (Era has its own data). |
| `wowboxer-site/content/guides/addon.md` (line 104) | The Talents tab text is still right; it could say the guides were rebuilt for the live talents (11 Nov). |
| `wowboxer-site/content/_parked/companion.md` | Parked; its talent text describes the pre-launch data. Leave it parked or mark it as outdated. |
| `wowboxer-site/content/squads/duo.md`, `trio.md`, `party.md`, `quad.md` | "Talent trees differ" (Era vs Forever): still right, no talent names. |
| `wowboxer-site/content/_data/camping.yaml` | Line 11 "Blessing of Kings is baseline or a Protection talent in Forever" → baseline: a Paladin trainer spell at level 20 (not in any live tree). Line 134 Divine Spirit `talent: true` → false: a Priest trainer spell at 30 in the live client. Line 84 Moonkin Aura `talent: true` stays (Moonkin Form is Balance row 7). |

No site page lists a build's talents or a talent-calculator link.

## 7. Open points

- [AFKLAR: Berserk is in the Druid Feral skill line as AcquireMethod 3 only, and no talent teaches it. Left out like
  Lava Burst and Binding Heal. If a quest or item teaches it, the live spellbook shows it under All spells.]
- [AFKLAR: the Legacy perk "Talented" (first point at level 10 − rank) is still the seed's rule; it is not in the
  client tables read here.]
- [AFKLAR: diag.talentTree from the owner's characters (§3).]
