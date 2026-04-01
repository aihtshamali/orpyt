#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="Orpyt"
PROJECT_PATH="$ROOT_DIR/Orpyt.xcodeproj"
SCHEME_NAME="Orpyt"
CONFIGURATION="${ORPYT_CONFIGURATION:-Release}"

BUILD_ROOT="$ROOT_DIR/build/release"
DERIVED_DATA_PATH="$BUILD_ROOT/DerivedData"
ARCHIVE_PATH="$BUILD_ROOT/$APP_NAME.xcarchive"
DMG_STAGING_DIR="$BUILD_ROOT/dmg"
DMG_RW_PATH="$BUILD_ROOT/$APP_NAME-rw.dmg"
DMG_BACKGROUND_DIR="$DMG_STAGING_DIR/.background"
DMG_BACKGROUND_PATH="$DMG_BACKGROUND_DIR/background.png"
PKG_BUILD_DIR="$BUILD_ROOT/pkg"
PKG_COMPONENT_PATH="$PKG_BUILD_DIR/$APP_NAME-component.pkg"
PKG_RESOURCES_DIR="$PKG_BUILD_DIR/resources"
PKG_DISTRIBUTION_PATH="$PKG_BUILD_DIR/distribution.xml"

DIST_DIR="$ROOT_DIR/dist/release"
APP_PATH_IN_ARCHIVE="$ARCHIVE_PATH/Products/Applications/$APP_NAME.app"
DIST_APP_PATH="$DIST_DIR/$APP_NAME.app"
ZIP_PATH="$DIST_DIR/$APP_NAME.zip"
DMG_PATH="$DIST_DIR/$APP_NAME.dmg"
PKG_PATH="$DIST_DIR/$APP_NAME.pkg"

ICNS_PATH="$ROOT_DIR/Assets/Orpyt.icns"
ASSETS_DIR="$ROOT_DIR/Assets"
PKG_IDENTIFIER="com.orpyt.clocks.pkg"
MARKETING_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT_DIR/Info.plist" 2>/dev/null || echo "1.0")"

ALLOW_UNSIGNED="${ORPYT_ALLOW_UNSIGNED:-0}"
SKIP_DMG="${ORPYT_SKIP_DMG:-0}"
NOTARY_PROFILE="${ORPYT_NOTARY_PROFILE:-}"
NOTARY_APPLE_ID="${ORPYT_NOTARY_APPLE_ID:-}"
NOTARY_TEAM_ID="${ORPYT_NOTARY_TEAM_ID:-}"
NOTARY_PASSWORD="${ORPYT_NOTARY_PASSWORD:-}"
VOLUME_NAME="${ORPYT_DMG_VOLUME_NAME:-Orpyt}"
APP_SIGN_IDENTITY="${ORPYT_APP_SIGN_IDENTITY:-Developer ID Application: Ratnam & Co Limited (95NDRZT8W5)}"
INSTALLER_SIGN_IDENTITY="${ORPYT_INSTALLER_SIGN_IDENTITY:-Developer ID Installer: Ratnam & Co Limited (95NDRZT8W5)}"
DMG_WINDOW_WIDTH=700
DMG_WINDOW_HEIGHT=460
DMG_ICON_SIZE=160
DMG_APP_X=170
DMG_APP_Y=235
DMG_APPS_X=530
DMG_APPS_Y=235

mkdir -p "$BUILD_ROOT" "$DIST_DIR"
rm -rf "$ARCHIVE_PATH" "$DERIVED_DATA_PATH" "$DMG_STAGING_DIR" "$DIST_APP_PATH" "$PKG_BUILD_DIR"
rm -f "$ZIP_PATH" "$DMG_PATH" "$DMG_RW_PATH" "$PKG_PATH"

# ── Build ────────────────────────────────────────────────────────────────────

XCODEBUILD_ARGS=(
  -project "$PROJECT_PATH"
  -scheme "$SCHEME_NAME"
  -configuration "$CONFIGURATION"
  -destination "generic/platform=macOS"
  -derivedDataPath "$DERIVED_DATA_PATH"
  -archivePath "$ARCHIVE_PATH"
  ENABLE_HARDENED_RUNTIME=YES
  CODE_SIGNING_ALLOWED=NO
  CODE_SIGNING_REQUIRED=NO
  CODE_SIGN_IDENTITY=""
  archive
)

xcodebuild "${XCODEBUILD_ARGS[@]}"

if [[ ! -d "$APP_PATH_IN_ARCHIVE" ]]; then
  echo "Archive did not produce $APP_PATH_IN_ARCHIVE" >&2
  exit 1
fi

