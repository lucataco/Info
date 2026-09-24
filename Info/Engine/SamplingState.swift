import Foundation
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

    var cpuStatus: MetricStatus = .loading
    var memoryStatus: MetricStatus = .loading
    var gpuStatus: MetricStatus = .loading
    var networkStatus: MetricStatus = .loading

    var cpuHistory: RingBuffer<HistoryPoint>
    var memoryHistory: RingBuffer<HistoryPoint>
    var gpuHistory: RingBuffer<HistoryPoint>
    var netUpHistory: RingBuffer<HistoryPoint>
    var netDownHistory: RingBuffer<HistoryPoint>

    var cpuValues: [Double] { cpuHistory.values.map(\.value) }
    var memoryValues: [Double] { memoryHistory.values.map(\.value) }
    var gpuValues: [Double] { gpuHistory.values.map(\.value) }
    var netUpValues: [Double] { netUpHistory.values.map(\.value) }
    var netDownValues: [Double] { netDownHistory.values.map(\.value) }

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

    func setEnabledMetrics(_ metrics: [MetricKind]) {
        let enabled = Set(metrics)
        if !enabled.contains(.cpu) {
            cpu = nil
            cpuStatus = .disabled
            cpuHistory.removeAll()
        }
        if !enabled.contains(.memory) {
            memory = nil
            memoryStatus = .disabled
            memoryHistory.removeAll()
        }
        if !enabled.contains(.gpu) {
            gpu = nil
            gpuStatus = .disabled
            gpuHistory.removeAll()
        }
        if !enabled.contains(.network) {
            network = nil
            networkStatus = .disabled
            netUpHistory.removeAll()
            netDownHistory.removeAll()
        }
        onUpdate?()
    }

    func ingest(_ snapshot: MetricsSnapshot) {
        updateMetric(snapshot.cpu,
                     enabled: snapshot.enabledMetrics.contains(.cpu),
                     current: &cpu,
                     status: &cpuStatus,
                     history: &cpuHistory,
                     timestamp: snapshot.timestamp) { $0.total }

        updateMetric(snapshot.memory,
                     enabled: snapshot.enabledMetrics.contains(.memory),
                     current: &memory,
                     status: &memoryStatus,
                     history: &memoryHistory,
                     timestamp: snapshot.timestamp) { $0.usage }

        updateMetric(snapshot.gpu,
                     enabled: snapshot.enabledMetrics.contains(.gpu),
                     current: &gpu,
                     status: &gpuStatus,
                     history: &gpuHistory,
                     timestamp: snapshot.timestamp) { $0.utilization }

        if !snapshot.enabledMetrics.contains(.network) {
            network = nil
            networkStatus = .disabled
            netUpHistory.removeAll()
            netDownHistory.removeAll()
        } else if let networkSample = snapshot.network {
            network = networkSample
            networkStatus = .live(at: snapshot.timestamp)
            netUpHistory.append(HistoryPoint(value: Double(networkSample.uploadBytesPerSec),
                                             timestamp: snapshot.timestamp))
            netDownHistory.append(HistoryPoint(value: Double(networkSample.downloadBytesPerSec),
                                               timestamp: snapshot.timestamp))
        } else if network == nil {
            networkStatus = .unavailable
        } else {
            networkStatus = .stale(since: networkStatus.updatedAt)
        }

        onUpdate?()
    }

    private func updateMetric<Value>(
        _ value: Value?,
        enabled: Bool,
        current: inout Value?,
        status: inout MetricStatus,
        history: inout RingBuffer<HistoryPoint>,
        timestamp: Date,
        valueForHistory: (Value) -> Double
    ) {
        guard enabled else {
            current = nil
            status = .disabled
            history.removeAll()
            return
        }

        if let value {
            current = value
            status = .live(at: timestamp)
            history.append(HistoryPoint(value: valueForHistory(value), timestamp: timestamp))
        } else if current == nil {
            status = .unavailable
        } else {
            status = .stale(since: status.updatedAt)
        }
    }
}
