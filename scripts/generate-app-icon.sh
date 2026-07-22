#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
PROJECT_ROOT=${SCRIPT_DIR:h}
TEMP_ROOT=${SOURCELEAF_TEMP_ROOT:-"$PROJECT_ROOT/临时文件/构建"}
ICON_ROOT="$TEMP_ROOT/图标"
ICONSET="$ICON_ROOT/SourceLeaf.iconset"
OUTPUT="$ICON_ROOT/SourceLeaf.icns"

mkdir -p "$ICON_ROOT"
if [[ -d "$ICONSET" ]]; then
  mv "$ICONSET" "$ICON_ROOT/旧图标集.$$.iconset"
fi
xcrun swift "$SCRIPT_DIR/generate-app-icon.swift" "$ICONSET"
iconutil -c icns "$ICONSET" -o "$OUTPUT"
print -r -- "$OUTPUT"
