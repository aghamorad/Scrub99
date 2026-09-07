#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build/typecheck"
if [[ -d "${XCODE_APP:-/Applications/Xcode.app}" ]]; then
  XCODE_APP="${XCODE_APP:-/Applications/Xcode.app}"
elif [[ -d "/Applications/Xcode-beta.app" ]]; then
  XCODE_APP="/Applications/Xcode-beta.app"
else
  echo "Scrub99 type-checking requires Xcode.app or Xcode-beta.app in /Applications." >&2
  exit 1
fi
SWIFTC="$XCODE_APP/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc"
SDK="$XCODE_APP/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"

if [[ ! -x "$SWIFTC" || ! -d "$SDK" ]]; then
  echo "Scrub99 type-checking could not find a usable macOS SDK and Swift compiler in $XCODE_APP." >&2
  exit 1
fi

mkdir -p "$BUILD_DIR/ModuleCache"

"$SWIFTC" \
  -typecheck \
  -warnings-as-errors \
  -sdk "$SDK" \
  -target arm64-apple-macosx13.0 \
  -module-cache-path "$BUILD_DIR/ModuleCache" \
  "$ROOT_DIR/Scrub99/Sources/AppDelegate.swift" \
  "$ROOT_DIR/Scrub99/Sources/AppState.swift" \
  "$ROOT_DIR/Scrub99/Sources/Scrub99App.swift" \
  "$ROOT_DIR"/Scrub99/Sources/Core/*.swift \
  "$ROOT_DIR/Scrub99/Sources/Scanner/ScanModels.swift" \
  "$ROOT_DIR/Scrub99/Sources/Scanner/BoundedScanner.swift" \
  "$ROOT_DIR"/Scrub99/Sources/Classifier/*.swift \
  "$ROOT_DIR/Scrub99/Sources/Cleanup/CleanupModels.swift" \
  "$ROOT_DIR/Scrub99/Sources/Cleanup/SafetyPolicy.swift" \
  "$ROOT_DIR/Scrub99/Sources/Cleanup/SafeCleanupEngine.swift" \
  "$ROOT_DIR"/Scrub99/Sources/UI/*.swift

echo "Scrub99 GUI source type-check passed with warnings treated as errors"
