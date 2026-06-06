import Observation
import Foundation

/// On-demand CPU/GPU temperature via the SMC. Default OFF; only runs while a
/// panel is visible AND the user enabled temperature in settings, at a slow 5s
/// cadence. This keeps the one power-hungry path (SMC) cold by default.
@MainActor
@Observable
final class TemperatureModel {
    var celsius: Double?

    private var task: Task<Void, Never>?
    private let keys: [String]

    init(kind: MetricKind) {
        keys = kind == .gpu ? SMCConnection.gpuKeys : SMCConnection.cpuKeys
    }

    deinit { MainActor.assumeIsolated { task?.cancel() } }

    func start(enabled: Bool) {
        guard enabled, task == nil else { return }
        let keys = self.keys
        task = Task { [weak self] in
            while !Task.isCancelled {
                let value = await Self.read(keys: keys)
                if Task.isCancelled { return }
                self?.celsius = value
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    private static func read(keys: [String]) async -> Double? {
        await Task.detached(priority: .utility) {
            guard let smc = SMCConnection() else { return nil }
            defer { smc.close() }
            return smc.averageTemperature(keys: keys)
        }.value
    }
}
