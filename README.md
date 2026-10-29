# WoWBoxer (in-game addon)

WoWBoxer, the multiboxing tool inside World of Warcraft: **Forever** (interface 16001) and **Classic Era** (11509).
It gives each of your characters the recommended keys for its class, role and level, builds them as WBX macros and
puts them on your action bars, and keeps them up to date when you level. Made for manual multiboxing: one key press is
always one action on one character.

## What it does
- **The book** – `/wbx` opens a spellbook with your keys: the recommended keys for your level, optional sequence keys
  (Off / Simple / Medium / Advanced), your own keys (built in the in-game editor) and helpers (Follow, Assist, Focus,
  pet keys). Bookmarks on the right: *My keys*, *All spells*, *Custom keys*, *Talents*, *Setup*, *Squad*, *Share*.
  - **Drag** any key (or any learned spell from *All spells*) onto any action button, or press **Place all**. Keys you
    moved stay where you put them. When WoWBoxer places keys, their icons fly to the buttons (can be turned off).
  - The line at the top always says the next thing to do, with the button that does it. A 3-step guide on a new
    character. Hover a key to see what it does; right-click it to bind a key or leave it out.
  - **Level-up:** offers to update changed keys (same buttons, new spells); nothing changes without a click.
- Works at any resolution and UI scale: the window fits the screen, and a size option is in Setup.
- **Squad** – your characters, their roles and who leads (Home cards, Edit squad with Add my party and templates,
  Readiness, Key map, Plan). Followers' keys assist the leader via party1–4 or focus. *Send squad to my party* offers
  it to your other clients – they review and import it with a click; nothing ever acts for another client.
- **Sequence keys** – tick *Use sequence keys* and pick Simple / Medium / Advanced; the key gets the main spell's icon
  and a strip of small step icons on the action button that frames the next spell.
- **Talents** – the guide's point order for your level; on Forever also what you have actually spent.
- **Setup** – which bars your keys go on, window size, animations, multibox checklist, recommended settings (with backup/restore) and recommended addons.
- **Share** – copy your squad as a `!WBX:1!` string to your other characters.
- **Team status** (optional, display only) – a small panel showing which of your clients lost follow, has another
  target than the leader, or is low on mana.
- Minimap button (left-click open, right-click menu, drag to move) and an Addon Compartment entry on Forever.

## What it never does
No input broadcasting, no automation: it never casts, targets, follows, moves or accepts anything. It never touches a
macro that does not start with `WBX`, never runs code from an imported string, and writes macros, bars, bindings and
settings only after you click, and only out of combat. Messages between your clients are only displayed.

## Install
Unzip `WoWBoxer` into `World of Warcraft\_forever_\Interface\AddOns` (or `_classic_era_`), restart the game, and type
`/wbx`. On Classic Era the addon uses WoW: Forever data filtered by your real spellbook; the talent trees differ.

## Commands
`/wbx` open · `/wbx sync` place all keys · `/wbx show` list keys · `/wbx bars` where each key is ·
`/wbx keys` game key bindings · `/wbx cvars` / `/wbx cvars restore` · `/wbx team on|off` · `/wbx minimap` ·
`/wbx scale 0.9` · `/wbx reset` · `/wbx selftest` · `/wbx log` · `/wbx debug` · `/wbx help`

## Credits and licence
MIT licence. Talent data: Zephras (zephras.com), CC BY 4.0, changed by WoWBoxer; The Forever Era.
World of Warcraft and its names and icons are © Blizzard Entertainment. WoWBoxer is a free fan project and is not
affiliated with or endorsed by Blizzard.

## Development
Data and macro rules come from the web companion (`vendor/companion`, read-only snapshot); the Lua engine is a port that
must stay in parity with it. See `CLAUDE.md`, `docs/backlog.md` and `docs/status.md`.
```
bash tools/check.sh                    # lint, luacheck, data check, parity + all tests, share-string tests
powershell -File tools/install.ps1     # copy into the Classic Era and Forever AddOns folders
python tools/read_log.py               # read the in-game diagnose, layout audit and log after a /reload
```
