import Observation
import Foundation

/// Lightweight, observable settings backed by `UserDefaults`. Writes are tiny
/// and infrequent (only on user change) — never on the sampling path.
@MainActor
@Observable
final class Preferences {
    private let defaults: UserDefaults

    private enum Keys {
        static let metrics = "enabledMetrics"
        static let interval = "updateInterval"
        static let temperature = "showTemperature"
        static let publicIP = "showPublicIP"
        static let connectivity = "showConnectivity"
        static let didOnboard = "didOnboard"
        static let menuBarSparkline = "menuBarSparkline"
        static let menuBarValue = "menuBarValue"
        static let menuBarLabel = "menuBarLabel"
        static let menuBarTextSize = "menuBarTextSize"
        static let menuBarSpacing = "menuBarSpacing"
    }

    /// Which metrics appear in the menu bar, in canonical order.
    var enabledMetrics: [MetricKind] { didSet { persistMetrics() } }

    /// Sampling cadence in seconds (clamped 1...5; default 2 for low power).
    var updateInterval: Double { didSet { defaults.set(updateInterval, forKey: Keys.interval) } }

    // Opt-in heavier features (Phase 7), default off.
    var showTemperature: Bool { didSet { defaults.set(showTemperature, forKey: Keys.temperature) } }
    var showPublicIP: Bool { didSet { defaults.set(showPublicIP, forKey: Keys.publicIP) } }
    var showConnectivity: Bool { didSet { defaults.set(showConnectivity, forKey: Keys.connectivity) } }

    /// Whether the first-run onboarding has completed.
    var didOnboard: Bool { didSet { defaults.set(didOnboard, forKey: Keys.didOnboard) } }

    // Menu bar appearance.
    var showMenuBarSparkline: Bool { didSet { defaults.set(showMenuBarSparkline, forKey: Keys.menuBarSparkline) } }
    var showMenuBarValue: Bool { didSet { defaults.set(showMenuBarValue, forKey: Keys.menuBarValue) } }
    var menuBarLabel: MenuBarLabelStyle { didSet { defaults.set(menuBarLabel.rawValue, forKey: Keys.menuBarLabel) } }
    var menuBarTextSize: MenuBarTextSize { didSet { defaults.set(menuBarTextSize.rawValue, forKey: Keys.menuBarTextSize) } }
    var menuBarSpacing: MenuBarSpacing { didSet { defaults.set(menuBarSpacing.rawValue, forKey: Keys.menuBarSpacing) } }

    var menuBarStyle: MenuBarStyle {
        MenuBarStyle(showSparkline: showMenuBarSparkline,
                     showValue: showMenuBarValue,
                     label: menuBarLabel,
                     textSize: menuBarTextSize,
                     spacing: menuBarSpacing)
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if let raw = defaults.array(forKey: Keys.metrics) as? [String] {
            enabledMetrics = raw.compactMap(MetricKind.init(rawValue:))
        } else {
            enabledMetrics = MetricKind.allCases
        }

        let stored = defaults.double(forKey: Keys.interval)
        updateInterval = stored == 0 ? 2.0 : min(5, max(1, stored))

        showTemperature = defaults.bool(forKey: Keys.temperature)
        showPublicIP = defaults.bool(forKey: Keys.publicIP)
        showConnectivity = defaults.bool(forKey: Keys.connectivity)
        didOnboard = defaults.bool(forKey: Keys.didOnboard)

        // Default sparkline OFF. Wide graph items can collide with macOS's
        // hidden/overflow chevron on crowded menu bars, so graphs are opt-in.
        showMenuBarSparkline = defaults.object(forKey: Keys.menuBarSparkline) == nil
            ? false : defaults.bool(forKey: Keys.menuBarSparkline)
        showMenuBarValue = defaults.object(forKey: Keys.menuBarValue) == nil
            ? true : defaults.bool(forKey: Keys.menuBarValue)
        menuBarLabel = MenuBarLabelStyle(rawValue: defaults.string(forKey: Keys.menuBarLabel) ?? "") ?? .text
        menuBarTextSize = MenuBarTextSize(rawValue: defaults.string(forKey: Keys.menuBarTextSize) ?? "") ?? .medium
        menuBarSpacing = MenuBarSpacing(rawValue: defaults.string(forKey: Keys.menuBarSpacing) ?? "") ?? .compact
    }

    func isEnabled(_ kind: MetricKind) -> Bool { enabledMetrics.contains(kind) }

    func setEnabled(_ kind: MetricKind, _ on: Bool) {
        var set = Set(enabledMetrics)
        if on {
            set.insert(kind)
        } else {
            set.remove(kind)
        }
        enabledMetrics = MetricKind.allCases.filter { set.contains($0) }
    }

    private func persistMetrics() {
        defaults.set(enabledMetrics.map(\.rawValue), forKey: Keys.metrics)
    }
}
