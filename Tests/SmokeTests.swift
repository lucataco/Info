import Testing
import Foundation
@testable import Info

@Suite struct LoggingTests {
    @Test func subsystemIsStable() {
        #expect(Log.subsystem == "com.info.app")
    }
}

@Suite struct RingBufferTests {
    @Test func appendsUntilCapacityThenWraps() {
        var rb = RingBuffer<Int>(capacity: 3)
        rb.append(1); rb.append(2)
        #expect(rb.values == [1, 2])
        rb.append(3); rb.append(4)            // wraps, drops 1
        #expect(rb.values == [2, 3, 4])
        #expect(rb.count == 3)
        #expect(rb.last == 4)
        rb.removeAll()
        #expect(rb.values.isEmpty)
        #expect(rb.last == nil)
    }

    @Test func emptyBuffer() {
        let rb = RingBuffer<Double>(capacity: 5)
        #expect(rb.isEmpty)
        #expect(rb.values.isEmpty)
        #expect(rb.last == nil)
    }
}

@Suite struct CPUMathTests {
    @Test func fullyBusy() {
        #expect(CPUMath.busyFraction(user: 50, system: 50, idle: 0, nice: 0) == 1.0)
    }

    @Test func fullyIdle() {
        #expect(CPUMath.busyFraction(user: 0, system: 0, idle: 100, nice: 0) == 0.0)
    }

    @Test func halfBusyIncludesNice() {
        // (10 user + 10 system + 5 nice) / 50 total = 0.5
        #expect(CPUMath.busyFraction(user: 10, system: 10, idle: 25, nice: 5) == 0.5)
    }

    @Test func zeroTotalIsSafe() {
        #expect(CPUMath.busyFraction(user: 0, system: 0, idle: 0, nice: 0) == 0.0)
    }
}

@Suite struct FormattingTests {
    @Test func percentRounds() {
        #expect(Fmt.percent(0.234) == "23%")
        #expect(Fmt.percent(0.236) == "24%")
        #expect(Fmt.percent(1.0) == "100%")
        #expect(Fmt.percent(1.2) == "100%")
        #expect(Fmt.percent(.nan) == "—")
    }

    @Test func bytesScale() {
        #expect(Fmt.bytes(512) == "512 B")
        #expect(Fmt.bytes(1536) == "1.5 KB")
        #expect(Fmt.bytes(1024 * 1024) == "1.0 MB")
    }

    @Test func shortRate() {
        #expect(Fmt.rateShort(0) == "0B")
        #expect(Fmt.rateShort(1536) == "1.5K")
    }
}

@Suite struct TopProcessesParseTests {
    @Test func parsesCPUSortedOutput() {
        let out = """
        99512  76.3 yes
        7614  12.0 Google Chrome
        100 0.5 launchd
        """
        let rows = TopProcessesModel.parse(out, kind: .cpu, limit: 5)
        #expect(rows.count == 3)
        #expect(rows[0].id == 99512)
        #expect(rows[0].name == "yes")
        #expect(rows[0].detail == "76%")
        #expect(rows[1].name == "Google Chrome")     // name with a space
    }

    @Test func parsesMemoryOutputWithSpacedNames() {
        let out = " 72086 1039536 Google Chrome Helper (Renderer)\n70181 1914736 parakeet"
        let rows = TopProcessesModel.parse(out, kind: .memory, limit: 5)
        #expect(rows.count == 2)
        #expect(rows[0].name == "Google Chrome Helper (Renderer)")
        #expect(rows[0].detail.contains("GB") || rows[0].detail.contains("MB"))
    }

    @Test func respectsLimit() {
        let out = (0..<20).map { "\($0) 1.0 proc\($0)" }.joined(separator: "\n")
        #expect(TopProcessesModel.parse(out, kind: .cpu, limit: 5).count == 5)
    }

    @Test func skipsMalformedLines() {
        let out = "garbage line\n123 5.0 realproc\n\n"
        let rows = TopProcessesModel.parse(out, kind: .cpu, limit: 5)
        #expect(rows.count == 1)
        #expect(rows[0].id == 123)
    }
}

