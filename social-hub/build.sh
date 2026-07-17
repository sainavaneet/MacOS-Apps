#!/bin/bash
set -euo pipefail

# ── Config ──────────────────────────────────────────────
APP_NAME="SocialHub"
DISPLAY_NAME="Social Hub"
BUNDLE_ID="com.sainavaneet.SocialHub"
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_BUNDLE="/tmp/$APP_NAME-build/$DISPLAY_NAME.app"
INSTALL_DIR="/Applications"
INSTALL_PATH="$INSTALL_DIR/$DISPLAY_NAME.app"

# ── Step 1: Build release ──────────────────────────────
echo "▸ Building $APP_NAME (release)..."
cd "$PROJECT_DIR"
swift build -c release 2>&1 | tail -10

BINARY="$PROJECT_DIR/.build/release/$APP_NAME"
if [ ! -f "$BINARY" ]; then
    echo "✗ Build failed — binary not found"
    exit 1
fi
echo "✓ Build succeeded"

# ── Step 2: Assemble app bundle ────────────────────────
echo "▸ Assembling app bundle..."
rm -rf "/tmp/$APP_NAME-build"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BINARY" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp "$PROJECT_DIR/Sources/App/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
echo -n "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

# Icon (optional)
APPICONSET="$PROJECT_DIR/Sources/App/Assets.xcassets/AppIcon.appiconset"
ICNS="$APP_BUNDLE/Contents/Resources/AppIcon.icns"
if [ -d "$APPICONSET" ] && command -v iconutil &>/dev/null; then
    ICONSET="/tmp/$APP_NAME.iconset"
    rm -rf "$ICONSET"
    mkdir -p "$ICONSET"
    for f in "$APPICONSET"/*.png; do
        [ -f "$f" ] || continue
        size=$(sips -g pixelWidth "$f" 2>/dev/null | awk '/pixelWidth/{print $2}')
        case "$size" in
            16)   cp "$f" "$ICONSET/icon_16x16.png" ;;
            32)   cp "$f" "$ICONSET/icon_16x16@2x.png"; cp "$f" "$ICONSET/icon_32x32.png" ;;
            64)   cp "$f" "$ICONSET/icon_32x32@2x.png" ;;
            128)  cp "$f" "$ICONSET/icon_128x128.png" ;;
            256)  cp "$f" "$ICONSET/icon_128x128@2x.png"; cp "$f" "$ICONSET/icon_256x256.png" ;;
            512)  cp "$f" "$ICONSET/icon_256x256@2x.png"; cp "$f" "$ICONSET/icon_512x512.png" ;;
            1024) cp "$f" "$ICONSET/icon_512x512@2x.png" ;;
        esac
    done
    if [ "$(ls -A "$ICONSET" 2>/dev/null)" ]; then
        iconutil -c icns "$ICONSET" -o "$ICNS" 2>/dev/null || echo "⚠ iconutil failed"
    fi
    rm -rf "$ICONSET"
fi

echo "✓ App bundle ready"

# ── Step 3: Sign (ad-hoc) ──────────────────────────────
codesign --force --deep --sign - "$APP_BUNDLE" 2>/dev/null || true

# ── Step 4: Remove old copies ──────────────────────────
echo "▸ Removing old copies..."
pkill -x "$APP_NAME" 2>/dev/null && sleep 1 || true
for loc in "/Applications/$DISPLAY_NAME.app" "$HOME/Applications/$DISPLAY_NAME.app" "$HOME/Desktop/$DISPLAY_NAME.app"; do
    [ -d "$loc" ] && rm -rf "$loc" && echo "  Removed $loc"
done

# ── Step 5: Install ───────────────────────────────────
echo "▸ Installing to $INSTALL_PATH..."
cp -R "$APP_BUNDLE" "$INSTALL_PATH"
touch "$INSTALL_PATH"
rm -rf "/tmp/$APP_NAME-build"

echo "✓ $DISPLAY_NAME installed to $INSTALL_PATH"
echo ""
echo "  Launch: open \"$INSTALL_PATH\""
