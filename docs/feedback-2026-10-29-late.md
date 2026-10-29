# Feedback 29 Oct, 23:19 (the owner): key 3 lost, "macro" not "key", Edit macro, New macro

## 1. Bug: action button 3 lost its key "3"

**Found in the owner's files (Classic Era, character Boxtester, account ACCOUNT2):**

- The log has `bind 3 -> WBX K2 (was ACTIONBUTTON3)` at 20:38.
- `bindings-cache.wtf` still contains `bind 3 MACRO WBX K2`.
- So key 3 presses the macro WBX K2 directly, and action button 3 has no key any more.
- This happened with 0.9.4, eight minutes before the Bind key fix in 0.9.5 (20:46). The fix stops new cases but did
  not repair this one. Also, today's **Unbind** only removes the macro binding: key 3 would then do nothing, instead of
  going back to button 3.

**Fix (all writes after a click, out of combat, `SaveBindings` on the character set):**

1. **Remember what a key did before.** Every bind stores `cdb.bindPrev[key] = <previous command>`. **Unbind** and
   **Reset to default** put that command back with `SetBinding(key, prev)`.
2. **Repair old cases.** When a key has a direct `MACRO WBX …` binding and no `bindPrev`, use the game's standard
   key for the buttons: `1`–`9`, `0`, `-`, `=` → ACTIONBUTTON1–12.
   - The top line / checklist then says: "Your **3** presses WBX K2 directly, so action button 3 has no keybind."
   - The button **Give 3 back to button 3** does `SetBinding("3", "ACTIONBUTTON3")` and saves.
   - If the macro should stay reachable: "Put WBX K2 on button 3 too?" uses `Core.placeOn`.
3. **Never again.** Keep 0.9.5's rule: a key that belongs to an action button is never rebound with
   `SetBindingMacro`; the macro is put on that button instead. Add a regression test: pressing **3** on an
   occupied button → Yes → `placeOn`, and the binding stays ACTIONBUTTON3.
4. **Diagnose.** Write all direct `MACRO WBX` bindings and their `bindPrev`, so `read_log.py` shows them.

## 2. Words: "macro" and "keybind", not "key"

The owner: the things WoWBoxer makes are **macros**. When a macro sits on an action button that has a key bound, that is
its **keybind**. Replace the word "key" for our macros everywhere in the UI, help, guide, chat lines, tooltips,
changelog style, README and the CurseForge text:

| Today | New |
|---|---|
| My keys (tab/bookmark) | **My macros** |
| key / keys (a WBX macro) | **macro / macros** |
| sequence keys / Use sequence keys | **sequence macros** / **Use sequence macros** |
| squad keys / Place squad keys | **squad macros** / **Place squad macros** |
| own key / New own key / Custom keys | **my macro** / **New macro** / **My own macros** |
| Bind key… | **Set keybind…** |
| Unbind | **Remove keybind** |
| "WBX K2 is now on 3" | "WBX K2 now has keybind **3**" |
| Update keys / keys to update | **Update macros** / **macros to update** |
| Keep off my bars, Place all, Leave out | unchanged |

Tooltip: show the keybind as "Keybind: 3 (action button 3)", or "No keybind – drag it to a bar or Set keybind…".

Names in code (`K1`, `keyLabel`) can stay; this is about the text players see. Update the help "?" texts and the
3-step guide too.

## 3. Right-click → **Edit macro…** (Advanced mode)

The owner right-clicked **Holy Light** on the Paladin and only saw *Pick up* and *Bind key*.
- `Advanced.menuItems` only adds items for cells that are recommended macros (`c.name and c.item`) and only when
  Advanced is on.
- Spells on the All spells page, and spells without a WBX macro, get nothing.

**New:**

- **Advanced on:** every macro and every spell in the book has **Edit macro…** in its right-click menu.
  - A spell without a WBX macro: Edit macro… creates a new own macro from that spell (single spell), then opens the
    editor.
- **Standard:** show **Edit macro… (Advanced mode)** greyed out, with the tip "Turn on Advanced in the window header
  to change who this macro casts on". That way the feature can be found without being usable by accident.
- **One editor window for everything** ("Macro editor"): replaces today's separate Targeting… and Edit macro text…
  windows.
  - Top: the spell(s) and the type (**Single spell** · **Sequence** · **Priority**).
  - **Target list** (§2 of `advanced-mode.md`): mouseover, my target, the leader, the leader's target, every squad
    member and squad pet by name with their unit here ("Bo (party1)", "Bo's pet (party1pet)"), party1–4 / party1pet–4
    pet, focus, myself.
    - Hover a row: the conditional, e.g. `[@party1pet,help,nodead]`, plus its meaning.
  - Options: Friendly/Enemy, Skip if dead, modifier line, reset, startattack/petattack.
  - Live preview + length.
  - Buttons: **Save** · **Edit text** (the frozen-text last resort) · **Back to WoWBoxer's version** · **Cancel**.
- "Also heal Bo's pet" stays as a one-click shortcut in the right-click menu of friendly macros.

## 4. **New macro** (replaces "New own key")

The editor opens with one choice: **Single spell** or **Sequence** (Priority under "More").

- **Single spell:** pick a learned spell (search box), then the targeting.
  - Standard mode has presets:
    - **Enemy:** mouseover > leader's target > my target.
    - **Friendly:** mouseover > leader > me.
    - **Myself.**
    - **Friendly: a squad pet** (Hunter/Warlock pets in the squad).
  - Advanced mode adds the full target list.
- **Sequence:** today's editor (steps + filler, reset, warnings), with the same targeting presets / list.
- **Engine:**
  - A single spell is the existing custom `priority` kind with one step (`buildCustom` already returns
    `kind = "single"`), so the engine is unchanged and parity stays at 0.
  - Targeting is the `Override` layer from 0.9.9.
- Names stay `WBX C1`–`WBX C8`. Hard rules unchanged: ≤ 255 chars, whitelist, writes after a click and out of combat.

## 5. Tests

- Bind: bindPrev saved; Unbind restores; the repair line + Give back for 1–=; no `SetBindingMacro` on an action
  button key (regression); diagnose list.
- Words: a test that scans the UI strings for `" key"`/`"Keys"` used about our macros (allow-list for keybind,
  key press, Escape key …).
- Edit macro in the menu: Advanced → present for recommended macros, own macros, spells on All spells and spells
  without a macro. Standard → greyed with tip.
- New macro: single spell with each preset; sequence unchanged; single spell + Advanced targeting; ≤ 255.
