# WoWBoxer addon – backlog

## The owner: in-game check of the new book (one Classic Era client is enough)
1. Restart WoW, log in the warlock, `/wbx`: spells left, helpers + "Selected" right, nothing across the middle.
2. Hover a key with an orange dot, then press **Update keys** in the banner; the dot goes away.
3. Custom keys → New key → **Paste…** your warlock macro: it wraps inside the box, no scrolling.
4. Click the **?** on My keys, Squad and Setup (PrtScn each), then `/reload` and tell Claude "done".

Shared work list. **Claude Code (PC) owns the code** and ticks items off here (`[x]` + commit hash). The cloud session
only adds research and items here and in `docs/research/`; it never edits code. Read this file at the start of every
milestone. Research behind the items: `docs/research/2026-10-27-ui-bars-minimap.md`.

The owner's direction (2026-10-27, after the first in-game test: "it works as an add-on, but there is a lot of work to do"):
**own character first** – the single-character flow must be excellent; the squad stays but simple. Optimise, bug-fix,
minimap button, much more drag & drop of macros onto the action bars.

## Earlier in-game test (2–3 clients in one party, Classic Era) – dropdowns, sequence icons, the new squad
1. Close every WoW client and start 2–3 Classic Era clients (new files load only at client start). In one of them type
   `/console taintLog 1` once (it is saved; Claude reads `Logs\taint.log`).
2. Log in your characters and invite them into one party with Dorin as party leader.
3. On Dorin: `/wbx` → bookmark **Squad** → **Edit squad** → **Add my party**; drag one row by its grip to another
   place; change a role with its dropdown. Then **Home** → **Send squad to my party**.
4. On every other client: the card "Dorin shares squad …" → **Review** → **Import squad**, then **My keys** → **Place all**.
5. On a Paladin, Priest or Warlock: My keys → tick **Use sequence keys**, pick **Medium**, press **Update keys**. Look at
   the action bar: the sequence key has a real icon and small step icons; cast it a few times (the gold frame moves).
6. On the warlock: My keys – check the **Helpers** section (hover Follow) and that Follow/Assist/Pet show real icons on
   the bar after **Update keys**. Custom keys → New own key → **Paste…** your macro → read the warnings → **Copy…**.
7. On Dorin: Squad → Home, Readiness, Key map and Plan – PrtScn each. Then `/reload` on every client and tell Claude "done".

## Squad v2 – simple (docs/squad-v2-simple.md, the owner 2026-10-29)
- [x] 1. Templates removed; nothing switches the active squad as a side effect (Duplicate gone too).
- [x] 2. One-screen Squad page: empty state, rows (crown, role, [x], inline editor), Add character, Add my party,
      party suggestion, "Saved", Send to my other characters, More menu, squad dropdown with New/Delete; 3-step guide.
- [ ] 3. Squad keys: tick boxes on the Squad page + "Squad keys" in My keys; Invite squad by name (Name-Realm, split
      over 255, `/invite` whitelisted); Follow/Assist/Target/Focus/Pet stay on party units.
- [ ] 4. Reminders: only real changes; Keep off my bars; Don't show again per character; Level-up reminders On/Off;
      at most one chat line at login.
- [ ] 5. Copy budgets + resolution/overlap matrix green; help "?" for the new Squad page.

## Needs the owner in game
Built behind probes and tested in the simulator; only the real client can confirm these. (Claude Code keeps this list.)
- **Book v3 + help (11a8094, ece3175):** the orange "changed" dot (`Interface\COMMON\Indicator-Yellow` tinted orange),
  the round "?" and callout badges (`TempPortraitAlphaMask`), the warning icon `UI-Dialog-Icon-AlertNew`;
  `SetNonSpaceWrap` on the macro box; the scroll bar hiding when the spell list fits (`scrollBarHideable`, tooltips
  on the arrows); `HelpPlate_Show` on Era / Forever (diagnose `ui.helpPlate`, `ui.helpUsed`) – if Blizzard's plates
  look wrong, we switch to our own overlay; Esc closes the overlay (`EnableKeyboard` + propagate other keys).
