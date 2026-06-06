import AppKit

/// Program entry point.
///
/// Info is an AppKit "agent" app (no Dock icon, no main window). We use a plain
/// `NSApplication` + delegate rather than a SwiftUI `App` scene so we have full
/// control over the status-item lifecycle and window activation policy. SwiftUI
/// is still used for the detail popover, settings, and onboarding via
/// `NSHostingController`.
@main
enum InfoApp {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        // `.accessory` => menu-bar agent: no Dock tile, no app switcher entry.
        // (Belt and suspenders alongside LSUIElement in Info.plist.)
        app.setActivationPolicy(.accessory)
        app.run()
        // Keep the delegate alive for the lifetime of the run loop.
        withExtendedLifetime(delegate) {}
    }
}
