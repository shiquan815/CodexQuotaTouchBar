#!/bin/zsh
set -euo pipefail

APP_NAME="CodexQuotaTouchBar"
ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$ROOT_DIR/build"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
MACOS_DIR="$APP_DIR/Contents/MacOS"
RESOURCES_DIR="$APP_DIR/Contents/Resources"
MODULE_CACHE_DIR="$BUILD_DIR/module-cache"
ICONSET_DIR="$BUILD_DIR/AppIcon.iconset"
ICON_TOOL="$BUILD_DIR/make_icon"
SOURCE_ICON="$ROOT_DIR/Assets/codex.webp"
ICON_SOURCE_ARGS=()
if [[ -f "$SOURCE_ICON" ]]; then
  ICON_SOURCE_ARGS=("$SOURCE_ICON")
fi

rm -rf "$APP_DIR"
rm -rf "$ICONSET_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$MODULE_CACHE_DIR" "$ICONSET_DIR"

clang "$ROOT_DIR/Tools/make_icon.m" \
  -fobjc-arc \
  -framework Cocoa \
  -o "$ICON_TOOL"

"$ICON_TOOL" 16 "$ICONSET_DIR/icon_16x16.png" "${ICON_SOURCE_ARGS[@]}"
"$ICON_TOOL" 32 "$ICONSET_DIR/icon_32x32.png" "${ICON_SOURCE_ARGS[@]}"
"$ICON_TOOL" 64 "$ICONSET_DIR/icon_64x64.png" "${ICON_SOURCE_ARGS[@]}"
"$ICON_TOOL" 128 "$ICONSET_DIR/icon_128x128.png" "${ICON_SOURCE_ARGS[@]}"
"$ICON_TOOL" 256 "$ICONSET_DIR/icon_256x256.png" "${ICON_SOURCE_ARGS[@]}"
"$ICON_TOOL" 512 "$ICONSET_DIR/icon_512x512.png" "${ICON_SOURCE_ARGS[@]}"
"$ICON_TOOL" 1024 "$ICONSET_DIR/icon_1024x1024.png" "${ICON_SOURCE_ARGS[@]}"

node "$ROOT_DIR/Tools/make_icns.js" "$RESOURCES_DIR/AppIcon.icns" \
  icp4 "$ICONSET_DIR/icon_16x16.png" \
  icp5 "$ICONSET_DIR/icon_32x32.png" \
  icp6 "$ICONSET_DIR/icon_64x64.png" \
  ic07 "$ICONSET_DIR/icon_128x128.png" \
  ic08 "$ICONSET_DIR/icon_256x256.png" \
  ic09 "$ICONSET_DIR/icon_512x512.png" \
  ic10 "$ICONSET_DIR/icon_1024x1024.png"

clang "$ROOT_DIR/Sources/main.m" \
  -fobjc-arc \
  -framework Cocoa \
  -o "$MACOS_DIR/$APP_NAME"

cat > "$APP_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>CodexQuotaTouchBar</string>
  <key>CFBundleIdentifier</key>
  <string>local.codex.quota.touchbar</string>
  <key>CFBundleName</key>
  <string>Codex Quota Touch Bar</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleIconName</key>
  <string>AppIcon</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>2</string>
  <key>LSMinimumSystemVersion</key>
  <string>10.12</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

echo "$APP_DIR"
