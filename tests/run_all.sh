#!/usr/bin/env bash
# Runs every Lua test file with $LUA (default: lua, else texlua). Vectors are generated first if missing.
set -euo pipefail
cd "$(dirname "$0")/.."
# Windows without a lua binary: real Lua 5.1 through lupa (python -m pip install --user lupa)
LUA="${LUA:-$(command -v lua || command -v luajit || command -v texlua || echo "python tools/lua.py")}"
[ -f tests/vectors/custom.json ] || node tools/export_vectors.js
fail=0
for t in tests/test_*.lua tests/parity.lua; do
  [ -f "$t" ] || continue
  echo "== $t ($LUA)"
  $LUA "$t" || fail=1
done
exit $fail
