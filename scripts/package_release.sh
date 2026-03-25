#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="MacKeyMap"
APP_DIR="$ROOT_DIR/dist/$APP_NAME.app"
APP_VERSION="${MACKEYMAP_VERSION:-$(tr -d '[:space:]' < "$ROOT_DIR/VERSION")}"
ZIP_PATH="$ROOT_DIR/dist/$APP_NAME-$APP_VERSION-macos.zip"

"$ROOT_DIR/scripts/build_app.sh" release
rm -f "$ZIP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$ZIP_PATH"
echo "Packaged $ZIP_PATH"
