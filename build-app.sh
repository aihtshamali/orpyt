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

swift build

if [[ -d "$APP_DIR" ]]; then
  chflags -R nouchg "$APP_DIR" 2>/dev/null || true
  chmod -R u+w "$APP_DIR" 2>/dev/null || true
  rm -rf "$APP_DIR" 2>/dev/null || true
fi
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

# Embed Sparkle.framework if present (required for SPM builds)
SPARKLE_FW="$(find "$BUILD_DIR/artifacts" -name "Sparkle.framework" -path "*/macos-arm64_x86_64/*" 2>/dev/null | head -1)"
if [[ -n "$SPARKLE_FW" ]]; then
  mkdir -p "$CONTENTS_DIR/Frameworks"
  cp -R "$SPARKLE_FW" "$CONTENTS_DIR/Frameworks/"
  # Add rpath so dyld can find the embedded framework
  install_name_tool -add_rpath @loader_path/../Frameworks "$MACOS_DIR/$APP_NAME" 2>/dev/null || true
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
else
  # Ad-hoc sign so Gatekeeper accepts the modified binary (rpath added above)
  codesign --force --deep --sign - "$APP_DIR" 2>/dev/null || true
fi

rm -rf "$DIST_APP_DIR"
mkdir -p "$DIST_DIR"
ditto "$APP_DIR" "$DIST_APP_DIR"

echo "$DIST_APP_DIR"
