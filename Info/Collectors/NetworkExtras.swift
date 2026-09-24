import Foundation
import Observation
import Darwin

enum PublicIP {
    static let defaultEndpoint = "https://api.ipify.org"

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }()

    static func fetch(from endpoint: String = defaultEndpoint) async -> String? {
        guard let url = URL(string: endpoint) else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        guard let (data, response) = try? await session.data(for: request),
              let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200,
              httpResponse.url?.host == url.host,
              data.count <= 64,
              let text = String(data: data, encoding: .utf8)?
                  .trimmingCharacters(in: .whitespacesAndNewlines),
              isValidIP(text) else { return nil }
        return text
    }

    private static func isValidIP(_ value: String) -> Bool {
        var ipv4 = in_addr()
        var ipv6 = in6_addr()
        return value.withCString { pointer in
            inet_pton(AF_INET, pointer, &ipv4) == 1 || inet_pton(AF_INET6, pointer, &ipv6) == 1
        }
    }
}

enum Connectivity {
    static let defaultHost = "https://captive.apple.com"

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }()

    static func latencyMs(host: String = defaultHost) async -> Double? {
        guard let url = URL(string: host) else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 5
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let start = Date()
        guard let (_, response) = try? await session.data(for: request),
              let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode),
              httpResponse.url?.host == url.host else { return nil }
        return Date().timeIntervalSince(start) * 1000
    }
}

@MainActor
@Observable
final class NetworkExtrasModel {
    var publicIP: String?
    var latencyMs: Double?
    var publicIPChecked = false
    var latencyChecked = false

    @ObservationIgnored nonisolated(unsafe) private var task: Task<Void, Never>?
    @ObservationIgnored nonisolated(unsafe) private var cancellation: CancellationToken?

    deinit {
        task?.cancel()
        cancellation?.cancel()
    }

    func start(showIP: Bool, showLatency: Bool) {
        guard task == nil, showIP || showLatency else { return }
        let cancellation = CancellationToken()
        self.cancellation = cancellation
        publicIP = nil
        latencyMs = nil
        publicIPChecked = false
        latencyChecked = false
        task = Task { [weak self, cancellation] in
            defer {
                Task { @MainActor [weak self] in
                    guard self?.cancellation === cancellation else { return }
                    self?.task = nil
                    self?.cancellation = nil
                }
            }
            if showIP {
                let ip = await PublicIP.fetch()
                guard !Task.isCancelled && !cancellation.isCancelled else { return }
                self?.publicIP = ip
                self?.publicIPChecked = true
            }

            var failures = 0
            while !Task.isCancelled && !cancellation.isCancelled && showLatency {
                let latency = await Connectivity.latencyMs()
                guard !Task.isCancelled && !cancellation.isCancelled else { return }
                if let latency {
                    self?.latencyMs = latency
                    self?.latencyChecked = true
                    failures = 0
                    try? await Task.sleep(for: .seconds(5))
                } else {
                    self?.latencyMs = nil
                    self?.latencyChecked = true
                    failures += 1
                    try? await Task.sleep(for: .seconds(RetryBackoff.delay(failureCount: failures, base: 5)))
                }
            }
        }
    }

    func stop() {
        cancellation?.cancel()
        task?.cancel()
        task = nil
        cancellation = nil
        publicIP = nil
        latencyMs = nil
        publicIPChecked = false
        latencyChecked = false
    }
}
