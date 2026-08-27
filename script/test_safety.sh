#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build/safety-tests"
SWIFTC="/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc"
SDK="/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"

if [[ ! -x "$SWIFTC" || ! -d "$SDK" ]]; then
  echo "Scrub99 safety tests require a full Xcode installation at /Applications/Xcode.app." >&2
  exit 1
fi

mkdir -p "$BUILD_DIR/ModuleCache"

"$SWIFTC" \
  -sdk "$SDK" \
  -target arm64-apple-macosx13.0 \
  -module-cache-path "$BUILD_DIR/ModuleCache" \
  "$ROOT_DIR/Scrub99/Sources/Core/Models.swift" \
  "$ROOT_DIR/Scrub99/Sources/Core/GlobMatcher.swift" \
  "$ROOT_DIR/Scrub99/Sources/Core/ApplicationRules.swift" \
  "$ROOT_DIR/Scrub99/Sources/Scanner/ScanModels.swift" \
  "$ROOT_DIR/Scrub99/Sources/Scanner/BoundedScanner.swift" \
  "$ROOT_DIR/Scrub99/Sources/Cleanup/SafetyPolicy.swift" \
  "$ROOT_DIR/Scrub99/Sources/Cleanup/CleanupModels.swift" \
  "$ROOT_DIR/Scrub99/Sources/Cleanup/SafeCleanupEngine.swift" \
  "$ROOT_DIR/Scrub99/Sources/UI/ResultsSorting.swift" \
  "$ROOT_DIR/Scrub99Tests/SafetyTests.swift" \
  -o "$BUILD_DIR/Scrub99SafetyTests"

"$BUILD_DIR/Scrub99SafetyTests"
