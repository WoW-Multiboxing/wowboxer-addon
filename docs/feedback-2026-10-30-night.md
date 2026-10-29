# Feedback 30 Oct, 00:15 (the owner): bug sweep – own macros, Clear target, keybind 3, guide, automation, reset

The owner: "Bug fix everything here, do your research, whatever is needed." Below are the findings from his files and
from Blizzard's UI source, with a fix for each point.

## 1. One editor for all macros (own macros are broken and the editors differ)

- **What's wrong:** "New macro", right-click → "Edit" on an own macro (`WBX C1`–`C8`, still the old KeyEditor) and
  right-click → "Edit macro…" (the new Macro editor) open **different windows**.
- **Fix:**
  - **One Macro editor** for everything: new macro, own macros, recommended macros, spells.
  - The KeyEditor's sequence controls move into it as the Spells section (steps, filler, fills, reset, warnings).
  - The old KeyEditor window is deleted.
  - Right-click shows the same "Edit macro…" entry everywhere.
- **Own macros, end to end:** run every flow in the simulator **and** write each step into the diagnose so
  `read_log.py` shows it. Fix whatever fails.
  - create a single spell and a sequence;
  - edit, rename, delete;
  - drag, Place;
  - level-up update;
  - share string import/export;
  - Advanced targeting on an own macro;
  - Back to WoWBoxer's version.
- **Test:** every path opens the same window with the same contents (one test per entry point).

## 2. "Clear target on click" does not change on followers

**Found in Blizzard's Classic Era 1.15.9 UI source** (`Blizzard_SettingsDefinitions_Frame/Controls.lua`):

```lua
-- Sticky Targeting
local setting = Settings.SetupCVarCheckbox(category, "deselectOnClick", GAMEFIELD_DESELECT_TEXT, ...)
setting:NegateBoolean();
```

- The CVar is owned by the Settings system: the "Sticky Targeting" checkbox is the CVar negated.
- A player on Blizzard's forum reports that `SetCVar("deselectOnClick")` from an addon no longer changes it, while the
  Sticky Targeting checkbox does. The owner's logs show "cvars applied: 1" on the follower account (ACCOUNT1), but the value
  did not stay.

**Fix, for every CVar in `Rules.CVARS`:**

1. If `Settings.GetSetting(name)` exists, change it **through the setting**: `setting:SetValue(v)`.
   - For a negated boolean, set the setting value so that the CVar ends up as wanted.
   - Read `C_CVar.GetCVar` after setting it; if it is the opposite, flip the boolean once.
2. Otherwise use `C_CVar.SetCVar`.
3. **Always read back.**
   - If the value didn't change, the row says **"Didn't stick"** in orange.
   - It also offers **"Open Options"**: `Settings.OpenToCategory` on Controls, or the category the setting belongs to.
   - The tip says: "Untick Sticky Targeting there."
4. **Diagnose:** per CVar, write the value before, wanted, after, and the method (setting or SetCVar).

Also check after `/reload` that the value survived: account-wide CVars are saved per WoW **account**, so every
follower account needs Apply once.

## 3. Keybind 3 goes missing again on the Paladin

**Found** (Classic Era, account ACCOUNT2, character Boxtester):

- The log has `bind 3 -> WBX K3 (was MACRO WBX K2)`.
- So a **second** bind on 3 was made while 3 was still the old broken direct binding. Because the key pressed a WBX
  macro (not ACTIONBUTTON3), `classify` called it "other" and rebound it instead of repairing it.
- `bindings-cache.wtf` still has `bind 3 MACRO WBX K2`, written at 23:06.
- The "Give 3 back" repair from 0.10.0 was never clicked.

**Fixes:**

1. **A key 1–= that presses a WBX macro directly is broken.** Treat it as the action button key.
   - **Bind:** `classify` returns the button kind (put the macro on button 3), never "other".
   - **On login:** a small popup (not only the top line):
     > Key 3 presses a WoWBoxer macro directly, so action button 3 has no keybind.
     > [Fix now] puts back ACTIONBUTTON3 · [Not now]
   - The popup asks once per login until fixed. The write happens after the click (rule 4).
