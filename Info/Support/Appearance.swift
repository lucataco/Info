import AppKit

/// User-selectable app appearance. `system` follows the macOS light/dark
/// setting automatically; `light`/`dark` force a fixed appearance.
enum AppearanceMode: String, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    /// The `NSAppearance` to apply, or `nil` to follow the system setting.
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }

    /// Applies this mode app-wide. Setting `NSApp.appearance` to `nil` makes
    /// every window (status item drawing, panels, settings) track the system
    /// light/dark setting again.
    @MainActor
    func apply() {
        NSApp.appearance = nsAppearance
    }
}