@Suite struct PreferencesTests {
    private func freshSuite() -> UserDefaults { UserDefaults(suiteName: "test.\(UUID().uuidString)")! }

    @Test @MainActor func defaultsAreAllMetricsAndTwoSeconds() {
        let p = Preferences(defaults: freshSuite())
        #expect(p.enabledMetrics == MetricKind.allCases)
        #expect(p.updateInterval == 2.0)
        #expect(p.showTemperature == false)
        #expect(p.showMenuBarSparkline == false)
        #expect(p.showMenuBarValue == true)
        #expect(p.menuBarSpacing == .compact)
    }

    @Test @MainActor func toggleKeepsCanonicalOrder() {
        let p = Preferences(defaults: freshSuite())
        p.setEnabled(.cpu, false)
        #expect(!p.isEnabled(.cpu))
        #expect(p.enabledMetrics == [.gpu, .memory, .network])
        p.setEnabled(.cpu, true)
        #expect(p.enabledMetrics == MetricKind.allCases) // re-sorted canonically
    }

    @Test @MainActor func canDisableAllMetricsBecauseFallbackItemExists() {
        let p = Preferences(defaults: freshSuite())
        p.enabledMetrics = [.cpu]
        p.setEnabled(.cpu, false)
        #expect(p.enabledMetrics.isEmpty)
    }

    @Test @MainActor func persistsAcrossInstances() {
        let suite = freshSuite()
        let first = Preferences(defaults: suite)
        first.setEnabled(.gpu, false)
        first.updateInterval = 3
        let second = Preferences(defaults: suite)
        #expect(!second.isEnabled(.gpu))
        #expect(second.updateInterval == 3)
    }

    @Test @MainActor func persistsEmptyMetricList() {
        let suite = freshSuite()
        let first = Preferences(defaults: suite)
        first.enabledMetrics = []
        let second = Preferences(defaults: suite)
        #expect(second.enabledMetrics.isEmpty)
    }

    @Test @MainActor func persistsMenuBarStyle() {
        let suite = freshSuite()
        let first = Preferences(defaults: suite)
        first.showMenuBarSparkline = false
        first.showMenuBarValue = false
        first.menuBarLabel = .icon
        first.menuBarTextSize = .large
        first.menuBarSpacing = .spacious
        let second = Preferences(defaults: suite)
        #expect(second.menuBarStyle == MenuBarStyle(showSparkline: false,
                                                    showValue: false,
                                                    label: .icon,
                                                    textSize: .large,
                                                    spacing: .spacious))
    }
}

@Suite struct MetricCollectorsTests {
    @Test func onlyEnabledCollectorsRun() {
        final class Counters {
            var cpu = 0, gpu = 0, memory = 0, network = 0
        }
        let counters = Counters()
        let collectors = MetricCollectors(
            cpu: { counters.cpu += 1; return CPUSample(total: 1, system: 0, user: 1, idle: 0, perCore: []) },
            gpu: { counters.gpu += 1; return GPUSample(name: "GPU", utilization: 1) },
            memory: { counters.memory += 1; return MemorySample(total: 1, used: 1, free: 0, app: 0, wired: 0, compressed: 0, cached: 0, pressure: .normal, swapTotal: 0, swapUsed: 0) },
            network: { counters.network += 1; return NetworkSample(interface: nil, uploadBytesPerSec: 1, downloadBytesPerSec: 1, totalUploaded: 1, totalDownloaded: 1) }
        )

        let snapshot = collectors.sample(enabledMetrics: [.cpu, .network])
        #expect(snapshot.cpu != nil)
        #expect(snapshot.network != nil)
        #expect(snapshot.gpu == nil)
        #expect(snapshot.memory == nil)
        #expect(counters.cpu == 1)
        #expect(counters.network == 1)
        #expect(counters.gpu == 0)
        #expect(counters.memory == 0)
    }

