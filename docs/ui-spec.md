# UI spec (from the Design mockup "WoWBoxer addon window", 2026-10-27)

The mockup is a private Design artifact in the owner's claude.ai account; this file is the text version so the code can
match it. In game the window is ~640–680 × 460–500 px. Match the look, not the exact pixels.

## Look
- Dark brown panel `#1a140e`, gold border `#8a6d32`, header strip `#241b11`, inner boxes `#120e09` with border `#4a3a1c`.
- Titles gold `#ffd100` (GameFontNormal family); body text parchment `#e8dcc0`; secondary text `#a89a7e`.
- Primary action = red Blizzard button (UIPanelButtonTemplate) with gold text; secondary = plain button.
- Status colours: New `#7cc7ff` (blue), Changed `#f0b43c` (orange), OK `#8fbf6a` (green), No slot / error `#ff8a80`.
- Class-coloured character names (RAID_CLASS_COLORS). Icons 26 px with a thin gold border.

## Frame
- Header: "WoWBoxer" (large gold) + one line: `<Name>` (class colour) · Class · Level N · Leader / follows <leader> via partyN · squad name. Close button top right.
- Tabs under the header: **Keys | Squad | Talents | Setup | Share**; the active tab looks raised (gold text).
- Footer strip (Keys tab): Bars selector, "Replace occupied buttons" checkbox, "N / MAX macro slots", then
  "Macros only" (secondary) and **"Create & place keys"** (primary, right-most).

## Keys tab (main)
- Green banner at the top only when something changed: "**Level 12:** 3 keys changed (Holy Strike rank 2, …, new
  Consecration on K5). Same buttons, new macros." + red **Update keys** button.
- Left (≈60 %): "Your keys" + sequence tier buttons (Off / Simple / Medium / Advanced, active one highlighted).
  Rows: icon · key name (mono, muted) · spell/label · status (coloured) · bar slot ("Bar 1 · 3"). Alternating row shades.
  Under the list: trainer hint in amber ("Visit your trainer: …").
- Right (≈40 %): selected key title ("WBX S1 · Damage"), macro text in a dark mono box (green-ish text), "96 / 255
  characters · priority list, highest first", and one muted line with the targeting rule for this character.
- Drag & drop: every key icon can be dragged to an action button (hint "drag to your bar").

## Squad tab
- Top: squad selector, "Followers use the leader's level" checkbox, New squad, **Add character** (primary).
- One card per character: round class-coloured badge, name + badge LEADER / THIS CHARACTER, sub line
  (Class · Race · Level · guide · sequence), role, unit ("plays normally" / "assists via party1"), Edit. The current
  character's card has a gold border.
- Info box at the bottom: how leader/follower targeting works and "import the same squad string on every client".

## Talents tab
- Left column (≈250 px): Guide selector (default marked ★), guide type in green ("Exact point order from the guide"),
  gold-bordered "Next at level N" box (icon, talent, "Rank x of y · Tree", "Then: …"), source + licence line.
- Right: "Point order" list: Lv · icon · talent · rank; past rows muted, current row highlighted gold, future normal.

## Setup tab
- Left: "Multibox checklist" rows (green ✓ / amber ! / blue i, title + muted hint); below "Recommended addons"
  (Loaded green, Installed-not-loaded amber, Missing red).
- Right: "Settings for a leader/follower" table (Setting · Now · Rec. · status), buttons "Restore old values" and
  **"Apply N settings"**.

## Share tab
- Left "Import": hint, paste box (mono), validation box (green "Valid: squad … (3 characters, Forever)", one line per
  character, this character highlighted gold, what it brings, "Nothing changes in the game until you press Create &
  place keys"), Clear + **Import squad**.
- Right "Export": hint, string box (selected for Ctrl+C), explanation "never macro text or code", **Select all**.

## Level-up toast
- Small dark-green box near the top of the screen: "WoWBoxer – level N: X key(s) changed (…). Same buttons, new
  macros." Buttons: Later · Show · **Update keys**.
