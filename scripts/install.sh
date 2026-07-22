#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
PROJECT_ROOT=${SCRIPT_DIR:h}
INSTALL_ROOT=${SOURCELEAF_INSTALL_ROOT:-"$HOME/Applications"}
BUILD_OUTPUT=${SOURCELEAF_APP_OUTPUT:-"$PROJECT_ROOT/临时文件/构建/产物/SourceLeaf.app"}
TARGET_PATH="$INSTALL_ROOT/SourceLeaf.app"
INCOMING_PATH="$INSTALL_ROOT/.SourceLeaf.app.incoming.$$"

stop_installed_app() {
  [[ -d "$TARGET_PATH" ]] || return 0
  local executable="$TARGET_PATH/Contents/MacOS/SourceLeaf"
  local pids
  pids=$(pgrep -f "^${executable}$" || true)
  [[ -n "$pids" ]] || return 0

  osascript -e 'tell application id "dev.sourceleaf.app" to quit' >/dev/null 2>&1 || true
  for _ in {1..25}; do
    pids=$(pgrep -f "^${executable}$" || true)
    [[ -z "$pids" ]] && return 0
    sleep 0.2
  done
  print -r -- "$pids" | xargs kill -TERM
  for _ in {1..25}; do
    pids=$(pgrep -f "^${executable}$" || true)
    [[ -z "$pids" ]] && return 0
    sleep 0.2
  done
  print -u2 -r -- "Could not stop the installed SourceLeaf process safely."
  return 1
}

SOURCELEAF_APP_OUTPUT="$BUILD_OUTPUT" "$SCRIPT_DIR/build-app-bundle.sh"
mkdir -p "$INSTALL_ROOT"
ditto "$BUILD_OUTPUT" "$INCOMING_PATH"
codesign --verify --deep --strict "$INCOMING_PATH"

stop_installed_app

if [[ -e "$TARGET_PATH" ]]; then
  BACKUP_ROOT="$PROJECT_ROOT/临时文件/安装备份"
  mkdir -p "$BACKUP_ROOT"
  mv "$TARGET_PATH" "$BACKUP_ROOT/SourceLeaf-$(date +%Y%m%d-%H%M%S).app"
fi
mv "$INCOMING_PATH" "$TARGET_PATH"

codesign --verify --deep --strict "$TARGET_PATH"
spctl --assess --type execute "$TARGET_PATH" 2>/dev/null || true
print -r -- "Installed SourceLeaf at $TARGET_PATH"
if [[ "${SOURCELEAF_SKIP_LAUNCH:-0}" != "1" ]]; then
  open "$TARGET_PATH"
fi
