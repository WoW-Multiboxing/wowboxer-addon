# WoWBoxer (in-game addon)

The WoW multiboxing companion inside the game. Set up your squad (characters, class, role, leader/follower) and, for
each character and level, WoWBoxer shows the recommended talents and guide steps, builds the recommended macros and
sequence keys for your level, creates them (out of combat) and places them on your action bars. When you level up it
offers to update them: same keys, new bodies. Plus multibox helpers: leader/follow/assist checklist, recommended
settings (with backup and restore), recommended addons, and import/export of your setup as a string shared with the
WoWBoxer website and companion.

**Clients:** WoW: Forever (interface 16001) first, Classic Era (11509). One package.

**Rules it follows (non-negotiable):** one key press = one action on one character. No input broadcasting, no
automation of gameplay, no auto-follow/accept/taxi, no secure-action tricks. Imported strings are data only (never
executed). Macros are at most 255 characters, use a whitelist of slash commands, are always named `WBX …`, and are
only written out of combat after you click. WoWBoxer never touches macros without the `WBX` prefix.

## Use
`/wbx` (or `/wowboxer`) opens the window. `/wbx help` lists commands.

## Development
```
node tools/build_data.js         # WoWBoxer/Data/*.lua from vendor/companion/app_data.json
node tools/export_vectors.js     # parity vectors from the companion's own JavaScript
python3 tools/lint51.py          # Lua 5.1 syntax + compliance checks
tests/run_all.sh                 # parity + mock tests (LUA=lua5.1 / luajit / texlua)
node share/test.js               # import/export string reference implementation
```
CI runs everything on Lua 5.1 and LuaJIT, plus luacheck.

The engine (`WoWBoxer/Engine.lua`, `WoWBoxer/Kit.lua`) is a line-by-line port of the companion's `engine.js` and kit
helpers in `app.js`; `tests/parity.lua` proves identical output on ~140,000 cases.

## Credits and licence
Code: MIT. Talent data: [Zephras](https://zephras.com/data/) (CC BY 4.0, changed) and The Forever Era; spell data:
The Forever Era and wowforevertalents.com; guides as credited in the addon. World of Warcraft, Warcraft and Blizzard
Entertainment are trademarks or registered trademarks of Blizzard Entertainment, Inc. Names and icons © Blizzard
Entertainment. WoWBoxer is a non-commercial fan project and is not affiliated with or endorsed by Blizzard.
