# WoWBoxer addon – backlog

Shared work list. **Claude Code (PC) owns the code** and ticks items off here (`[x]` + commit hash). The cloud session
only adds research and items here and in `docs/research/`; it never edits code. Read this file at the start of every
milestone. Research behind the items: `docs/research/2026-10-27-ui-bars-minimap.md`.

The owner's direction (2026-10-27, after the first in-game test: "it works as an add-on, but there is a lot of work to do"):
**own character first** – the single-character flow must be excellent; the squad stays but simple. Optimise, bug-fix,
minimap button, much more drag & drop of macros onto the action bars.

## The owner: in-game test (one round, Classic Era) – the new spellbook window
1. Close every WoW client completely and start one again (new files are only read at client start). Log in on a
   **new or low-level** character so the 3-step guide shows.
2. Type `/wbx`: go through the guide (Step 1 role + leads/follows, Step 2 **Place all** – watch the icons fly to your
   bar, Step 3 Close). Press PrtScn on the book, then click each bookmark on the right once.
3. In the book: drag one key onto another action button, right-click a key → **Bind key…** → press a free key (e.g. F6).
4. `/reload`, then tell Claude "done" (Claude reads the layout audit – it now reports overlaps measured with the real
   fonts – the log, macros and screenshots and fixes the rest).

## Needs the owner in game
Built behind probes and tested in the simulator; only the real client can confirm these. (Claude Code keeps this list.)
- **Spellbook window (2e69fb4):** textures `UI-Quickslot2`, `UI-ActionButton-Border` (new-key glow),
  `UI-SpellbookIcon-Prev/NextPage-*`, bookmark icons; the 2 x 6 grid at the real font; `SetMaxLines` on the step line.
- **Fly to the bar (bbe0aee):** AnimationGroup Translation/Scale/Alpha on Era 1.15 and Forever; which buttons
  `Fly.buttonForSlot` finds (diagnose `fly.buttons`, `fly.iconIntro`); flash position over the button.
- **Layout audit now reports overlaps** (text over button / text over text) with the real fonts (`kind = overlap`).
- Layout audit (4d5b52b): opening `/wbx` once writes measured cut-off texts / too-narrow buttons / overflow to the diagnose → `tools/read_log.py`. Then screenshots only for what the audit cannot see.
- Layout of every tab at the real font sizes (screenshots with PrtScn → `_classic_era_\Screenshots`).
- Drag from the Keys tab onto an action button (`PickupMacro` after creating the macro).
- "Bind key": key capture frame (`EnableKeyboard`/`SetPropagateKeyboardInput`), `SetBindingMacro` + `SaveBindings(2)`.
- Minimap button position/drag on a round minimap; Addon Compartment entry on Forever (and whether Era has one).
- Stance page warning: `GetBonusBarOffset` (Era) / `C_ActionBar.GetBonusBarOffset` (Forever) on a Warrior.
- Hidden-bar warning: `MultiBarBottomLeft:IsShown()` when the bar is switched off.
- Class badges on the Squad tab (`CLASS_ICON_TCOORDS` + the character-create class texture).
- Talent read-back on Forever: `C_ClassTalents.GetActiveConfigID` → `C_Traits` nodes → names match the data? (diagnose: `talents.source/spent/unknown`).
- `/wbx keys` / minimap "Key bindings": `QuickKeybindFrame` on Forever, `KeyBindingFrame` on Era.
- Custom-key editor: dropping a spell from the spellbook (`GetCursorInfo` → "spell", …, spellID) on the steps strip.
- Team status with 2–3 grouped clients: `C_ChatInfo.SendAddonMessage` on PARTY, `AUTOFOLLOW_BEGIN/END`, `UnitGUID("target")` (may be secret on Forever → shown as "?").
- Non-English client (if anyone tries one): macros use `C_Spell.GetSpellName` names.
- Minimap level-up dot texture `Interface\COMMON\Indicator-Yellow`.

## UI v2 – spellbook, guide, any resolution, fly to the bar (`docs/ui-spec-v2.md`, the owner 2026-10-27 evening)
- [x] (2e69fb4) §3 Layout engine: the simulator computes boxes from anchors, scale and text metrics; `tests/layout.lua`
      fails on text over a button/text, cut text, labels wider than their button, windows off screen. Matrix in
      `tests/test_ui.lua`: 1024x768, 1920x1080, 2560x1080, 3440x1440, 1280x1024, 870x696 x UI scale 1 / 0.64 / 1.15,
      plus stress runs (font x0.62, long names, window scale 1.3 on 835x668). Buttons size to their label; one-line
      labels truncate with the full text in a tooltip; window scaled to fit (96 % x 94 %), position per character,
      back to the centre when off screen; level-up toast sized from its text (one sentence + Update keys / Later).
- [x] (2e69fb4) §1 The main view is a spellbook: two pages of 2 x 6 spell buttons (icon + `UI-Quickslot2` border, gold
      name, plain second line "Key 3 · Bar 1 · 3 · F6"), new/changed keys glow, bookmarks on the right (My keys, All
      spells, Custom keys, Talents, Setup, Squad, Share), page arrows "Page 1 / 2". Drag = create/update + PickupMacro;
      click = select (details line with Bind key / Unbind / Leave out / Edit); right-click or Shift-click = menu.
      Hover = spell-like tooltip: what the key does in plain words, macro text in green, "Drag to your action bar".
