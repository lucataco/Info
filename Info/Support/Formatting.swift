import Foundation

/// Compact formatting helpers for the menu bar and panels.
enum Fmt {
    /// e.g. 0.234 -> "23%"
    static func percent(_ fraction: Double) -> String {
        guard fraction.isFinite else { return "—" }
        let clamped = min(1, max(0, fraction))
        return "\(Int((clamped * 100).rounded()))%"
    }

    /// Binary byte size, e.g. 1536 -> "1.5 KB"
    static func bytes(_ value: UInt64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB", "PB"]
        var v = Double(value)
        var i = 0
        while v >= 1024 && i < units.count - 1 {
            v /= 1024
            i += 1
        }
        if i == 0 { return "\(Int(v)) \(units[i])" }
        return String(format: "%.1f %@", v, units[i])
    }

    /// Byte rate, e.g. "1.5 MB/s"
    static func rate(_ bytesPerSec: UInt64) -> String {
        bytes(bytesPerSec) + "/s"
    }

    /// Short byte rate for the menu bar, e.g. "1.5M" (no unit suffix noise).
    static func rateShort(_ bytesPerSec: UInt64) -> String {
        let units = ["B", "K", "M", "G", "T"]
        var v = Double(bytesPerSec)
        var i = 0
        while v >= 1024 && i < units.count - 1 {
            v /= 1024
            i += 1
        }
        if i == 0 { return "\(Int(v))\(units[i])" }
        if v >= 100 { return "\(Int(v))\(units[i])" }
        return String(format: "%.1f%@", v, units[i])
    }
}