    @Test func emptyEnabledSetRunsNoCollectors() {
        final class Counter { var count = 0 }
        let counter = Counter()
        let collectors = MetricCollectors(
            cpu: { counter.count += 1; return nil },
            gpu: { counter.count += 1; return nil },
            memory: { counter.count += 1; return nil },
            network: { counter.count += 1; return nil }
        )
        _ = collectors.sample(enabledMetrics: [])
        #expect(counter.count == 0)
    }
}

@Suite struct SamplingStateTests {
    @Test @MainActor func clearsEnabledMetricWhenCollectorFails() {
        let state = SamplingState()
        state.ingest(MetricsSnapshot(
            enabledMetrics: [.cpu],
            cpu: CPUSample(total: 0.5, system: 0.2, user: 0.3, idle: 0.5, perCore: []),
            memory: nil,
            gpu: nil,
            network: nil))
        #expect(state.cpu != nil)
        #expect(!state.cpuHistory.isEmpty)

        state.ingest(MetricsSnapshot(enabledMetrics: [.cpu], cpu: nil, memory: nil, gpu: nil, network: nil))
        #expect(state.cpu == nil)
        #expect(state.cpuHistory.isEmpty)
    }

    @Test @MainActor func disabledMetricDoesNotClearExistingValue() {
        let state = SamplingState()
        state.ingest(MetricsSnapshot(
            enabledMetrics: [.cpu],
            cpu: CPUSample(total: 0.5, system: 0.2, user: 0.3, idle: 0.5, perCore: []),
            memory: nil,
            gpu: nil,
            network: nil))

        state.ingest(MetricsSnapshot(enabledMetrics: [], cpu: nil, memory: nil, gpu: nil, network: nil))
        #expect(state.cpu != nil)
        #expect(!state.cpuHistory.isEmpty)
    }
}

@Suite struct StatusItemControllerTests {
    @Test @MainActor func emptyMetricsInstallsFallbackItem() {
        let controller = StatusItemController()
        let prefs = Preferences(defaults: UserDefaults(suiteName: "test.\(UUID().uuidString)")!)
        prefs.enabledMetrics = []
        controller.install(state: SamplingState(), prefs: prefs, metrics: [])
        #expect(controller.statusItems.count == 1)
        #expect(controller.statusItems.first?.button?.title == "Info")
        controller.tearDown()
    }

    @Test func popoverPositionsBelowTopMenuItem() {
        let visible = NSRect(x: 0, y: 0, width: 1000, height: 700)
        let anchor = NSRect(x: 800, y: 700, width: 40, height: 22)
        let origin = StatusItemController.popoverOrigin(anchor: anchor,
                                                        size: NSSize(width: 300, height: 200),
                                                        visible: visible)
        #expect(origin.y == 492) // clamped to visible.maxY - height - margin
    }

    @Test func popoverFallsBackAboveWhenBelowDoesNotFit() {
        let visible = NSRect(x: 0, y: 0, width: 1000, height: 700)
        let anchor = NSRect(x: 100, y: 20, width: 40, height: 22)
        let origin = StatusItemController.popoverOrigin(anchor: anchor,
                                                        size: NSSize(width: 300, height: 200),
                                                        visible: visible)
        #expect(origin.y == 48) // anchor.maxY + gap
    }

    @Test func popoverClampsHorizontallyToScreen() {
        let visible = NSRect(x: 0, y: 0, width: 1000, height: 700)
        let anchor = NSRect(x: 990, y: 700, width: 20, height: 22)
        let origin = StatusItemController.popoverOrigin(anchor: anchor,
                                                        size: NSSize(width: 300, height: 200),
                                                        visible: visible)
        #expect(origin.x == 692) // visible.maxX - width - margin
    }

    @Test func popoverFrameStaysInsideNarrowScreen() {
        let visible = NSRect(x: 1440, y: 0, width: 320, height: 240)
        let anchor = NSRect(x: 1740, y: 240, width: 20, height: 22)
        let frame = StatusItemController.popoverFrame(anchor: anchor,
                                                      size: NSSize(width: 400, height: 300),
                                                      visible: visible)
        #expect(frame.minX >= visible.minX + 8)
        #expect(frame.maxX <= visible.maxX - 8)
        #expect(frame.minY >= visible.minY + 8)
        #expect(frame.maxY <= visible.maxY - 8)
    }

