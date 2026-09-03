#!/bin/zsh
# Builds STLViewer and packages it into a launchable macOS .app bundle.
set -e

CONFIG=${1:-release}
APP_NAME="STL Viewer"
BUNDLE="build/${APP_NAME}.app"

echo "Building ($CONFIG)…"
swift build -c "$CONFIG"

BIN_PATH=$(swift build -c "$CONFIG" --show-bin-path)

echo "Assembling bundle at $BUNDLE"
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS"
mkdir -p "$BUNDLE/Contents/Resources"

cp "$BIN_PATH/STLViewer" "$BUNDLE/Contents/MacOS/STLViewer"

cp Info.plist "$BUNDLE/Contents/Info.plist"

# Ad-hoc code signature so macOS will launch it locally.
codesign --force --deep --sign - "$BUNDLE" 2>/dev/null || true

echo "Done: $BUNDLE"
echo "Launch with: open \"$BUNDLE\""
