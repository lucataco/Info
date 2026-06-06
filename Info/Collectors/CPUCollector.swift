import Darwin

/// Reads CPU usage with cheap Mach calls only (no SMC, no shelling out).
///
/// - Aggregate user/system/idle via `host_statistics(HOST_CPU_LOAD_INFO)`.
/// - Per-core busy fraction via `host_processor_info(PROCESSOR_CPU_LOAD_INFO)`.
///
/// Confined to `MetricsEngine.queue`; not Sendable on purpose.
final class CPUCollector {
    private var prevAggregate: host_cpu_load_info?
    private var prevCoreTicks: [[Double]]?

    func sample() -> CPUSample? {
        let perCore = readPerCore() ?? []
        guard let aggregate = readAggregate() else { return nil }
        return CPUSample(
            total: aggregate.total,
            system: aggregate.system,
            user: aggregate.user,
            idle: aggregate.idle,
            perCore: perCore
        )
    }

    // MARK: - Aggregate

    private func readAggregate() -> (total: Double, system: Double, user: Double, idle: Double)? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride
        )
        let result = withUnsafeMutablePointer(to: &info) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        defer { prevAggregate = info }
        guard let prev = prevAggregate else { return nil }

        // cpu_ticks indices: 0=user 1=system 2=idle 3=nice
        let user = Double(info.cpu_ticks.0) - Double(prev.cpu_ticks.0)
        let system = Double(info.cpu_ticks.1) - Double(prev.cpu_ticks.1)
        let idle = Double(info.cpu_ticks.2) - Double(prev.cpu_ticks.2)
        let nice = Double(info.cpu_ticks.3) - Double(prev.cpu_ticks.3)
        let totalTicks = user + system + idle + nice
        guard totalTicks > 0 else { return nil }

        let busy = CPUMath.busyFraction(user: user, system: system, idle: idle, nice: nice)
        return (
            total: busy,
            system: system / totalTicks,
            user: (user + nice) / totalTicks,
            idle: idle / totalTicks
        )
    }

    // MARK: - Per core

    private func readPerCore() -> [Double]? {
        var cpuCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0

        let result = host_processor_info(
            mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &cpuCount, &info, &infoCount
        )
        guard result == KERN_SUCCESS, let info else { return nil }
        defer {
            let raw = UnsafeMutableRawPointer(info)
            vm_deallocate(
                mach_task_self_,
                vm_address_t(UInt(bitPattern: raw)),
                vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.stride)
            )
        }

        let buffer = UnsafeBufferPointer(start: info, count: Int(infoCount))
        let stateCount = Int(CPU_STATE_MAX)
        var current: [[Double]] = []
        current.reserveCapacity(Int(cpuCount))

        for core in 0..<Int(cpuCount) {
            let base = core * stateCount
            guard base + stateCount <= buffer.count else { break }
            current.append([
                Double(buffer[base + Int(CPU_STATE_USER)]),
                Double(buffer[base + Int(CPU_STATE_SYSTEM)]),
                Double(buffer[base + Int(CPU_STATE_IDLE)]),
                Double(buffer[base + Int(CPU_STATE_NICE)]),
            ])
        }

        defer { prevCoreTicks = current }
        guard let prev = prevCoreTicks, prev.count == current.count else { return nil }

        return zip(prev, current).map { p, c in
            CPUMath.busyFraction(
                user: c[0] - p[0],
                system: c[1] - p[1],
                idle: c[2] - p[2],
                nice: c[3] - p[3]
            )
        }
    }
}
