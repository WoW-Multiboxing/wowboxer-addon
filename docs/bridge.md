# Bridge: what the addon tells the window app

The addon writes `WoWBoxerDB.bridge` in its account SavedVariables
(`WTF\Account\<ACCOUNT>\SavedVariables\WoWBoxer.lua`). The window app (WoWBoxer, workstream C, repo
`wowboxer-layouts`) reads that file. Nothing in it changes the game. The first part of the contract is in
`wowboxer-layouts/docs/classes-and-accounts.md`.

WoW writes SavedVariables only at **logout and `/reload`**. The app therefore sees the state from the last
logout/reload, never live values.

## `bridge` (version 1, since 0.9)
`{version, character, realm, class, level, loggedInAt, savedAt}`: which character this account last logged in,
written at login and logout.

## `bridge.bars`: action bar fit (since 1.1.2 / test 1.2.0-test.3)
Added for the owner's bug of 6 Nov 2026: "with action bars 2 and 3 on, some buttons are missing in the smaller windows".
The addon measures where every button of every visible Blizzard action bar actually is. That covers Edit Mode on
Forever and the classic layout on Era/TBC. It then works out the largest UI scale at which all the bars fit. The
addon only reads; it never scales, moves or hides a bar.

**When it is measured:**
- 5 s after login;
- 1 s after `UI_SCALE_CHANGED` / `DISPLAY_SIZE_CHANGED`;
- on `/wbx barfit`;
- at logout and `/reload`, which is the copy that reaches the file.

```lua
bars = {
  version = 1,
  measuredAt = 1762400000,          -- time()
  game = "forever" | "era" | "tbc",
  window = { w = 870, h = 696 },    -- GetPhysicalScreenSize(): the window's client area in pixels
  scale = 0.93,                     -- UIParent:GetEffectiveScale() now (= the UI scale)
  ui = { w = 1032, h = 826 },       -- UIParent size in UI units now
  bars = {                          -- only bars that are shown; Blizzard bars only
    { key = "main" | "bottomLeft" | "bottomRight" | "right" | "left" | "bar5" | "bar6" | "bar7" | "menu",
      label = "Bottom Left bar (bar 2)",
      buttons = 12,                 -- buttons measured (empty slots of a shown bar count; "menu": shown bag and menu buttons)
      outside = 0,                  -- buttons not completely inside the window
      covered = 0,                  -- buttons lying on a button of another bar
      left = 0, bottom = 0, right = 0, top = 0,  -- the bar's box in UI units, origin bottom-left of the window
      anchor = "center/bottom",     -- which window edges the bar follows: left|center|right / bottom|middle|top
      dx = 0, dy = 0 },             -- since 1.2.0-test.4: how far the game pushed the bar from where its anchors put it
                                    -- (kept on the screen in a too small window); box - dx/dy = the anchored place
  },
  outside = 0, covered = 0,         -- totals over all bars
  squeezed = false,                 -- since 1.2.0-test.4: a bar was pushed, or something is outside/covered
  fitScale = 0.88,                  -- largest UI scale in [0.64, 1.00] at which every shown bar fits; nil = not even 0.64
  fitsAtMin = true,                 -- false when fitScale is nil
  minScale = 0.64,
}
```

**What `fitScale` means:**
- It is the UI scale to write (`uiScale`, with `useUiScale 1`) so that, in this window, every button of every shown
  bar is inside the window with a margin of 4 UI units, and no bar lies on top of another.
- The margin is 4 units except on an edge the bar is anchored to and already sits closer to by design: Forever puts
  bar 1 two units above the bottom edge, and that bar keeps the room the game gave it. (Until 1.2.0-test.4 the
  margin applied there too, so live Forever logs said "0 outside, 0 covered; fits all at scale none".)
- The fit scale is computed from the anchored places (box − dx/dy), not from where a too small window pushed the bars.
  The app does not rely on dx/dy yet: for a squeezed record it uses its default places (`[AFKLAR]` until dx/dy are
  checked against a big window on Forever).
