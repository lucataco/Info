# Changelog

All notable changes to Info are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.4.5] — 2026-06-21

### Changed
- Xcode project (`Info.xcodeproj/`) is now gitignored — it is a generated
  artifact of XcodeGen. Run `make generate` (or any `make` target) to create it.
- `PLAN.md` refreshed: corrected the architecture diagram and file structure to
  match the implementation; reworded the "App Nap friendly" claim to accurately
  describe the `NSSupportsAutomaticTermination=false` setting.
- `NetworkCollector.primaryInterface()` simplified — removed a redundant double
  `guard let store` that re-bound an already-unwrapped value.
- Debug CLI hooks (`--read-temp`, `--test-net`) and `SnapshotTool` now use
  `os.Logger` instead of `NSLog`, matching the documented logging strategy.

### Added
- `MetricsEngineTests` suite (8 tests) covering engine lifecycle: start, stop,
  pause/resume, interval change, enabled-metrics toggle, and empty-metrics
  gating.
- `CHANGELOG.md`.
- SwiftLint configuration (`.swiftlint.yml`) and `make lint` target.

## [0.4.4] — 2026-06-11

### Added
- Light / dark / system appearance setting.

## [0.4.3] — 2026-06-06

### Added
- Interactive history charts with hover readouts and labeled axes.

## [0.4.2] — 2026-06-06

### Added
- Menu bar layout options (inline, tight, stacked).

## [0.4.1] — 2026-06-06

### Fixed
- Restore popover heights.

## [0.4.0] — 2026-06-06

### Fixed
- Harden popover clipping.

## [0.3.0] — 2026-06-06

### Fixed
- Fix popover clipping.

## [0.2.0] — 2026-06-06

### Added
- Richer GPU and Network detail panels.
- Menu bar fixes.

## [0.1.0] — 2026-06-06

### Added
- CPU, GPU, memory, and network collectors with a single coalesced timer.
- Menu bar status items with live sparklines.
- SwiftUI detail panels with Swift Charts.
- Settings (metrics, menu bar appearance, general).
- Onboarding with macOS 26 "Allow in Menu Bar" detection.
- Launch at login via `SMAppService`.
- Opt-in extras: SMC temperature, public IP, connectivity latency (all off by
  default, panel-gated).
- Sleep / screen-lock power gating.
