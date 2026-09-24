import Foundation
import Darwin

@MainActor
enum NetworkInfo {
    private struct CacheEntry {
        let value: String?
        let storedAt: Date
    }

    private static var cache: [String: CacheEntry] = [:]
    private static let cacheLifetime: TimeInterval = 30

    static func localAddress(interface: String? = nil) -> String? {
        let key = interface ?? "*"
        let now = Date()
        if let entry = cache[key], now.timeIntervalSince(entry.storedAt) < cacheLifetime {
            return entry.value
        }

        let value = localIPv4(interface: interface) ?? localIPv6(interface: interface)
        if let value {
            cache[key] = CacheEntry(value: value, storedAt: now)
        }
        return value
    }

    static func localIPv4(interface: String? = nil) -> String? {
        localAddress(interface: interface, family: AF_INET)
    }

    static func localIPv6(interface: String? = nil) -> String? {
        localAddress(interface: interface, family: AF_INET6)
    }

    private static func localAddress(interface: String?, family: Int32) -> String? {
        var addresses: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addresses) == 0 else { return nil }
        defer { freeifaddrs(addresses) }

        var cursor = addresses
        while let entry = cursor {
            defer { cursor = entry.pointee.ifa_next }
            let name = String(cString: entry.pointee.ifa_name)
            if name == "lo0" { continue }
            if let interface, name != interface { continue }
            guard let address = entry.pointee.ifa_addr,
                  address.pointee.sa_family == UInt8(family) else { continue }

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(address, socklen_t(address.pointee.sa_len),
                                     &host, socklen_t(host.count),
                                     nil, 0, NI_NUMERICHOST)
            if result == 0 {
                let ip = host.withUnsafeBufferPointer { buffer -> String in
                    buffer.baseAddress.map { String(cString: $0) } ?? ""
                }
                if !ip.isEmpty, !ip.hasPrefix("fe80:") { return ip }
            }
        }
        return nil
    }
}
