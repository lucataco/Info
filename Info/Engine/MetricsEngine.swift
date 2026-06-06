import Foundation

/// Collectors are injected so the engine's enabled-metric gating can be tested
/// without touching Mach/IOKit/network APIs.
struct MetricCollectors {
    var cpu: () -> CPUSample?
    var gpu: () -> GPUSample?
    var memory: () -> MemorySample?
    var network: () -> NetworkSample?

    static func live() -> MetricCollectors {
        let cpu = CPUCollector()
        let gpu = GPUCollector()
        let memory = MemoryCollector()
        let network = NetworkCollector()
        return MetricCollectors(
            cpu: { cpu.sample() },
            gpu: { gpu.sample() },
            memory: { memory.sample() },
            network: { network.sample() }
        )
    }

    func sample(enabledMetrics: Set<MetricKind>) -> MetricsSnapshot {
        MetricsSnapshot(
            enabledMetrics: enabledMetrics,
            cpu: enabledMetrics.contains(.cpu) ? cpu() : nil,
            memory: enabledMetrics.contains(.memory) ? memory() : nil,
            gpu: enabledMetrics.contains(.gpu) ? gpu() : nil,
            network: enabledMetrics.contains(.network) ? network() : nil
        )
    }
}

/// Drives all sampling from a single coalesced timer.
///
/// Concurrency model: every access to the collectors and timer happens on the
/// private serial `queue`. That invariant is what makes this `@unchecked
/// Sendable` safe — the collectors hold mutable delta state but are only ever
/// touched on `queue`. Publishing hops to the main actor.
///
/// This is the single biggest power lever vs. Stats: one timer for all four
/// cheap metrics (not one timer per reader per module), `.utility` QoS, and a
/// generous leeway so the OS can coalesce our wakeups with everyone else's.
final class MetricsEngine: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.info.app.sampling", qos: .utility)

    private let collectors: MetricCollectors

    private var timer: DispatchSourceTimer?
    private var interval: TimeInterval
    private var paused = false
    private var enabledMetrics: Set<MetricKind>

    private let publish: @MainActor @Sendable (MetricsSnapshot) -> Void

    init(interval: TimeInterval,
         enabledMetrics: [MetricKind] = MetricKind.allCases,
         collectors: MetricCollectors = .live(),
         publish: @escaping @MainActor @Sendable (MetricsSnapshot) -> Void) {
        self.interval = interval
        self.enabledMetrics = Set(enabledMetrics)
        self.collectors = collectors
        self.publish = publish
    }

    func start() {
        queue.async { [weak self] in
            guard let self, self.timer == nil else { return }
            self.updateTimer(wasActive: false, primeOnStart: true)
            Log.engine.info("Sampling started at \(self.interval, format: .fixed(precision: 1))s")
        }
    }

    func stop() {
        queue.async { [weak self] in
            self?.timer?.cancel()
            self?.timer = nil
        }
    }

    /// Pause/resume sampling for sleep / screen-lock / occlusion gating.
    func setPaused(_ value: Bool) {
        queue.async { [weak self] in
            guard let self else { return }
            let wasActive = self.isActive
            self.paused = value
            self.updateTimer(wasActive: wasActive, primeOnStart: true)
            Log.engine.debug("paused=\(value)")
        }
    }

    func setInterval(_ newValue: TimeInterval) {
        queue.async { [weak self] in
            guard let self else { return }
            self.interval = newValue
            if self.timer != nil { self.installTimer() }
        }
    }

    func setEnabledMetrics(_ metrics: [MetricKind]) {
        queue.async { [weak self] in
            guard let self else { return }
            let wasActive = self.isActive
            self.enabledMetrics = Set(metrics)
            self.updateTimer(wasActive: wasActive, primeOnStart: true)
        }
    }

    // MARK: - Private (all on `queue`)

    private func installTimer() {
        timer?.cancel()
        let t = DispatchSource.makeTimerSource(queue: queue)
        let leewayMs = Int(max(0.05, interval * 0.15) * 1000)
        t.schedule(deadline: .now() + interval,
                   repeating: interval,
                   leeway: .milliseconds(leewayMs))
        t.setEventHandler { [weak self] in self?.tick() }
        timer = t
        t.resume()
    }

    private func tick() {
        guard !paused, !enabledMetrics.isEmpty else { return }
        let state = Log.signposter.beginInterval("sample")
        let snapshot = sampleAll()
        Log.signposter.endInterval("sample", state)
        let publish = self.publish
        Task { @MainActor in publish(snapshot) }
    }

    private func sampleAll() -> MetricsSnapshot {
        collectors.sample(enabledMetrics: enabledMetrics)
    }

    private var isActive: Bool { !paused && !enabledMetrics.isEmpty }

    private func cancelTimer() {
        timer?.cancel()
        timer = nil
    }

    private func updateTimer(wasActive: Bool, primeOnStart: Bool) {
        guard isActive else {
            cancelTimer()
            return
        }

        if primeOnStart {
            _ = sampleAll()
        }

        if !wasActive || timer == nil {
            installTimer()
        }
    }
}