- **Dropdowns (2b3d34d):** which kind each client uses (diagnose `ui.dropdown`: `blizzard` = `WowStyle1DropdownTemplate`
  + `SetupMenu`, `own` = WoWBoxer's list); our list's look, Esc and click-outside; the Blizzard menu's radios on Forever.
- **Sequence icons (b35eb80):** the macro icon file ID from `C_Spell.GetSpellTexture`/`GetSpellTexture` (macros-cache
  shows it in `read_log`); the step strip on Blizzard action buttons: `GetActionText`, `QueryCastSequence` (diagnose
  `strip.query`), `GetMacroSpell` for priority keys; **taint**: `Logs\taint.log` must not name WoWBoxer (read_log prints it).
- **Helper icons + copy/paste:** helper macros get an icon by name (`CreateMacro(name, "Ability_Tracking", …)`) or by
  `GetFileIDFromPath` when the client has it – check the bar shows them and Update keys does not repeat forever;
  the copy box (Ctrl+C from a selected edit box) and the paste box (Ctrl+V).
- **Squad sync (2c338bf):** chunked `Q|` messages on PARTY between 2–3 clients (throttling), the offer card, Review →
  Import; `P|` preset offers; `R|` readiness + version in the team status (diagnose `team.peers`); the session card
  ~20 s after login when grouped; `UnitIsGroupLeader`/`UnitClass`/`UnitRace` on party units for Add my party.
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

## Squad overhaul, dropdowns, sequence icons (`docs/squad-overhaul.md`, the owner 2026-10-27 22:16)
- [x] (2b3d34d) §2 Real dropdowns everywhere: `W.dropdown` = Blizzard's `DropdownButton` + `WowStyle1DropdownTemplate`
      + `SetupMenu`/`CreateRadio` when the client has the menu system, else our own list dropdown (shared list frame,
      radio rows, Esc / click outside / choice closes it). Never `UIDropDownMenu`. Every "‹ value ›" cycle replaced: role,
      plays as, sequence tier, class, race, guide, bars, window size, squad picker, templates, key editor.
- [x] (2b3d34d) Sequence control: `[x] Use sequence keys` + Simple / Medium / Advanced (disabled while off, the tier is
      remembered as `seqTier`) on the My keys header, in guide step 1 and in every member row of Edit squad. Classes
      without sequences: box disabled + "Not for this class" with the Paladin/Priest/Warlock note in the tooltip.
- [x] (b35eb80) §1.1 The "?" fix: sequence and priority keys get the main spell's icon file ID (filler of a
      castsequence, first line of a priority key); an old "?" counts as a change, so Update keys does one EditMacro.
- [x] (b35eb80) §1.3 Composite icons in the book (2 = side by side, 3 = main half + two quarters, 4 = 2 x 2), purple
      SEQ/PRI badge and frame, the steps with small icons and ×N in the tooltip.
- [x] (b35eb80) §1.2 Step strip on the action bars (`UI/SeqStrip.lua`): mini icons along the bottom of the Blizzard
      button, gold frame around the next step (`QueryCastSequence`, `GetMacroSpell`), SEQ/PRI badge; own frames with
      textures only, anchors only out of combat, event-driven and coalesced (0.2 s); Setup "Sequence strip on action
      bars". Taint check in Era: in the checklist above.
- [x] (bcc0e91) §3.1 Data model: slot order (= member order, drag to reorder), tags (whitelist + automatic from
      class/role), leader presets (leader + roles), notes; all in the share string.
