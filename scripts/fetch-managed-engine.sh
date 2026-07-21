#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
PROJECT_ROOT=${SCRIPT_DIR:h}
VERSION=0.16.9
DOWNLOAD_ROOT=${SOURCELEAF_ENGINE_DOWNLOAD_ROOT:-"$PROJECT_ROOT/临时文件/引擎下载/Tectonic-$VERSION"}
OUTPUT_ROOT=${SOURCELEAF_ENGINE_OUTPUT_ROOT:-"$PROJECT_ROOT/临时文件/引擎组装/Tectonic-$VERSION"}

mkdir -p "$DOWNLOAD_ROOT" "$OUTPUT_ROOT"

fetch_architecture() {
  local source_arch=$1
  local bundle_arch=$2
  local expected_sha=$3
  local archive="tectonic-$VERSION-$source_arch-apple-darwin.tar.gz"
  local archive_path="$DOWNLOAD_ROOT/$archive"
  local download_url="https://github.com/tectonic-typesetting/tectonic/releases/download/tectonic%40$VERSION/$archive"
  local destination="$OUTPUT_ROOT/$bundle_arch"

  if [[ ! -f "$archive_path" ]] || [[ "$(shasum -a 256 "$archive_path" | awk '{print $1}')" != "$expected_sha" ]]; then
    print -u2 -r -- "Downloading Tectonic $VERSION for $bundle_arch ..."
    curl --noproxy '*' -fL --retry 3 --output "$archive_path.incoming" "$download_url"
    mv "$archive_path.incoming" "$archive_path"
  fi

  local actual_sha
  actual_sha=$(shasum -a 256 "$archive_path" | awk '{print $1}')
  if [[ "$actual_sha" != "$expected_sha" ]]; then
    print -u2 -r -- "Tectonic checksum mismatch for $bundle_arch: expected $expected_sha, got $actual_sha"
    exit 1
  fi

  local extraction="$DOWNLOAD_ROOT/extract-$bundle_arch.$$"
  mkdir -p "$extraction"
  tar -xzf "$archive_path" -C "$extraction"
  if [[ ! -x "$extraction/tectonic" ]]; then
    print -u2 -r -- "The Tectonic archive for $bundle_arch did not contain an executable."
    exit 1
  fi
  mkdir -p "$destination"
  cp "$extraction/tectonic" "$destination/tectonic"
  chmod 755 "$destination/tectonic"
  rm -rf "$extraction"
}

fetch_architecture \
  aarch64 \
  arm64 \
  edb67c61aba768289f6da441c9e6f523cfaff4f8b2a5708523ef29c543f8e88e

fetch_architecture \
  x86_64 \
  x86_64 \
  79d8839fa3594bfea9b2bf2ac0a0455bcc4d0de956a5e5c403107e9a72f79e86

file "$OUTPUT_ROOT/arm64/tectonic" "$OUTPUT_ROOT/x86_64/tectonic" >&2
HOST_ARCH=$(uname -m)
if [[ "$HOST_ARCH" == arm64 || "$HOST_ARCH" == x86_64 ]]; then
  "$OUTPUT_ROOT/$HOST_ARCH/tectonic" --version >&2
fi
print -r -- "$OUTPUT_ROOT"
