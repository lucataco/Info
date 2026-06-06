#if DEBUG
import AppKit
import SwiftUI

/// DEBUG-only: renders the real menu-bar item views and SwiftUI panels offscreen to
/// PNGs so we can visually verify without Screen Recording permission. Never
/// compiled into release builds.
enum SnapshotTool {
    @MainActor
    static func render(toBase base: String) {
        let variants: [(String, MenuBarStyle)] = [
            ("text_graph", MenuBarStyle(showSparkline: true, label: .text, textSize: .medium)),
            ("icon_graph", MenuBarStyle(showSparkline: true, label: .icon, textSize: .medium)),
            ("text_nograph", MenuBarStyle(showSparkline: false, label: .text, textSize: .medium)),
            ("icon_nograph_large", MenuBarStyle(showSparkline: false, label: .icon, textSize: .large)),
            ("icon_only", MenuBarStyle(showSparkline: false, showValue: false, label: .icon, textSize: .medium)),
            ("none_graph", MenuBarStyle(showSparkline: true, label: .none, textSize: .medium)),
        ]
        for (name, style) in variants {
            writeStrip(dark: true, style: style, to: "\(base)_\(name).png")
        }
    }

    /// Renders each onboarding step (text/icons/charts render; AppKit-backed
    /// buttons/toggles won't, but the layout and previews are verifiable).
    @MainActor
    static func renderOnboarding(toBase base: String) {
        let prefs = Preferences(defaults: UserDefaults(suiteName: "info.snapshot.onboard") ?? .standard)
        let state = seededState()
        for step in 0...4 {
            let content = OnboardingView(
                prefs: prefs, state: state,
                statusItemsProvider: { [] }, onMetricsChanged: {}, onFinish: {},
                initialStep: step)
                .environment(\.colorScheme, .dark)
            let renderer = ImageRenderer(content: content)
            renderer.scale = 2
            guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let data = rep.representation(using: .png, properties: [:]) else { continue }
            try? data.write(to: URL(fileURLWithPath: base + "_step\(step).png"))
            NSLog("onboarding snapshot wrote step %d", step)
        }
    }

    @MainActor
    private static func seededState() -> SamplingState {
        let state = SamplingState()
        for _ in 0..<40 {
            state.ingest(MetricsSnapshot(
                enabledMetrics: Set(MetricKind.allCases),
                cpu: CPUSample(total: Double.random(in: 0.1...0.7), system: 0.1, user: 0.2, idle: 0.7, perCore: []),
                memory: MemorySample(total: 137_000_000_000, used: UInt64(Double.random(in: 0.18...0.24) * 137_000_000_000),
                                     free: 0, app: 0, wired: 0, compressed: 0, cached: 0, pressure: .normal, swapTotal: 0, swapUsed: 0),
                gpu: GPUSample(name: "GPU", utilization: Double.random(in: 0...0.5)),
                network: NetworkSample(interface: "en0", uploadBytesPerSec: UInt64.random(in: 0...500_000),
                                       downloadBytesPerSec: UInt64.random(in: 0...2_000_000),
                                       totalUploaded: 0, totalDownloaded: 0)))
        }
        state.ingest(MetricsSnapshot(
            enabledMetrics: Set(MetricKind.allCases),
            cpu: CPUSample(total: 0.42, system: 0.12, user: 0.30, idle: 0.58,
                           perCore: (0..<12).map { _ in Double.random(in: 0.05...0.95) }),
            memory: MemorySample(total: 137_000_000_000, used: 30_000_000_000, free: 107_000_000_000,
                                 app: 18_000_000_000, wired: 8_000_000_000, compressed: 4_000_000_000,
                                 cached: 26_000_000_000, pressure: .normal, swapTotal: 0, swapUsed: 0),
            gpu: GPUSample(name: "Apple M-series GPU", utilization: 0.27,
                           renderUtilization: 0.22, tilerUtilization: 0.05),
            network: NetworkSample(interface: "en0", uploadBytesPerSec: 320_000,
                                   downloadBytesPerSec: 1_450_000,
                                   totalUploaded: 2_000_000_000, totalDownloaded: 18_000_000_000)))
        return state
    }

