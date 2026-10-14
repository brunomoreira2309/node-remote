#!/bin/bash
# Builds Node Remote and installs it in /Applications, so it opens from Finder,
# Launchpad and Spotlight. Opening it again while it runs shows the panel.
set -euo pipefail
cd "$(dirname "$0")/.."
bash scripts/build.sh
TARGET="/Applications/Node Remote.app"
# Quit a running copy so the new build replaces it cleanly.
osascript -e 'tell application id "br.local.NodeRemote" to quit' >/dev/null 2>&1 || true
pkill -f "Node Remote.app/Contents/MacOS/NodeRemote" >/dev/null 2>&1 || true
rm -rf "$TARGET"
ditto "dist/Node Remote.app" "$TARGET"
xattr -cr "$TARGET" || true
codesign --verify --deep --strict "$TARGET"
printf 'Installed at %s\n' "$TARGET"
open "$TARGET"