# ── Copy + inject icon ───────────────────────────────────────────────────────

ditto "$APP_PATH_IN_ARCHIVE" "$DIST_APP_PATH"

# Inject the .icns and wire CFBundleIconFile so Finder shows the icon.
if [[ -f "$ICNS_PATH" ]]; then
  cp "$ICNS_PATH" "$DIST_APP_PATH/Contents/Resources/Orpyt.icns"
  /usr/libexec/PlistBuddy -c "Delete :CFBundleIconFile" "$DIST_APP_PATH/Contents/Info.plist" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string Orpyt" "$DIST_APP_PATH/Contents/Info.plist"
  # Touch so Finder re-reads the bundle metadata
  touch "$DIST_APP_PATH"
fi

# ── Re-sign ──────────────────────────────────────────────────────────────────

# Re-sign with Developer ID Application + secure timestamp (required for notarisation).
# Covers the Resources directory now that we injected the .icns.
if [[ "$ALLOW_UNSIGNED" != "1" ]]; then
  codesign --force --deep \
    --sign "$APP_SIGN_IDENTITY" \
    --timestamp \
    --options runtime \
    --entitlements "$ROOT_DIR/Orpyt.entitlements" \
    "$DIST_APP_PATH"
fi

# ── ZIP ──────────────────────────────────────────────────────────────────────

ditto -c -k --keepParent "$DIST_APP_PATH" "$ZIP_PATH"

# ── PKG — native macOS installer ─────────────────────────────────────────────

mkdir -p "$PKG_BUILD_DIR" "$PKG_RESOURCES_DIR"

pkgbuild \
  --component "$DIST_APP_PATH" \
  --install-location /Applications \
  --identifier "$PKG_IDENTIFIER" \
  --version "$MARKETING_VERSION" \
  --scripts "$ROOT_DIR/Packaging/scripts" \
  "$PKG_COMPONENT_PATH"

cp "$ROOT_DIR/Packaging/InstallerResources/welcome.html" "$PKG_RESOURCES_DIR/welcome.html"
cp "$ROOT_DIR/Packaging/InstallerResources/conclusion.html" "$PKG_RESOURCES_DIR/conclusion.html"
if [[ -f "$ROOT_DIR/Assets/logo.png" ]]; then
  cp "$ROOT_DIR/Assets/logo.png" "$PKG_RESOURCES_DIR/logo.png"
fi
if [[ -f "$ROOT_DIR/LICENSE" ]]; then
  cp "$ROOT_DIR/LICENSE" "$PKG_RESOURCES_DIR/LICENSE.txt"
fi
sed "s/__VERSION__/$MARKETING_VERSION/g" \
  "$ROOT_DIR/Packaging/distribution.xml.template" > "$PKG_DISTRIBUTION_PATH"

PRODUCTBUILD_ARGS=(
  --distribution "$PKG_DISTRIBUTION_PATH"
  --package-path "$PKG_BUILD_DIR"
  --resources "$PKG_RESOURCES_DIR"
  "$PKG_PATH"
)

HAS_INSTALLER_CERT=0
if [[ "$ALLOW_UNSIGNED" != "1" ]] && security find-identity -v -p basic 2>/dev/null | grep -qF "$INSTALLER_SIGN_IDENTITY"; then
  HAS_INSTALLER_CERT=1
fi

if [[ "$HAS_INSTALLER_CERT" == "1" ]]; then
  PRODUCTBUILD_ARGS=(
    --sign "$INSTALLER_SIGN_IDENTITY"
    "${PRODUCTBUILD_ARGS[@]}"
  )
fi

productbuild "${PRODUCTBUILD_ARGS[@]}"

