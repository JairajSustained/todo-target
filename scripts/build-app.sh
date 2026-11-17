#!/bin/sh
# Builds build/TodoTarget.app and build/TodoTarget.zip.
# Needs only the Swift command line tools (no Xcode IDE).
# The app is ad-hoc signed, not notarized (see the README for the Gatekeeper steps).
set -eu

cd "$(dirname "$0")/.."
ROOT=$(pwd)
BUILD="$ROOT/build"
APP="$BUILD/TodoTarget.app"

# Try a universal build (Apple silicon + Intel). Fall back to Apple silicon only.
ARCH_FLAGS="--arch arm64 --arch x86_64"
if ! swift build -c release $ARCH_FLAGS; then
  echo "NOTE: the universal build (arm64 + x86_64) failed. Building for Apple silicon (arm64) only." >&2
  echo "NOTE: the resulting app will not run on Intel Macs." >&2
  ARCH_FLAGS="--arch arm64"
  swift build -c release $ARCH_FLAGS
fi

BIN_DIR=$(swift build -c release $ARCH_FLAGS --show-bin-path)

rm -rf "$APP" "$BUILD/TodoTarget.zip"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/TodoTarget" "$APP/Contents/MacOS/TodoTarget"
cp "$ROOT/resources/Info.plist" "$APP/Contents/Info.plist"

codesign --force --deep -s - "$APP"
ditto -c -k --keepParent "$APP" "$BUILD/TodoTarget.zip"

echo "Built $APP"
echo "Built $BUILD/TodoTarget.zip"
echo "Architectures: $(lipo -archs "$APP/Contents/MacOS/TodoTarget")"
