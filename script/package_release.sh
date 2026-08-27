#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="${1:-$ROOT_DIR/dist}"
SWIFTC="/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc"
SDK="/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"
APP_NAME="Scrub99"
APP_BUNDLE="$OUTPUT_DIR/$APP_NAME.app"
ZIP_PATH="$OUTPUT_DIR/$APP_NAME-macOS-arm64.zip"
PACKAGE_ROOT="$(mktemp -d /private/tmp/scrub99-package.XXXXXX)"
STAGED_APP="$PACKAGE_ROOT/$APP_NAME.app"

cleanup() {
  rm -rf "$PACKAGE_ROOT"
}
trap cleanup EXIT

if [[ ! -x "$SWIFTC" || ! -d "$SDK" ]]; then
  echo "Scrub99 packaging requires Xcode at /Applications/Xcode.app." >&2
  exit 1
fi

mkdir -p "$STAGED_APP/Contents/MacOS" "$STAGED_APP/Contents/Resources/Rules" "$OUTPUT_DIR"

"$SWIFTC" \
  -O \
  -whole-module-optimization \
  -sdk "$SDK" \
  -target arm64-apple-macosx13.0 \
  -module-cache-path "$ROOT_DIR/.build/package/ModuleCache" \
  -o "$STAGED_APP/Contents/MacOS/$APP_NAME" \
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

cp "$ROOT_DIR/Scrub99/Info.plist" "$STAGED_APP/Contents/Info.plist"
cp "$ROOT_DIR/Scrub99/Resources/AppIcon.icns" "$STAGED_APP/Contents/Resources/AppIcon.icns"
ditto "$ROOT_DIR/Scrub99/Resources/Rules" "$STAGED_APP/Contents/Resources/Rules"

codesign --force --deep --sign - "$STAGED_APP"
codesign --verify --deep --strict "$STAGED_APP"

if [[ -e "$APP_BUNDLE" || -e "$ZIP_PATH" ]]; then
  echo "Safety stop: output already exists in $OUTPUT_DIR" >&2
  exit 1
fi

ditto "$STAGED_APP" "$APP_BUNDLE"
ditto -c -k --sequesterRsrc --keepParent "$STAGED_APP" "$ZIP_PATH"

shasum -a 256 "$ZIP_PATH"
