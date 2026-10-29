# Vendored companion snapshot

Read-only copy of the WoW Forever Multibox Companion (workstream A) that the addon is generated and tested from:

- `app_data.json` – output of the companion's `build/build_data.py` (talents, spells, guides, kit picks, races, racials)
- `engine.js` – the companion's pure macro/sequence/talent engine
- `app.js` – the companion UI; `tools/export_vectors.js` extracts the kit functions (`coreList`, `seqOf`, `seqPlan`, …) from it verbatim

Do not edit these files here. Refresh them with `bash tools/sync_companion.sh [../wowboxer-site/companion]` and re-run
`node tools/build_data.js` and the tests. Source of truth: `wowboxer-site/companion/` (Git; owned by workstream D, row A).
