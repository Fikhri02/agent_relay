#!/bin/bash
# Builds a Release app and zips it with the skill and install steps.
# Usage: tool/package.sh [output-dir]   (default: build/package)
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="${1:-build/package}"
FLUTTER="${FLUTTER:-$HOME/Developer/flutter/bin/flutter}"
VERSION=$(grep '^version:' pubspec.yaml | awk '{print $2}' | cut -d+ -f1)
COMMIT=$(git rev-parse --short HEAD)
NAME="AgentRelay-$VERSION-$COMMIT"

"$FLUTTER" build macos --release
STAGE=$(mktemp -d)/"$NAME"
mkdir -p "$STAGE"
cp -R "build/macos/Build/Products/Release/Agent Relay.app" "$STAGE/"
mkdir -p "$STAGE/skill"
cp -R skill/inbox "$STAGE/skill/inbox"
cp install-skill.sh "$STAGE/"
cp tool/INSTALL.txt "$STAGE/INSTALL.txt"
mkdir -p "$OUT"
rm -f "$OUT/$NAME.zip"
(cd "$(dirname "$STAGE")" && ditto -c -k --keepParent "$NAME" "$OLDPWD/$OUT/$NAME.zip")
echo "$OUT/$NAME.zip"
