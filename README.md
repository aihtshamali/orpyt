<p align="center">
  <img src="./Assets/logo.png" alt="Orpyt Logo" width="160" />
</p>

<h1 align="center">Orpyt</h1>

<p align="center">
  <strong>A native macOS menu bar clock for people working across time zones.</strong>
</p>

<p align="center">
  Orpyt keeps two cities in sync with a fast popover, a full settings window, and optional live weather.
</p>

<p align="center">
  <img src="./Assets/desktop-orpyt.png" alt="Orpyt Screenshot" width="900" />
</p>

---

## Features

- Dual clocks directly in the macOS menu bar
- Configurable primary and secondary time zones
- Show one clock or both
- Optional 24-hour format
- Optional seconds, weekday, date, timezone abbreviation, and GMT offset
- Custom labels for each clock
- Ambient or weather-based icon mode
- Live weather with graceful fallback
- Native settings window
- Smooth, animated overview cards

---

## Requirements

- macOS 13 Ventura or later
- Xcode 15 or later
- Apple Developer account (required for WeatherKit entitlement)

---

## Project Layout

- `Sources/OrpytApp.swift` — main app source
- `Package.swift` — Swift package manifest
- `Orpyt.xcodeproj` — canonical Xcode project
- `Orpyt.entitlements` — app entitlements (WeatherKit, etc.)
- `Assets/` — app logo and screenshots
- `build-app.sh` — local bundle builder

---

## Run

Clone the repo, then build and launch the local `.app` bundle:

```bash
git clone git@github.com:aihtshamali/orpyt.git
cd Orpyt
./build-app.sh
open .build/Orpyt.app
```

---

## Open in Xcode

```bash
cd Orpyt
open Orpyt.xcodeproj
```

---

## Philosophy

Orpyt is designed to feel:

- **fast to glance**
- **calm to use**
- **invisible when not needed**

Every detail — from spacing to animation — is intentional.

---

## Contributing

Contributions are welcome.

- Open an issue for discussion
- Submit a focused pull request
- Keep changes simple and consistent

See [`CONTRIBUTING.md`](./CONTRIBUTING.md) for details.

---

## License

See [`LICENSE`](./LICENSE) for details.
