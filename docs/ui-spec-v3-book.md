# UI spec v3 – the book, less text (the owner, 2026-10-27 23:38, screenshot of "My keys" on a level-4 Warlock)

"The overview in the spellbook is weird. Too much text, like AI slop – it must be to the point and simple. There should
be a visual distinction between the spells you actually use and the helper spells."

## What is wrong in the screenshot
1. **Section headers sit in grid cells** ("Spell keys / One spell per press" and "Helpers / Follow, assist and p…" take a
   spell slot with no icon), so the grid looks broken and items jump around.
2. **The right page is empty** while the left page is crowded; the 2-column grid runs across the book's spine
   ("Shadow Bolt" starts at the gutter).
3. **Helpers look exactly like spells** (same size, same gold name, same "· Changed").
4. **Too many words:** header line "Warlockér · Warlock · Level 4 · follows Warlocker (party1) · squad Warlocker's
   squad · Classic Era (Forever data)"; banner "6 keys changed (Shadow Bolt, Summon Imp, Follow the leader, ...). Same
   buttons, new spells."; every button repeats "Key 1 · Changed"; truncated names ("Take the leader'…",
   "Pet passive + fol…"); the bottom detail strip shows a "?" icon with "Spell keys · One spell per press".
5. Status only as text in gold – "Changed" everywhere, no colour, nothing to scan.

## The new "My keys" spread
```
 LEFT PAGE – YOUR SPELLS                      RIGHT PAGE – HELPERS + DETAILS
 ─ Spells ─────────────────────────           ─ Party helpers ──────────────
 [1] Shadow Bolt      [2] Immolate             (o) Follow     (o) Assist
 [3] Summon Imp       [4] Corruption           (o) Pet attack (o) Pet back
 ─ Sequences ──────────────────────           ─ Selected ───────────────────
 [9] Damage ▸ Imm › SB×4   (purple)            [icon] Shadow Bolt   Key 1 · F1
                                               Casts on your mouseover, else
                                               Warlocker's target.
                                               /cast [...] Shadow Bolt   (small, mono)
 ‹ page 1/1 ›                                  [Update keys]
```
- **Section headers are full-width rules** (small caps gold text + thin line), never grid cells. No sub-text under them.
- **Spells (left page):** the spellbook look – 37 px icon with the action-button border, name in gold, *one* short
  second line only when it adds something (bar + keybind: "Bar 1 · 1 · F1"). The key number sits on the icon like an
  action bar hotkey (white, top-left). Two columns per page; never across the spine.
- **Sequences:** same row size, purple border, SEQ/PRI badge, composite icon, second line "Imm › SB ×4".
- **Helpers (right page):** visibly secondary – smaller round/ghost buttons (28 px, silver border, desaturated), names in
  light grey, no second line. Section title "Party helpers" (followers) / "Pet" (pet classes). Leaders without a pet
  see no helper section.
- **Status by colour, not words:** new = the spellbook's new-spell glow; changed = small orange dot on the icon corner;
  up to date = nothing; not on a bar = dimmed border. Words only in the tooltip.
- **Selected detail on the right page** (replaces the bottom strip): icon, name, key + binding, ONE plain sentence of
  what it does, the macro text small and muted, and the single action for that key.
- **Header line:** `Warlockér · Warlock 4 · Follower` (squad name and client go into the tooltip of the name).
- **Banner:** `6 keys changed` + **Update keys**. Hover lists them. Level-up toast: `Level 5: 2 keys changed` +
  Update / Later.
- Footer: only `11/30 macros` in muted text, right-aligned. Settings live in Setup.

## Copy rules (apply to every tab)
- Labels ≤ 3 words, buttons ≤ 2 words, status ≤ 2 words, one-line hints ≤ 8 words. Sentences only in tooltips and in
  the guide (≤ 1 sentence per step).
- No filler: drop "Same buttons, new spells", "One spell per press", "Display only", "Nothing changes until…" from the
  page – put it in a tooltip once if it matters.
- Plain game words: "Follow", "Assist", "Pet attack", "Pet back", "Damage sequence", "Heal sequence", "Key 3", "Bar 1".
- No truncation of names: short helper names (above) and widths from the layout engine.
- Examples: "Take the leader's target" → **Assist**; "Follow the leader" → **Follow**; "Send pet to the same target" →
  **Pet attack**; "Pet passive + follow" → **Pet back**; "11 of 30 character macro slots used" → **11/30 macros**;
  "Classic Era (Forever data)" → small tag **Era** with a tooltip.

## Tests
- `tests/test_copy.lua`: walk every visible FontString/Button text in every tab and state (fresh char, follower,
  leader, pet class, sequences on, level-up banner) and fail on: label/button/status/hint over the word budgets above,
  any "…" truncation of a spell or helper name, a header occupying a grid cell, text crossing the book's spine.
- Keep the resolution/scale overlap matrix green.
