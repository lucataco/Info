import Foundation

// MARK: - Per-metric samples (all Sendable value types)

struct CPUSample: Sendable, Equatable {
    /// Overall busy fraction 0...1 (user + system + nice).
    var total: Double
    var system: Double
    var user: Double
    var idle: Double
    /// Per-logical-core busy fraction 0...1.
    var perCore: [Double]
}

enum MemoryPressure: Sendable, Equatable {
    case normal, warning, critical
}

struct MemorySample: Sendable, Equatable {
    var total: UInt64
    var used: UInt64
    var free: UInt64
    var app: UInt64
    var wired: UInt64
    var compressed: UInt64
    var cached: UInt64
    var pressure: MemoryPressure
    var swapTotal: UInt64
    var swapUsed: UInt64

    var usage: Double { total > 0 ? Double(used) / Double(total) : 0 }
}

struct GPUSample: Sendable, Equatable {
    var name: String
    /// Device utilization 0...1.
    var utilization: Double
    var renderUtilization: Double?
    var tilerUtilization: Double?
}

struct NetworkSample: Sendable, Equatable {
    var interface: String?
    var uploadBytesPerSec: UInt64
    var downloadBytesPerSec: UInt64
    /// Cumulative bytes observed since launch.
    var totalUploaded: UInt64
    var totalDownloaded: UInt64
}

/// One tick's worth of all metrics. Any field may be nil if that collector
/// could not produce a value this tick (e.g. first sample, missing hardware).
struct MetricsSnapshot: Sendable {
    var cpu: CPUSample?
    var memory: MemorySample?
    var gpu: GPUSample?
    var network: NetworkSample?
}

// MARK: - Pure math (unit-testable, no system calls)

enum CPUMath {
    /// Busy fraction (0...1) from a delta of cumulative CPU ticks.
    static func busyFraction(user: Double, system: Double, idle: Double, nice: Double) -> Double {
        let total = user + system + idle + nice
        guard total > 0 else { return 0 }
        return min(1, max(0, (user + system + nice) / total))
    }
}