if [[ "$SKIP_DMG" != "1" ]]; then
  # ── DMG — styled window (icon left, Applications shortcut right) ───────────
  mkdir -p "$DMG_BACKGROUND_DIR"
  swift "$ROOT_DIR/Packaging/make_dmg_background.swift" "$DMG_BACKGROUND_PATH" "$DMG_WINDOW_WIDTH" "$DMG_WINDOW_HEIGHT"

  # Calculate size: app size + 20 MB headroom for background, symlink, and DS_Store.
  APP_SIZE_KB=$(du -sk "$DIST_APP_PATH" | awk '{print $1}')
  DMG_SIZE_MB=$(( (APP_SIZE_KB / 1024) + 20 ))

  # Create an empty writable DMG of the right size, then copy files in after mounting.
  hdiutil create \
    -fs HFS+ \
    -volname "$VOLUME_NAME" \
    -size "${DMG_SIZE_MB}m" \
    -ov \
    "$DMG_RW_PATH"

  MOUNT_OUTPUT=$(hdiutil attach -readwrite -noverify -noautoopen "$DMG_RW_PATH" 2>&1)
  MOUNT_POINT=$(echo "$MOUNT_OUTPUT" | grep '/Volumes/' | awk -F'\t' '{print $NF}' | sed 's/^[[:space:]]*//' | head -1)
  MOUNT_NAME="$(basename "$MOUNT_POINT")"

  # Copy app and background into the mounted volume.
  # Note: macOS 26 beta blocks writing signed .app bundles to mounted volumes.
  # Detect this and skip DMG gracefully rather than failing the whole build.
  if ! ditto "$DIST_APP_PATH" "$MOUNT_POINT/$APP_NAME.app" 2>/dev/null; then
    echo "Warning: cannot write app bundle to mounted volume (macOS beta TCC restriction). Skipping DMG."
    hdiutil detach "$MOUNT_POINT" 2>/dev/null || true
    rm -f "$DMG_RW_PATH"
    SKIP_DMG=1
  else
    mkdir -p "$MOUNT_POINT/.background"
    cp "$DMG_BACKGROUND_PATH" "$MOUNT_POINT/.background/background.png"
    ln -sf /Applications "$MOUNT_POINT/Applications"
  fi
  if [[ "$SKIP_DMG" != "1" ]]; then

  # Set the volume icon from the .icns file.
  if [[ -f "$ICNS_PATH" ]]; then
    cp "$ICNS_PATH" "$MOUNT_POINT/.VolumeIcon.icns"
    /usr/bin/SetFile -a C "$MOUNT_POINT" 2>/dev/null || true
  fi

  # Style the Finder window: size, icon positions, background colour, hide toolbar.
  osascript <<APPLESCRIPT
tell application "Finder"
  tell disk "$MOUNT_NAME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set pathbar visible of container window to false
    set sidebar width of container window to 0
    set the bounds of container window to {260, 180, 260 + $DMG_WINDOW_WIDTH, 180 + $DMG_WINDOW_HEIGHT}
    set viewOptions to the icon view options of container window
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to $DMG_ICON_SIZE
    set text size of viewOptions to 16
    set background picture of viewOptions to file ".background:background.png"
    set position of item "$APP_NAME.app" of container window to {$DMG_APP_X, $DMG_APP_Y}
    set position of item "Applications" of container window to {$DMG_APPS_X, $DMG_APPS_Y}
    update without registering applications
    delay 5
    close
  end tell
end tell
APPLESCRIPT

  sync

  hdiutil detach "$MOUNT_POINT"

  # Convert to compressed read-only final DMG.
  hdiutil convert "$DMG_RW_PATH" -format UDZO -imagekey zlib-level=9 -o "$DMG_PATH"
  rm -f "$DMG_RW_PATH"
  fi  # end SKIP_DMG check after ditto
fi  # end outer SKIP_DMG check

# ── Verify ───────────────────────────────────────────────────────────────────

if codesign --verify --deep --strict --verbose=1 "$DIST_APP_PATH" >/dev/null 2>&1; then
  echo "Code signature verification passed for $DIST_APP_PATH"
else
  echo "Code signature verification skipped or failed for $DIST_APP_PATH"
fi

# ── Notarise + staple ────────────────────────────────────────────────────────

if [[ -n "$NOTARY_PROFILE" ]]; then
  xcrun notarytool submit "$PKG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$PKG_PATH"
  if [[ "$SKIP_DMG" != "1" ]]; then
    xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG_PATH"
  fi
elif [[ -n "$NOTARY_APPLE_ID" && -n "$NOTARY_TEAM_ID" && -n "$NOTARY_PASSWORD" ]]; then
  xcrun notarytool submit \
    "$PKG_PATH" \
    --apple-id "$NOTARY_APPLE_ID" \
    --team-id "$NOTARY_TEAM_ID" \
    --password "$NOTARY_PASSWORD" \
    --wait
  xcrun stapler staple "$PKG_PATH"
  if [[ "$SKIP_DMG" != "1" ]]; then
    xcrun notarytool submit \
      "$DMG_PATH" \
      --apple-id "$NOTARY_APPLE_ID" \
      --team-id "$NOTARY_TEAM_ID" \
      --password "$NOTARY_PASSWORD" \
      --wait
    xcrun stapler staple "$DMG_PATH"
  fi
else
  echo "Skipping notarization. Set ORPYT_NOTARY_PROFILE or Apple ID/team/password env vars to notarize."
fi

# ── Sparkle appcast ──────────────────────────────────────────────────────────
# Requires SPARKLE_PRIVATE_KEY env var (base64 Ed25519 key from generate_keys -x).
# Downloads generate_appcast if not already cached in build root.

