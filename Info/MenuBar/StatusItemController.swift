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
    private var popoverPinned = false
    private var localEventMonitor: Any?
    private var globalEventMonitor: Any?
    private var popoverNotificationTokens: [NSObjectProtocol] = []

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
            if let bar = makeBar(kind: kind, style: style) {
                bars.append(bar)
            }
        }

        refresh()
        Log.menubar.info("Installed \(self.bars.count) status item(s)")
    }

    /// Creates one status item for `kind`. Positions persist per metric via
    /// `autosaveName`, so toggling a metric off and on keeps its spot.
    private func makeBar(kind: MetricKind, style: MenuBarStyle) -> Bar? {
        let view = MenuBarItemView(kind: kind, style: style)
        let item = NSStatusBar.system.statusItem(withLength: view.preferredWidth())
        guard let button = item.button else {
            NSStatusBar.system.removeStatusItem(item)
            return nil
        }
        item.autosaveName = "Info.\(kind.rawValue)"
        button.toolTip = kind.title
        button.setAccessibilityLabel(kind.title)

        view.frame = button.bounds
        view.autoresizingMask = [.width, .height]
        button.addSubview(view)

        button.target = self
        button.action = #selector(handleClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])

        return Bar(kind: kind, item: item, view: view)
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
            let data = MenuBarItemData.current(for: bar.kind, state: state)
            bar.view.apply(data)
            // Expose the live value to VoiceOver — the item is custom-drawn, so
            // the button itself must carry it.
            bar.item.button?.setAccessibilityValue(data.accessibilityValue)
        }
    }

    /// Applies a new set of enabled metrics by diffing against the current
    /// items: survivors are kept in place (no flicker, popover stays open),
    /// removed metrics disappear, and new ones are created.
    func setMetrics(_ metrics: [MetricKind]) {
        guard let prefs, state != nil else { return }

        if let popoverKind, !metrics.contains(popoverKind) {
            closePopover()
        }

        for bar in bars where !metrics.contains(bar.kind) {
            NSStatusBar.system.removeStatusItem(bar.item)
        }
        bars.removeAll { !metrics.contains($0.kind) }

        let existing = Set(bars.map(\.kind))
        for kind in metrics where !existing.contains(kind) {
            if let bar = makeBar(kind: kind, style: prefs.menuBarStyle) {
                bars.append(bar)
            }
        }
        bars.sort {
            (MetricKind.allCases.firstIndex(of: $0.kind) ?? 0)
                < (MetricKind.allCases.firstIndex(of: $1.kind) ?? 0)
        }

        if metrics.isEmpty {
            if fallbackItem == nil { installFallbackItem() }
        } else if let fallbackItem {
            NSStatusBar.system.removeStatusItem(fallbackItem)
            self.fallbackItem = nil
        }

        refresh()
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
            closePopover()
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

        let panelView = MetricPanel(
            kind: bar.kind, state: state, prefs: prefs,
            onOpenSettings: { [weak self] in
                self?.closePopover()
                self?.onOpenSettings?()
            },
            onPinChanged: { [weak self] pinned in
                self?.popoverPinned = pinned
            })
        let hosting = NSHostingController(rootView: panelView)
        let fitting = hosting.sizeThatFits(in: NSSize(width: MetricPanel.panelWidth,
                                                      height: .greatestFiniteMagnitude))
        let size = Self.popoverSize(fitting: fitting, width: MetricPanel.panelWidth)
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                            styleMask: [.titled, .fullSizeContentView],
                            backing: .buffered,
                            defer: false)
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        panel.contentViewController = hosting
        panel.setContentSize(size)
        position(panel, below: button)
        installDismissMonitors()
        installPopoverNotifications(for: panel)
        panel.orderFrontRegardless()
        clampToVisibleScreen(panel, fallback: button.window?.screen)
        DispatchQueue.main.async { [weak panel, fallback = button.window?.screen] in
            guard let panel else { return }
            Self.clamp(panel, fallback: fallback)
        }

        popoverWindow = panel
        popoverKind = bar.kind
    }

    private func position(_ panel: NSPanel, below button: NSStatusBarButton) {
        guard let window = button.window else { return }
        let rectInWindow = button.convert(button.bounds, to: nil)
        let anchor = window.convertToScreen(rectInWindow)
        let visible = Self.visibleFrame(containing: anchor, fallback: window.screen)
        panel.setFrame(Self.popoverFrame(anchor: anchor,
                                         size: panel.frame.size,
                                         visible: visible),
                       display: true)
    }

    private static func visibleFrame(containing anchor: NSRect, fallback: NSScreen?) -> NSRect {
        if let fallback { return fallback.visibleFrame }

        let center = NSPoint(x: anchor.midX, y: anchor.midY)
        let screen = NSScreen.screens.first { $0.frame.contains(center) }
            ?? NSScreen.screens.first { $0.frame.intersects(anchor) }
            ?? NSScreen.main
        return screen?.visibleFrame ?? .zero
    }

    nonisolated static func popoverSize(fitting: NSSize,
                                        width: CGFloat,
                                        minHeight: CGFloat = 300,
                                        maxHeight: CGFloat = 560) -> NSSize {
        let measuredHeight = fitting.height.isFinite ? fitting.height : 0
        return NSSize(width: width, height: min(maxHeight, max(minHeight, measuredHeight)))
    }

    nonisolated static func popoverFrame(anchor: NSRect,
                                         size: NSSize,
                                         visible: NSRect,
                                         margin: CGFloat = 8,
                                         gap: CGFloat = 6) -> NSRect {
        let constrainedSize = NSSize(width: min(size.width, max(1, visible.width - margin * 2)),
                                     height: min(size.height, max(1, visible.height - margin * 2)))
        return NSRect(origin: popoverOrigin(anchor: anchor,
                                           size: constrainedSize,
                                           visible: visible,
                                           margin: margin,
                                           gap: gap),
                      size: constrainedSize)
    }

    private func clampToVisibleScreen(_ panel: NSPanel, fallback: NSScreen?) {
        Self.clamp(panel, fallback: fallback)
    }

    private static func clamp(_ panel: NSPanel, fallback: NSScreen?) {
        let visible = panel.screen?.visibleFrame ?? fallback?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let frame = clampedFrame(panel.frame, visible: visible)
        if frame != panel.frame {
            panel.setFrame(frame, display: true)
        }
    }

    nonisolated static func clampedFrame(_ frame: NSRect,
                                         visible: NSRect,
                                         margin: CGFloat = 8) -> NSRect {
        let size = NSSize(width: min(frame.width, max(1, visible.width - margin * 2)),
                          height: min(frame.height, max(1, visible.height - margin * 2)))
        let minX = visible.minX + margin
        let maxX = max(minX, visible.maxX - size.width - margin)
        let minY = visible.minY + margin
        let maxY = max(minY, visible.maxY - size.height - margin)
        let x = min(max(frame.minX, minX), maxX)
        let y = min(max(frame.minY, minY), maxY)
        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }

    nonisolated static func popoverOrigin(anchor: NSRect,
                                          size: NSSize,
                                          visible: NSRect,
                                          margin: CGFloat = 8,
                                          gap: CGFloat = 6) -> NSPoint {
        var x = anchor.midX - size.width / 2
        let minX = visible.minX + margin
        let maxX = max(minX, visible.maxX - size.width - margin)
        x = min(max(x, minX), maxX)

        let belowY = anchor.minY - size.height - gap
        let aboveY = anchor.maxY + gap
        var y = belowY >= visible.minY + margin ? belowY : aboveY
        let minY = visible.minY + margin
        let maxY = max(minY, visible.maxY - size.height - margin)
        y = min(max(y, minY), maxY)

        return NSPoint(x: x, y: y)
    }

    private func closePopover() {
        popoverWindow?.close()
        popoverWindow = nil
        popoverKind = nil
        popoverPinned = false
        removeDismissMonitors()
        removePopoverNotifications()
    }

    private func installPopoverNotifications(for panel: NSPanel) {
        removePopoverNotifications()
        let center = NotificationCenter.default
        popoverNotificationTokens.append(center.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: panel,
            queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.closePopoverUnlessPinned() }
        })
        popoverNotificationTokens.append(center.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: NSApp,
            queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.closePopoverUnlessPinned() }
        })
    }

    private func removePopoverNotifications() {
        let center = NotificationCenter.default
        popoverNotificationTokens.forEach(center.removeObserver)
        popoverNotificationTokens.removeAll()
    }

    private func installDismissMonitors() {
        removeDismissMonitors()
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown && event.keyCode == 53 { // Escape
                self.closePopover()
                return nil
            }
            if self.isStatusButtonEvent(event) {
                return event
            }
            if let panel = self.popoverWindow, event.window !== panel {
                self.closePopoverUnlessPinned()
            }
            return event
        }
        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            DispatchQueue.main.async { self?.closePopoverUnlessPinned() }
        }
    }

    /// Outside clicks and focus loss only dismiss an unpinned popover. Escape,
    /// clicking the status item again, and disabling the metric always close.
    private func closePopoverUnlessPinned() {
        guard !popoverPinned else { return }
        closePopover()
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

    private func isStatusButtonEvent(_ event: NSEvent) -> Bool {
        guard let window = event.window else { return false }
        for item in statusItems {
            guard let button = item.button, button.window === window else { continue }
            let location = button.convert(event.locationInWindow, from: nil)
            if button.bounds.contains(location) { return true }
        }
        return false
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
