# CLAUDE.md – wowboxer-addon

Workstream E of the WoWBoxer project. Plan and decisions live in the project folder (`02_Spec/Addon-plan.md`, `LOG.md`
blocks tagged `[WS-E]`); this file only covers working in the repo.

- Code, UI and comments in English. Lua 5.1 only (WoW). No libraries (no Ace) unless decided in the plan.
- `WoWBoxer/Data/*.lua` is generated: change `tools/build_data.js` or the vendored companion data, never the files.
- `vendor/companion/` is a read-only snapshot of the web companion (source of truth for data and macro rules).
- Engine changes must keep `tests/parity.lua` at 0 failures (regenerate vectors with `node tools/export_vectors.js`).
- Hard rules: one key press = one action on one character; never loadstring/RunScript; macros ≤ 255 chars, whitelist
  of slash commands, `WBX` prefix only, writes only out of combat after a click. `tools/lint51.py` enforces the
  forbidden-API list.
- Run before every push: `python3 tools/lint51.py && node tools/build_data.js --check && tests/run_all.sh && node share/test.js`.
