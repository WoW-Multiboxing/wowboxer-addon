#!/usr/bin/env bash
# Builds dist/WoWBoxer (version stamped) and dist/WoWBoxer-<version>.zip. Usage: tools/package.sh [version]
set -euo pipefail
cd "$(dirname "$0")/.."
VER="${1:-$(git describe --tags --always 2>/dev/null || echo dev)}"
rm -rf dist && mkdir -p dist
cp -r WoWBoxer dist/WoWBoxer
sed -i "s/@project-version@/$VER/" dist/WoWBoxer/WoWBoxer.toc
cp LICENSE dist/WoWBoxer/LICENSE.txt
(cd dist && python3 -c "import shutil; shutil.make_archive('WoWBoxer-$VER', 'zip', '.', 'WoWBoxer')")
echo "dist/WoWBoxer-$VER.zip"
