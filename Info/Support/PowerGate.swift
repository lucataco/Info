import AppKit

/// Pauses sampling when it can't possibly be seen, to spend as little energy as
/// possible: on system sleep and on screen lock. Resumes on wake/unlock.
///
/// This is a key low-power behavior — while the Mac sleeps or the screen is
/// locked, Info does zero work.
@MainActor
final class PowerGate {
    private enum PauseReason: Hashable { case sleep, screenLocked }

    private let engine: MetricsEngine
    private var workspaceTokens: [NSObjectProtocol] = []
    private var distributedTokens: [NSObjectProtocol] = []
    private var pauseReasons = Set<PauseReason>()

    init(engine: MetricsEngine) {
        self.engine = engine
    }

    func start() {
        let workspace = NSWorkspace.shared.notificationCenter

        workspaceTokens.append(workspace.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { self.add(.sleep) }
        })
        workspaceTokens.append(workspace.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { self.remove(.sleep) }
        })

        let distributed = DistributedNotificationCenter.default()
        distributedTokens.append(distributed.addObserver(
            forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { self.add(.screenLocked) }
        })
        distributedTokens.append(distributed.addObserver(
            forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { self.remove(.screenLocked) }
        })
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
        engine.setPaused(paused)
        Log.engine.debug("power gate paused=\(paused)")
    }
}
