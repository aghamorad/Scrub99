#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build/safety-tests"
if [[ -d "${XCODE_APP:-/Applications/Xcode.app}" ]]; then
  XCODE_APP="${XCODE_APP:-/Applications/Xcode.app}"
elif [[ -d "/Applications/Xcode-beta.app" ]]; then
  XCODE_APP="/Applications/Xcode-beta.app"
else
  echo "Scrub99 safety tests require Xcode.app or Xcode-beta.app in /Applications." >&2
  exit 1
fi
SWIFTC="$XCODE_APP/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc"
SDK="$XCODE_APP/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"

if [[ ! -x "$SWIFTC" || ! -d "$SDK" ]]; then
  echo "Scrub99 safety tests could not find a usable macOS SDK and Swift compiler in $XCODE_APP." >&2
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
  "$ROOT_DIR/Scrub99/Sources/Core/RuleEngine.swift" \
  "$ROOT_DIR/Scrub99/Sources/Scanner/ScanModels.swift" \
  "$ROOT_DIR/Scrub99/Sources/Scanner/BoundedScanner.swift" \
  "$ROOT_DIR/Scrub99/Sources/Classifier/Classifier.swift" \
  "$ROOT_DIR/Scrub99/Sources/Cleanup/SafetyPolicy.swift" \
  "$ROOT_DIR/Scrub99/Sources/Cleanup/ProtectionList.swift" \
  "$ROOT_DIR/Scrub99/Sources/Cleanup/CleanupModels.swift" \
  "$ROOT_DIR/Scrub99/Sources/Cleanup/SafeCleanupEngine.swift" \
  "$ROOT_DIR/Scrub99Tests/SafetyTests.swift" \
  -o "$BUILD_DIR/Scrub99SafetyTests"

"$BUILD_DIR/Scrub99SafetyTests"
