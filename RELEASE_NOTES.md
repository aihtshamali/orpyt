# Orpyt Release Notes

## Highlights

- Added colored clock and meeting accents so the popover is easier to scan at a glance.
- Added a sticky Mac-style popover header with native material, a soft divider, and toolbar shadow.
- Removed the bulky persistent popover scrollbar while keeping scrolling available for taller content.
- Fixed calendar permission sync so Orpyt picks up Calendar access changes made in System Settings without getting stuck on the access prompt.
- Added smarter calendar context with menu bar meeting alerts, Today’s Plan, join/copy meeting actions, and manual calendar refresh.
- Added an Apple-compliant feedback prompt plus a Settings link for feature suggestions through GitHub Discussions.
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
- This build is version `1.2` / build `17` for App Store submission.
- Calendar access does not need to be re-granted if it is already enabled in macOS Settings.
- The new review prompt waits for calm value moments and never appears during permission, subscription, or active meeting friction.
- Feature suggestions now open GitHub Discussions at `https://github.com/aihtshamali/orpyt/discussions`.
- Time scroller interaction is now faster for keyboard-and-pointer users because labeled offsets are click targets.
- Menu bar icon controls have moved into a more focused layout in Settings.