- [x] (2e69fb4) §2 Next step line on top of the book, always one sentence + the one button (Place all, Update keys,
      Use Bottom Left, Choose bars, Key bindings) – combat, hidden bar, stance page, no macro slot, trainer covered.
      3-step first-run guide (role + leads/follows, Place all with where/what gets replaced, done); "Show the guide"
      in the minimap menu and Setup.
- [x] (bbe0aee) §5 Fly to the bar: own AnimationGroups on UIParent (Translation + Scale up/down + Alpha, 0.7 s, stagger
      0.12 s), then an additive flash over the button. For Place all, Update keys and new keys. No visible Blizzard
      button (bar addons, hidden bar, other stance page) = no flight. Setting "Animations" in Setup.
      Decision: Blizzard's `IconIntroTracker` is not reused – it is driven by `SPELL_PUSHED_TO_ACTIONBAR` and calling
      it from addon code would taint the action bar code; ours only reads button positions.
- [x] (bbe0aee) Setup tab: Main keys on / Other keys on, Window size (70–130 %), Replace other buttons, Animations,
      Show the guide, Macros only – moved out of the main view.
- [x] (be12851) Plain words everywhere ("Key 3", "No free macro slot", "Left out", "Smite (Key 2) is now on F");
      tests fail on internal names in the window and on any visible button without a tooltip, on every tab.
- [x] (90e5375) Right-click menu offers nothing in combat (no pick-up or key capture while fighting).

