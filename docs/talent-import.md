# Talents: import a Wowhead link, save as a build (the owner, 29 Oct 2026, 22:02)

Goal: on the Talents tab you click **Import**, paste a Wowhead WoW Forever talent-calculator link, see what it contains,
and click **Save as** with a name. The build then shows in the Guide list like a guide, with every point and its
level, so the existing "next point" and "plan ahead" views work with it.

Example: `https://www.wowhead.com/forever/talent-calc/druid/v2410222-4_t0/0abaaaDEF1aaaa` gives this:

- Druid, **11/4/0**, 15 points, exact click order.
- Level 10 Improved Wrath, 11 Genesis, 12–14 Improved Wrath, 15–16 Improved Moonfire, 17–18 Nature's Majesty,
  19–20 Nature's Reach, 21–24 Ferocity.

## 1. The link format (worked out from Wowhead's own calculator script, 29 Oct)

`…/forever/talent-calc/<class>/<points>[/<order>]`

- **`<points>`**:
  - Starts with the hash version `v2` (stripped exactly; another `v…` = "newer format, update WoWBoxer").
  - Then one digit per talent, in Wowhead's order: row, then column. Trees are separated by `-`; trailing zeros are left
    out. `410222-4` = Balance 4,1,0,2,2,2 and Feral 4.
  - Then `_` options: `t0`–`t5` = the Forever "Talented" rank, `l<level>` = player level, `r<race>` = race. Use
    `t`; ignore the rest.
- **`<order>`** (optional; only there when the author turned on talent order):
  - `0`/`1`/`2` switches tree.
  - A lowercase token from `abcdefghjkmnpqrstvwzxyilou468-~!` = +1 rank of the talent at that position.
  - The same position as an uppercase token from `ABCDEFGHJKMNPQRSTVWZXYILOU579_^.` = all remaining ranks at once.
- **No order in the link:** build the order from the points with rows first, as the companion does for
  "final-derived" guides. The preview says "order by WoWBoxer".
- **Matching is by talent name**, using Wowhead's order of names per tree. Wowhead and WoWBoxer's data place a few
  talents differently, so position alone would pick the wrong talent.

## 2. Ready-made, checked

- `docs/patches/wowhead_import.js`: the reference decoder (about 80 lines; port it to Lua as-is).
  `node docs/patches/wowhead_import.js <link>` prints the build level by level.
- `docs/patches/wowhead-forever-trees.json`: Wowhead's talent name order per class and tree (names and max ranks
  only, 17 KB), made from Wowhead's Forever calculator data (hash version v2).
  - Generate `WoWBoxer/Data/WowheadOrder.lua` from it in `tools/build_data.js`, with `--check` as for the other data.
  - Move the JSON to `vendor/wowhead/forever-trees.json`, read-only like `vendor/companion/`.
- `docs/patches/wowhead_import.test.js`:
  - **121 pass, 0 fail.** Every companion guide is written as a Wowhead link (with and without max-rank tokens) and
    reads back to exactly the same order; bad links give the right error; the example decodes as above.
  - 10 skipped: Mage guides with a talent that exists only in WoWBoxer's data (see §5).

## 3. UI (Talents tab)

- **Import** button next to the Guide dropdown. It opens a small window:
  - **Paste box:** "Paste a Wowhead talent link (WoW Forever)". Ctrl+V; the preview updates as you type.
  - **Preview:** class icon + "Druid · 11/4/0 · 15 points · exact click order (levels 10–24)" + any warnings in orange.
    Examples: "Incineration: 5 points on Wowhead, max 3 here", "order by WoWBoxer".
  - **Name** box, pre-filled with "Wowhead 11/4/0".
  - **Save as:** saves the build. **Save and use:** saves it and picks it for this character.
- **Class rules:**
  - A link for another class still saves under that class, and the window says "Saved for Druid – pick it on a Druid".
  - Use is only offered for the right class.
- **Talented rank:** if the link's `t` differs from this character's Talented rank, show one info line only. Never
  change the character's Talented rank automatically.
- **Guide dropdown:** a "My builds" group at the top, marked "(yours)", then the guides as today. The Source tooltip
  shows "Imported from Wowhead" + the link + the date.
- **Rename / Delete** on your own builds (right-click the entry or small buttons under the dropdown). Delete asks Yes/No.
- **Nice to have:** **Copy Wowhead link** on any guide or build (the encoder in the test file), shown in the existing
  CopyBox, so you can open it on Wowhead.

## 4. Data and rules

- Store builds account-wide in `WoWBoxerDB.builds[cls]`: a list of `{id = "u<n>", name, kind = "exact-order" |
  "final-derived", order = {talent keys}, talented, link, saved = date}`.
  - They behave like guides: `Kit.guidesOf(cls)` returns your builds first, then the data guides.
  - `m.guide = "u<n>"` works everywhere a guide id works today.
  - A deleted build falls back to `K.defaultGuideFor`.
- **Hard rule 2:** the link is data only. Parse it with string functions; never `loadstring`/`RunScript`.
- **Limits:**
  - Link ≤ 300 characters, ≤ 51 points, max ranks clamped to WoWBoxer's tree.
  - The order is checked with `E.validateOrder`; it is repaired with `E.repairOrder` and a warning, and refused if it
    can't be repaired.
- **Writes:** saving only writes WoWBoxer's SavedVariables, never the game's talents. No `LearnTalent`: the player still
  spends points in the game's talent window, as the Talents tab already says.
- **Squad share string:** include the member's own build (order + name) when the member uses one, so it travels with the
  squad. Keep the data only (no link text needed), and keep it under the share-string size limit.

## 5. Data finding for workstream A

Wowhead's Forever trees and WoWBoxer's data (Zephras + The Forever Era) agree on **25 of 27 trees**. They disagree on:

- **Mage Arcane:** WoWBoxer has an extra **Arcane Focus** that Wowhead does not have, and the rows are in a different
  order.
- **Mage Fire:** Improved Fire Blast is placed differently; **Incineration** is 5 ranks on Wowhead vs 3 here;
  **Critical Mass** is 3 on Wowhead vs 5 here.

Re-check both trees on the launch client ([AFKLAR]) and correct the data. Add a note in row A.

## 6. Tests

- Port the round-trip test to `tests/` in Lua: all guides, the example link, bad links, a class mismatch, a link
  without order, a rank clamp, more than 51 points, and the newer-version error.
- UI test: Import → preview → Save as → the build shows under "My builds" → Use → the Talents tab shows its next point.
