import AppKit

/// Pauses sampling when it can't possibly be seen, to spend as little energy as
/// possible: on system sleep and on screen lock. Resumes on wake/unlock.
///
/// This is a key low-power behavior — while the Mac sleeps or the screen is
/// locked, Info does zero work.
@MainActor
final class PowerGate {
    private enum PauseReason: Hashable { case sleep, screenLocked, displaySleep }

    private let engine: MetricsEngine
    private let activity: AppActivityState
    private var workspaceTokens: [NSObjectProtocol] = []
    private var distributedTokens: [NSObjectProtocol] = []
    private var pauseReasons = Set<PauseReason>()

    init(engine: MetricsEngine, activity: AppActivityState) {
        self.engine = engine
        self.activity = activity
    }

    func start() {
        let workspace = NSWorkspace.shared.notificationCenter

        if Self.isScreenLocked {
            pauseReasons.insert(.screenLocked)
            activity.setScreenLocked(true)
        }

        workspaceTokens.append(workspace.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.add(.sleep) }
        })
        workspaceTokens.append(workspace.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.remove(.sleep) }
        })
        workspaceTokens.append(workspace.addObserver(
            forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.add(.displaySleep) }
        })
        workspaceTokens.append(workspace.addObserver(
            forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.remove(.displaySleep) }
        })

        let distributed = DistributedNotificationCenter.default()
        distributedTokens.append(distributed.addObserver(
            forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.add(.screenLocked) }
        })
        distributedTokens.append(distributed.addObserver(
            forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.remove(.screenLocked) }
        })
        applyPauseState()
    }

    func stop() {
        let workspace = NSWorkspace.shared.notificationCenter
        workspaceTokens.forEach(workspace.removeObserver)
        let distributed = DistributedNotificationCenter.default()
        distributedTokens.forEach(distributed.removeObserver)
        workspaceTokens.removeAll()
        distributedTokens.removeAll()
    }

    private func add(_ reason: PauseReason) {
        pauseReasons.insert(reason)
        applyPauseState()
    }

    private func remove(_ reason: PauseReason) {
        pauseReasons.remove(reason)
        applyPauseState()
    }

    private func applyPauseState() {
        let paused = !pauseReasons.isEmpty
        activity.setSleeping(pauseReasons.contains(.sleep) || pauseReasons.contains(.displaySleep))
        activity.setScreenLocked(pauseReasons.contains(.screenLocked))
        engine.setPaused(paused)
        Log.engine.debug("power gate paused=\(paused)")
    }

    private static var isScreenLocked: Bool {
        guard let dictionary = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return dictionary["CGSSessionScreenIsLocked"] as? Bool == true
    }
}
