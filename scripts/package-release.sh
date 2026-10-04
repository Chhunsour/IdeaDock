#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
VERSION="${1:-1.2.1}"
DIST_DIR="$PROJECT_DIR/dist"

mkdir -p "$DIST_DIR"
echo "Packaging IdeaDock v$VERSION..."
"$SCRIPT_DIR/build.sh" "$DIST_DIR/IdeaDock.app"

cd "$DIST_DIR"
zip -qr "IdeaDock-macOS-v$VERSION.zip" "IdeaDock.app"
echo "Package created at $DIST_DIR/IdeaDock-macOS-v$VERSION.zip"
