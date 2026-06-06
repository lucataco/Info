import Foundation
import IOKit

/// Reads GPU utilization from the IORegistry `IOAccelerator` entries'
/// `PerformanceStatistics` dictionary.
///
/// Unlike Stats, missing keys are handled **silently** — Stats logged an error
/// per accelerator per second when a key was absent, which is a major source of
/// its log spam. Confined to `MetricsEngine.queue`.
final class GPUCollector {
    func sample() -> GPUSample? {
        guard let matching = IOServiceMatching("IOAccelerator") else { return nil }
        var iterator = io_iterator_t()
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS
        else { return nil }
        defer { IOObjectRelease(iterator) }

        var best: GPUSample?
        var service = IOIteratorNext(iterator)
        while service != 0 {
            let current = service
            defer {
                IOObjectRelease(current)
                service = IOIteratorNext(iterator)
            }

            guard let perf = property(current, "PerformanceStatistics") as? [String: Any] else {
                continue
            }

            guard let utilPercent = intValue(perf["Device Utilization %"])
                ?? intValue(perf["GPU Activity(%)"]) else { continue }

            let candidate = GPUSample(
                name: name(for: current),
                utilization: clamp01(Double(utilPercent) / 100),
                renderUtilization: intValue(perf["Renderer Utilization %"]).map { clamp01(Double($0) / 100) },
                tilerUtilization: intValue(perf["Tiler Utilization %"]).map { clamp01(Double($0) / 100) }
            )

            // Prefer the busiest accelerator (handles multi-GPU sensibly).
            if best == nil || candidate.utilization > (best?.utilization ?? 0) {
                best = candidate
            }
        }
        return best
    }

    // MARK: - Helpers

    private func name(for entry: io_registry_entry_t) -> String {
        var resolved = "GPU"
        if let data = IORegistryEntrySearchCFProperty(
            entry, kIOServicePlane, "model" as CFString, kCFAllocatorDefault,
            IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents)
        ) {
            if let d = data as? Data,
               let s = String(data: d, encoding: .utf8)?.trimmingCharacters(in: CharacterSet(charactersIn: "\0 ")),
               !s.isEmpty {
                resolved = s
            } else if let s = data as? String, !s.isEmpty {
                resolved = s
            }
        }
        return resolved
    }

    private func property(_ entry: io_registry_entry_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue()
    }

    private func intValue(_ any: Any?) -> Int? {
        (any as? NSNumber)?.intValue
    }

    private func clamp01(_ v: Double) -> Double { min(1, max(0, v)) }
}