- [x] (bcc0e91) §3.2 Squad bookmark with sub-pages: **Home** (party-frame cards: class, name, crown, role, level, keys,
      follow, same target, mana; this character in gold; composition hints, follow chain, version check, leader
      preset dropdown + Save as preset), **Edit squad** (rows with grip, name, class/race/role/plays-as dropdowns,
      sequence keys, This is me, Remove; Add character, **Add my party**, templates Duo/Trio/Quad/5-man/Undead trio,
      everyone's sequence keys, New / Duplicate / Delete), **Readiness** (party, unit, keys, Follow/Assist, settings,
      signal; the fix button on your own line), **Key map** (member x key with icons, gaps in red, the key of this
      client in the header, Copy cheat sheet), **Plan** (level, next trainer visit, next talent, leader's level).
- [x] (bcc0e91) §3.4 "Dorin is party2 here – use party2?" in the book's next step (one click on this client).
- [x] (2c338bf) §3.3 Send squad to my party: the share string in chunks (`Q|id|i|n|…`, 0.3 s apart, max 90), checked
      like a pasted string; the card "Dorin shares squad … – Review / Ignore"; Import only after the click on that
      client; logged on both sides; only from your own party. Leader preset switch → "Apply / Ignore" on clients that
      have that squad. Version check (Home + Readiness) and a session card after login when grouped.
- [x] Helper keys (the owner 2026-10-28: "they pop out of nowhere"): Follow, Assist, Focus, Pet and Pet back get icons that
      say what they do (on the bar too, not "?"), their own **Helpers** section in the book (sections: Spell keys,
      Sequence keys, Helpers, Extra keys, each on a new row), and a hover that says what the key does, how to use it and
      why WoWBoxer made it.
- [x] Copy / paste keys: right-click → **Copy…** (macro text for /macro on any character; own keys also a `!WBXK:1!`
      WoWBoxer key), key editor **Copy…** / **Paste…** (a WoWBoxer key or plain `/castsequence` / `/cast` text; only
      spell names are taken, spells of other classes are left out and named). Data only, the addon writes the macro.
- [x] Key editor warns about buffs and summons in an enemy key and about long casts (the owner's warlock key: Demon Skin +
      Summon Imp stalled the sequence). Addon-side for now; WS-A should add the same warning to the companion.
- [x] Tests: `tests/test_keys.lua` (helpers, paste/copy, warnings, box layout), `tests/test_dropdown.lua`, `tests/test_seqicons.lua`, `tests/test_squad.lua`, `tests/test_sync.lua`
      (three simulated clients in one party), every squad page and offer card in the layout matrix.

## UI v3 – the book, less text (`docs/ui-spec-v3-book.md`, the owner 2026-10-27 23:38–23:42)
- [x] (11a8094) "My keys" spread: LEFT page = next-step banner + **Spells** then **Sequences**; RIGHT page = Role,
      Plays as, sequence keys, **Party helpers** / **Pet**, the **Selected** key (icon, name, key + binding, one
      sentence, macro text small and muted, Bind key) and `11/30 macros`. Section headers are full-width rules, never
      grid cells; nothing crosses the spine; the bottom detail strip with the "?" icon is gone. All spells / Custom
      keys: banner + hint, 2 x 8 per page; clicking an own key opens the editor.
- [x] (11a8094) Visual hierarchy: spells = 37 px buttons with the action-button border, gold name (two lines rather
      than "…"), the hotkey on the icon; sequences purple + SEQ/PRI + composite icon + "Imm › SB ×4"; helpers 26 px,
      silver border, desaturated, grey short names (Follow, Assist, Focus, Pet attack, Pet back), no second line.
- [x] (11a8094) Status by colour: new = glow, changed = orange dot, not on a bar = dimmed border, left out = grey; the
      words live in the tooltips. Right-click gets Unbind when a key is bound directly.
- [x] (11a8094) Header `Name · Class N · Leader/Follower` + small **Era** tag (squad, leader, client in the tooltip);
      banner `N keys changed` + Update keys (names in the tooltip); toast `Level N: X keys changed` + Update / Later.
- [x] (11a8094) Key editor: macro in a scroll box whose text width = the inner width, word + non-space wrap, grows down
      with a scroll bar; box 312 x 186, a 255-character macro fits without scrolling; counter `234/255`. **Steps**
      (tooltip), **Filler: Shadow Bolt ×2** / **No filler**, warnings = orange ! + at most two short lines (full text
      in the tooltip); spells already in the key marked; the unlabeled icons were the scroll bar – it hides when the
      list fits and its arrows have tooltips.
- [x] (ece3175) "?" in the title bar for every page (tabs, squad sub-pages, key editor): hover = 2–4 lines, click =
      dimmed page + 3–5 numbered gold callouts on the real controls + legend (HelpPlate if the client has it), click or
      Esc closes; pulses once on the first visit.
- [x] (ece3175) Squad guide (Make the squad → Roles → Share → Keys everywhere → Check) with the step's button and
      progress dots; from the Squad "?", the minimap menu, and offered once when a second character joins the party.
- [x] (f9c3bea) Copy rules on every tab, the toast, the guides, the cards and the editor (labels ≤ 3 words, buttons ≤ 2,
      status ≤ 2, hints ≤ 8; sentences in tooltips/guides only).
- [x] (f9c3bea) `tests/test_copy.lua`: word budgets in five states, no cut names, no header in a grid cell, nothing
      across the spine, a 255-character macro fully visible, a "?" with tooltip and 3–5 callouts on every page; the
      resolution/scale matrix also covers the long macro, the help overlays and the squad guide.

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
- [x] Release pipeline part 2: CurseForge upload from the tag workflow (`tools/cf_upload.py`, `docs/release.md`); the
      repo can stay private. v0.9.0 (beta) uploaded to CurseForge project 1771228 (file 9356598, Forever 1.60.1 +
      Classic Era 1.15.9) on 2026-10-28. Next version: write `docs/changes/<ver>.md`, tag, push.

- [x] (1a50919: Macros.localize, token-wise; round-trip test over every engine macro) Non-English clients: macros use the English spell names from the data, so `/cast` fails on e.g. deDE/frFR.
      Design note (Claude Code): build a map English name → `C_Spell.GetSpellName(rank-1 spell ID)` once per login and
      localise *tokens* in the finished body (after `/cast [..] `, between `, ` in `/castsequence`, after `#showtooltip`),
      longest names first, never substrings ("Heal" inside "Greater Heal"); re-check 255 characters after. The owner's
      clients are enUS, so not urgent.

## Done
- [x] M0–M3 (data, engine parity, macro sync, bars, share string, UI) – see `docs/status.md`.
- [x] Auto-diagnose after login, `tools/install.ps1`, `tools/read_log.py` (ae586a2, 24575da).
