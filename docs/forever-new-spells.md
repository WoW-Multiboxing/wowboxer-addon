# Spells the data lacked (owner, 10 Nov 2026)

Found: Rup, a Human priest on Forever (level 18), learned **Divine Grace (Rank 2)** at the trainer (spell 1277371), but
`WoWBoxer/Data/Forever/Class_priest.lua` had no Divine Grace, so All spells never showed it. The Forever seed
(`vendor/companion`) predates launch and lacks the spells that are new in Forever.

## How the list was made

1. **Blizzard's client tables** for each game, read through wago.tools:
   - Forever: build **1.60.1.70862** (product `wowf`, the build on the owner's PC, `.build.info`).
   - Classic Era: build 1.15.9.70576.
   - TBC Anniversary: build 2.5.6.70577.
   - Tables used:
     - `SkillLineAbility` (class skill lines and race masks), `SkillLine`, `SkillRaceClassInfo`.
     - `SpellName` and `Spell` (rank text, tooltip text).
     - `SpellLevels` (trainer levels), `SpellMisc` (passive/hidden flags, icons), `SpellCooldowns`, `SpellCastTimes`, `SpellDuration`.
   - Every active (not passive, not hidden) spell of a class skill line was compared with our data by name.
2. **Left out**:
   - Pet abilities (Beast Training).
   - Rune engravings and Season of Discovery leftovers, i.e. spell IDs with no trainer row: Heart of the Lion,
     Aspect of the Viper 415423, Shadowfiend 401977, Aspect of the Falcon, Black Arrow, Fel Armor 403619 and others.
   - Effects and procs: Lightwell Renew, Focused Casting, Judgement of X, trap effects, "… Effect".
   - Talent passives.
3. **Cross-checked** with the per-class Forever spell lists of talentsforever.com (beta client 1.60.1.70755), e.g.
   <https://talentsforever.com/priest/abilities>. Each spell below is on that list.
4. **Macro rule** (category and action): WoWBoxer's, from the spell's own tooltip text. Priest racials use the same
   rules as in TBC (`datasrc/tbc/spells.json`).

The Forever spells go into `datasrc/forever/spells-extra.json`, which `tools/build_data.js` merges after the seed;
`vendor/companion` stays read-only. Era and TBC spells go into the existing `new` lists of
`datasrc/<game>/spells.json`; their ranks, levels and icons come from the client tables as before.

Even with the data complete, All spells also reads the **live spellbook** (`Compat.spellbookItems`, `Kit.bookSpells`).
Every active spell of a class tab that is still not in the data shows with the game's name, icon and ID, and the
tooltip line "From your spellbook". The book's future spells show under Future spells, at the level from
`GetSpellLevelLearned`. `WoWBoxerDB.diag[char].extraSpells` lists them, and `python tools/read_log.py` prints them.
**After the owner's logins:** each spell in that list is one the data still lacks; add it here.

## WoW Forever (`datasrc/forever/spells-extra.json`)

IDs are rank 1 … last rank (with the trainer level); cast/cd are seconds from the client tables.
Source: the client tables of build 1.60.1.70862 for each spell, plus the talentsforever.com class page named.

| Class | Spell | Levels / ranks (IDs) | Race | New/changed | What it does (tooltip) | Macro rule | Cross-check |
|---|---|---|---|---|---|---|---|
| Priest | Divine Grace | 10, 18, 26, 34, 42, 50, 58 (1277370, 1277371, 1277372, 1277374, 1277376, 1277377, 1277378) | Human | new | Instant heal on a friend below a health %, removes Weakened Soul; not on self. cd 600 | Heal · friendly target (no @player) | [priest](https://talentsforever.com/priest/abilities) |
| Priest | Feedback | 20, 30, 40, 50, 60 (13896, 19271, 19273, 19274, 19275) | Human | changed | Anti-magic shell burns the caster's mana. cd 180 | Defense · self | priest |
| Priest | Desperate Prayer | 10 … 58, 7 ranks (13908 … 19243) | Dwarf (only, in Forever) | changed | Instantly heals you. cd 600 | Heal · self | priest |
| Priest | Chastise | 20, 30, 40, 50, 60 (1277331 … 1277335) | Dwarf | new | Holy damage, roots a Humanoid up to 2 s. cd 120 | Damage · ranged (as in TBC) | priest |
| Priest | Starshards | 10 … 58, 7 ranks (10797 … 19305) | Night Elf | changed | Arcane damage over 6 s. cd 30 | Damage · ranged | priest |
| Priest | Elune's Grace | 20 (2651) | Night Elf | changed | Fewer melee/ranged hits for 15 s. cd 300 | Defense · self | priest |
| Priest | Confounding Flash | 10 (1277455) | Gnome | new | Confuses nearby enemies for 3 s; 0.5 s cast, cd 120 | Control · self | priest |
| Priest | Contingency Plan | 20, 30, 40, 50, 60 (1277462, 1277634, 1277638, 1277639, 1277640) | Gnome | new | Ward on an ally: a shield and a heal when they drop low. cd 600 | Defense · friendly | priest |
| Priest | Hex of Weakness | 10 … 60, 6 ranks (9035 … 19285) | Troll | changed | Less attack power and healing on the enemy for 2 min | Debuff · ranged | priest |
| Priest | Shadowguard | 20 … 60, 6 ranks (18137, 19308 … 19312) | Troll | changed | Shadow damage to attackers, 10 min buff | Buff · self | priest |
| Rogue | Shank | 24, 44 (1329283, 1329549) | – | new | Off-hand strike, 50 % weapon damage, gives Energy. cd 10 | Damage · melee | [rogue](https://talentsforever.com/rogue/abilities) |
| Rogue | Death Mark | 40, 48, 56, 60 (1316709, 1325756, 1325757, 1325758) | – | new (talent, Subtlety row 7) | Finisher, stores damage and deals it after 6 s. cd 10 | Damage · melee | rogue |
| Warrior | Reckless Swings | 25 (1329555) | – | new (talent, Fury row 4) | Next melee hits give more Rage for 8 s. cd 15 | Buff · self | [warrior](https://talentsforever.com/warrior/abilities) |
| Paladin | Oath of Light | 25 (1328548) | – | new (talent, Holy row 4) | Oath on an ally: more healing from your Holy Light/Flash/Shock, 5 min | Buff · friendly | [paladin](https://talentsforever.com/paladin/abilities) |
| Shaman | Totemic Call | 22 (437009) | – | new | Moves your active totems to you. cd 30 | Totem · self | [shaman](https://talentsforever.com/shaman/abilities) |

Mage, warlock, druid and hunter (the hunter's own spells): nothing missing. Their talentsforever.com lists match our
data (pets' Beast Training spells aside). The race masks come from `SkillLineAbility.RaceMasks_0`.

### [AFKLAR]

- **Reckless Swings, Oath of Light, Death Mark** come from talents that are *not* in our pre-launch Forever talent trees
  (Zephras data; the client's `Talent` table is the old one too). In the data they are `gate = "talent"` with no
  talent key, so All spells lists them only once the spellbook has them. `[AFKLAR: Forever's real talent trees]`
- **Sense Undead (paladin)**: in the client's class skill line and on the talentsforever.com paladin page, but with no
  level in either. Not in the data, so it shows from the spellbook when known. `[AFKLAR: its Forever trainer level]`
- talentsforever.com lists **Binding Heal** (priest), **Lightwell**, **Voice of Truth**, **Revoke**, **Salvation**,
  **Mass Salvation** and **Blessing of Light** (paladin) as gone from Forever. Our data still has them. They are not
  touched here: this fix only adds. `[AFKLAR: remove after an in-game check]`
- Whether Forever's spellbook lists future spells at all (`Enum.SpellBookItemType.FutureSpell`).
  `[AFKLAR: see diag.extraSpells (future = true)]`
- The level of a rank the client gives as 0 (Reckless Swings, Oath of Light): the talent row's level from
  talentsforever.com (25).

### Rerun on the live client (11 Nov 2026, build 1.60.1.70888)

The talents-and-guides rerun (`docs/talents-rerun-2026-11-11.md`, `docs/forever-talent-diff.md`) now reads Forever's
spell ranks and trainer levels from the client tables too (`tools/fetch_client.py forever`), not from the seed.

- **Nothing new is missing.** Every active spell of a Forever class skill line in build 70888 is in the data. What
  the tables still have that the data does not: pet abilities and pet training (Bite, Claw, Dash, the resistances,
  Great Stamina …), effects and procs (Abolish Poison Effect, Lightwell Renew, Bane of Doom Effect, Chilled,
  Clearcasting), talent passives (Hack and Slash, Weaponmaster, Pyroclasm, Magic Absorption) and Season of Discovery
  leftovers with no trainer row (Aspect of the Falcon/Viper, Black Arrow, Heart of the Lion, Shadowfiend, Felfire,
  Metamorphosis : Demon Charge). The same rules as above leave them out.
- **The extras here are now talents of the live trees:** Reckless Swings (Fury row 4, level 25), Oath of Light
  (Holy row 4, 25), Death Mark (Subtlety row 7, 40). Their talent keys come from the live tree, and the level is
  never before the row.
- **Gone from Forever** (no talent and no trainer in 70888; Wowhead's Forever class abilities agree): Lava Burst,
  Berserk, Binding Heal. Removed from the data. **Renamed:** Elemental Mastery → Lightning Mastery (the same spell 16166).
- **Changed levels and ranks** (the client wins): see `docs/forever-talent-diff.md` §4.4, e.g. Righteous Fury 10 (was 16),
  Holy Shield 30 (Protection row 5), Stormstrike 40 (Enhancement row 7), Lacerate a Feral talent from 25, Ferocious Bite
  a new rank at 24, Exorcism, Seal of Righteousness and Touch of Weakness with every rank's ID.

## Classic Era (`datasrc/era/spells.json` → new)

Same method, client build 1.15.9.70576. Ranks and levels come from the client.

- **Paladin:** Sense Undead (20), Summon Charger (60, mount).
- **Mage:** Detect Magic (16).
- **Rogue:** the named poison ranks as their own spells:
  - Instant Poison II–VI
  - Deadly Poison II–V
  - Crippling Poison II
  - Mind-numbing Poison II–III
  - Wound Poison II–IV
- **Warlock:** the named stone ranks, plus Detect Lesser and Detect Greater Invisibility:
  - Create Healthstone (Minor/Lesser/Greater/Major)
  - Create Soulstone (Minor/Lesser/Greater/Major)
  - Create Firestone (Lesser/Greater/Major)
  - Create Spellstone (Greater/Major)

  Era names each rank differently, so `/cast Create Healthstone` makes only the middle one.
- **Left out:** Season of Discovery runes (Commanding Shout 403215, Meathook, Avenging Wrath 407788, Divine Steed,
  Shamanistic Rage 425336, Thrash, Metamorphosis …), effects (Judgement of X, trap and Hellfire effects, Pounce
  Bleed, Moonkin Aura) and talent passives.

## TBC Anniversary (`datasrc/tbc/spells.json` → new)

Client build 2.5.6.70577.

- **Paladin:** Sense Undead (20), Summon Charger (60; Alliance and Horde IDs as two ranks).
- **Mage:** Teleport and Portal to Exodar and Theramore (Alliance), Silvermoon and Stonard (Horde), and Shattrath
  (both factions' IDs).
- **Rogue:**
  - Instant Poison II–VII
  - Deadly Poison II–VII
  - Crippling Poison II
  - Mind-numbing Poison II–III
  - Wound Poison II–V
  - Anesthetic Poison
- **Shaman:** Totemic Call (30).
- **Left out:** effects (Judgement of X, Holy Vengeance, Blood Corruption, Create Soulwell), Curse of Idiocy (not
  trainable in TBC) and talent passives.

## Fixed on the way

`tools/build_data.js` gave every Era/TBC spell from a `new` list the ID `""`. All of them, e.g. Starshards and Hex of
Weakness, shared one ID, so dragging one of them could make a macro for another. Each now gets its own ID
(`priest-starshards`). The golden snapshot changed only in the spell lists and the drag-a-spell extras. Every
class/role/level/unit macro, sequence and kit is byte for byte the same (checked section by section).
