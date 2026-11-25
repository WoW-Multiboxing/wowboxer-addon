# Feedback 25 Nov (the owner): Macro editor bugs, especially sequences

> "I think there are some bugs in when you create macros and you click on and off with the macro editor, especially
> for sequencing. So take a look into that and see what you can find of bugs."

Found by reading `UI/KeyEditor.lua` + `UI/Advanced.lua` and **reproduced in the simulator**:
`python tools/lua.py docs/patches/repro-macro-editor.lua` (from the repo root; prints one `REPRO` line per case).
His own macros on Rup (SavedVariables 25 Nov) show bug 2 for real: "Dot Wand" = Shadow Word: Pain + filler Shoot ×2,
"Test" = Mind Blast, Devouring Plague + filler Shoot ×2.

## Bugs (all reproduced, 1.3.0-test.14)

1. **Add rejects spells the picker offers.** `KE.addStep` checks `Kit.spellsOf` (data spells only), but the picker
   (`KE.spellChoices`) lists `Kit.customSpellsOf` (+ Shoot, book spells, talent spells). Add on Shoot, Divine Grace or a
   talent spell, or dropping one from the spellbook, prints "not in WoWBoxer's spell list". `KE.usePasted` has the same
   check (drops them from a pasted macro). Fix: one list for picker, Add, drop and paste (`customSpellsOf` + learned).
2. **Shoot as the filler stops the wand.** The engine builds
   `/castsequence … reset=combat Shadow Word: Pain, Shoot, Shoot`; the second Shoot press while the wand shoots turns
   it off (plain Shoot toggles; `!` can't be used in /castsequence). `E.customWarnings` checks Shoot in the steps only,
   not the filler, so there is no warning. Fix: Shoot is never a filler or a sequence step: the Filler button is hidden
   on Shoot, and a sequence with Shoot gets the automatic wand line (`/cast [aim] !Shoot` after the sequence, as the
   recommended keys do) instead. Migrate saved macros (Rup's two) once: filler Shoot → no filler + wand line; tell the
   player in one chat line. Keep the warning for any other path.
3. **Deleting an own macro moves the others to new names.** Own macros are named by position (`WBX C<index>`);
   `KE.delete` does `table.remove`, so C3 becomes C2, etc. Everything keyed by name stays behind: targeting overrides
   (`cdb.overrides`), extra-line choices (`cdb.keyLines`), the game macro on the action bar and its keybind. Repro:
   delete C1 → C2's override now targets the macro that used to be C3; the bar slot with WBX C2 casts the old C3.
   Fix (pick one, keep saved data working, `test_savedvars` green): stable slots – a deleted macro leaves a hole that a
   new macro fills first (C<n> never changes for an existing macro); or remap overrides/keyLines/bar slots/binds on
   delete. Stable slots are the simpler and safer.
4. **Unsaved spell changes are dropped without a word.** `KE.dirty()` exists but nothing calls it. Cancel, Esc,
   closing the window, switching page/tab, opening another macro, or a second "New macro" throw the draft away. Only
   targeting changes (`f.touched`) ask, and only on Advanced → Standard. Fix: one guard for every way the editor
   closes or switches macro: "Unsaved changes – Save · Discard · Keep editing" when `KE.dirty()` or `f.touched`.
5. **Sequence → Single keeps all steps on screen, then saves only the first.** The strip still shows every step; Save
   keeps step 1 silently. Fix: when switching to Single with more than one step, keep the steps in the draft (switching
   back restores them) but show only step 1 + "Single uses the first spell"; Priority ↔ Sequence keep everything.
   Priority hides the filler: don't keep a hidden filler (or the gold tick in the picker) on a Priority/Single macro.
6. **A Priority macro with one step reopens as Single.** `KE.Open` turns `priority` + 1 step into `single`; saving it
   again is fine, but the kind dropdown shows the wrong kind and a second step later makes it a Sequence by default.
   Fix: store `single` as its own kind (or a flag) so it round-trips; migrate nothing that is already saved.
7. **Turning Advanced on while the editor is open leaves Targeting greyed.** `A.setMode(true)` only refreshes the
   header switch; the editor keeps "Advanced mode" and a disabled Targeting tab until it is reopened. Fix: re-run
   `A.showSection(f.section)` on every mode change.

Also check while there (not reproduced yet, read from the code):
- A step button's `OnClick` removes that step even when the cursor holds a spell (a drop onto a step button removes
  instead of adding). With a spell on the cursor, a click on the strip or a step should add.
- The editor's Save is enabled on a new macro with no spells (the error comes only after the click).
- `KE.Refresh` is not called on `Core.changed` (learning a spell, level-up while the editor is open).

## Done when

- Each bug above is a test in `tests/test_editor_flows.lua` / `tests/test_ownmacros.lua` (the repro cases become
  asserts), plus: switch Spells ↔ Targeting ↔ Spells many times on a new sequence, an own sequence and a recommended
  macro – the draft, the targets and the preview never change by switching alone.
- Golden snapshot unchanged (own macros are not in it); `test_savedvars` green.
- TEST BUILD + ≤4-line checklist. No release before "ship it".
