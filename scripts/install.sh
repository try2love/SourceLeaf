#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
PROJECT_ROOT=${SCRIPT_DIR:h}
INSTALL_ROOT=${SOURCELEAF_INSTALL_ROOT:-"$HOME/Applications"}
BUILD_OUTPUT=${SOURCELEAF_APP_OUTPUT:-"$PROJECT_ROOT/临时文件/构建/产物/SourceLeaf.app"}
TARGET_PATH="$INSTALL_ROOT/SourceLeaf.app"
INCOMING_PATH="$INSTALL_ROOT/.SourceLeaf.app.incoming.$$"

SOURCELEAF_APP_OUTPUT="$BUILD_OUTPUT" "$SCRIPT_DIR/build-app-bundle.sh"
mkdir -p "$INSTALL_ROOT"
ditto "$BUILD_OUTPUT" "$INCOMING_PATH"
codesign --verify --deep --strict "$INCOMING_PATH"

if [[ -e "$TARGET_PATH" ]]; then
  BACKUP_ROOT="$PROJECT_ROOT/临时文件/安装备份"
  mkdir -p "$BACKUP_ROOT"
  mv "$TARGET_PATH" "$BACKUP_ROOT/SourceLeaf-$(date +%Y%m%d-%H%M%S).app"
fi
mv "$INCOMING_PATH" "$TARGET_PATH"

codesign --verify --deep --strict "$TARGET_PATH"
spctl --assess --type execute "$TARGET_PATH" 2>/dev/null || true
print -r -- "Installed SourceLeaf at $TARGET_PATH"
