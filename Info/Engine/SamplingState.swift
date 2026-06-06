import Observation

/// The single source of truth the UI reads from. Lives on the main actor.
///
/// SwiftUI panels observe it via the Observation framework; the AppKit status
/// items refresh via the `onUpdate` hook (AppKit views don't auto-observe).
@MainActor
@Observable
final class SamplingState {
    let historyLength: Int

    var cpu: CPUSample?
    var memory: MemorySample?
    var gpu: GPUSample?
    var network: NetworkSample?

    var cpuHistory: RingBuffer<Double>
    var memoryHistory: RingBuffer<Double>
    var gpuHistory: RingBuffer<Double>
    var netUpHistory: RingBuffer<Double>
    var netDownHistory: RingBuffer<Double>

    /// Non-observed callback for AppKit consumers (status item redraws).
    @ObservationIgnored var onUpdate: (() -> Void)?

    init(historyLength: Int = 60) {
        self.historyLength = historyLength
        self.cpuHistory = RingBuffer(capacity: historyLength)
        self.memoryHistory = RingBuffer(capacity: historyLength)
        self.gpuHistory = RingBuffer(capacity: historyLength)
        self.netUpHistory = RingBuffer(capacity: historyLength)
        self.netDownHistory = RingBuffer(capacity: historyLength)
    }

    func ingest(_ snapshot: MetricsSnapshot) {
        if snapshot.enabledMetrics.contains(.cpu) {
            cpu = snapshot.cpu
            if let c = snapshot.cpu { cpuHistory.append(c.total) } else { cpuHistory.removeAll() }
        }
        if snapshot.enabledMetrics.contains(.memory) {
            memory = snapshot.memory
            if let m = snapshot.memory { memoryHistory.append(m.usage) } else { memoryHistory.removeAll() }
        }
        if snapshot.enabledMetrics.contains(.gpu) {
            gpu = snapshot.gpu
            if let g = snapshot.gpu { gpuHistory.append(g.utilization) } else { gpuHistory.removeAll() }
        }
        if snapshot.enabledMetrics.contains(.network) {
            network = snapshot.network
            if let n = snapshot.network {
                netUpHistory.append(Double(n.uploadBytesPerSec))
                netDownHistory.append(Double(n.downloadBytesPerSec))
            } else {
                netUpHistory.removeAll()
                netDownHistory.removeAll()
            }
        }
        onUpdate?()
    }
}
