#!/bin/bash
set -euo pipefail

# ── Config ──────────────────────────────────────────────
APP_NAME="Assistant"
BUNDLE_ID="com.sainavaneet.Assistant"
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_BUNDLE="/tmp/$APP_NAME-build/$APP_NAME.app"
INSTALL_DIR="/Applications"
INSTALL_PATH="$INSTALL_DIR/$APP_NAME.app"

# ── Step 1: Build release ──────────────────────────────
echo "▸ Building $APP_NAME (release)..."
cd "$PROJECT_DIR"
swift build -c release 2>&1 | tail -5

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

# Copy binary
cp "$BINARY" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# Copy Info.plist from source
cp "$PROJECT_DIR/Sources/App/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

# PkgInfo
echo -n "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

# Icon — generate .icns from appiconset if iconutil is available, else use existing
APPICONSET="$PROJECT_DIR/Sources/App/Assets.xcassets/AppIcon.appiconset"
ICNS="$APP_BUNDLE/Contents/Resources/AppIcon.icns"

if [ -d "$APPICONSET" ] && command -v iconutil &>/dev/null; then
    # Build iconset from pngs
    ICONSET="/tmp/$APP_NAME.iconset"
    rm -rf "$ICONSET"
    mkdir -p "$ICONSET"

    # Map appiconset pngs to iconset names
    for f in "$APPICONSET"/*.png; do
        base=$(basename "$f")
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
        iconutil -c icns "$ICONSET" -o "$ICNS" 2>/dev/null && echo "✓ Icon generated from appiconset" || echo "⚠ iconutil failed, keeping existing icon"
    fi
    rm -rf "$ICONSET"
elif [ ! -f "$ICNS" ]; then
    echo "⚠ No icon found — app will use default icon"
fi

echo "✓ App bundle ready"

# ── Step 3: Remove all old copies ──────────────────────
echo "▸ Removing old copies of $APP_NAME..."

# Kill running instances
pkill -x "$APP_NAME" 2>/dev/null && echo "  Stopped running instance" && sleep 1 || true

# Search common locations
LOCATIONS=(
    "/Applications/$APP_NAME.app"
    "$HOME/Applications/$APP_NAME.app"
    "$HOME/Desktop/$APP_NAME.app"
    "$HOME/Downloads/$APP_NAME.app"
)

for loc in "${LOCATIONS[@]}"; do
    if [ -d "$loc" ]; then
        rm -rf "$loc"
        echo "  Removed $loc"
    fi
done

# Clean old Xcode DerivedData builds (MeetingAssistant, assistant, meeting-assistant)
DERIVED="$HOME/Library/Developer/Xcode/DerivedData"
if [ -d "$DERIVED" ]; then
    for d in "$DERIVED"/MeetingAssistant-* "$DERIVED"/assistant-* "$DERIVED"/meeting-assistant-*; do
        if [ -d "$d" ]; then
            rm -rf "$d"
            echo "  Removed DerivedData: $(basename "$d")"
        fi
    done
fi

# ── Step 4: Install ───────────────────────────────────
echo "▸ Installing to $INSTALL_PATH..."
cp -R "$APP_BUNDLE" "$INSTALL_PATH"
# Installed copy should NOT have the Spotlight blocker
rm -f "$INSTALL_PATH/.metadata_never_index"

# Reset icon cache so Finder picks up the new icon
touch "$INSTALL_PATH"

# Clean up temp build
rm -rf "/tmp/$APP_NAME-build"

# Remove stale project .app bundle if it exists (causes Spotlight duplicates)
if [ -d "$PROJECT_DIR/$APP_NAME.app" ]; then
    rm -rf "$PROJECT_DIR/$APP_NAME.app"
    echo "  Removed stale project bundle"
fi

echo "✓ $APP_NAME installed to $INSTALL_PATH"
echo ""
echo "  Launch: open $INSTALL_PATH"
