import Foundation

final class CancellationToken: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool {
        lock.withLock { cancelled }
    }

    func cancel() {
        lock.withLock {
            cancelled = true
        }
    }
}

enum RetryBackoff {
    static func delay(failureCount: Int, base: Double = 5, maximum: Double = 60) -> Double {
        guard failureCount > 0 else { return base }
        let multiplier = pow(2, Double(min(failureCount - 1, 10)))
        return min(maximum, base * multiplier)
    }
}