2. **Audit every write to bindings and bars.** `SetBinding*`, `SaveBindings`, `PickupAction`, `PlaceAction` and
   `ClearCursor` after a pickup:
   - each one in one function in `Binds.lua` / `Bars.lua`, with a log line that says **who** asked (`source=`);
   - a test that no other file calls them (lint rule in `tools/lint51.py`).
3. **Snapshot.** The diagnose writes the 12 main buttons and their keybinds at login: slot, content, key. "Button 3
   missing" can then be seen in the files without the owner having to explain.
4. **Binding set.** `SaveBindings(2)` switches a character to character-specific bindings.
   - Check `GetCurrentBindingSet()` before and after, and keep the set the character already used.
   - If it was account-wide, write to the account set and tell the player once.

## 4. First-run guide from the right-click menu and the "?"

- **Right-click menu (minimap / Addon Compartment) → "First-run guide":** today it only opens the window. It must
  **restart the guide from step 1**: reset the guide state, open My macros, show step 1.
- **"?" button (top right):**
  - Tooltip: "Help for this page. **Right-click:** start the first-run guide again."
  - Right-click does exactly that.
- `/wbx guide` does the same.

## 5. Automation: "Accept from" for everything

One setting at the top of the Automation page, used by **every** accept (invites, quest shares, resurrections,
summons, trades and role checks):

- **Squad only** (default): WoWBoxer squad members in your party.
- **Squad, friends and guild:** also your friends list, Battle.net friends on this game and guild members.
- **Everyone** shows a warning first: "Anyone can then invite you, share quests or summon you".

Each automation row shows the current choice: "Accepts from: Squad". In Advanced mode a row can override it. Tests:
each level × each automation × stranger, friend, guild member, squad member.

## 6. Nudge players to Automation (it is a big part now)

- **Its own bookmark** in the book: **Automation**, next to Setup. It is no longer hidden inside Setup.
- **First-run guide:** a new step "Automation: pick **Levelling squad** or choose yourself", with the two buttons.
- **Checklist / top line,** once per character: "Automation is off – turn on **Levelling squad**? [Yes] [Choose…]
  [Not now]".
- **Game settings (Setup):** one line under the list: "WoWBoxer can also accept invites, quests and summons for you →
  Automation".
- The Squad page "Send to my other characters" offer also carries the automation choice, so the squad gets the same
  settings. The other clients still confirm with a click.

## 7. "Reset to default" always visible, and a real reset

- **Header:** a **Reset** button next to Standard | Advanced on every page. It opens the existing two-step window
  (ticks → summary → type RESET).
- **Goal:** back to how the character was before WoWBoxer. Add:
  - **Bars:**
    - From now on, before WoWBoxer **first** changes an action slot (Place, placeOn, drag-place, Replace), store what
      was there in `cdb.barOriginal[slot]`: spell id, item id, macro name or empty. Never overwrite an entry once
      stored.
    - Reset puts every stored slot back (`PickupSpell` / `PickupItem` / `PickupMacro`, then `PlaceAction`) and empties
      the slots that were empty.
    - Slots changed before this version can't be restored. The summary lists them: "Button 3 and 8 were changed
      before WoWBoxer kept a copy".
  - **Keybinds:** every `bindPrev` restored, all direct `MACRO WBX` keybinds removed, broken 1–= keys given back to
    their buttons.
  - **Settings:** CVars restored, through §2's method.
  - **Macros:** WBX macros deleted (only WBX).
  - **WoWBoxer data:** this character (and optionally squads/builds), Advanced off, Automation off.
- After the reset, a Reload UI button. The diagnose writes what was restored and what could not be.

## 8. Tests and release

- Tests for every point above. The simulator needs `Settings.GetSetting` with `NegateBoolean`,
  `GetCurrentBindingSet`, and the friends/guild APIs.
- Release live as usual. The in-game checklist (max 4 lines) must cover:
  1. Follower: Apply → "Clear target on click" OK after `/reload`.
  2. Paladin: Fix now → button 3 has keybind 3.
  3. Right-click minimap → First-run guide starts at step 1.
  4. Reset → bars as before.
