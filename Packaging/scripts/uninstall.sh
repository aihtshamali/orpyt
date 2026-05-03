#!/bin/zsh
# Orpyt uninstaller — removes the app and all stored data from the local system.
# Run as: sudo zsh uninstall.sh
# or double-click after making it executable.

set -euo pipefail

BUNDLE_ID="com.orpyt.app"
APP="/Applications/Orpyt.app"

echo "=== Orpyt Uninstaller ==="

# Quit the running app if it is open
if pgrep -x "Orpyt" &>/dev/null; then
    echo "Stopping Orpyt..."
    pkill -x "Orpyt" 2>/dev/null || true
    sleep 1
fi

# Remove the app bundle
if [[ -d "$APP" ]]; then
    echo "Removing $APP..."
    rm -rf "$APP"
else
    echo "App not found at $APP (already removed?)"
fi

# Remove all stored user data
PREFS="$HOME/Library/Preferences/${BUNDLE_ID}.plist"
APP_SUPPORT="$HOME/Library/Application Support/${BUNDLE_ID}"
CACHES="$HOME/Library/Caches/${BUNDLE_ID}"
SAVED_STATE="$HOME/Library/Saved Application State/${BUNDLE_ID}.savedState"
GROUP_CONTAINERS="$HOME/Library/Group Containers"

[[ -f "$PREFS" ]] && { echo "Removing preferences..."; rm -f "$PREFS"; }
[[ -d "$APP_SUPPORT" ]] && { echo "Removing application support data..."; rm -rf "$APP_SUPPORT"; }
[[ -d "$CACHES" ]] && { echo "Removing caches..."; rm -rf "$CACHES"; }
[[ -d "$SAVED_STATE" ]] && { echo "Removing saved state..."; rm -rf "$SAVED_STATE"; }

# Remove any group containers that match the bundle ID
for dir in "$GROUP_CONTAINERS"/*"$BUNDLE_ID"*; do
    [[ -d "$dir" ]] && { echo "Removing group container $dir..."; rm -rf "$dir"; }
done

# Flush preferences cache
defaults delete "$BUNDLE_ID" 2>/dev/null || true

# Reset TCC (Privacy) permissions — requires sudo
if [[ $EUID -eq 0 ]]; then
    echo "Resetting Privacy permissions (Calendar, Location)..."
    tccutil reset Calendar "$BUNDLE_ID" 2>/dev/null || true
    tccutil reset Location "$BUNDLE_ID" 2>/dev/null || true
    tccutil reset All "$BUNDLE_ID" 2>/dev/null || true
else
    echo "Skipping TCC reset (run as sudo to also clear Privacy permissions)"
fi

# Remove any LaunchAgent
LAUNCH_AGENT="$HOME/Library/LaunchAgents/${BUNDLE_ID}.plist"
if [[ -f "$LAUNCH_AGENT" ]]; then
    echo "Removing LaunchAgent..."
    launchctl unload "$LAUNCH_AGENT" 2>/dev/null || true
    rm -f "$LAUNCH_AGENT"
fi

echo ""
echo "Orpyt has been fully removed."
