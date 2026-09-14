#!/bin/zsh
# Generates Resources/AppIcon.icns from a source PNG.
#
# Usage:
#   ./make-icon.sh [path/to/icon.png]
# Defaults to ./icon.png. The source should be a square image, ideally 1024x1024.
set -e

SCRIPT_DIR=${0:A:h}
cd "$SCRIPT_DIR"

SRC=${1:-icon.png}
if [[ ! -f "$SRC" ]]; then
    echo "Source image not found: $SRC"
    echo "Save the icon as ./icon.png (1024x1024 PNG) or pass a path."
    exit 1
fi

ICONSET="build/AppIcon.iconset"
OUT="Resources/AppIcon.icns"

rm -rf "$ICONSET"
mkdir -p "$ICONSET"
mkdir -p "Resources"

# Standard macOS icon sizes (@1x and @2x).
sips -z 16 16     "$SRC" --out "$ICONSET/icon_16x16.png"      >/dev/null
sips -z 32 32     "$SRC" --out "$ICONSET/icon_16x16@2x.png"   >/dev/null
sips -z 32 32     "$SRC" --out "$ICONSET/icon_32x32.png"      >/dev/null
sips -z 64 64     "$SRC" --out "$ICONSET/icon_32x32@2x.png"   >/dev/null
sips -z 128 128   "$SRC" --out "$ICONSET/icon_128x128.png"    >/dev/null
sips -z 256 256   "$SRC" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
sips -z 256 256   "$SRC" --out "$ICONSET/icon_256x256.png"    >/dev/null
sips -z 512 512   "$SRC" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
sips -z 512 512   "$SRC" --out "$ICONSET/icon_512x512.png"    >/dev/null
sips -z 1024 1024 "$SRC" --out "$ICONSET/icon_512x512@2x.png" >/dev/null

iconutil -c icns "$ICONSET" -o "$OUT"
rm -rf "$ICONSET"

echo "Created $OUT"
