#!/usr/bin/env bash
# Everything that must be green before a push (same as CI). Usage: bash tools/check.sh
set -eo pipefail
cd "$(dirname "$0")/.."
python tools/lint51.py
# luacheck like CI (standalone luacheck.exe on Windows: %LOCALAPPDATA%\wowboxer-tools\luacheck)
LC=$(command -v luacheck || true)
[ -z "$LC" ] && [ -n "$LOCALAPPDATA" ] && [ -x "$LOCALAPPDATA/wowboxer-tools/luacheck/luacheck.exe" ] && LC="$LOCALAPPDATA/wowboxer-tools/luacheck/luacheck.exe"
if [ -n "$LC" ]; then
  "$LC" WoWBoxer tests --no-color -q | tail -3
else
  # CI fails on any luacheck warning; without it here a push can turn main red (10-12 Nov 2026)
  echo "################################################################################" >&2
  echo "##  LUACHECK IS NOT INSTALLED - CI WILL STILL RUN IT AND FAIL ON ANY WARNING  ##" >&2
  echo "##  Install: gh release download v1.2.0 -R lunarmodules/luacheck              ##" >&2
  echo "##    -p luacheck.exe -D \"\$LOCALAPPDATA/wowboxer-tools/luacheck\"             ##" >&2
  echo "################################################################################" >&2
fi
node tools/build_data.js --check
node tools/export_vectors.js > /dev/null
out=$(bash tests/run_all.sh 2>&1) || { echo "$out" | grep -E "passed|FAIL|lua:"; exit 1; }
echo "$out" | grep -E "passed"
node share/test.js | tail -1
