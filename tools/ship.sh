#!/usr/bin/env bash
# Commit already done? Then: rebase on origin (the research session only adds docs), run the full gate, push,
# install into both clients. Never pushes red. Usage: bash tools/ship.sh
set -e
cd "$(dirname "$0")/.."
GITC=(-c credential.helper= -c 'credential.helper=!gh auth git-credential')
timeout 60 git "${GITC[@]}" pull -q --rebase origin main
bash tools/check.sh
timeout 60 git "${GITC[@]}" push -q origin main
git log --oneline -1
powershell -ExecutionPolicy Bypass -File tools/install.ps1 | tail -2
# wait for CI on this push and say so if it is red
sleep 5
id=$(gh run list -R WoW-Multiboxing/wowboxer-addon -L 1 --json databaseId -q '.[0].databaseId')
if gh run watch -R WoW-Multiboxing/wowboxer-addon "$id" --exit-status > /dev/null 2>&1; then echo "CI green"; else echo "CI RED: gh run view $id --log-failed"; exit 1; fi
