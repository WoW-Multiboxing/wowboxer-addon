# Feedback 30 Oct, 15:14 (the owner, test build 0.13.x): Macro editor and menu bugs

The owner is happy with the look and with the Targeting panel itself. These bugs are what is left; they come from his
three screenshots. **Change nothing else.**

## 1. Spells and Targeting must always be two tabs of the same window

- **What's wrong:**
  - **Right-click → Edit macro…** (screenshot 1, "Macro editor – Damage") opens with only a **Targeting** tab.
    There is no way back to Spells, and two empty button outlines sit behind the title.
  - **New macro** (screenshot 2) shows Spells + Targeting.
  - With **Single spell** chosen, the Targeting tab is missing, so a single-spell macro can't get its targeting at all.
- **Fix:**
  - **One tab bar, always the same:** **Spells · Targeting** (Options and Preview stay below, as today).
  - Both tabs are shown and clickable from **every** entry point and for **every** kind (single spell, sequence,
    priority, a recommended macro, an own macro).
  - Switching tabs keeps unsaved changes. Save and Cancel apply to both tabs.
  - No leftover or hidden buttons behind the title. Every control has one owner frame; hide frames, never only
    their textures.
  - **Standard mode:** New macro still offers the target presets (Enemy, Friendly, Myself, a squad pet) on the Spells
    tab. The Targeting tab is then shown greyed with "Advanced mode" (the same pattern as the greyed menu item).
- **Spells tab layout (screenshot 2):**
  - The type dropdown is cut ("Sequence (/castsequen…"): widen it or use short labels (**Single spell · Sequence ·
    Priority**) with the long explanation in the tooltip.
  - **Paste… / Copy…** sit inside the preview box, on top of the text: move them under the box, aligned with the
    character count.
  - The preview text wraps mid-word (`nodead]` split as `node` / `ad]`): wrap only at spaces/commas, or let the box
    scroll sideways.

## 2. The Advanced confirm opens behind the Macro editor

- **What's wrong:** switching Standard → Advanced while the editor is open puts "Turn on Advanced mode?" behind the
  editor.
- **Fix:**
  - All our dialogs (Advanced confirm, Reset, keybind fix, level-up offer, copy box) use **one dialog layer**: a strata
  above the main window and the editor (`FULLSCREEN_DIALOG`), raised with `Raise()` on show.
  - Only one dialog at a time. Esc closes the top one.
  - Switching Advanced → Standard with the editor open closes the editor (after "Unsaved changes – keep editing /
    discard" if anything changed) or turns it read-only. It never leaves a half-advanced editor.

## 3. Right-click menu says "(Advanced mode)" while Advanced is on

- **What's wrong (screenshot 3, All spells):** the menu shows **Edit macro… (Advanced mode)** greyed out although the
  header says Advanced. The menu reads a stale or wrong flag.
- **Fix:**
  - Every menu builder reads the mode from one function (`Advanced.on()`) at the moment the menu opens.
  - Test: switch the mode, then open the menu on a recommended macro, an own macro, a known spell, a future spell and
    a squad macro. Each must show the right entries in both modes.

## 4. Right-click menus linger

- **What's wrong:** after a quick right-click and mouse move, the menu stays open until the next right-click.
- **Fix: our menus close on**
  - a click anywhere else (also on the world), using a full-screen click-catcher behind the menu or the global
    mouse-down hook;
  - Esc;
  - switching page or tab, hiding or moving the window, entering combat;
  - opening another menu;
  - the mouse being away from the menu and its anchor for 1.5 s.
- Only one menu exists at a time. When Blizzard's own menu API is used (Forever), call its close function for all of
  the cases above too.

## 5. Check every flow, both modes, both clients

Before handing over the next test build, walk through these in the simulator (tests) **and** with `/wbx shots` in the
game, with a screenshot of each in `docs/screens/`:

- New macro → Single spell → Targeting tab → drag a target → Save → the macro text is right.
- New macro → Sequence → Spells and Targeting tabs, back and forth → Save.
- Right-click a recommended macro → Edit macro… → both tabs → Back to WoWBoxer's version.
- Right-click an own macro → Edit macro… → both tabs.
- Right-click a spell on All spells (known, and a future spell) → Edit macro… (Advanced on) / greyed (Standard).
- With the editor open, switch Standard ↔ Advanced → the confirm is on top; Cancel and Turn on both work.
- Right-click, move the mouse away fast, click the world → the menu is gone.

Also run `/wbx selftest`, and check that there are no Lua errors in the log (`tools/read_log.py`) on both clients.
