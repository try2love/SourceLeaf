#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
PROJECT_ROOT=${SCRIPT_DIR:h}
CONFIGURATION=${SOURCELEAF_CONFIGURATION:-release}
TEMP_ROOT=${SOURCELEAF_TEMP_ROOT:-"$PROJECT_ROOT/临时文件/构建"}
SCRATCH_PATH="$TEMP_ROOT/SwiftPM"
OUTPUT_PATH=${SOURCELEAF_APP_OUTPUT:-"$TEMP_ROOT/产物/SourceLeaf.app"}
BUILD_ARCHS=${SOURCELEAF_ARCHS:-"arm64 x86_64"}

mkdir -p "$TEMP_ROOT" "${OUTPUT_PATH:h}"

ARCH_ARGS=()
for architecture in ${(z)BUILD_ARCHS}; do
  ARCH_ARGS+=(--arch "$architecture")
done

swift build \
  --configuration "$CONFIGURATION" \
  --scratch-path "$SCRATCH_PATH" \
  "${ARCH_ARGS[@]}"

BIN_PATH=$(swift build \
  --configuration "$CONFIGURATION" \
  --scratch-path "$SCRATCH_PATH" \
  "${ARCH_ARGS[@]}" \
  --show-bin-path)

STAGING_PATH="$TEMP_ROOT/组装/SourceLeaf.app.$$.staging"
mkdir -p "$STAGING_PATH/Contents/MacOS" "$STAGING_PATH/Contents/Resources"
cp "$BIN_PATH/SourceLeaf" "$STAGING_PATH/Contents/MacOS/SourceLeaf"

for resource_bundle in "$BIN_PATH"/*.bundle(N); do
  ditto "$resource_bundle" "$STAGING_PATH/Contents/Resources/${resource_bundle:t}"
done

cp "$PROJECT_ROOT/LICENSE" "$STAGING_PATH/Contents/Resources/LICENSE"
cp "$PROJECT_ROOT/NOTICE" "$STAGING_PATH/Contents/Resources/NOTICE"

sed \
  -e "s/__VERSION__/${SOURCELEAF_VERSION:-0.1.0}/g" \
  "$PROJECT_ROOT/scripts/Info.plist.in" > "$STAGING_PATH/Contents/Info.plist"

codesign --force --deep --sign - "$STAGING_PATH"
codesign --verify --deep --strict "$STAGING_PATH"

if [[ -e "$OUTPUT_PATH" ]]; then
  BACKUP_PATH="$TEMP_ROOT/备份/SourceLeaf-$(date +%Y%m%d-%H%M%S).app"
  mkdir -p "${BACKUP_PATH:h}"
  mv "$OUTPUT_PATH" "$BACKUP_PATH"
fi
mv "$STAGING_PATH" "$OUTPUT_PATH"

print -r -- "$OUTPUT_PATH"
