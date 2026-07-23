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

if [[ ${SOURCELEAF_SKIP_MANAGED_ENGINE:-0} != 1 ]]; then
  ENGINE_ROOT=$("$SCRIPT_DIR/fetch-managed-engine.sh")
  mkdir -p "$STAGING_PATH/Contents/Resources/Engines"
  ditto "$ENGINE_ROOT/arm64" "$STAGING_PATH/Contents/Resources/Engines/arm64"
  ditto "$ENGINE_ROOT/x86_64" "$STAGING_PATH/Contents/Resources/Engines/x86_64"
fi

for resource_bundle in "$BIN_PATH"/*.bundle(N); do
  ditto "$resource_bundle" "$STAGING_PATH/Contents/Resources/${resource_bundle:t}"
done

ditto "$PROJECT_ROOT/Sources/SourceLeafApp/Resources/en.lproj" "$STAGING_PATH/Contents/Resources/en.lproj"
ditto "$PROJECT_ROOT/Sources/SourceLeafApp/Resources/zh-Hans.lproj" "$STAGING_PATH/Contents/Resources/zh-Hans.lproj"

cp "$PROJECT_ROOT/LICENSE" "$STAGING_PATH/Contents/Resources/LICENSE"
cp "$PROJECT_ROOT/NOTICE" "$STAGING_PATH/Contents/Resources/NOTICE"
cp "$PROJECT_ROOT/THIRD_PARTY_LICENSES.md" "$STAGING_PATH/Contents/Resources/THIRD_PARTY_LICENSES.md"
cp "$PROJECT_ROOT/ThirdParty/Tectonic-LICENSE.txt" "$STAGING_PATH/Contents/Resources/Tectonic-LICENSE.txt"
ICON_PATH=$("$SCRIPT_DIR/generate-app-icon.sh")
cp "$ICON_PATH" "$STAGING_PATH/Contents/Resources/SourceLeaf.icns"

sed \
  -e "s/__VERSION__/${SOURCELEAF_VERSION:-0.3.10}/g" \
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