- `menu` (since 1.2.0-test.4) is the bag and menu buttons (micro buttons, bag slots, backpack). On Forever they ride
  on the main bar to the right of bar 1 and are the first to go in a narrow window. Since 1.3.0-test.3 they also
  count as `covered` when they really lie on a bar: at least a third of a button deep in both directions (owner
  10 Nov: on the 870x696 followers the menu, x 445–960, lay on bar 1, x 0–562, and said covered = 0). Era's tall
  micro buttons only touch the bars above them by a few units, so they still do not count there.
- It is computed from the real positions. Each bar keeps following the window edges it is anchored to. A smaller
  scale makes the window bigger in UI units, so a centred bar moves by half of the growth and a right-anchored bar by
  all of it. Button sizes in UI units do not change.
- The value is absolute, not relative to the current scale: 0.82 means "set the UI scale to 0.82".
- It is never above 1.00 and never below 0.64, the game's minimum.
- `nil` means even 0.64 is not enough. The card should then say so in plain words, for example: "Even the smallest UI
  scale can't fit all your action bars in this window. Make the window larger or turn off a bar."

**For the app:**
- Use `fitScale` for the window size it was measured in: compare `window` with the size the layout gives this client.
- After the app changes the window size or the scale, the addon measures again, but the file only changes at the next
  logout or `/reload`.
- Without a `bars` table (an old addon, or the AddOn not installed), keep today's main-bar estimate.
- UI Scale is one value per install (`WTF\Config.wtf`). For clients of the same install, take the smallest
  `fitScale` of the characters whose windows share that install.

## Real numbers (Forever, 6 and 9 Nov 2026)
- Bridge record (2560x1369 window, UI 2244x1200 at 0.64, bars 1–3): bar 1 at x 521–1083, y 2–47 (centre − 601 …
  centre − 39); bar 2 at 543–1105, y 72–117; bar 3 at 1127–1689. **Bars 2 and 3 sit side by side**, 1146 units
  together. Bar 1, the menu and the bags together need about 1190 units.
- `wbx snap` of the owner's three Forever windows (9 Nov): in the 870x696 followers Forever draws at UI scale 1.00
  (no `uiScale` line: about 1 unit per pixel, never below 0.64, so a 696-pixel window is 768 units high and 960 wide).
  The addon's record from the same minute: bar 1 at x 0–562 (pushed against the left edge), bar 2 at 22–584, bar 3 at
  398–960 (pushed against the right edge) **on top of 4 buttons of bar 2**; the bags run off the right edge. That is
  the owner's bug. UI scale 0.79 fits everything there (the app's Auto-fit, wowboxer-layouts `ActionBars`).
- Classic Era: bars 2 and 3 sit inside the 1024-wide main bar art and the right bars above it, so the verified 4:3
  rule for the main bar already covers them.

## How the app uses it (wowboxer-layouts, `feature/autofit-all-bars`)
- Which bars are on: the character's `config-cache.wtf`, `SET enableMultiActionBars "<mask>"` (1 = bar 2, 2 = bar 3,
  4 = right, 8 = right 2, 16/32/64 = bars 5–7; a missing line = 0). This is in the file on both games.
- Where they are: `bridge.bars` when the account has one, otherwise the app's default layout per game. On Classic Era
  the main bar is always the 1024-unit art.
- The character: `bridge.character` if its WTF folder exists, otherwise the folder WoW wrote last.
- The app recomputes the fit for the window size the layout gives (it does not use `fitScale` as is, because the
  measured window is often not the planned one).

Model numbers from `tests/test_barfit.lua` (window sizes in UI units at scale 1):

| Client | Bars | 1707x960 | 900x720 | 640x512 |
|---|---|---|---|---|
| Era/TBC | 1, 1+2, 1+2+3 | fits (1.00) | 0.88 | none (needs < 0.64) |
| Era/TBC | 1+2+3 + right bars | fits (1.00) | 0.88 | none |
| Forever | 1, 1+2, 1+2+3 | fits | fits | fits |
| Forever | 1+2+3 + right bars | fits | 0.99 | 0.70 (right bars lie on bars 1–3) |

