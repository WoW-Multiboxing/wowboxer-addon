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
    { key = "main" | "bottomLeft" | "bottomRight" | "right" | "left" | "bar5" | "bar6" | "bar7",
      label = "Bottom Left bar (bar 2)",
      buttons = 12,                 -- buttons measured (empty slots of a shown bar count)
      outside = 0,                  -- buttons not completely inside the window
      covered = 0,                  -- buttons lying on a button of another bar
      left = 0, bottom = 0, right = 0, top = 0,  -- the bar's box in UI units, origin bottom-left of the window
      anchor = "center/bottom" },   -- which window edges the bar follows: left|center|right / bottom|middle|top
  },
  outside = 0, covered = 0,         -- totals over all bars
  fitScale = 0.88,                  -- largest UI scale in [0.64, 1.00] at which every shown bar fits; nil = not even 0.64
  fitsAtMin = true,                 -- false when fitScale is nil
  minScale = 0.64,
}
```

**What `fitScale` means:**
- It is the UI scale to write (`uiScale`, with `useUiScale 1`) so that, in this window, every button of every shown
  bar is inside the window with a margin of 4 UI units, and no bar lies on top of another.
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

Model numbers from `tests/test_barfit.lua` (window sizes in UI units at scale 1):

| Client | Bars | 1707x960 | 900x720 | 640x512 |
|---|---|---|---|---|
| Era/TBC | 1, 1+2, 1+2+3 | fits (1.00) | 0.88 | none (needs < 0.64) |
| Era/TBC | 1+2+3 + right bars | fits (1.00) | 0.88 | none |
| Forever | 1, 1+2, 1+2+3 | fits | fits | fits |
| Forever | 1+2+3 + right bars | fits | 0.99 | 0.70 (right bars lie on bars 1–3) |

On Era, bars 2 and 3 sit inside the 1024-wide main bar art, so they need no more width than bar 1. Their buttons go
missing for the same reason as bar 1's. On Forever, the bottom bars are narrow (562 units), and the problem is the
right bars covering them in small windows.

## Not built: the addon scaling its own bar (`bridge.barFit`, `bridge.barScale`)
`docs/backlog.md` P3 "Fit the action bar per client" keeps those two names reserved. That would be an opt-in Setup
switch with which the addon scales the bars itself (hard rule 4: it changes bars, so the player clicks it on). It
needs the owner's go-ahead. Until then `barFit`/`barScale` are never written, and the app's Auto-fit owns the UI scale.
