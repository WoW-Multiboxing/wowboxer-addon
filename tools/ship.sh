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