These are the old stacked-bars mock. The real Forever layout (bars 2 and 3 side by side) is in "Real numbers" above
and in the test "the real Forever layout".

## The addon lays the bars out per window (since 1.3.0-test.11, owner 12 Nov 2026)
UI Scale is one value per install and never below 0.64, so it cannot fit every window shape (owner 12 Nov: two
1280x1392 followers, "even the smallest UI Scale (0.64) can't fit them all"). There is no login popup any more.
test.9/10 scaled Blizzard's bar frames by hand; Edit Mode kept moving them back and the XP bar broke (owner's
screenshots 12 Nov 11:10). Since test.11 the addon works **through Edit Mode** (`WoWBoxer/BarLayout.lua`) on every
client that has it (Forever, Classic Era 1.15.9; probed at runtime):
- **What:** a Character layout "WoWBoxer" (each window is one character) = a copy of the layout that was active, with
  only the bottom group changed: bar 1, bars 2–3, the stance and pet bars, the micro menu, the bags, the XP and
  reputation bars. Blizzard's own buttons (keybinds, macros, action slots unchanged), art, vehicle/override bars.
  1. The game's own layout fits the window (no button outside, none on another bar): nothing is written.
  2. Otherwise the arrangement and icon size with the largest icons (Edit Mode's sizes, 100 % down to 50 %, fewest
     rows on a tie): **2 rows** (bar 1 + menu + bags, the XP bar, bars 2 + 3), **3 rows** (bars 2 and 3 on their own
     rows) or **4 rows** (menu + bags at the bottom), centred at the bottom; the XP/reputation bar sized to the button
     area; stance and pet bars above the top row; never onto the chat, the unit frames or the side bars, never above
     45 % of the window. Era's gryphons stay where the rows above fit between them (else Edit Mode's *hide bar art*).
  3. Nothing fits even at 50 %: nothing is written, one chat line says so.
- **Applying:** `C_EditMode.SaveLayouts` (+ `SetActiveLayout` the first time), then Edit Mode is opened and closed
  through `ShowUIPanel`/`HideUIPanel`, so Blizzard's secure code applies it (as LibEditModeOverride does). Only out of
  combat, never while Edit Mode is open or while something is on the cursor, nothing with Bartender4/Dominos/ElvUI.
  Saved and applied only when the layout really changes. **Off** = the layout that was active before is active again
  and "WoWBoxer" is deleted. The player picks another layout in Edit Mode: WoWBoxer leaves it (paused until the
  setting is ticked again).
- **When:** login, `/reload`, `DISPLAY_SIZE_CHANGED`, `UI_SCALE_CHANGED`, `EDIT_MODE_LAYOUTS_UPDATED`, bars shown or
  hidden, Edit Mode closed, a drag ended.
- **Setting:** *Setup → Fit action bars* ("Fit action bars to this window"), on by default, per character;
  `/wbx barfit on|off`, `/wbx barfit min 50–100` (smallest icon size); `/wbx barfit` prints what it did.
- **Bridge:** `bridge.barFit = "addon"` while it is on (**for the window app: then never lower UI Scale for that
  client**; `false` when off, paused or a bar addon owns the bars), `bridge.barMode = "fits" | "layout" | "nofit" |
  "paused" | "off"`, `bridge.barRows` (2–4), `bridge.barScale` (icon size, 0.5–1.0), `bridge.barLayout` (diagnose:
  window, plan, per-system sizes and places, obstacles). `bridge.bars` (the measurement) is taken after the layout.
  Until test.10 `barFit` was `true`; treat `true` the same as `"addon"`.
- Clients without Edit Mode keep the old per-frame scale (BarFit.lua second half; only where one frame holds the bars).
- `[AFKLAR: Forever accepts a Character layout saved by an addon and applies it on the open/close without "blocked
  action" warnings, and Blizzard's bar widths match buttons × icon size + padding – checked in TEST BUILD 1.3.0-test.11]`
