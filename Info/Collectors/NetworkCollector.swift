import Foundation
import Darwin
import SystemConfiguration

/// Reads network throughput from `getifaddrs` byte counters (delta per tick) on
/// the primary interface reported by SystemConfiguration.
///
/// No external requests, no pings — that's all opt-in (Phase 7). Confined to
/// `MetricsEngine.queue`.
final class NetworkCollector {
    private var prevUpload: UInt64?
    private var prevDownload: UInt64?
    private var prevTimestamp: TimeInterval?
    private var prevInterface: String?
    private var totalUploaded: UInt64 = 0
    private var totalDownloaded: UInt64 = 0
    private var store: SCDynamicStore?  // cached; creating one per tick is wasteful

    func sample() -> NetworkSample? {
        let primary = primaryInterface()
        guard let counters = byteCounters(for: primary) else { return nil }
        let now = ProcessInfo.processInfo.systemUptime

        if prevInterface != primary {
            prevInterface = primary
            prevUpload = counters.upload
            prevDownload = counters.download
            prevTimestamp = now
            return NetworkSample(interface: primary,
                                 uploadBytesPerSec: 0,
                                 downloadBytesPerSec: 0,
                                 totalUploaded: totalUploaded,
                                 totalDownloaded: totalDownloaded)
        }

        defer {
            prevUpload = counters.upload
            prevDownload = counters.download
            prevTimestamp = now
            prevInterface = primary
        }

        guard let pUp = prevUpload, let pDown = prevDownload, let pTime = prevTimestamp else {
            return NetworkSample(interface: primary, uploadBytesPerSec: 0, downloadBytesPerSec: 0,
                                 totalUploaded: 0, totalDownloaded: 0)
        }

        let dt = now - pTime
        guard dt > 0 else { return nil }

        // Guard against counter wrap / interface change (negative delta).
        let upDelta = counters.upload >= pUp ? counters.upload - pUp : 0
        let downDelta = counters.download >= pDown ? counters.download - pDown : 0
        totalUploaded &+= upDelta
        totalDownloaded &+= downDelta

        return NetworkSample(
            interface: primary,
            uploadBytesPerSec: UInt64(Double(upDelta) / dt),
            downloadBytesPerSec: UInt64(Double(downDelta) / dt),
            totalUploaded: totalUploaded,
            totalDownloaded: totalDownloaded
        )
    }

    // MARK: - Helpers

    private func primaryInterface() -> String? {
        if store == nil {
            store = SCDynamicStoreCreate(nil, "com.info.app" as CFString, nil, nil)
        }
        guard let store else { return nil }

        // Prefer the IPv4 primary interface; fall back to IPv6.
        for key in ["State:/Network/Global/IPv4", "State:/Network/Global/IPv6"] as [CFString] {
            if let dict = SCDynamicStoreCopyValue(store, key) as? [String: Any],
               let interface = dict["PrimaryInterface"] as? String {
                return interface
            }
        }
        return nil
    }

    /// Sum tx/rx bytes. If `interface` is known, only that one; otherwise all
    /// non-loopback link-layer interfaces.
    private func byteCounters(for interface: String?) -> (upload: UInt64, download: UInt64)? {
        var addrs: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addrs) == 0 else { return nil }
        defer { freeifaddrs(addrs) }

        var upload: UInt64 = 0
        var download: UInt64 = 0
        var found = false

        var cursor = addrs
        while let entry = cursor {
            defer { cursor = entry.pointee.ifa_next }
            let name = String(cString: entry.pointee.ifa_name)
            if let interface, name != interface { continue }
            if interface == nil, Self.shouldSkipFallbackInterface(name) { continue }
            let flags = entry.pointee.ifa_flags
            guard flags & UInt32(IFF_UP) != 0,
                  flags & UInt32(IFF_RUNNING) != 0,
                  flags & UInt32(IFF_LOOPBACK) == 0 else { continue }
            guard let addr = entry.pointee.ifa_addr,
                  addr.pointee.sa_family == UInt8(AF_LINK),
                  let raw = entry.pointee.ifa_data else { continue }

            let data = raw.assumingMemoryBound(to: if_data.self).pointee
            upload &+= UInt64(data.ifi_obytes)
            download &+= UInt64(data.ifi_ibytes)
            found = true
        }
        return found ? (upload, download) : nil
    }

    private static func shouldSkipFallbackInterface(_ name: String) -> Bool {
        let noisyPrefixes = ["lo", "awdl", "llw", "utun", "ipsec", "bridge", "gif", "stf", "p2p"]
        return noisyPrefixes.contains { name.hasPrefix($0) }
    }
}