## P0 – own character, polish and bugs
- [x] (66c60fc) **Solo by default.** First `/wbx` on a character without a squad: create a one-character squad silently (this
      character, leader) instead of the empty "Start a squad" page. Keys tab header gets the two choices that matter for
      one character: **Role** (cycle from the class's roles) and **Plays as** (Leader / Follower via party1–4/focus).
      The Squad tab stays for multiboxers but is not needed to get keys.
- [x] (2e69fb4: anchor layout + overlap matrix in test_ui on 18 screens/UI scales + stress; in-game audit reports overlaps; screenshots still welcome) Walk every tab in Classic Era and screenshot it; fix overlaps and cut-off text. Known risks in the M3 code:
      the `UIPanelScrollFrameTemplate` scrollbar sits outside the scroll frame's width and can overlap the preview
      panel on the Keys tab (list 360 px wide, preview starts at x 368); fixed pixel widths everywhere (window 660×480);
      Setup's header uses spaces for column alignment.
- [x] (d43a145: red note in the window + chat with /wbx debug) Errors inside a tab refresh are only logged (`UI.Refresh` pcall). Print them in chat when `/wbx debug` is on,
      and surface a one-line "something went wrong, see /wbx log" in the window.
- [x] (d43a145) Keys banner wording: only say "Level N:" after a real level change; first time say "Create your N keys".
- [x] (d43a145: Warrior/Druid/Rogue default to Bottom Left + Bottom Right; warning when bar 1 shows a bonus page (`C_ActionBar.GetBonusBarOffset` or `GetBonusBarOffset`)) Bar 1 for **stance/form classes** (Warrior always; Druid in forms; Rogue in stealth; Priest in Shadowform):
      bar 1 shows slots 73–120, so keys placed in 1–12 are invisible. Detect the bonus page (probe the 12.x
      replacement for the deprecated `GetBonusBarOffset`) or default these classes to Bottom Left, and explain it.
- [x] (d43a145: warning names the hidden bar and where to enable it) Before placing on a bar, check it is visible (Edit Mode / interface options); if not, say which bar to enable.
- [x] (d43a145: verified – `Compat.macroLimits` reads `MAX_CHARACTER_MACROS`) Macro slots: Classic Era has **30** per character (seen in the diagnose) – make sure the UI reads
      `MAX_CHARACTER_MACROS`, not a constant.
- [x] (d43a145: position saved on drag, `/wbx scale`, `/wbx reset`; ESC to verify in game) Remember window position; ESC closes (already via UISpecialFrames – verify); scale option (0.8–1.2).

## P1 – minimap, drag & drop, keybindings
- [x] (66c60fc, own button, no LibDBIcon) **Minimap button** (recommended: embed LibDBIcon-1.0 + LibStub + CallbackHandler + LibDataBroker, BSD-style,
      has a Forever file; licence files in `WoWBoxer/Libs/`). Left-click toggles the window, right-click menu
      (Sync keys, Settings, Hide), tooltip with character + "N keys to update", draggable, hide option + `/wbx minimap`.
      Small marker when an update is waiting after a level-up.
- [x] (66c60fc) **Addon compartment** on Forever: `## AddonCompartmentFunc: WoWBoxer_OnCompartmentClick` (+ OnEnter/OnLeave
      for a tooltip). Globals only.
- [x] (66c60fc) **Drag & drop:** every key on the Keys tab is a big draggable icon; `OnDragStart` (out of combat) creates or
      updates that WBX macro and calls `PickupMacro(index)` so the player drops it on any action button. Same for spells
      in the "other spells" list (creates `WBX <spell>` first). Show "drag me" hints; keep "Create & place keys".
- [x] (66c60fc: Binds.lua, bind/unbind with confirm) Show the **key binding** of every placed key (`GetBindingKey` on the button's binding command; bonus pages use
      `ACTIONBUTTONn`). Button "Set keys…" opens Blizzard's Quick Keybind mode (Forever) / Key Bindings (Era).
      Optional later: bind directly with `SetBindingMacro` + `SaveBindings(2)` after a click, never overwriting silently.
- [x] (d43a145: minimap, reset, scale, bars) `/wbx` sub-commands: `minimap`, `reset` (window position), `bars` (print where each key is).

## P2 – squad basics
- [x] (0d168b8: cards + inline editor for add/edit/remove, plays-as, leader) Squad tab works for: add, rename, change class/race/role, remove, make leader, follower unit, "this is me".
      Editing a member = small inline editor (name box + cycles) instead of the current row of cycles.
- [x] (already in M3: Import squad jumps to Keys) Import on a second client: after "Import squad", jump to Keys with "You are <name>" confirmed.
- [x] (d43a145: Fix button "Use partyN") Checklist: show "Leader is partyN" with the fix inline (one click sets the unit).

## P3 – later (plan §3)
- [x] (5fd776a) Bridge for WoWBoxer Window Layouts (WS-C contract, `wowboxer-layouts/docs/classes-and-accounts.md`):
      `WoWBoxerDB.bridge = {version, character, realm, class, level, loggedInAt, savedAt}` at login and logout/reload.
- [x] (54ee117: Forever only via C_Traits like Leatrix/Questie; Era says why not; "Take next" + "Off the plan" on the Talents tab; diagnose records it) Talent read-back: Forever via `C_ClassTalents` + `C_Traits` (as Leatrix Plus Forever does), Era via
      `GetTalentInfo`; show "you are off the guide" and the next point to take.
- [x] (877ff61: Keys tab "New key" / "Edit"; picker + drop from the spellbook; preview + companion warnings; WBX C1–C8) Custom-key editor in game (drag spells into a sequence via `OnReceiveDrag`), same rules as the companion.
- [x] (0bf1f4d: Team.lua + team panel, /wbx team on|off; throttled 1.5 s + 15 s heartbeat; checklist line) Display-only team status over addon messages (lost follow, different target than the leader, low mana).
- [ ] Classic Era dataset (talents/spells/guides for 1.15), TBC Anniversary. Decision (Claude Code, 2026-10-27): not
      built autonomously – it is a research/data job for the companion pipeline (workstream A). Until then Era uses
      Forever data filtered by the real spellbook, and the Talents tab says the trees differ.
- [x] (f238e40: `.github/workflows/release.yml`, tag-only: same checks, zip on a GitHub Release) Release pipeline, part 1.
- [ ] **Fit the action bar per client** (from WS-C, 2026-10-27; their backlog item 2a). UI Scale is one shared value per
      install (`WTF\Config.wtf`), so the Window Layouts app has to shrink the whole UI to make small follower windows
      show the whole bar. Per client instead: `barScale = min(1, UIParent:GetWidth() / 1024)` (Classic main bar incl.
      gryphons = 1024 UI units; 830x664 followers lose the bags below ~1.26 aspect) on `MainMenuBar` (Edit Mode bars on
      Forever: probe), applied on PLAYER_LOGIN / UI_SCALE_CHANGED / DISPLAY_SIZE_CHANGED, out of combat only.
      Hard rule 4: it changes the action bars, so it is **opt-in** – a Setup checkbox "Fit the action bar to this
      window" (one click, remembered per character), never on by default. Handshake for WS-C:
      `WoWBoxerDB.bridge.barFit = true` + `bridge.barScale` while it is on, so the app's Auto-fit can leave UI Scale
      alone. Waiting for the owner's go (new feature); needs a taint check on `MainMenuBar:SetScale` in both clients.
- [ ] Release pipeline part 2: BigWigsMods packager → CurseForge/Wago when the owner makes the repo public (needs his
      accounts/tokens and the project IDs in the TOC).

- [x] (1a50919: Macros.localize, token-wise; round-trip test over every engine macro) Non-English clients: macros use the English spell names from the data, so `/cast` fails on e.g. deDE/frFR.
      Design note (Claude Code): build a map English name → `C_Spell.GetSpellName(rank-1 spell ID)` once per login and
      localise *tokens* in the finished body (after `/cast [..] `, between `, ` in `/castsequence`, after `#showtooltip`),
      longest names first, never substrings ("Heal" inside "Greater Heal"); re-check 255 characters after. The owner's
      clients are enUS, so not urgent.

## Done
- [x] M0–M3 (data, engine parity, macro sync, bars, share string, UI) – see `docs/status.md`.
- [x] Auto-diagnose after login, `tools/install.ps1`, `tools/read_log.py` (ae586a2, 24575da).
