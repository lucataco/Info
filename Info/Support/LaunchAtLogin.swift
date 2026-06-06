import ServiceManagement

/// Modern launch-at-login via `SMAppService` (macOS 13+), the replacement for
/// the deprecated `SMLoginItemSetEnabled`.
enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static var requiresApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                try SMAppService.mainApp.unregister()
            }
            return true
        } catch {
            Log.app.error("Launch at login \(enabled ? "register" : "unregister") failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// Deep-link to System Settings › General › Login Items for user approval.
    static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
