#!/usr/bin/env bash
# Refresh vendor/companion from the companion source (workstream A, wowboxer-site/companion). Copies engine.js,
# app.js and app_data.json with LF line endings and stamps VERSION.json. Then: node tools/build_data.js &&
# node tools/export_vectors.js && bash tests/run_all.sh. Usage: bash tools/sync_companion.sh [path to companion/]
set -euo pipefail
cd "$(dirname "$0")/.."
SRC="${1:-../wowboxer-site/companion}"
[ -f "$SRC/src/engine.js" ] || { echo "no companion at $SRC"; exit 1; }
for f in src/engine.js src/app.js data/app_data.json; do
  tr -d '\r' < "$SRC/$f" > "vendor/companion/$(basename "$f")"
done
rev=$(git -C "$SRC" rev-parse --short HEAD 2>/dev/null || echo "?")
ver=$(head -1 vendor/companion/engine.js | grep -o 'v[0-9][0-9.]*' | head -1)
printf '{\n  "companion": "%s",\n  "source": "wowboxer-site/companion",\n  "commit": "%s"\n}\n' "$ver" "$rev" > vendor/companion/VERSION.json
echo "vendor/companion <- $SRC ($ver, $rev)"
