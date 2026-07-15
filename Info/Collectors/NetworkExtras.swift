import Observation
import Foundation

/// Public IP lookup — **opt-in, on-demand, cached**. Unlike Stats (which calls
/// the author's server on by default), this is off by default and uses a
/// well-known generic echo endpoint only when the user turns it on.
enum PublicIP {
    static let defaultEndpoint = "https://api.ipify.org"

    static func fetch(from endpoint: String = defaultEndpoint) async -> String? {
        guard let url = URL(string: endpoint) else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let text = String(data: data, encoding: .utf8)?
                  .trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty, text.count < 64 else { return nil }
        return text
    }
}

/// Connectivity latency — opt-in, measured with a lightweight HEAD request only
/// while the Network panel is open (no constant background pings).
enum Connectivity {
    static let defaultHost = "https://captive.apple.com"

    static func latencyMs(host: String = defaultHost) async -> Double? {
        guard let url = URL(string: host) else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 5
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let start = Date()
        guard let (_, response) = try? await URLSession.shared.data(for: request),
              response is HTTPURLResponse else { return nil }
        return Date().timeIntervalSince(start) * 1000
    }
}

/// Drives the optional Network panel extras while it's visible.
@MainActor
@Observable
final class NetworkExtrasModel {
    var publicIP: String?
    var latencyMs: Double?
    /// True once a public-IP fetch attempt has finished — lets the UI show
    /// "Unavailable" on failure instead of an eternal "…".
    var publicIPChecked = false
    /// True once a latency measurement attempt has finished.
    var latencyChecked = false

    private var task: Task<Void, Never>?
    private var generation = 0

    deinit { MainActor.assumeIsolated { task?.cancel() } }

    func start(showIP: Bool, showLatency: Bool) {
        guard task == nil, showIP || showLatency else { return }
        publicIPChecked = false
        latencyChecked = false
        generation += 1
        let generation = self.generation
        task = Task { [weak self] in
            defer {
                Task { @MainActor in
                    guard self?.generation == generation else { return }
                    self?.task = nil
                }
            }
            if showIP {
                let ip = await PublicIP.fetch()
                if Task.isCancelled { return }
                self?.publicIP = ip
                self?.publicIPChecked = true
            }
            while !Task.isCancelled && showLatency {
                let latency = await Connectivity.latencyMs()
                if Task.isCancelled { return }
                self?.latencyMs = latency
                self?.latencyChecked = true
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    func stop() {
        generation += 1
        task?.cancel()
        task = nil
    }
}
