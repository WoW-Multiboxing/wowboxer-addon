# UI redesign: the "war table" look (the owner, 30 Oct 2026)

The owner: "It has an old feeling. Keep the classic, simple style, but make it way more modern and neat. All core functions
stay the same."

**Mockup:** Design canvas "WoWBoxer add-on redesign" (claude.ai artifact LtCsgMFY4M4ddmi5PkVPVK). It has four
screens: My macros, Squad, Automation, Macro editor.

- It is built on the WoWBoxer design system (artifact Dvayk234hxkHc8GYjaQpSe), the same look as wowboxer.com and the
  window app: a dark navy war table, gold trim and class colours.
- **Do not start before the owner has approved the mockup.** He may ask for changes first.

## 1. What changes and what does not

- **Only the look and the layout change.** Every function, text, macro rule, write rule and test stays.
- **Same flow:** pages, the top line ("next step"), right-click menus, drag and drop, the fly animation, the step
  strip, Advanced mode, Reset.
- **Works on both clients:** Classic Era 1.15 and Forever 16001. Use capability probes as today, and fall back to the
  current look on any piece of API that is missing.

## 2. The look, as tokens (`WoWBoxer/UI/Theme.lua`, one place, no colours anywhere else)

| Token | Value | Use |
|---|---|---|
| night | #0b0e14 | behind the window (only where we draw a backdrop) |
| night-2 | #0f131c | left navigation, inset wells, input fields |
| panel | #151a24 | window body |
| panel-2 | #1c2333 | header, cards, rows |
| panel-3 | #232b3e | active nav item, selected segment, raised card |
| gold | #c9a24a | 1 px trim, borders of important controls, icons |
| gold-hi | #e8c66a | links, focus, small highlights |
| gold-lo | #8c6b26 | border of primary buttons |
| line | gold at 32 % | window border, card borders that matter |
| line-soft | gold at 16 % | quiet separators, card borders |
| ui-gold | #ffd100 | headings, button labels, active labels |
| parchment | #e9dfc4 | names and titles inside cards |
| text | #d6cdb6 | body text |
| muted | #a79f8a | secondary text |
| ok / warn / no | #8ccb7a / #e6b455 / #e37a7e | states, always with a word |
| horde | #b3262b | the ONE primary button per page (Update macros, Place spells, Send, Save) |
| tt-bg / tt-edge | #090b16 / #8e8e8e | macro text preview (tooltip look) |

Class colours stay the game's own: `RAID_CLASS_COLORS`, with the token values as fallback.

- **Shapes:**
  - 1 px borders everywhere (flat textures, `SetColorTexture`; no Blizzard dialog borders or gradient bevels).
  - Corners: 4 px on buttons, 6 px on cards, 10 px on the window, made with a small rounded-corner mask/9-slice
    texture of our own (`Media/Round*.tga`).
  - If a mask is not available on a client: square corners. That is fine.
- **Type:**
  - Headings, the title and the primary buttons in **Cinzel** (Bold/SemiBold); everything else in **Inter**
    (Regular/SemiBold).
  - Both are SIL OFL fonts. Ship them as `.ttf` in `WoWBoxer/Media/Fonts/` together with their licence files.
  - Character names, spell names and chat-like text keep the **game font** (`GameFontNormal` family), so every locale
    and accented name renders. The website and window app already use Cinzel and Inter.
- **Spacing:** an 8 px grid. Window padding 16–22 px, card padding 8–12 px, gaps 8 px between cards and 14 px between
  sections.
- **Icons:**
  - Real spell icons, 40 px, with a 1 px black outline and rounded corners.
  - The keybind is a small chip at the bottom right of the icon.
  - The state is a coloured word under the name (Changed · update / On bar / Not on a bar), never colour alone.

## 3. Layout (see the mockup)

- **Header** (52 px), left to right:
  - our crest logo, "WoWBoxer" in Cinzel ui-gold;
  - a character chip (class-colour dot + name + "Warlock 24 · Follows Dorin (party1)");
  - on the right: the **Standard | Advanced** segmented switch, **Reset**, the round **?** and close.
  - The window is dragged by the header.
- **Left navigation rail** (172 px, night-2), replacing the bookmark icons on the right edge:
  - icon + word for My macros, All spells, Talents, Squad, Automation, Setup, Share;
  - small state words on the right ("1 POINT", "OFF").
  - The macro-slot meter ("18 of 30 macro slots") sits at the bottom.
  - Under 700 px window width the rail collapses to icons with tooltips.
- **Next-step banner:** a panel-2 card with a warn/ok icon, a bold line + a muted line, and the page's primary button
  on the right.
- **Controls row:**
  - dropdowns as flat pills with a gold ▾;
  - the sequence on/off as a toggle switch;
  - Simple/Medium/Advanced as a segmented control.
- **Content:**
  - **Spell macros:** a two-column card grid.
  - **Squad macros:** a list.
  - **Footer:** secondary buttons as outline buttons, one red primary.
  - Same for Squad (party-frame rows with class edge, LEADER chip, role, follow line, HP/mana bars, Up/Down/×), Automation
    (preset cards, Accept from segmented control, toggle rows), Setup, Talents, Share.
- **Dialogs** (Macro editor, Reset, Advanced confirm, level-up offer, keybind fix):
  - the same window style;
  - tabs with a gold underline;
  - drag-and-drop targets as dashed tiles → solid rows with a number and a ⋮⋮ grip;
  - a monospace preview in a tooltip-style box.
- **Tooltips and menus:**
  - the game's GameTooltip stays, so other addons that skin it keep working;
  - our right-click menus get the flat style.
- **Motion:** 150–200 ms fades and hovers (panel-2 → panel-3). Keep the fly animation. "Animations" off in Setup turns
  all of it off.
- **Scale:** the window scale and "fits the screen" stay. The minimum size is the one where every page still works
  without clipping; check at 1280×720 and 3440×1440 with UI scale 0.64–1.0.

## 4. How to build it (suggested order; small commits, a test build after each step)

1. **Theme layer:**
   - `UI/Theme.lua` (tokens, fonts, textures);
   - new widget skins in `UI/Widgets.lua`: button (primary/secondary/ghost), check → toggle and checkbox, dropdown
     pill, segmented, card, chip, scroll bar, edit box, divider.
   - All existing `W.*` calls keep their signatures, so the pages change look without code changes.
   - Remove the Blizzard templates (`UIPanelButtonTemplate`, `UICheckButtonTemplate`, `UIPanelScrollFrameTemplate`)
     from our visible widgets.
2. **Window shell:** header, left rail (replaces the right-side bookmarks), body padding. The page API (`RegisterTab`)
   stays the same.
3. **Pages:** in this order, each one compared with the mockup:
   1. My macros;
   2. Squad;
   3. Automation;
   4. Macro editor;
   5. then All spells, Talents, Setup, Share;
   6. dialogs and popups.
4. **Polish:** hover states, focus, empty states ("No squad yet – Use my party"), the collapsed rail, scale checks.

Every step:

- tests green; `tests/test_ui.lua` keeps working and checks that no page overlaps or clips at the minimum size (the
  layout audit);
- install a **test build** (not a release);
- take screenshots of every page in the game on both clients (`docs/screens/<page>.png`, for the website and
  CurseForge gallery too);
- put the 4-line checklist at the top of `docs/backlog.md`.

## 5. Not part of this

- New features.
- Changes to macro rules or texts beyond what the new layout needs. Texts may get shorter where the mockup is shorter.
