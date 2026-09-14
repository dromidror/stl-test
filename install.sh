#!/bin/zsh
# Builds a permanent, self-contained STL Viewer.app and installs it.
#
# By default it installs to ~/Applications (no admin rights needed).
# Pass a destination directory to override, e.g.:
#   ./install.sh /Applications
set -e

APP_NAME="STL Viewer"
DEST_DIR=${1:-"$HOME/Applications"}
STAGING="build/${APP_NAME}.app"
TARGET="${DEST_DIR}/${APP_NAME}.app"

SCRIPT_DIR=${0:A:h}
cd "$SCRIPT_DIR"

echo "Building release + bundle…"
./bundle.sh release

echo "Installing to: $TARGET"
mkdir -p "$DEST_DIR"

# Remove any previous install, then copy the freshly built bundle.
rm -rf "$TARGET"
cp -R "$STAGING" "$TARGET"

# Re-sign in place (ad-hoc) so Gatekeeper is happy at the final location.
codesign --force --deep --sign - "$TARGET" 2>/dev/null || true

# Clear the quarantine flag so it opens without the "unidentified developer"
# prompt on this machine.
xattr -dr com.apple.quarantine "$TARGET" 2>/dev/null || true

echo ""
echo "Installed \"$APP_NAME\" to $DEST_DIR"
echo "Launch it from Finder, Spotlight, or with:"
echo "  open \"$TARGET\""
