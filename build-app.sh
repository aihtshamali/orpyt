#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="Orpyt"
BUILD_DIR="$ROOT_DIR/.build"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
DIST_APP_DIR="$DIST_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

mkdir -p "$BUILD_DIR/home" "$BUILD_DIR/clang-cache" "$BUILD_DIR/swiftpm-cache"

env \
  HOME="$BUILD_DIR/home" \
  CLANG_MODULE_CACHE_PATH="$BUILD_DIR/clang-cache" \
  SWIFTPM_MODULECACHE_OVERRIDE="$BUILD_DIR/swiftpm-cache" \
  swift build

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$BUILD_DIR/debug/$APP_NAME" "$MACOS_DIR/$APP_NAME"
cp "$ROOT_DIR/Info.plist" "$CONTENTS_DIR/Info.plist"

if [[ -f "$ROOT_DIR/Assets/logo.png" ]]; then
  cp "$ROOT_DIR/Assets/logo.png" "$RESOURCES_DIR/logo.png"
fi

if [[ -f "$ROOT_DIR/Assets/appstore.png" ]]; then
  cp "$ROOT_DIR/Assets/appstore.png" "$RESOURCES_DIR/appstore.png"
fi

if [[ -f "$ROOT_DIR/Assets/Orpyt.icns" ]]; then
  cp "$ROOT_DIR/Assets/Orpyt.icns" "$RESOURCES_DIR/Orpyt.icns"
fi

if [[ "${ORPYT_ENABLE_SIGNING:-0}" == "1" && -z "${ORPYT_SIGN_IDENTITY:-}" ]]; then
  ORPYT_SIGN_IDENTITY="$(
    security find-identity -v -p codesigning \
      | awk -F\" '/Apple Development:/ {print $2; exit}'
  )"
fi

if [[ "${ORPYT_ENABLE_SIGNING:-0}" == "1" && -n "${ORPYT_SIGN_IDENTITY:-}" ]]; then
  codesign \
    --force \
    --deep \
    --sign "$ORPYT_SIGN_IDENTITY" \
    --entitlements "$ROOT_DIR/Orpyt.entitlements" \
    "$APP_DIR"
fi

rm -rf "$DIST_APP_DIR"
mkdir -p "$DIST_DIR"
ditto "$APP_DIR" "$DIST_APP_DIR"

echo "$DIST_APP_DIR"
