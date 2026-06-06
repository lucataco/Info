import AppKit
import SwiftUI

/// Owns one menu-bar `NSStatusItem` per enabled metric, each rendering a live
/// `MenuBarItemView`. Left-click opens a SwiftUI detail popover; right-click
/// shows a small menu.
@MainActor
final class StatusItemController {
    private weak var state: SamplingState?
    private weak var prefs: Preferences?

    private final class Bar {
        let kind: MetricKind
        let item: NSStatusItem
        let view: MenuBarItemView
        init(kind: MetricKind, item: NSStatusItem, view: MenuBarItemView) {
            self.kind = kind
            self.item = item
            self.view = view
        }
    }

    private var bars: [Bar] = []
    private var fallbackItem: NSStatusItem?
    private var popoverWindow: NSPanel?
    private var popoverKind: MetricKind?
    private var localEventMonitor: Any?
    private var globalEventMonitor: Any?

    /// Invoked when the user picks "Settings…" from the right-click menu.
    var onOpenSettings: (() -> Void)?

    /// Current status items (used by onboarding to check menu-bar visibility).
    var statusItems: [NSStatusItem] { bars.map(\.item) + [fallbackItem].compactMap { $0 } }

    func install(state: SamplingState, prefs: Preferences, metrics: [MetricKind] = MetricKind.allCases) {
        self.state = state
        self.prefs = prefs
        let style = prefs.menuBarStyle

        if metrics.isEmpty {
            installFallbackItem()
            Log.menubar.info("Installed fallback status item")
            return
        }

        for kind in metrics {
            let view = MenuBarItemView(kind: kind, style: style)
            let item = NSStatusBar.system.statusItem(withLength: view.preferredWidth())
            guard let button = item.button else {
                NSStatusBar.system.removeStatusItem(item)
                continue
            }
            button.toolTip = kind.title

            view.frame = button.bounds
            view.autoresizingMask = [.width, .height]
            button.addSubview(view)

            button.target = self
            button.action = #selector(handleClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])

            bars.append(Bar(kind: kind, item: item, view: view))
        }

        refresh()
        Log.menubar.info("Installed \(self.bars.count) status item(s)")
    }

