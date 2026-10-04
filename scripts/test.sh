#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
WORKSPACE_DIR="$PROJECT_DIR"
if [ "$(basename "$(dirname "$PROJECT_DIR")")" = "outputs" ]; then
    WORKSPACE_DIR="$(cd "$PROJECT_DIR/../.." && pwd)"
fi
BUILD_ROOT="${IDEADOCK_BUILD_ROOT:-$WORKSPACE_DIR/work/IdeaDock-build}"
mkdir -p "$BUILD_ROOT/clang-modules" "$BUILD_ROOT/swift-modules" "$BUILD_ROOT/swiftpm-cache" "$BUILD_ROOT/swiftpm-config" "$BUILD_ROOT/swiftpm-security"
export CLANG_MODULE_CACHE_PATH="$BUILD_ROOT/clang-modules"
export SWIFTPM_MODULECACHE_OVERRIDE="$BUILD_ROOT/swift-modules"

COMMON_ARGS=(--package-path "$PROJECT_DIR" --scratch-path "$BUILD_ROOT/package" --cache-path "$BUILD_ROOT/swiftpm-cache" --config-path "$BUILD_ROOT/swiftpm-config" --security-path "$BUILD_ROOT/swiftpm-security" --manifest-cache local --disable-sandbox)
swift build "${COMMON_ARGS[@]}" -c debug
BIN_DIR="$(swift build "${COMMON_ARGS[@]}" -c debug --show-bin-path)"
"$BIN_DIR/IdeaDock" --self-test
