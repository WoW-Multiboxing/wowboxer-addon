# Sequences for all nine classes (the owner, 29 Oct 2026, 21:34)

Today, sequence keys exist only for the trio classes: Warlock, Priest and Paladin. Warrior, Rogue, Hunter, Mage, Shaman
and Druid get nothing, and the Sequences dropdown is hidden for them. Goal: every class and role gets
Simple / Medium / Advanced, built with the same rules as today.

**Ready-made proposal (checked):**

- `docs/patches/engine-v8.5-proposed.js`: the companion engine with the new `SEQ` entries plus a small priority
  extension.
- `docs/patches/engine-v8.5-sequences.diff`: the same change as a diff against `vendor/companion/engine.js` (8.4.0).
- `node docs/patches/check-sequences.js`: proves the following.
  - **0 macros over 255 characters.** Covers every class, role and tier; leader, party1–4 and focus; levels 1–60.
  - **0 changes** to Warlock, Priest and Paladin output.
  - Add class names (e.g. `node docs/patches/check-sequences.js rogue,mage`) to print the macros at levels 20, 40 and 60.

## 1. Rules (unchanged, from the engine header)

- **One key press = one cast.** The game's own `/castsequence` and `/cast` only: no broadcasting, nothing automatic.
- **Two kinds of key:**
  - `sequence`: `/castsequence reset=combat` with openers/DoTs first, then the filler. The loop length is sized from
    cast times, DoT durations and cooldowns, as today.
  - `priority`: several `/cast` lines, highest first, where the game skips lines that cannot be cast. Used when most
    abilities have cooldowns or conditions (Execute, Overpower, Revenge).
- **Spells not learned yet are left out**, so keys grow with level. A tier with a single spell becomes a normal key.
- **Kept out on purpose:**
  - **Next-swing abilities** (Heroic Strike, Cleave, Maul, Raptor Strike): they are off the global cooldown, so one
    press would do two things. They stay on their own keys.
  - **Long cooldowns, channels, crowd control and ground-targeted spells:** they stay on their own keys.

## 2. What each class gets

| Class / role | Kind | Simple | Medium | Advanced |
|---|---|---|---|---|
| Warrior tank | priority | Revenge → Sunder Armor | Shield Slam → Revenge → Sunder | + Thunder Clap ([combat]) before Sunder |
| Warrior melee | priority | Execute → Overpower → Mortal Strike / Bloodthirst | + Victory Rush | + Whirlwind ([combat]), Slam |
| Rogue | sequence (combo) | 3× builder, Eviscerate | 2× builder, Slice and Dice, 3× builder, Eviscerate | 2×, SnD, 4×, Eviscerate (5 CP) |
| Hunter | priority + pet + `!Auto Shot` | Arcane Shot | Arcane Shot → Aimed Shot | Aimed → Arcane → Multi-Shot |
| Mage | sequence | Fire Blast + bolt filler | + Arcane Wrath | Pyroblast opener + Fire Blast + Arcane Wrath |
| Shaman ranged | sequence | Flame Shock + Lightning Bolt | + Lava Burst | + Chain Lightning |
| Shaman melee | priority | Stormstrike → Earth Shock | Stormstrike → Flame Shock | + Fire Nova ([combat]) |
| Shaman healer | sequence (help, combat/12) + damage key | Riptide + 2× Healing Wave | same | + Chain Heal |
| Druid ranged | sequence | Moonfire + Wrath | + Insect Swarm | Insect Swarm, Moonfire + Starfire |
| Druid melee (cat) | sequence (combo) | 3× Claw, Rip / Ferocious Bite | Rake, 3× Claw, finisher | two finisher loops |
| Druid tank (bear) | priority | Primal Bite → Swipe | Primal Bite → Lacerate (Swipe before 42) | same as Medium |
| Druid healer | sequence (help) + damage key | Rejuvenation + 2× Healing Touch | + Regrowth | + Wild Growth |

Notes on the table:

- Rogue builder = Hemorrhage when talented, otherwise Sinister Strike.
- Mage filler = Frostfire Bolt (40+), otherwise Frostbolt, otherwise Fireball.
- Healers get two keys (Heal + Damage), like Priest today.

Example at level 60, follower on party1 (Rogue, Medium, 243 characters):

```
#showtooltip
/startattack [@mouseover,harm,nodead][@party1target,harm,nodead]
/castsequence [@mouseover,harm,nodead][@party1target,harm,nodead] reset=combat Hemorrhage, Hemorrhage, Slice and Dice, Hemorrhage, Hemorrhage, Hemorrhage, Eviscerate
```

## 3. Engine changes (small, in the diff)

1. New `SEQ` entries for warrior, rogue, hunter, mage, shaman and druid. `seqSupported` is then true for all nine classes.
2. `buildPriority`:
   - `/startattack` only when `aim: 'melee'`; new `pet: true` adds `/petattack`; new `autoshot: true` adds a final
     `/cast [aim] !Auto Shot` (the `!` keeps Auto Shot on).
   - Leader on a ranged priority key uses mouseover > own target.
   - No spells learned yet: a hunter gets an Auto Shot + pet key; a non-melee priority returns nothing.
   - The Paladin output is byte-identical (checked).
3. Rogue and Cat sequences use the existing `allowDup` and `startattack` options, so the same builder can repeat.
4. Header text: "All nine classes (v8.5)".

## 4. Process (CLAUDE.md: the companion first)

1. The companion is the source of truth: `wowboxer-site/companion/` (00_Workstreams row A; D owns that code).
   - Apply the diff there as one small commit, "companion v8.5: sequences for all nine classes", and run its tests.
   - The web page is parked, so this changes nothing live on the site.
   - Note it in LOG.md (`[WS-E]`) and in row A: "v8.5 sequences for all classes added by E; D please review".
2. Re-sync `vendor/companion/` with `tools/sync_companion.sh`, then run
   `node tools/build_data.js && node tools/export_vectors.js`.
3. Port it to `WoWBoxer/Engine.lua`: the `SEQ` table and the `buildPriority` changes. `tests/parity.lua` must stay at 0
   failures, and the vectors already cover sequences for every class.
4. UI: the Sequences tick + Simple/Medium/Advanced dropdown now show for every class.
   - The book's sequence marking, combined icons and step strip work as today.
   - The help text says which keys are sequences and which are priority keys, in one sentence each.

## 5. To check in the game ([AFKLAR], write results in the diagnose / LOG)

- **Combo points for followers.**
  - Do Rogue/Cat combo points add up when the builder hits `[@party1target]` while the follower's own target is
    something else?
  - If not: the help text tells followers to press **Assist** first (one press, as today). No automatic `/assist` in
    the key.
- **Hunter:** does `/cast !Auto Shot` after Aimed Shot clip or cancel the Aimed cast? If it does, drop Aimed Shot from
  Medium.
- **Warrior priority:** the lines with Execute, Overpower and Victory Rush must fall through to the next line when they
  can't be used (wrong health, no dodge, no kill).
- **Spell names on the Forever client:** Primal Bite, Arcane Wrath, Frostfire Bolt, Riptide, Lava Burst, Stormstrike
  and Hemorrhage, as in `app_data.json`. A missing name is simply left out.