    private func installFallbackItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = item.button else {
            NSStatusBar.system.removeStatusItem(item)
            return
        }
        button.title = "Info"
        button.toolTip = "Info — Settings"
        button.target = self
        button.action = #selector(handleFallbackClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        fallbackItem = item
    }

    /// Apply a new menu-bar appearance to all items.
    func setStyle(_ style: MenuBarStyle) {
        for bar in bars {
            bar.view.style = style
            bar.item.length = bar.view.preferredWidth()
        }
        refresh()
    }

    func refresh() {
        guard let state else { return }
        for bar in bars {
            switch bar.kind {
            case .cpu:
                bar.view.updateSingle(
                    history: state.cpuHistory.values,
                    value: state.cpu.map { Fmt.percent($0.total) } ?? "—")
            case .gpu:
                bar.view.updateSingle(
                    history: state.gpuHistory.values,
                    value: state.gpu.map { Fmt.percent($0.utilization) } ?? "—")
            case .memory:
                bar.view.updateSingle(
                    history: state.memoryHistory.values,
                    value: state.memory.map { Fmt.percent($0.usage) } ?? "—")
            case .network:
                let down = state.network.map { Fmt.rateShort($0.downloadBytesPerSec) } ?? "—"
                let up = state.network.map { Fmt.rateShort($0.uploadBytesPerSec) } ?? "—"
                bar.view.updateMirrored(
                    download: state.netDownHistory.values,
                    upload: state.netUpHistory.values,
                    lines: ["\u{2193}\(down)", "\u{2191}\(up)"])
            }
        }
    }

    /// Rebuild the menu-bar items for a new set of enabled metrics.
    func setMetrics(_ metrics: [MetricKind]) {
        guard let state, let prefs else { return }
        closePopover()
        tearDown()
        install(state: state, prefs: prefs, metrics: metrics)
    }

    func tearDown() {
        closePopover()
        for bar in bars { NSStatusBar.system.removeStatusItem(bar.item) }
        bars.removeAll()
        if let fallbackItem {
            NSStatusBar.system.removeStatusItem(fallbackItem)
            self.fallbackItem = nil
        }
    }

    // MARK: - Interaction

    @objc private func handleClick(_ sender: NSStatusBarButton) {
        guard let bar = bars.first(where: { $0.item.button === sender }) else { return }
        let isRight = NSApp.currentEvent?.type == .rightMouseUp
        if isRight {
            showMenu(for: bar, on: sender)
        } else {
            togglePopover(for: bar, on: sender)
        }
    }

    @objc private func handleFallbackClick(_ sender: NSStatusBarButton) {
        let isRight = NSApp.currentEvent?.type == .rightMouseUp
        if isRight {
            showFallbackMenu(on: sender)
        } else {
            onOpenSettings?()
        }
    }

    private func togglePopover(for bar: Bar, on button: NSStatusBarButton) {
        if popoverWindow != nil && popoverKind == bar.kind {
            closePopover()
            return
        }
        guard let state, let prefs else { return }
        closePopover()

        let hosting = NSHostingController(rootView: MetricPanel(kind: bar.kind, state: state, prefs: prefs))
        hosting.view.layoutSubtreeIfNeeded()
        let fitting = hosting.view.fittingSize
        let size = NSSize(width: max(300, fitting.width),
                          height: min(520, max(180, fitting.height)))
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                            styleMask: [.titled, .fullSizeContentView],
                            backing: .buffered,
                            defer: false)
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        panel.contentViewController = hosting
        position(panel, below: button)
        installDismissMonitors()
        panel.orderFrontRegardless()

        popoverWindow = panel
        popoverKind = bar.kind
    }

    private func position(_ panel: NSPanel, below button: NSStatusBarButton) {
        guard let window = button.window else { return }
        let rectInWindow = button.convert(button.bounds, to: nil)
        let anchor = window.convertToScreen(rectInWindow)
        let screen = window.screen ?? NSScreen.screens.first { $0.frame.intersects(anchor) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSScreen.screens.first?.visibleFrame ?? .zero
        panel.setFrameOrigin(Self.popoverOrigin(anchor: anchor,
                                               size: panel.frame.size,
                                               visible: visible))
    }

    nonisolated static func popoverOrigin(anchor: NSRect,
                                          size: NSSize,
                                          visible: NSRect,
                                          margin: CGFloat = 8,
                                          gap: CGFloat = 6) -> NSPoint {
        var x = anchor.midX - size.width / 2
        x = min(max(x, visible.minX + margin), visible.maxX - size.width - margin)

        let belowY = anchor.minY - size.height - gap
        let aboveY = anchor.maxY + gap
        var y = belowY >= visible.minY + margin ? belowY : aboveY
        y = min(max(y, visible.minY + margin), visible.maxY - size.height - margin)

        return NSPoint(x: x, y: y)
    }

    private func closePopover() {
        popoverWindow?.close()
        popoverWindow = nil
        popoverKind = nil
        removeDismissMonitors()
    }

    private func installDismissMonitors() {
        removeDismissMonitors()
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown && event.keyCode == 53 { // Escape
                self.closePopover()
                return nil
            }
            if let panel = self.popoverWindow, event.window !== panel {
                self.closePopover()
            }
            return event
        }
        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            DispatchQueue.main.async { self?.closePopover() }
        }
    }

    private func removeDismissMonitors() {
        if let localEventMonitor {
            NSEvent.removeMonitor(localEventMonitor)
            self.localEventMonitor = nil
        }
        if let globalEventMonitor {
            NSEvent.removeMonitor(globalEventMonitor)
            self.globalEventMonitor = nil
        }
    }

    private func showMenu(for bar: Bar, on button: NSStatusBarButton) {
        showStatusMenu(title: bar.kind.title, on: button)
    }

    private func showFallbackMenu(on button: NSStatusBarButton) {
        showStatusMenu(title: "Info", on: button)
    }

    private func showStatusMenu(title: String, on button: NSStatusBarButton) {
        let menu = NSMenu()
        let header = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())
        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(withTitle: "Quit Info",
                     action: #selector(NSApplication.terminate(_:)),
                     keyEquivalent: "q")
        menu.popUp(positioning: nil,
                   at: NSPoint(x: 0, y: button.bounds.height + 4),
                   in: button)
    }

    @objc private func openSettings() {
        onOpenSettings?()
    }
}
