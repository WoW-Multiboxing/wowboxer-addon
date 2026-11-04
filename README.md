# WoWBoxer (in-game addon)

WoWBoxer, the multiboxing tool inside World of Warcraft: **Forever** (interface 16001), **Classic Era** (11509) and
**TBC Anniversary** (20506). Download: [CurseForge](https://www.curseforge.com/wow/addons/wowboxer), [Wago](https://addons.wago.io/addons/rNkgpzNa)
or the [GitHub releases](https://github.com/WoW-Multiboxing/wowboxer-addon/releases); guides on [wowboxer.com](https://wowboxer.com/).
It gives each of your characters the recommended macros for its class, role and level, builds them as WBX macros and
puts them on your action bars, and keeps them up to date when you level. Made for manual multiboxing: one key press is
always one action on one character.

## What it does
- **The book** – `/wbx` opens a spellbook with your macros: the recommended macros for your level, optional sequence macros
  (Off / Simple / Medium / Advanced), your own macros (built in the in-game editor) and squad macros (Follow, Assist, Focus,
  pet macros). Pages in the left rail: *My macros*, *All spells*, *Macro editor*, *Talents*, *Squad*, *Automation*, *Setup*, *Share*.
  - **Drag** any macro (or any learned spell from *All spells*) onto any action button, or press **Place all**. Macros you
    moved stay where you put them. When WoWBoxer places macros, their icons fly to the buttons (can be turned off).
  - The line at the top always says the next thing to do, with the button that does it. A 3-step guide on a new
    character. Hover a macro to see what it does and its keybind; right-click it to set a keybind or leave it out.
  - **Level-up:** offers to update changed macros (same buttons, new spells); nothing changes without a click.
- Works at any resolution and UI scale: the window fits the screen, and a size option is in Setup.
- **Squad** – your characters, their roles and who leads (Home cards, Edit squad with Add my party and templates,
  Readiness, Key map, Plan). Followers' macros assist the leader via party1–4 or focus. *Send squad to my party* offers
  it to your other clients – they review and import it with a click; nothing ever acts for another client.
- **Sequence macros** – tick *Use sequence macros* and pick Simple / Medium / Advanced; the macro gets the main spell's icon
  and a strip of small step icons on the action button that frames the next spell.
- **Talents** – the guide's point order for your level; on Forever also what you have actually spent.
- **Setup** – which bars your macros go on, window size, animations, multibox checklist, recommended settings (with backup/restore) and recommended addons.
- **Share** – copy your squad as a `!WBX:1!` string to your other characters.
- **Team status** (optional, display only) – a small panel showing which of your clients lost follow, has another
  target than the leader, is low on mana, is away, and each character's gold and free bag slots. The leader also sees
  whispers your followers get (GM whispers tagged, with a sound) and a loud warning when a follower stops following.
- **Automation** (Setup → Automation, one tick each, squad only) – accept invites, quests, resurrections and summons,
  share and turn in quests, follow the leader's dialog and flight choices, sell junk and a shared sell list, repair,
  restock reagents.
- Minimap button (left-click open, right-click menu, drag to move) and an Addon Compartment entry on Forever.
- **Community and help** – Discord, YouTube and the website at the bottom of the left rail and in the minimap menu:
  a click shows the link in a copy box (addons cannot open a browser or use the clipboard, so you press Ctrl+C).
- **Report a problem** – builds a text with your WoWBoxer version, game version, class/level/role, settings, macro
  slots and the last log lines (character and realm names left out unless you tick the box). You copy it and paste it
  in #setup-help on Discord – WoWBoxer never sends anything by itself.

## What it never does
No input broadcasting: one key press is one action on one character. WoWBoxer automates the boring parts (invites,
quests, dialogs, vendor) with WoW's own addon API. Details and reasoning: [`docs/compliance.md`](docs/compliance.md).
Casting, targeting, moving, following and talking to NPCs always stay your own key press on that character. Every
automation is a tick in Setup → Automation and only reacts to the characters of your squad. WoWBoxer never touches a
macro that does not start with `WBX`, never runs code from an imported string, and writes macros, bars, keybinds and
settings only after you click, and only out of combat.

## Install
Use the CurseForge or Wago app, or unzip `WoWBoxer` into `World of Warcraft\_forever_\Interface\AddOns` (or
`_classic_era_`, `_anniversary_`), restart the game, and type `/wbx`. Each game loads its own data (talents, spells,
races, sequences).

## Commands
`/wbx` open · `/wbx sync` place all macros · `/wbx show` list macros · `/wbx bars` where each macro is ·
`/wbx keys` game key bindings · `/wbx cvars` / `/wbx cvars restore` · `/wbx team on|off` · `/wbx sell add|remove [item]` · `/wbx minimap` ·
`/wbx scale 0.9` · `/wbx reset` · `/wbx selftest` · `/wbx log` · `/wbx debug` · `/wbx ?` (all commands) ·
`/wbx discord` · `/wbx youtube` · `/wbx website` · `/wbx help` (help on Discord) · `/wbx report` (Report a problem)

## Credits and licence
MIT licence. Talent data: Zephras (zephras.com), CC BY 4.0, changed by WoWBoxer; The Forever Era.
World of Warcraft and its names and icons are © Blizzard Entertainment. WoWBoxer is a free fan project and is not
affiliated with or endorsed by Blizzard.

## Development
The addon is the source of truth for data and macro rules. Per-game data in `WoWBoxer/Data/<Game>/` is generated by
`tools/build_data.js` (Forever from the frozen seed in `vendor/companion/`, Era and TBC from `datasrc/`); never edit it by
hand. See [`CONTRIBUTING.md`](CONTRIBUTING.md), `CLAUDE.md` (the project's rules), `docs/backlog.md` and `docs/release.md`.
Security issues: [`SECURITY.md`](SECURITY.md).
```
bash tools/check.sh                    # lint, luacheck, data check, parity + all tests, share-string tests
powershell -File tools/install.ps1     # copy into the Classic Era and Forever AddOns folders
python tools/read_log.py               # read the in-game diagnose, layout audit and log after a /reload
```
