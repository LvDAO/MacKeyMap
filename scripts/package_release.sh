#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="MacKeyMap"
APP_DIR="$ROOT_DIR/dist/$APP_NAME.app"
ZIP_PATH="$ROOT_DIR/dist/$APP_NAME-macos.zip"

"$ROOT_DIR/scripts/build_app.sh" release
rm -f "$ZIP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$ZIP_PATH"
echo "Packaged $ZIP_PATH"
