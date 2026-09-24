import AppKit
import Observation

@MainActor
@Observable
final class AppActivityState {
    private(set) var isSleeping = false
    private(set) var isScreenLocked = false
    private(set) var isApplicationActive = true

    private var tokens: [NSObjectProtocol] = []

    var shouldSample: Bool {
        !isSleeping && !isScreenLocked
    }

    var shouldRunOptionalWork: Bool {
        shouldSample && isApplicationActive
    }

    func start() {
        guard tokens.isEmpty else { return }
        let center = NotificationCenter.default
        tokens.append(center.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: NSApp, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.isApplicationActive = true
            }
        })
        tokens.append(center.addObserver(
            forName: NSApplication.didResignActiveNotification, object: NSApp, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.isApplicationActive = false
            }
        })
    }

    func stop() {
        tokens.forEach(NotificationCenter.default.removeObserver)
        tokens.removeAll()
    }

    func setSleeping(_ value: Bool) {
        isSleeping = value
    }

    func setScreenLocked(_ value: Bool) {
        isScreenLocked = value
    }
}
