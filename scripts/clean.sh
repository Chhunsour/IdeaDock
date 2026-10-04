#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "Cleaning build artifacts..."
rm -rf "$PROJECT_DIR/.build"
rm -rf "$PROJECT_DIR/work"
echo "Build directories cleaned."
