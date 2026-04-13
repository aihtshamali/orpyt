# Orpyt Release Notes

## Highlights

- Fixed calendar permission sync so Orpyt picks up Calendar access changes made in System Settings without getting stuck on the access prompt.
- Next Meeting now updates correctly after the app becomes active again or when the popover is opened.
- Continued polish across the native menu bar popover, settings, packaging, and release pipeline.

## Included In This Release

- Signed `Orpyt.app`
- Signed and notarized `Orpyt.pkg`
- `Orpyt.zip` for direct bundle distribution

## Installation

1. Download `Orpyt.pkg`
2. Open it with macOS Installer
3. Follow the standard installation steps
4. Launch Orpyt from Applications

## Notes

- The PKG notarization was accepted and stapled successfully.
- On this machine, DMG generation was skipped during the final signed release because macOS blocked writing the styled app bundle to the mounted DMG volume under a beta TCC restriction.
- The PKG is the recommended release artifact for this build.

## Upgrade Notes

- Existing users can install over the current version.
- Calendar access does not need to be re-granted if it is already enabled in macOS Settings.
