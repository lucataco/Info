import Observation

/// System-level conditions that decide whether panel extras (top processes,
/// temperature, latency, public IP) may run. Fed by `PowerGate`.
///
/// Deliberately *not* gated on `NSApp.isActive`: Info is an accessory app and
/// its panels open without activating it (clicking a status item even hands
/// focus back to the previous app), so "app active" is almost never true while
/// a panel is on screen. Panels already start/stop their extras on appear and
/// disappear, so visibility is the gate.
@MainActor
@Observable
final class AppActivityState {
    private(set) var isSleeping = false
    private(set) var isScreenLocked = false

    var shouldRunOptionalWork: Bool {
        !isSleeping && !isScreenLocked
    }

    func setSleeping(_ value: Bool) {
        isSleeping = value
    }

    func setScreenLocked(_ value: Bool) {
        isScreenLocked = value
    }
}
