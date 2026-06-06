import AppKit

/// Best-effort detection of whether our menu-bar items are actually showing.
///
/// macOS 26 added System Settings › Menu Bar › "Allow in Menu Bar"; if the app
/// isn't allowed, our status items silently won't appear and no error is raised.
/// There's no public API to query that allow-list, so we use a heuristic: an
/// item counts as visible if it's marked visible and its button's window
/// overlaps an actual screen.
@MainActor
enum MenuBarVisibility {
    static func isLikelyVisible(_ items: [NSStatusItem]) -> Bool {
        guard !items.isEmpty else { return false }
        return items.contains { item in
            guard item.isVisible,
                  let button = item.button,
                  !button.isHidden,
                  button.alphaValue > 0,
                  !button.bounds.isEmpty,
                  let window = button.window else { return false }
            let buttonFrame = window.convertToScreen(button.convert(button.bounds, to: nil))
            guard buttonFrame.width > 1, buttonFrame.height > 1 else { return false }
            return NSScreen.screens.contains { $0.visibleFrame.intersects(buttonFrame) }
        }
    }

    /// Open System Settings to the Menu Bar / Control Center area so the user can
    /// allow Info. Tries known panes, then falls back to System Settings itself.
    static func openMenuBarSettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.ControlCenter-Settings.extension",
            "x-apple.systempreferences:com.apple.Menubar-Settings.extension",
            "x-apple.systempreferences:",
        ]
        for string in candidates {
            if let url = URL(string: string), NSWorkspace.shared.open(url) { return }
        }
    }
}
