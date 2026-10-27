#!/usr/bin/env bash
# Everything that must be green before a push (same as CI). Usage: bash tools/check.sh
set -e
cd "$(dirname "$0")/.."
python tools/lint51.py
node tools/build_data.js --check
node tools/export_vectors.js > /dev/null
out=$(bash tests/run_all.sh 2>&1) || { echo "$out" | grep -E "passed|FAIL|lua:"; exit 1; }
echo "$out" | grep -E "passed"
node share/test.js | tail -1
