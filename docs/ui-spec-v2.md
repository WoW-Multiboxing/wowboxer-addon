# UI spec v2 – "WoWBoxer spellbook" (the owner, 2026-10-27 evening)

Feedback after testing: (1) it must be **far more intuitive what to do**; (2) text overlaps buttons in the window and
the pop-up on the owner's settings – it must work at **any resolution, aspect ratio and UI scale**; (3) the look is OK, but
the main view should **feel like the game's spellbook**: you open it and drag your keys from it onto your bars.
This supersedes the Keys-tab layout in `docs/ui-spec.md`; colours and the other tabs stay.

## 1. The main view is a spellbook
- Book-like window (two pages side by side, parchment/dark book background like the Classic spellbook), opens with
  `/wbx`, the minimap button or the addon compartment.
- Each page: a grid of **spell buttons** exactly like the spellbook: 2 columns × 6 rows, square icon (≈37 px) with the
  action-button border (`Interface\Buttons\UI-Quickslot2` or the spellbook's slot texture), name to the right in gold,
  a second line in white/grey ("Key 1 · Changed", "Sequence · Medium", "On Bar 1 · 3 · key 1").
- **Drag any button straight to an action bar** (creates/updates that WBX macro first, then `PickupMacro`). Click =
  select (details on the right page / tooltip). Shift-click or right-click = small menu (Pick up, Bind key, Leave out).
- Hover = a real tooltip like a spell tooltip: name, what the key does in plain words ("Casts Smite on your mouseover,
  else the leader's target"), the macro text in green, "Drag to your action bar".
- **Bookmark tabs on the right edge** (like the spellbook's school tabs): *My keys* (kit + sequences + helpers),
  *All spells* (every learned spell, drag to make an extra key), *Custom keys*, *Talents*, *Setup*, *Squad*, *Share*.
  Page arrows + "Page 1/2" at the bottom, as in the game.
- New/changed keys glow (the spellbook's "new spell" glow) until they are placed or updated.

## 2. Make it obvious what to do
- One clear next step at the top of the left page, always in the same place, e.g.
  "**Step 2 of 3:** drag your keys onto your action bar – or press *Place all*", with the button right there.
- First-run guide on a fresh character (3 steps, dismissible, can be reopened from the menu):
  1. "Who is this character?" – role + Leader / Follower of <name> via party1 (big buttons, sensible defaults).
  2. "Put your keys on your bar" – drag, or *Place all* (shows where they will go and what gets replaced).
  3. "Done – WoWBoxer will tell you when a level-up changes a key."
- Plain words everywhere: no "WBX K3", "noslot", "skipped" in the UI. Use "Key 3", "No free macro slot",
  "Left out". Internal names only in tooltips.
- Every button has a tooltip saying what will happen in the game. Empty states always say what to do next.
- Level-up pop-up: one sentence + two buttons (**Update keys**, Later); never more text than fits.

## 3. Works at every resolution and UI scale
- No fixed pixel layout for text: anchor text LEFT and RIGHT to its neighbours, `SetWordWrap`, `SetMaxLines`
  (or truncate with "…" and show the full text in the tooltip). Buttons size to their text (`GetTextWidth` + padding)
  with a minimum width; rows grow in height when text wraps.
- Window size from the screen: `min(designWidth, UIParent:GetWidth() * 0.9)` etc.; clamp to screen; remember position
  per character; scale slider (0.7–1.3) in Setup and `/wbx scale`.
- Pop-ups/toasts: width from the text, anchored under the top centre, clamped to the screen.
- Test matrix in `tests/test_ui.lua` (mock reports text width as length × font size × 0.55): UIParent 1024×768,
  1920×1080, 2560×1080 (21:9), 3440×1440, 1280×1024 (5:4), UI scale 0.64 and 1.15. Assert no font string overlaps a
  button or runs outside its parent (compute boxes from anchors in the mock), and nothing leaves the screen.
- Check in game with screenshots (Classic Era) at the owner's real resolution (his small follower windows are 870×696).

## 4. Keep
- All rules in CLAUDE.md. Drag & drop only picks up a macro; the player drops it. Writes only after a click, out of combat.
- Colours and the other tabs from `docs/ui-spec.md` (they move into the bookmark tabs).
