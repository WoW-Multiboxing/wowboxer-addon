# Advanced mode + Reset to default (the owner, 29 Oct 2026, 22:54)

Goal: experienced multiboxers can change **who a key casts on**, for example a healer who also heals the hunter's pet.
They can also build custom keys with full targeting. New players never see any of this unless they switch it on, and
anyone can get back to a clean WoWBoxer with **Reset to default**.

Standard mode stays exactly as it is today. Everything below is extra and switched off by default.

## 1. Standard | Advanced switch (window header)

- A small two-part switch in the header next to the title: **Standard | Advanced**. Standard is selected by default.
  The setting is account-wide (`db.settings.advanced`), so it shows the same on all characters.
- Clicking **Advanced** opens a confirm window, not a plain tooltip:
  > **Turn on Advanced mode?**
  > Advanced mode lets you change who each key casts on and edit your keys' macro text. It is meant for experienced
  > multiboxers. A wrong target can make a key do nothing, or heal or hit the wrong unit.
  > You can undo any change: each key has "Back to WoWBoxer's version", and Setup has Reset to default.
  > [ ] I understand
  > **[Turn on Advanced]** (disabled until ticked) · **[Cancel]**
- Clicking **Standard** again: your changes stay active (they are your keys). One line on My keys says
  "3 keys use your own targeting · Show" until you remove them.
- Advanced mode only shows more controls. It never changes a key by itself.

## 2. Targeting per key (right-click any key in the book → "Targeting…", Advanced only)

A small window for one key:

- **Target list.** An ordered list of who the key tries, top first, with Up / Down / Remove and **Add target**.
  - Each row shows a plain name plus the unit, e.g. "Anna's pet (party2pet)".
  - **Hover a row** to see exactly what it adds to the macro, e.g. `[@party2pet,help,nodead]`, and what it means:
    "Casts on Anna's pet when it exists, is friendly and alive".
- **Add target** offers:
  - Mouseover.
  - Your target.
  - The leader (their party unit here).
  - The leader's target.
  - **Each squad member by name with their unit here.** These are read from the party (`Squad.unitOf`), e.g.
    "Bo (party1)".
  - **Each squad pet:** for Hunters and Warlocks in the squad, "Bo's pet (party1pet)", plus "My pet (pet)".
  - party1–4 and party1pet–party4pet (raw, for people who know them).
  - Focus, Target of target, Myself (player).
- **Options per row:**
  - Friendly / Enemy: preset from the spell and changeable.
  - Skip if dead: on by default; off for Resurrection.
  - Hold a modifier, e.g. Shift = myself: adds `[mod:shift,@player]` at the top.
- **Preview** of the whole macro with its character count (≤ 255), plus errors in plain words, e.g. "Too long: remove a
  target or untick Skip if dead".
- Buttons: **Save** · **Back to WoWBoxer's version** · **Cancel**.

**Shortcut for the pet case.** On a heal key, the right-click menu has "Also heal Bo's pet". It adds Bo's pet after
the leader in one click. This is the 90 % case and doesn't need the full window.

**Squad units move.** If Bo is party1 today and party3 after a regroup, the key stores "Bo's pet", not "party1pet".
- The macro is rebuilt with Bo's current unit after the usual Update click.
- If Bo is not in the party, that row is left out of the macro and the key shows a small warning.

## 3. Custom keys in Advanced mode (KeyEditor)

- Next to the Aim dropdown (Enemy / Friendly): **Targeting…** opens the same target list as §2.
- Extra options that are only shown in Advanced mode:
  - reset (combat, target, seconds);
  - `/startattack` on/off;
  - `/petattack` on/off;
  - a modifier line, e.g. Shift = self, Ctrl = focus.
- **Edit macro text** (the last resort):
  - A text box with the full macro and live checks: ≤ 255 characters, slash-command whitelist (no `/run /script
    /console /click`), only WoW's own conditionals.
  - A text-edited key is **frozen**:
    - level-up updates skip it, with an orange mark: "Edited by you – not updated on level-up";
    - "Back to WoWBoxer's version" unfreezes it.

## 4. How it is built (keeps companion parity)

- Store overrides per character: `cdb.overrides[keyName] = { targets = {...} }` or `{ text = "..." }`.
  - Targets are stored by meaning (`{who = "member", name = "Bo", pet = true, help = true, nodead = true}`), not by
    unit.
- The engine is not changed:
  - `Engine.lua` builds the key exactly as the companion does, so `tests/parity.lua` stays at 0 failures.
  - A new `Override.lua` then replaces the conditional chain in the key's `/cast` / `/castsequence` / `/startattack` /
    `/petattack` lines with the player's chain.
  - Text overrides replace the body.
- **All the hard rules apply to the result:** `Rules.validate` (≤ 255, whitelist, WBX names); writes only after a
  click and out of combat; never `loadstring`. Overrides travel in the share string only as data (targets), never as
  macro text (hard rule 3: share strings carry no macro text).
- Book marking: a key with an override gets a small "edited" corner mark and the tooltip line "Your targeting:
  mouseover > leader > Bo's pet > me".

## 5. Reset to default (Setup, bottom, red text button)

**Step 1, "What do you want to reset?"**, with ticks and plain wording:

- [x] **This character:**
  - WoWBoxer's settings, key choices, overrides, bar placement memory and reminders for this character.
- [ ] **All my squads and saved builds** (account-wide).
- [ ] **WoWBoxer macros on this character:**
  - deletes the macros whose name starts with WBX;
  - other macros are never touched;
  - action buttons that held them become empty.
- [ ] **Game settings WoWBoxer changed:** runs Restore first, puts back the values WoWBoxer saved, then forgets the
  backup.

**Step 2, "Are you sure?"**:

- A summary of exactly what will go, e.g. "This character's settings, 3 key overrides, 18 WBX macros".
- **Type RESET to confirm.** The button stays disabled until the text matches.
- A note: "Your squads on other characters are not touched unless you ticked them."

**Then:**

- It is done out of combat; in combat the button is disabled with "Not in combat".
- One chat line says what was removed.
- An offer to **Reload UI now**, as a button the player clicks.

**Also:**

- `/wbx reset` stays as it is (window position only). Add `/wbx reset all` → opens the same two-step window; it never
  resets directly.
- Advanced mode switches back to Standard after a full reset.

## 6. Tests

- Override builder: every target kind, pet units, the modifier line, 255 trimming errors, member-unit remapping after a
  regroup, a member not in the party, frozen text keys skipped on level-up, Back to WoWBoxer's version.
- Whitelist: text overrides with `/run`, `/script`, `/console` or `/click` are refused; conditionals are checked.
- Mode: Standard hides all advanced controls; the confirm window needs the tick; overrides stay active after switching
  back.
- Reset: each tick removes exactly its part (a mock `DeleteMacro` only for WBX names); RESET must be typed; disabled in
  combat; CVar restore runs before the backup is forgotten.
- Parity unchanged (0 failures).

## 7. Open questions (Claude decides, notes in LOG)

- Where the "edited" corner mark sits on the key icon (it must not clash with the sequence strip).
- Whether the "Also heal <pet>" shortcut also shows in Standard mode. Proposal: no; Standard stays clean.
