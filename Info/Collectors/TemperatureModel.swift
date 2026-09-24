import Foundation
import Observation

enum TemperatureAvailability: Sendable, Equatable {
    case idle
    case loading
    case available
    case unavailable
}

@MainActor
@Observable
final class TemperatureModel {
    var celsius: Double?
    var availability: TemperatureAvailability = .idle

    @ObservationIgnored nonisolated(unsafe) private var task: Task<Void, Never>?
    @ObservationIgnored nonisolated(unsafe) private var cancellation: CancellationToken?
    private let keys: [String]

    init(kind: MetricKind) {
        keys = kind == .gpu ? SMCConnection.gpuKeys : SMCConnection.cpuKeys
    }

    deinit {
        task?.cancel()
        cancellation?.cancel()
    }

    func start(enabled: Bool) {
        guard enabled, task == nil else { return }
        let keys = self.keys
        let cancellation = CancellationToken()
        self.cancellation = cancellation
        celsius = nil
        availability = .loading
        task = Task { [weak self, cancellation] in
            defer {
                Task { @MainActor [weak self] in
                    guard self?.cancellation === cancellation else { return }
                    self?.task = nil
                    self?.cancellation = nil
                }
            }
            var failures = 0
            while !Task.isCancelled && !cancellation.isCancelled {
                let value = await Self.read(keys: keys)
                guard !Task.isCancelled && !cancellation.isCancelled else { return }
                if let value {
                    self?.celsius = value
                    self?.availability = .available
                    failures = 0
                } else {
                    self?.celsius = nil
                    self?.availability = .unavailable
                    failures += 1
                    if failures >= 3 { return }
                }
                let delay = value == nil ? RetryBackoff.delay(failureCount: failures, base: 5) : 5
                try? await Task.sleep(for: .seconds(delay))
            }
        }
    }

    func stop() {
        cancellation?.cancel()
        task?.cancel()
        task = nil
        cancellation = nil
        celsius = nil
        availability = .idle
    }

    private static func read(keys: [String]) async -> Double? {
        await Task.detached(priority: .utility) {
            guard let smc = SMCConnection() else { return nil }
            defer { smc.close() }
            return smc.averageTemperature(keys: keys)
        }.value
    }
}
