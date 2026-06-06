import AppKit
import SwiftUI

/// Manages the few auxiliary windows an agent app needs (settings, onboarding).
/// Agent apps have no standard window menu, so we create/show `NSWindow`s
/// hosting SwiftUI content directly and bring the app forward when shown.
@MainActor
final class WindowManager {
    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private var onboardingDelegate: WindowCloseDelegate?

    func showSettings<Content: View>(@ViewBuilder _ content: () -> Content) {
        if settingsWindow == nil {
            let window = makeWindow(title: "Info Settings",
                                    style: [.titled, .closable, .miniaturizable],
                                    size: NSSize(width: 440, height: 480))
            window.contentViewController = NSHostingController(rootView: content())
            settingsWindow = window
        }
        present(settingsWindow)
    }

    func showOnboarding<Content: View>(onClose: @escaping () -> Void,
                                       @ViewBuilder _ content: () -> Content) {
        let window = makeWindow(title: "Welcome to Info",
                                style: [.titled, .closable, .fullSizeContentView],
                                size: NSSize(width: 540, height: 500))
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.contentViewController = NSHostingController(rootView: content())

        let delegate = WindowCloseDelegate(onClose: onClose)
        window.delegate = delegate
        onboardingDelegate = delegate
        onboardingWindow = window
        present(window)
    }

    func closeOnboarding() {
        onboardingWindow?.close()
        onboardingWindow = nil
        onboardingDelegate = nil
    }

    // MARK: - Helpers

    private func makeWindow(title: String, style: NSWindow.StyleMask, size: NSSize) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: style, backing: .buffered, defer: false)
        window.title = title
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }

    private func present(_ window: NSWindow?) {
        guard let window else { return }
        NSApp.activate(ignoringOtherApps: true)
        window.center()
        window.makeKeyAndOrderFront(nil)
    }
}

@MainActor
private final class WindowCloseDelegate: NSObject, NSWindowDelegate {
    private let onClose: () -> Void
    init(onClose: @escaping () -> Void) { self.onClose = onClose }
    func windowWillClose(_ notification: Notification) { onClose() }
}