    @Test func clampedFrameMovesVisiblePanelBackOnScreen() {
        let visible = NSRect(x: 0, y: 0, width: 1000, height: 700)
        let offscreen = NSRect(x: 820, y: 200, width: 360, height: 300)
        let frame = StatusItemController.clampedFrame(offscreen, visible: visible)
        #expect(frame.maxX == visible.maxX - 8)
        #expect(frame.minX >= visible.minX + 8)
        #expect(frame.minY == offscreen.minY)
    }

    @Test @MainActor func popoverSizeDoesNotCollapseWhenFittingHeightIsUnavailable() {
        let size = StatusItemController.popoverSize(fitting: .zero, width: MetricPanel.panelWidth)
        #expect(size.width == MetricPanel.panelWidth)
        #expect(size.height == 300)
    }
}

@Suite struct HistoryStatsTests {
    @Test func peakAndMeanOverSeries() {
        let series = [0.2, 0.5, 0.8, 0.1]
        #expect(series.peak == 0.8)
        #expect(abs(series.mean - 0.4) < 0.0001)
    }

    @Test func emptySeriesIsZero() {
        let empty: [Double] = []
        #expect(empty.peak == 0)
        #expect(empty.mean == 0)
    }
}

@Suite struct MemorySampleTests {
    @Test func usageFraction() {
        let s = MemorySample(total: 1000, used: 250, free: 750, app: 100, wired: 100,
                             compressed: 50, cached: 0, pressure: .normal,
                             swapTotal: 0, swapUsed: 0)
        #expect(s.usage == 0.25)
    }

    @Test func zeroTotalIsSafe() {
        let s = MemorySample(total: 0, used: 0, free: 0, app: 0, wired: 0,
                             compressed: 0, cached: 0, pressure: .normal,
                             swapTotal: 0, swapUsed: 0)
        #expect(s.usage == 0.0)
    }
}

// MARK: - MetricsEngine lifecycle

@MainActor
final class SnapshotRecorder {
    private(set) var snapshots: [MetricsSnapshot] = []
    var count: Int { snapshots.count }
    func record(_ snapshot: MetricsSnapshot) { snapshots.append(snapshot) }
}

@Suite struct MetricsEngineTests {
    private func makeCollectors() -> MetricCollectors {
        MetricCollectors(
            cpu: { CPUSample(total: 0.5, system: 0.2, user: 0.3, idle: 0.5, perCore: []) },
            gpu: { GPUSample(name: "Test GPU", utilization: 0.3) },
            memory: { MemorySample(total: 1_000_000_000, used: 500_000_000, free: 500_000_000,
                                   app: 200_000_000, wired: 100_000_000, compressed: 50_000_000,
                                   cached: 150_000_000, pressure: .normal, swapTotal: 0, swapUsed: 0) },
            network: { NetworkSample(interface: "en0", uploadBytesPerSec: 100, downloadBytesPerSec: 200,
                                     totalUploaded: 1000, totalDownloaded: 2000) }
        )
    }

    @Test @MainActor func startPublishesSnapshots() async throws {
        let recorder = SnapshotRecorder()
        let engine = MetricsEngine(interval: 0.1, enabledMetrics: [.cpu], collectors: makeCollectors()) {
            recorder.record($0)
        }
        engine.start()
        try await Task.sleep(for: .milliseconds(450))
        engine.stop()
        try await Task.sleep(for: .milliseconds(50))
        #expect(recorder.count >= 2)
    }

    @Test @MainActor func stopHaltsPublishing() async throws {
        let recorder = SnapshotRecorder()
        let engine = MetricsEngine(interval: 0.1, enabledMetrics: [.cpu], collectors: makeCollectors()) {
            recorder.record($0)
        }
        engine.start()
        try await Task.sleep(for: .milliseconds(350))
        engine.stop()
        try await Task.sleep(for: .milliseconds(100))
        let countAfterStop = recorder.count
        try await Task.sleep(for: .milliseconds(400))
        #expect(recorder.count == countAfterStop)
        #expect(countAfterStop >= 1)
    }

