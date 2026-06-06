import Foundation

/// The four metrics Info can show. Drives ordering, labels, and SF Symbols.
enum MetricKind: String, CaseIterable, Sendable, Identifiable {
    case cpu, gpu, memory, network

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cpu: return "CPU"
        case .gpu: return "GPU"
        case .memory: return "Memory"
        case .network: return "Network"
        }
    }

    /// 3-letter fallback label drawn when the SF Symbol is unavailable.
    var shortLabel: String {
        switch self {
        case .cpu: return "CPU"
        case .gpu: return "GPU"
        case .memory: return "MEM"
        case .network: return "NET"
        }
    }

    /// Best-effort SF Symbol; the view falls back to `shortLabel` if it can't
    /// be resolved on this OS.
    var symbolName: String {
        switch self {
        case .cpu: return "cpu"
        case .gpu: return "square.grid.3x3.fill" // no "gpu" SF Symbol exists
        case .memory: return "memorychip"
        case .network: return "chart.bar.fill"
        }
    }

    var isMirrored: Bool { self == .network }
}
