#!/bin/zsh
# Builds, packages, and launches the STL Viewer app.
#
# Usage:
#   ./run.sh            # release build (default)
#   ./run.sh debug      # debug build
set -e

CONFIG=${1:-release}
APP_NAME="STL Viewer"
BUNDLE="build/${APP_NAME}.app"

SCRIPT_DIR=${0:A:h}
cd "$SCRIPT_DIR"

# Quit any running instance so the new build launches cleanly.
pkill -f "${BUNDLE}/Contents/MacOS/STLViewer" 2>/dev/null || true

# Build and assemble the .app bundle.
./bundle.sh "$CONFIG"

echo "Launching $APP_NAME…"
open "$BUNDLE"