    @Test @MainActor func pauseStopsAndResumeRestoresPublishing() async throws {
        let recorder = SnapshotRecorder()
        let engine = MetricsEngine(interval: 0.1, enabledMetrics: [.cpu], collectors: makeCollectors()) {
            recorder.record($0)
        }
        engine.start()
        try await Task.sleep(for: .milliseconds(350))
        #expect(recorder.count >= 1)

        engine.setPaused(true)
        try await Task.sleep(for: .milliseconds(100))
        let countWhilePaused = recorder.count
        try await Task.sleep(for: .milliseconds(400))
        #expect(recorder.count == countWhilePaused)

        engine.setPaused(false)
        try await Task.sleep(for: .milliseconds(400))
        #expect(recorder.count > countWhilePaused)
        engine.stop()
    }

    @Test @MainActor func emptyEnabledMetricsDoesNotPublish() async throws {
        let recorder = SnapshotRecorder()
        let engine = MetricsEngine(interval: 0.1, enabledMetrics: [], collectors: makeCollectors()) {
            recorder.record($0)
        }
        engine.start()
        try await Task.sleep(for: .milliseconds(400))
        #expect(recorder.count == 0)
        engine.stop()
    }

    @Test @MainActor func disablingAllMetricsStopsPublishing() async throws {
        let recorder = SnapshotRecorder()
        let engine = MetricsEngine(interval: 0.1, enabledMetrics: [.cpu], collectors: makeCollectors()) {
            recorder.record($0)
        }
        engine.start()
        try await Task.sleep(for: .milliseconds(350))
        #expect(recorder.count >= 1)

        engine.setEnabledMetrics([])
        try await Task.sleep(for: .milliseconds(100))
        let countAfterDisable = recorder.count
        try await Task.sleep(for: .milliseconds(400))
        #expect(recorder.count == countAfterDisable)
        engine.stop()
    }

    @Test @MainActor func setIntervalChangesCadence() async throws {
        let recorder = SnapshotRecorder()
        let engine = MetricsEngine(interval: 0.5, enabledMetrics: [.cpu], collectors: makeCollectors()) {
            recorder.record($0)
        }
        engine.start()
        try await Task.sleep(for: .milliseconds(300))
        #expect(recorder.count == 0)

        engine.setInterval(0.05)
        try await Task.sleep(for: .milliseconds(500))
        #expect(recorder.count >= 2)
        engine.stop()
    }

    @Test @MainActor func onlyEnabledMetricsArePublished() async throws {
        let recorder = SnapshotRecorder()
        let engine = MetricsEngine(interval: 0.1, enabledMetrics: [.cpu], collectors: makeCollectors()) {
            recorder.record($0)
        }
        engine.start()
        try await Task.sleep(for: .milliseconds(350))
        engine.stop()
        try await Task.sleep(for: .milliseconds(50))
        #expect(!recorder.snapshots.isEmpty)
        #expect(recorder.snapshots.allSatisfy { $0.cpu != nil })
        #expect(recorder.snapshots.allSatisfy { $0.gpu == nil })
    }

    @Test @MainActor func reEnablingMetricsResumesPublishing() async throws {
        let recorder = SnapshotRecorder()
        let engine = MetricsEngine(interval: 0.1, enabledMetrics: [.cpu], collectors: makeCollectors()) {
            recorder.record($0)
        }
        engine.start()
        try await Task.sleep(for: .milliseconds(350))
        let countAfterFirstRun = recorder.count
        #expect(countAfterFirstRun >= 1)

        engine.setEnabledMetrics([])
        try await Task.sleep(for: .milliseconds(300))
        engine.setEnabledMetrics([.cpu])
        try await Task.sleep(for: .milliseconds(350))
        #expect(recorder.count > countAfterFirstRun)
        engine.stop()
    }
}
