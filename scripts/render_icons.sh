#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ASSETS_DIR="$ROOT_DIR/Assets"
WORK_DIR="$ROOT_DIR/.build/icon-work"
WORK_DIR="$ROOT_DIR/.tmp-icons/icon-work"
MENU_SOURCE="$ASSETS_DIR/MenuBarTemplate.svg"
APP_SOURCE="$ASSETS_DIR/AppIconSource.svg"
MENU_OUTPUT="$ASSETS_DIR/MenuBarTemplate.png"
APP_ICON_OUTPUT="$ASSETS_DIR/AppIcon.icns"
ICONSET_DIR="$WORK_DIR/AppIcon.iconset"

render_svg_png() {
  local source_file="$1"
  local output_file="$2"
  qlmanage -t -s 1024 -o "$WORK_DIR" "$source_file" >/dev/null 2>&1
  local rendered_file
  rendered_file="$WORK_DIR/$(basename "$source_file").png"
  mv "$rendered_file" "$output_file"
}

mkdir -p "$WORK_DIR"

if [[ ! -f "$MENU_SOURCE" || ! -f "$APP_SOURCE" ]]; then
  echo "Icon source SVGs are missing from $ASSETS_DIR" >&2
  exit 1
fi

render_svg_png "$MENU_SOURCE" "$MENU_OUTPUT"
render_svg_png "$APP_SOURCE" "$WORK_DIR/AppIconSource.png"

rm -rf "$ICONSET_DIR"
mkdir -p "$ICONSET_DIR"

for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$WORK_DIR/AppIconSource.png" --out "$ICONSET_DIR/icon_${size}x${size}.png" >/dev/null
  double_size=$((size * 2))
  sips -z "$double_size" "$double_size" "$WORK_DIR/AppIconSource.png" --out "$ICONSET_DIR/icon_${size}x${size}@2x.png" >/dev/null
done

iconutil -c icns "$ICONSET_DIR" -o "$APP_ICON_OUTPUT"
echo "Rendered icon assets into $ASSETS_DIR"
