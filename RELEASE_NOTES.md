# Orpyt Release Notes

## Highlights

- Fixed calendar permission sync so Orpyt picks up Calendar access changes made in System Settings without getting stuck on the access prompt.
- Time scroller labels are now directly clickable, so jumping to `+3h`, `Now`, or any labeled offset is immediate.
- Reorganized settings so menu bar icon behavior is managed in one clear place, with weather display options kept in the Weather pane.
- Installer postinstall now launches Orpyt automatically after installation for the logged-in user.
- Cleaned the menu bar tooltip so transient weather failures do not show noisy “Weather unavailable” text on hover.

## Included In This Release

- Signed `Orpyt.app`
- Signed and notarized `Orpyt.pkg`
- `Orpyt.zip` for direct bundle distribution

## Installation

1. Download `Orpyt.pkg`
2. Open it with macOS Installer
3. Follow the standard installation steps
4. Orpyt launches automatically after install
5. If needed, you can also open it later from Applications

## Notes

- The PKG notarization was accepted and stapled successfully.
- On this machine, DMG generation was skipped during the final signed release because macOS blocked writing the styled app bundle to the mounted DMG volume under a beta TCC restriction.
- The PKG is the recommended release artifact for this build.

## Upgrade Notes

- Existing users can install over the current version.
- Calendar access does not need to be re-granted if it is already enabled in macOS Settings.
- Time scroller interaction is now faster for keyboard-and-pointer users because labeled offsets are click targets.
- Menu bar icon controls have moved into a more focused layout in Settings.
