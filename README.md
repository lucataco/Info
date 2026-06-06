# Info

Info is a lightweight macOS 26 menu bar system monitor for CPU, GPU, memory, and network usage.

## Features

- Live menu bar values with optional icons, text labels, and opt-in sparklines.
- Detail popovers with charts, per-core CPU bars, memory breakdown, GPU details, and network totals.
- Tabbed settings for Metrics, Menu Bar appearance, and General app behavior.
- Launch at login via `SMAppService`.
- In-memory history only; no per-sample database or log files.

## Privacy

By default, Info performs all monitoring locally and does not make external network requests.

Optional extras are off by default:

- Public IP: makes one HTTPS request to `https://api.ipify.org` while the Network panel is open.
- Connectivity latency: sends a lightweight `HEAD` request to `https://captive.apple.com` while the Network panel is open.
- CPU/GPU temperature: reads local SMC sensor keys while CPU/GPU panels are open.

Info does not store metric history on disk.

## Build

```sh
make build
```

## Package

```sh
make dmg
```

The distributable DMG is written to `build/Info.dmg`.

## Verify

```sh
make verify
```

Ad-hoc builds are expected to fail Gatekeeper assessment on other Macs. For distribution, use Developer ID signing and notarization.

## Notarize

```sh
make dmg CODE_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" DEVELOPMENT_TEAM=TEAMID
make notarize NOTARY_PROFILE=your-notarytool-profile
```

Create the notary profile with:

```sh
xcrun notarytool store-credentials your-notarytool-profile --apple-id you@example.com --team-id TEAMID --password app-specific-password
```
