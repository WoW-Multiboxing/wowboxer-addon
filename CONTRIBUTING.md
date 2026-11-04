# Contributing to WoWBoxer

Thanks for helping! Bug reports, ideas and pull requests are welcome.

## Reporting a problem
- In the game: `/wbx report` builds a text with your WoWBoxer and game version, class/level/role, settings and the last
  log lines. Character and realm names are left out unless you tick the box. Paste it in #setup-help on
  [Discord](https://discord.gg/Q5xwbqhKzQ) or in a [GitHub issue](https://github.com/WoW-Multiboxing/wowboxer-addon/issues).
- Say which game (Forever, Classic Era, TBC Anniversary) and what you expected to happen.

## The rules every change keeps
These are non-negotiable (see `CLAUDE.md` and [`docs/compliance.md`](docs/compliance.md)):
1. **No input broadcasting.** Casting, targeting, moving, following and NPC interaction always come from the player's
   own key press on that character. Never call protected or hardware-event functions from a script, and never try to
   get around those checks.
2. Automation uses WoW's normal addon API only. Each automation is a named option in Setup → Automation and reacts
   only to squad members in the party.
3. Imported strings and addon messages are **data only**: never `loadstring`, `RunScript` or `load` on them.
4. Macro names start with `WBX` (≤ 16 characters). Bodies are ≤ 255 characters, with no `/run`, `/script`,
   `/console` or `/click`.
5. Macros, action bars, bindings and settings change only after a click, and never in combat (`Core.whenSafe`).
6. Lua 5.1, no libraries, English code and UI, no ads and no obfuscation (Blizzard's UI Add-On Policy).

## Development
- `WoWBoxer/Data/<Game>/` is generated: change `datasrc/<game>/` or `vendor/companion/` (Forever's frozen seed,
  read-only) and run `node tools/build_data.js`. Hand-written per-game rules are in `WoWBoxer/Games/<Game>.lua`.
- Forever's macro output is pinned by `tests/golden/`. A deliberate change regenerates it (`tests/golden.lua --write`)
  in the same commit, with a one-line reason.
- Before a pull request, run:
  ```
  python tools/lint51.py && node tools/build_data.js --check && node tools/export_vectors.js
  bash tests/run_all.sh      # Lua 5.1 (or python tools/lua.py via lupa on Windows)
  node share/test.js
  ```
  CI runs the same checks plus luacheck.
- Keep commits small and the UI text short (the copy tests check word budgets).

By contributing you agree that your contribution is licensed under the MIT licence of this project.
