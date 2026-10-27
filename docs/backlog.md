# WoWBoxer addon – backlog

Shared work list. **Claude Code (PC) owns the code** and ticks items off here (`[x]` + commit hash). The cloud session
only adds research and items here and in `docs/research/`; it never edits code. Read this file at the start of every
milestone. Research behind the items: `docs/research/2026-10-27-ui-bars-minimap.md`.

The owner's direction (2026-10-27, after the first in-game test: "it works as an add-on, but there is a lot of work to do"):
**own character first** – the single-character flow must be excellent; the squad stays but simple. Optimise, bug-fix,
minimap button, much more drag & drop of macros onto the action bars.

## P0 – own character, polish and bugs
- [x] (66c60fc) **Solo by default.** First `/wbx` on a character without a squad: create a one-character squad silently (this
      character, leader) instead of the empty "Start a squad" page. Keys tab header gets the two choices that matter for
      one character: **Role** (cycle from the class's roles) and **Plays as** (Leader / Follower via party1–4/focus).
      The Squad tab stays for multiboxers but is not needed to get keys.
- [ ] (partly 66c60fc: Keys overlaps fixed) Walk every tab in Classic Era and screenshot it; fix overlaps and cut-off text. Known risks in the M3 code:
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
- [ ] (partly 66c60fc: Edit + no overlaps – verify in game) Squad tab works for: add, rename, change class/race/role, remove, make leader, follower unit, "this is me".
      Editing a member = small inline editor (name box + cycles) instead of the current row of cycles.
- [x] (already in M3: Import squad jumps to Keys) Import on a second client: after "Import squad", jump to Keys with "You are <name>" confirmed.
- [x] (d43a145: Fix button "Use partyN") Checklist: show "Leader is partyN" with the fix inline (one click sets the unit).

## P3 – later (plan §3)
- [ ] Talent read-back: Forever via `C_ClassTalents` + `C_Traits` (as Leatrix Plus Forever does), Era via
      `GetTalentInfo`; show "you are off the guide" and the next point to take.
- [ ] Custom-key editor in game (drag spells into a sequence via `OnReceiveDrag`), same rules as the companion.
- [ ] Display-only team status over addon messages (lost follow, different target than the leader, low mana).
- [ ] Classic Era dataset (talents/spells/guides for 1.15), TBC Anniversary.
- [ ] Release pipeline (BigWigsMods packager → CurseForge/Wago) when the repo goes public.

## Done
- [x] M0–M3 (data, engine parity, macro sync, bars, share string, UI) – see `docs/status.md`.
- [x] Auto-diagnose after login, `tools/install.ps1`, `tools/read_log.py` (ae586a2, 24575da).
