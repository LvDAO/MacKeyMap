#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURATION="${1:-debug}"
APP_NAME="MacKeyMap"
APP_EXECUTABLE="MacKeyMapApp"
APP_VERSION="${MACKEYMAP_VERSION:-$(tr -d '[:space:]' < "$ROOT_DIR/VERSION")}"
APP_BUILD_NUMBER="${MACKEYMAP_BUILD_NUMBER:-1}"
APP_DIR="$ROOT_DIR/dist/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
SIGN_IDENTITY="${MACKEYMAP_SIGN_IDENTITY:-}"
ICON_FILE="$ROOT_DIR/Assets/AppIcon.icns"
MENU_BAR_ICON_FILE="$ROOT_DIR/Assets/MenuBarTemplate.png"

mkdir -p "$ROOT_DIR/dist"
mkdir -p "$ROOT_DIR/target/debug" "$ROOT_DIR/target/release"

"$ROOT_DIR/scripts/render_icons.sh"

if [[ "$CONFIGURATION" == "release" ]]; then
  cargo build --manifest-path "$ROOT_DIR/rust-core/Cargo.toml" --release
  swift package clean
  swift build -c release
  SWIFT_BIN_DIR="$ROOT_DIR/.build/release"
else
  cargo build --manifest-path "$ROOT_DIR/rust-core/Cargo.toml"
  swift package clean
  swift build
  SWIFT_BIN_DIR="$ROOT_DIR/.build/debug"
fi

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

cp "$SWIFT_BIN_DIR/$APP_EXECUTABLE" "$MACOS_DIR/$APP_NAME"

if [[ -f "$ICON_FILE" ]]; then
  cp "$ICON_FILE" "$RESOURCES_DIR/AppIcon.icns"
fi

if [[ -f "$MENU_BAR_ICON_FILE" ]]; then
  cp "$MENU_BAR_ICON_FILE" "$RESOURCES_DIR/MenuBarTemplate.png"
fi

cat >"$CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>MacKeyMap</string>
  <key>CFBundleIdentifier</key>
  <string>com.lyuwt.MacKeyMap</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>MacKeyMap</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>${APP_VERSION}</string>
  <key>CFBundleVersion</key>
  <string>${APP_BUILD_NUMBER}</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSInputMonitoringUsageDescription</key>
  <string>MacKeyMap needs keyboard monitoring access to remap a Windows keyboard to macOS behavior.</string>
</dict>
</plist>
PLIST

chmod +x "$MACOS_DIR/$APP_NAME"

if [[ -z "$SIGN_IDENTITY" ]]; then
  SIGN_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | sed -n 's/.* "\(Apple Development:.*\)"/\1/p' | head -n 1)"
fi

if [[ -n "$SIGN_IDENTITY" ]]; then
  echo "Signing with $SIGN_IDENTITY"
  codesign --force --deep --timestamp=none --sign "$SIGN_IDENTITY" "$APP_DIR"
else
  echo "Signing with ad hoc identity"
  codesign --force --deep --timestamp=none --sign - "$APP_DIR"
fi

echo "Built $APP_DIR"