    /// Renders each metric panel with synthetic state into PNGs.
    @MainActor
    static func renderPanels(toBase base: String) {
        let state = seededState()
        let prefs = Preferences(defaults: UserDefaults(suiteName: "info.snapshot.panels") ?? .standard)
        for kind in MetricKind.allCases {
            writePanel(kind: kind, state: state, prefs: prefs, to: base + "_\(kind.rawValue).png")
        }
    }

    @MainActor
    private static func writePanel(kind: MetricKind, state: SamplingState, prefs: Preferences, to path: String) {
        // ImageRenderer is the correct way to rasterize SwiftUI (captures text,
        // which cacheDisplay misses).
        let content = MetricPanel(kind: kind, state: state, prefs: prefs)
            .environment(\.colorScheme, .dark)
            .background(Color(white: 0.13))
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let data = rep.representation(using: .png, properties: [:]) else { return }
        try? data.write(to: URL(fileURLWithPath: path))
        NSLog("panel snapshot wrote %@ (%dx%d)", path, Int(image.size.width), Int(image.size.height))
    }

    private final class Backdrop: NSView {
        var color: NSColor = .clear
        override func draw(_ dirtyRect: NSRect) {
            color.setFill()
            bounds.fill()
        }
    }

    @MainActor
    private static func makeBars(style: MenuBarStyle) -> [MenuBarItemView] {
        func ramp(_ n: Int, _ f: (Double) -> Double) -> [Double] {
            (0..<n).map { f(Double($0) / Double(n - 1)) }
        }
        let cpu = ramp(60) { x in min(1, max(0, 0.15 + 0.7 * x + 0.08 * sin(x * 18))) }
        let gpu = ramp(60) { x in max(0, 0.04 + (x > 0.55 ? 0.6 * (x - 0.55) : 0)) }
        let mem = ramp(60) { x in 0.20 + 0.02 * sin(x * 6) }
        let down = ramp(60) { x in abs(sin(x * 12)) * 1_500_000 * x }
        let up = ramp(60) { x in abs(cos(x * 9)) * 400_000 * x }

        let cpuV = MenuBarItemView(kind: .cpu, style: style)
        cpuV.updateSingle(history: cpu, value: Fmt.percent(cpu.last ?? 0))
        let gpuV = MenuBarItemView(kind: .gpu, style: style)
        gpuV.updateSingle(history: gpu, value: Fmt.percent(gpu.last ?? 0))
        let memV = MenuBarItemView(kind: .memory, style: style)
        memV.updateSingle(history: mem, value: Fmt.percent(mem.last ?? 0))
        let netV = MenuBarItemView(kind: .network, style: style)
        netV.updateMirrored(download: down, upload: up,
                            lines: ["\u{2193}\(Fmt.rateShort(UInt64(down.last ?? 0)))",
                                    "\u{2191}\(Fmt.rateShort(UInt64(up.last ?? 0)))"])
        return [cpuV, gpuV, memV, netV]
    }

    @MainActor
    private static func writeStrip(dark: Bool, style: MenuBarStyle, to path: String) {
        let thickness = NSStatusBar.system.thickness
        let bars = makeBars(style: style)
        let widths = bars.map { $0.preferredWidth() }
        let gap: CGFloat = 10, pad: CGFloat = 12
        let totalW = pad * 2 + widths.reduce(0, +) + gap * CGFloat(bars.count - 1)

        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)!
        let container = Backdrop(frame: NSRect(x: 0, y: 0, width: totalW, height: thickness))
        container.color = dark ? NSColor(white: 0.11, alpha: 1) : NSColor(white: 0.93, alpha: 1)
        container.appearance = appearance

        var x = pad
        for (i, bar) in bars.enumerated() {
            bar.frame = NSRect(x: x, y: 0, width: widths[i], height: thickness)
            bar.appearance = appearance
            container.addSubview(bar)
            x += widths[i] + gap
        }

        guard let rep = container.bitmapImageRepForCachingDisplay(in: container.bounds) else { return }
        appearance.performAsCurrentDrawingAppearance {
            container.cacheDisplay(in: container.bounds, to: rep)
        }
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: URL(fileURLWithPath: path))
            NSLog("snapshot wrote %@ (%dx%d pts)", path, Int(totalW), Int(thickness))
        }
    }
}
#endif
