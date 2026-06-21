# Info — a minimal, low-power macOS 26 system monitor

A clean-room, minimal reimagining of [exelban/stats](https://github.com/exelban/stats).
"Info" shows **CPU, GPU, Memory, and Network** in your menu bar as live sparklines,
while being dramatically lighter than Stats: near-zero disk writes, no log spam, and
the lowest practical power draw.

Target: **macOS 26 (Tahoe)**, Apple Silicon, Xcode 26.5 / Swift 6.3 (Swift 6 language mode).

---

## 1. Goals & non-negotiables

| Goal | How we achieve it |
|---|---|
| At-a-glance CPU / GPU / Memory / Network in the menu bar | Per-metric `NSStatusItem` with a live **sparkline** + value |
| **Near-zero disk writes** | No LevelDB, no history DB, no log files. History lives in in-memory ring buffers. Only tiny `UserDefaults` settings writes |
| **No error-log spam** | `os.Logger` with proper levels + rate-limiting; silent guards on missing IOKit/SMC keys; zero hot-path logging |
| **Lowest possible power** | One coalesced `DispatchSourceTimer` for all cheap metrics, `.utility` QoS, >=10% leeway, redraw-on-change only, full pause on sleep/lock/occlusion |
| Stable, no crashes | Swift 6 strict concurrency (actors/`Sendable`), zero force-unwraps on system data, every Mach/sysctl return checked |
| Magical onboarding | Live animated previews + macOS 26 "Allow in Menu Bar" detection & guidance |
| Privacy-first | Everything stays on-device by default; public-IP / ping are opt-in and on-demand only |

## 2. Tech stack

- **Swift 6.3** (Swift 6 language mode, strict concurrency), **macOS 26.0 minimum**, arm64.
- **AppKit shell** (`NSApplicationDelegate` via `NSApplicationDelegateAdaptor`) — agent app (`LSUIElement = true`).
- **AppKit `NSStatusItem` + custom `NSView`** for the live sparklines (`NSStatusItem.view` is deprecated, so we draw inside `statusItem.button`).
- **SwiftUI** (via `NSHostingController`) for the detail popover, Settings, and onboarding — with **Liquid Glass** (`glassEffect`, picked up automatically by `NSPopover` on the 26 SDK).
- **Swift Charts** for the in-popover history graphs.
- **`SMAppService`** for launch-at-login.
- **`os.Logger` + signposts** for observability.
- **Project generation: XcodeGen** (`brew install xcodegen`) driven by a single `project.yml`.

## 3. Architecture & data flow

```
        +----------------------------------------------+
        |  MetricsEngine (@unchecked Sendable,         |
        |  serial-queue-confined)                      |
        |  - ONE DispatchSourceTimer (.utility, leeway)|
        |  - tick -> CPU, GPU, RAM, Net collectors     |
        |  - in-memory ring buffers (history)          |
        |  - pause on sleep / lock / occluded / hidden |
        +---------------+------------------------------+
                        | @MainActor publish (Observable)
        +---------------+---------------+
        |                               |
 +------v-------+               +-------v---------+
 | StatusItem   |  click        | SwiftUI panel   |
 | Controller   +-------------->| (NSPopover +    |
 | - N status   |               |  NSHostingCtrl) |
 |   items      |               | - big value     |
 | - SparklineV |               | - Swift Chart   |
 |   (NSView)   |               | - per-metric    |
 +--------------+               |   details       |
                                +-----------------+
   Settings (SwiftUI)   Onboarding (SwiftUI)   os.Logger
```

**Key difference from Stats:** Stats runs *one timer per reader per module* and writes
every tick to LevelDB. Info runs **one shared timer** that samples all four cheap metrics
in sequence and keeps history **only in RAM**. Heavy/optional probes (SMC temperature,
public IP, connectivity latency) run on a **separate slow cadence and only while their
panel is open**.## 4. Collectors (lean, no hot-path logging)

Pure `Sendable` snapshots; each guards every system call and returns last-good on failure:

- **`CPUCollector`** — `host_processor_info(PROCESSOR_CPU_LOAD_INFO)` per-core, `host_statistics(HOST_CPU_LOAD_INFO)` system/user/idle; layout via `sysctl hw.physicalcpu/logicalcpu`; deltas vs previous sample.
- **`GPUCollector`** — IORegistry `IOAccelerator` -> `PerformanceStatistics["Device Utilization %"]` (+ renderer/tiler). Missing keys handled silently (Stats' 1 Hz error-spam source).
- **`MemoryCollector`** — `host_statistics64(HOST_VM_INFO64)` + `sysctl vm.swapusage` + `kern.memorystatus_vm_pressure_level`.
- **`NetworkCollector`** — `getifaddrs` byte counters (delta/sec), primary interface via `SCDynamicStore`.

**Opt-in / power-gated:**
- **`SMCConnection` + `TemperatureModel`** — minimal self-contained SMC client (`SMC.swift`). Default OFF; when on, sampled at a slow 5 s cadence only while a panel is open. Only piece that touches the SMC.
- **`PublicIP`** (in `NetworkExtras.swift`) — on-demand only when the Network panel opens, then cached; endpoint user-configurable; default OFF. No hardcoded third-party/author server.
- **`Connectivity`** (in `NetworkExtras.swift`) — latency probe only while the Network panel is open, slow cadence; default OFF.
- **Top processes (CPU/RAM)** — shell out to `ps` only while the panel is open.

## 5. Menu bar rendering (sparklines)

- One `NSStatusItem` per enabled metric (option to combine later).
- Custom `MenuBarItemView: NSView` in `statusItem.button`: compact label/value rendering with optional live line/area chart (Network = mirrored up/down), template/monochrome for the transparent macOS 26 bar.
- **Redraw only when the value changes** (Apple energy guidance).
- Click -> toggles an `NSPopover` anchored to that item.

## 6. Detail panel (SwiftUI + Liquid Glass)

`NSPopover` (transient) hosting `NSHostingController`. Per metric:
- **CPU**: big % ring, history chart, per-core mini-bars, system/user/idle split, top processes (lazy).
- **Memory**: used %, pressure gauge, app/wired/compressed/free breakdown, swap, top processes (lazy).
- **GPU**: utilization ring + render/tiler, history, temperature (if enabled).
- **Network**: up/down big numbers + mirrored history, totals, interface/SSID, local IP, public IP + latency (if enabled, lazy).

## 7. Settings (SwiftUI)

Enable/disable each metric, update interval (default **2 s**; 1 s option), sparkline width/
history length, launch-at-login (`SMAppService`), toggles for temperature / public-IP /
connectivity (with power/privacy notes), reset. Persisted via `@AppStorage`/`UserDefaults`
— no per-tick writes.

## 8. Onboarding — the "magic"

Short SwiftUI flow on first run (engine already sampling, so previews are live):

1. **Welcome** — "Your Mac's vitals, at a glance. Everything stays on your Mac."
2. **Make it appear** — create the status items, then detect visibility (`statusItem.isVisible` + button-window heuristics). If macOS 26's "Allow in Menu Bar" is suppressing them, show an explainer + deep link to System Settings -> Menu Bar; auto-advance when the item appears.
3. **Launch at login** — toggle -> `SMAppService.mainApp.register()`.
4. **Pick your metrics** — toggles with live animated previews. Defaults: CPU, Memory, Network, GPU on; temperature/public-IP/ping off.
5. **Done** — no donation pages.

## 9. Logging & reliability

- `os.Logger` subsystem `com.info.app`, categories per collector; debug/trace for samples, error only for real faults, rate-limited.
- `OSSignposter` around each sampling tick for Instruments.
- Swift 6 strict concurrency: `MetricsEngine` is a `final class` marked `@unchecked Sendable`, with all mutable state confined to a private serial `DispatchQueue` (the comment in `MetricsEngine.swift` explains the deviation from a plain `actor`); UI state is `@MainActor`; snapshots are `Sendable`.
- Zero force-unwraps on system data; every `kern_return_t`/`sysctl` checked.

## 10. Power & correctness safeguards

- Single coalesced `DispatchSourceTimer`, `.utility` QoS, leeway = 10-20% of interval.
- Pause sampling on: `NSWorkspace.willSleep`, screen lock, all items hidden, app occluded. Resume on wake/visibility.
- No auto-update/cloud in v1.
- `NSSupportsAutomaticTermination=false` (in `Info.plist`) — an always-on agent app must not be auto-terminated by the system despite having no windows. Power savings come instead from the coalesced timer, utility QoS, and sleep/lock pause above.

## 11. Project structure

```
Info/
  project.yml                 # XcodeGen spec
  Makefile                    # build / dmg / notarize / release targets
  Info/
    App/ InfoApp.swift, AppDelegate.swift, WindowManager.swift
    Engine/ MetricsEngine.swift, MetricsSnapshot.swift, RingBuffer.swift, SamplingState.swift
    Collectors/ CPUCollector.swift, GPUCollector.swift,
                MemoryCollector.swift, NetworkCollector.swift, NetworkInfo.swift,
                NetworkExtras.swift, SMC.swift, TemperatureModel.swift,
                TopProcesses.swift
    MenuBar/ StatusItemController.swift, MenuBarItemView.swift, MenuBarStyle.swift, MetricKind.swift
    Panel/ MetricPanels.swift, PanelComponents.swift
    Settings/ SettingsView.swift, Preferences.swift
    Onboarding/ OnboardingView.swift, MenuBarVisibility.swift
    Support/ Logging.swift, Formatting.swift, Appearance.swift, LaunchAtLogin.swift, PowerGate.swift, SnapshotTool.swift
    Resources/ Info.plist, Assets.xcassets
  Tests/ SmokeTests.swift
  tools/ make-icon.swift, package-dmg.sh, release.sh, Info.icns
```

## 12. Implementation phases (each with a verification gate)

1. **Scaffold** — `project.yml`, agent app launches with a dummy status item. *Gate: builds, runs, no Dock icon.*
2. **Engine + 4 collectors** — shared timer, in-memory history. *Gate: values match Activity Monitor; unit tests pass.*
3. **Sparkline status items** — live bar rendering, redraw-on-change. *Gate: smooth, legible on transparent bar.*
4. **SwiftUI panels** — NSPopover + Swift Charts + lazy top processes. *Gate: each metric's detail correct.*
5. **Settings + launch-at-login** (`SMAppService`). *Gate: toggles persist; login item registers.*
6. **Onboarding + menu-bar-visibility detection**. *Gate: guided flow; auto-advances when item appears.*
7. **Opt-in extras** — SMC temp, public IP, connectivity (gated/on-demand). *Gate: off by default; only active when panel open.*
8. **Power & reliability hardening**. *Gate: < 1 wake/sec idle (`powermetrics`/`timerfires`); no sampling-path disk writes (`fs_usage`); no error spam (Console); lower energy than Stats.*

## 13. Deliberately dropped from Stats

LevelDB history DB, custom file/stderr logger, cloud/MQTT `SystemStats`, SMC-heavy Sensors
& fan control, Bluetooth, Disk, Battery, Clock, WidgetKit desktop widgets, in-app updater,
donation pages, default public-IP request, default 1 Hz ICMP ping, the 500 ms multi-sample
CPU frequency reader, per-reader timers.

## 14. Open notes / risks

- **SMC temperature** is fragile (Apple changes keys per SoC) and is the one power-hungry path — hence default-off + slow + panel-gated.
- **"Allow in Menu Bar" detection** has no public API; we use `isVisible`/button-window heuristics + onboarding escape hatch + a fallback window. Exact System Settings deep-link pane id verified during build.
- Swift 6 strict concurrency is the single biggest lever for "stable, no error logs."
