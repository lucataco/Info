import Darwin

/// Reads memory usage via `host_statistics64` + `sysctl`. No disk, no SMC.
/// Confined to `MetricsEngine.queue`.
final class MemoryCollector {
    private let totalBytes: UInt64 = {
        var size: UInt64 = 0
        var len = MemoryLayout<UInt64>.size
        sysctlbyname("hw.memsize", &size, &len, nil, 0)
        return size
    }()

    /// Page size fetched once via the (concurrency-safe) host_page_size call,
    /// rather than the non-Sendable `vm_kernel_page_size` global.
    private let pageSize: UInt64 = {
        var ps: vm_size_t = 0
        host_page_size(mach_host_self(), &ps)
        return ps > 0 ? UInt64(ps) : 16384
    }()

    func sample() -> MemorySample? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride
        )
        let result = withUnsafeMutablePointer(to: &stats) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS, totalBytes > 0 else { return nil }

        let page = pageSize
        let internalPages = UInt64(stats.internal_page_count) * page
        let freePages = UInt64(stats.free_count) * page
        let speculative = UInt64(stats.speculative_count) * page
        let wired = UInt64(stats.wire_count) * page
        let compressed = UInt64(stats.compressor_page_count) * page
        let purgeable = UInt64(stats.purgeable_count) * page
        let external = UInt64(stats.external_page_count) * page

        // Activity Monitor's top-line "Memory Used" is closest to app + wired + compressed.
        let app = internalPages > purgeable ? internalPages - purgeable : 0
        let used = min(totalBytes, app + wired + compressed)
        let remaining = totalBytes > used ? totalBytes - used : 0
        let cache = min(external + purgeable, remaining)
        let free = min(freePages + speculative, remaining > cache ? remaining - cache : 0)
        let swap = swapUsage()

        return MemorySample(
            total: totalBytes,
            used: used,
            free: free,
            app: app,
            wired: wired,
            compressed: compressed,
            cached: cache,
            pressure: readPressure(),
            swapTotal: swap.total,
            swapUsed: swap.used
        )
    }

    private func readPressure() -> MemoryPressure {
        var level: Int32 = 0
        var len = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &len, nil, 0) == 0 else {
            return .normal
        }
        switch level {
        case 4: return .critical
        case 2: return .warning
        default: return .normal
        }
    }

    private func swapUsage() -> (total: UInt64, used: UInt64) {
        var usage = xsw_usage()
        var len = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &usage, &len, nil, 0) == 0 else { return (0, 0) }
        return (usage.xsu_total, usage.xsu_used)
    }
}
