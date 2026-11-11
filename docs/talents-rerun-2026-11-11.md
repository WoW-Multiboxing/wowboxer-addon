# Talents and guides rerun on the live WoW Forever data (the owner, 11 Nov 2026)

> "The talent points are not up to date with WoW Forever. We need to make a rerun and everything here. Also, we need
> to update all of the guides and so on."

## 1. Why it is out of date

- Forever talents and the talent guides still come from the **frozen pre-launch seed** (`vendor/companion/app_data.json`:
  Zephras + The Forever Era, written before 4 Nov). Era and TBC already come from Blizzard's own client tables
  (`tools/fetch_client.py` → `datasrc/<game>/blizzard-<build>.json`). Forever does not.
- Known mismatches even before launch (`docs/talent-import.md` §5): Mage Arcane (extra Arcane Focus, row order), Mage
  Fire (Improved Fire Blast position, Incineration 5 vs 3 ranks, Critical Mass 3 vs 5). Launch and the first hotfixes
  will have changed more.
- The seed has 90 talent guides; every one is built on the old trees.

## 2. Task

### 2.1 Forever talent data from the live client

1. Extend `tools/fetch_client.py` with `forever` (the build on the owner's PC: read it from the client, e.g.
   `_forever_\.build.info` / the Wago game key `forever`). Forever shows its talents through `C_Traits` in game, so
   the tables may be TraitTree/TraitNode/TraitNodeEntry/TraitDefinition instead of Talent/TalentTab: probe which
   tables wago.tools has for that build, and support what is there. Unknowns are `[AFKLAR]`, never guessed.
2. Write `datasrc/forever/blizzard-<build>.json` in the same shape as Era/TBC (trees, talents with t/r/c/m/ranks/req,
   spells with ranks per level, icons).
3. `tools/build_data.js`: Forever talents (and spell ranks/levels) come from that file. The seed stays read-only in
   `vendor/companion/` (never deleted) but is no longer the talent source. `datasrc/forever/spells-extra.json` still
   merges on top.
4. Cross-check every tree against the Wowhead Forever talent calculator (`vendor/wowhead/forever-trees.json`;
   refresh it from Wowhead's current calculator data and note the hash version). Write the diff per class and tree
   (talent added/removed/moved/rank change, name change) in `docs/forever-talent-diff.md`. Client and Wowhead must
   agree; if they don't, the client wins and the row says so.
5. **Ground truth in game:** the diagnose dumps the live tree of the logged-in character through `C_Traits` (tree,
   row, column, name, max rank, spent) to `diag.talentTree`. `read_log.py` compares it with our data and prints
   every difference. The owner's characters cover Paladin, Priest and Warlock.

### 2.2 Every guide rebuilt

1. Run every guide (seed guides, WoWBoxer starter builds, `datasrc/*/guides.json`) through `E.validateOrder` on the
   new trees. Write a table in `docs/forever-talent-diff.md` §Guides: guide id, OK / repaired / broken, what changed.
2. A guide whose talents still exist: repair the order (`E.repairOrder`) and keep the guide.
3. A guide that uses removed or reworked talents: rebuild it from a current Forever source (Wowhead Forever,
   Icy Veins Forever, Warcraft Tavern Forever leveling guides). Keep the spirit of the guide (spec, role, leveling
   order); put the source and date in its note. No source = say so in the note and use the WoWBoxer starter-build
   rules; never invent a "pro" build.
4. Make sure every class and role still has at least one guide and a default (`K.defaultGuideFor`).
5. Players' saved choices: a saved `m.guide` id that no longer exists falls back to the default with one chat line
   ("Your talent guide was updated for WoW Forever's live talents"). Own builds (`WoWBoxerDB.builds`, Wowhead
   imports) are kept; ones that no longer validate get a warning in the Guide list and on the Talents tab, never a
   silent change. `tests/test_savedvars.lua` must stay green.

### 2.3 "And so on": everything else that hangs on talents or levels

- Sequences, priority keys and recommended macros that use talented spells (Hemorrhage, Stormstrike, Penance,
  Lightwell, Power Infusion, Shadowform, …): still correct names and levels after 2.1.
- Spell levels and ranks for Forever from the client tables too (the same rerun), merged with `spells-extra.json`.
- Talent import (`wowhead_import`): works against the new trees; the example link in `docs/talent-import.md`
  still decodes or the doc says what changed.
- `docs/forever-new-spells.md`: update it with what the client tables show.
- Website (workstream D): list every page that names talents or talent builds (`wowboxer-site/content`) in
  `docs/forever-talent-diff.md` §Website, so the site session can update them. Don't edit the site from here.

### 2.4 Safety net

- The golden snapshot (`tests/golden/`) will change on purpose. Regenerate it in the same commit, with a one-line
  reason ("Forever talents and guides from the live client, 11 Nov 2026"), and list in the commit body how many
  outputs changed per class.
- Era and TBC output must not change at all (their golden parts byte-for-byte).
- New tests: client-table parsing for Forever (fixture CSVs), every guide validates on the new trees, saved-guide
  fallback, own build kept with a warning, diag.talentTree comparison.

## 3. Hand-over

Usual checks (lint, `build_data --check`, `export_vectors`, `run_all`, share test), TEST BUILD, a ≤4-line
checklist for the owner:

1. Paladin, Priest, Warlock: Talents tab → the next point matches the game's talent window.
2. Guide list shows the updated guides; your old choice still selected or "updated" line in chat.
3. `/reload` on all three → diag.talentTree saved (read_log shows 0 differences).
4. Macros/sequences still work as before.

No release before "ship it". LOG.md `[WS-E]` block + row E.