SPARKLE_TOOLS_DIR="${ORPYT_SPARKLE_TOOLS:-$BUILD_ROOT/sparkle-tools}"
GENERATE_APPCAST="$SPARKLE_TOOLS_DIR/bin/generate_appcast"
APPCAST_UPDATES_DIR="$BUILD_ROOT/appcast-updates"

if [[ -n "${SPARKLE_PRIVATE_KEY:-}" ]]; then
  # Download Sparkle tools if needed
  if [[ ! -x "$GENERATE_APPCAST" ]]; then
    echo "Downloading Sparkle tools..."
    mkdir -p "$SPARKLE_TOOLS_DIR"
    curl -sL "https://github.com/sparkle-project/Sparkle/releases/download/2.9.1/Sparkle-for-Swift-Package-Manager.zip" \
      -o "$SPARKLE_TOOLS_DIR/sparkle.zip"
    unzip -q -o "$SPARKLE_TOOLS_DIR/sparkle.zip" -d "$SPARKLE_TOOLS_DIR"
    rm "$SPARKLE_TOOLS_DIR/sparkle.zip"
  fi

  # Write private key to temp file for generate_appcast
  PRIVATE_KEY_FILE=$(mktemp)
  echo -n "$SPARKLE_PRIVATE_KEY" > "$PRIVATE_KEY_FILE"
  trap "rm -f '$PRIVATE_KEY_FILE'" EXIT

  # Collect all release artifacts into one dir and generate the appcast
  mkdir -p "$APPCAST_UPDATES_DIR"
  [[ "$SKIP_DMG" != "1" && -f "$DMG_PATH" ]] && cp "$DMG_PATH" "$APPCAST_UPDATES_DIR/"
  [[ -f "$PKG_PATH" ]] && cp "$PKG_PATH" "$APPCAST_UPDATES_DIR/"

  RELEASE_TAG="${ORPYT_RELEASE_TAG:-v$MARKETING_VERSION}"
  BASE_URL="https://github.com/aihtshamali/orpyt/releases/download/$RELEASE_TAG"

  "$GENERATE_APPCAST" \
    --ed-key-file "$PRIVATE_KEY_FILE" \
    --download-url-prefix "$BASE_URL/" \
    --link "https://github.com/aihtshamali/orpyt" \
    "$APPCAST_UPDATES_DIR"

  GENERATED_APPCAST="$APPCAST_UPDATES_DIR/appcast.xml"

  if [[ -f "$GENERATED_APPCAST" ]]; then
    # Push updated appcast to gh-pages branch
    GH_PAGES_DIR=$(mktemp -d)

    # Build an authenticated remote URL: prefer GITHUB_TOKEN for CI, fall back to SSH
    ORIGIN_URL="$(git -C "$ROOT_DIR" remote get-url origin)"
    if [[ -n "${GITHUB_TOKEN:-}" ]]; then
      # Convert any git@github.com:owner/repo.git → https://x-access-token:TOKEN@github.com/owner/repo.git
      HTTPS_URL="${ORIGIN_URL/git@github.com:/https://github.com/}"
      AUTHED_URL="${HTTPS_URL/https:\/\/github.com/https://x-access-token:${GITHUB_TOKEN}@github.com}"
    else
      AUTHED_URL="$ORIGIN_URL"
    fi

    git clone --branch gh-pages --depth 1 "$AUTHED_URL" "$GH_PAGES_DIR" 2>/dev/null

    cp "$GENERATED_APPCAST" "$GH_PAGES_DIR/appcast.xml"
    git -C "$GH_PAGES_DIR" add appcast.xml
    git -C "$GH_PAGES_DIR" -c user.name="Orpyt Release Bot" \
      -c user.email="release@orpyt.app" \
      commit -m "appcast: update for $RELEASE_TAG"
    git -C "$GH_PAGES_DIR" push "$AUTHED_URL" gh-pages
    rm -rf "$GH_PAGES_DIR"
    echo "Appcast updated and pushed to gh-pages."
  else
    echo "Warning: generate_appcast did not produce appcast.xml"
  fi
else
  echo "Skipping appcast generation. Set SPARKLE_PRIVATE_KEY to enable."
fi

echo ""
echo "Archive:  $ARCHIVE_PATH"
echo "App:      $DIST_APP_PATH"
echo "PKG:      $PKG_PATH"
echo "ZIP:      $ZIP_PATH"
if [[ "$SKIP_DMG" != "1" ]]; then
  echo "DMG:      $DMG_PATH"
fi
