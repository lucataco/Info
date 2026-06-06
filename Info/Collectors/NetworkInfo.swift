import Foundation
import Darwin

/// On-demand network details that are cheap and local (no external requests).
enum NetworkInfo {
    /// First non-loopback local address, preferring IPv4 and falling back to IPv6.
    static func localAddress(interface: String? = nil) -> String? {
        localIPv4(interface: interface) ?? localIPv6(interface: interface)
    }

    /// First non-loopback IPv4 address, or nil.
    static func localIPv4(interface: String? = nil) -> String? {
        localAddress(interface: interface, family: AF_INET)
    }

    /// First non-loopback IPv6 address, or nil.
    static func localIPv6(interface: String? = nil) -> String? {
        localAddress(interface: interface, family: AF_INET6)
    }

    private static func localAddress(interface: String?, family: Int32) -> String? {
        var addrs: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addrs) == 0 else { return nil }
        defer { freeifaddrs(addrs) }

        var cursor = addrs
        while let entry = cursor {
            defer { cursor = entry.pointee.ifa_next }
            let name = String(cString: entry.pointee.ifa_name)
            if name == "lo0" { continue }
            if let interface, name != interface { continue }
            guard let addr = entry.pointee.ifa_addr,
                  addr.pointee.sa_family == UInt8(family) else { continue }

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(addr, socklen_t(addr.pointee.sa_len),
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
