#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="${1:-$ROOT_DIR/dist}"
if [[ -d "${XCODE_APP:-/Applications/Xcode.app}" ]]; then
  XCODE_APP="${XCODE_APP:-/Applications/Xcode.app}"
elif [[ -d "/Applications/Xcode-beta.app" ]]; then
  XCODE_APP="/Applications/Xcode-beta.app"
else
  echo "Scrub99 packaging requires Xcode.app or Xcode-beta.app in /Applications." >&2
  exit 1
fi
SWIFTC="$XCODE_APP/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc"
SDK="$XCODE_APP/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"
APP_NAME="Scrub99"
MIN_MACOS="13.0"

if [[ ! -x "$SWIFTC" || ! -d "$SDK" ]]; then
  echo "Scrub99 packaging could not find a usable macOS SDK and Swift compiler in $XCODE_APP." >&2
  exit 1
fi

# Every Swift file the app is made of, listed once. swiftc takes no project file
# here, so a source added to the Xcode project and forgotten in this list is a
# build failure at packaging time rather than at commit time — which is exactly
# how ProtectionList.swift went missing from this script.
SOURCES=(
  "$ROOT_DIR/Scrub99/Sources/AppDelegate.swift"
  "$ROOT_DIR/Scrub99/Sources/AppState.swift"
  "$ROOT_DIR/Scrub99/Sources/Scrub99App.swift"
  "$ROOT_DIR"/Scrub99/Sources/Core/*.swift
  "$ROOT_DIR/Scrub99/Sources/Scanner/ScanModels.swift"
  "$ROOT_DIR/Scrub99/Sources/Scanner/BoundedScanner.swift"
  "$ROOT_DIR"/Scrub99/Sources/Classifier/*.swift
  "$ROOT_DIR/Scrub99/Sources/Cleanup/CleanupModels.swift"
  "$ROOT_DIR/Scrub99/Sources/Cleanup/SafetyPolicy.swift"
  "$ROOT_DIR/Scrub99/Sources/Cleanup/ProtectionList.swift"
  "$ROOT_DIR/Scrub99/Sources/Cleanup/SafeCleanupEngine.swift"
  "$ROOT_DIR"/Scrub99/Sources/UI/*.swift
)

WORK_ROOT="$(mktemp -d /private/tmp/scrub99-package.XXXXXX)"
cleanup() {
  rm -rf "$WORK_ROOT"
}
trap cleanup EXIT

UNIVERSAL_APP="$OUTPUT_DIR/$APP_NAME.app"
UNIVERSAL_ZIP="$OUTPUT_DIR/$APP_NAME-macOS-universal.zip"
ARM_ZIP="$OUTPUT_DIR/$APP_NAME-macOS-arm64.zip"
X86_ZIP="$OUTPUT_DIR/$APP_NAME-macOS-x86_64.zip"

for existing in "$UNIVERSAL_APP" "$UNIVERSAL_ZIP" "$ARM_ZIP" "$X86_ZIP"; do
  if [[ -e "$existing" ]]; then
    echo "Safety stop: $existing already exists." >&2
    exit 1
  fi
done

compile() {
  local arch="$1"
  local output="$2"
  "$SWIFTC" \
    -O \
    -whole-module-optimization \
    -sdk "$SDK" \
    -target "$arch-apple-macosx$MIN_MACOS" \
    -module-cache-path "$ROOT_DIR/.build/package/ModuleCache" \
    -o "$output" \
    "${SOURCES[@]}"
}

stage() {
  local binary="$1"
  local app="$2"
  rm -rf "$app"
  mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources/Rules"
  cp "$binary" "$app/Contents/MacOS/$APP_NAME"
  cp "$ROOT_DIR/Scrub99/Info.plist" "$app/Contents/Info.plist"
  cp "$ROOT_DIR/Scrub99/Resources/AppIcon.icns" "$app/Contents/Resources/AppIcon.icns"
  ditto "$ROOT_DIR/Scrub99/Resources/Rules" "$app/Contents/Resources/Rules"
  codesign --force --deep --sign - "$app"
  codesign --verify --deep --strict "$app"
}

echo "Compiling for Apple silicon (arm64)..."
compile arm64 "$WORK_ROOT/$APP_NAME-arm64"
echo "Compiling for Intel (x86_64)..."
compile x86_64 "$WORK_ROOT/$APP_NAME-x86_64"

lipo -create \
  "$WORK_ROOT/$APP_NAME-arm64" \
  "$WORK_ROOT/$APP_NAME-x86_64" \
  -output "$WORK_ROOT/$APP_NAME-universal"

mkdir -p "$OUTPUT_DIR" "$WORK_ROOT/stage-universal" "$WORK_ROOT/stage-arm64" "$WORK_ROOT/stage-x86_64"

echo "Staging and signing..."
stage "$WORK_ROOT/$APP_NAME-universal" "$WORK_ROOT/stage-universal/$APP_NAME.app"
stage "$WORK_ROOT/$APP_NAME-arm64" "$WORK_ROOT/stage-arm64/$APP_NAME.app"
stage "$WORK_ROOT/$APP_NAME-x86_64" "$WORK_ROOT/stage-x86_64/$APP_NAME.app"

# The universal app is the primary artefact and is copied out as a real .app as
# well as a zip, so a local reader can run it without unpacking anything. The
# two thin builds exist because an Intel reader downloading a universal bundle
# pays for a slice they will never execute.
ditto "$WORK_ROOT/stage-universal/$APP_NAME.app" "$UNIVERSAL_APP"
ditto -c -k --sequesterRsrc --keepParent "$WORK_ROOT/stage-universal/$APP_NAME.app" "$UNIVERSAL_ZIP"
ditto -c -k --sequesterRsrc --keepParent "$WORK_ROOT/stage-arm64/$APP_NAME.app" "$ARM_ZIP"
ditto -c -k --sequesterRsrc --keepParent "$WORK_ROOT/stage-x86_64/$APP_NAME.app" "$X86_ZIP"

echo
lipo -info "$UNIVERSAL_APP/Contents/MacOS/$APP_NAME"
echo
shasum -a 256 "$UNIVERSAL_ZIP" "$ARM_ZIP" "$X86_ZIP"
