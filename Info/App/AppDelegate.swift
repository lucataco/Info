import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var prefs: Preferences?
    private var state: SamplingState?
    private var engine: MetricsEngine?
    private var statusController: StatusItemController?
    private var powerGate: PowerGate?
    private let windows = WindowManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        if runDebugCommandsIfRequested() { return }
        let selfTest = CommandLine.arguments.contains("--selftest")
        #endif

        Log.app.info("Info launched (pid \(ProcessInfo.processInfo.processIdentifier))")

        installMainMenu()

        let prefs = Preferences()
        prefs.appearance.apply()
        let state = SamplingState()
        let controller = StatusItemController()
        controller.onOpenSettings = { [weak self] in self?.showSettings() }
        controller.install(state: state, prefs: prefs, metrics: prefs.enabledMetrics)
        state.onUpdate = { [weak controller] in controller?.refresh() }

        let engine = MetricsEngine(interval: prefs.updateInterval,
                                   enabledMetrics: prefs.enabledMetrics) { snapshot in
            state.ingest(snapshot)
        }
        engine.start()

        let powerGate = PowerGate(engine: engine)
        powerGate.start()

        self.prefs = prefs
        self.state = state
        self.statusController = controller
        self.engine = engine
        self.powerGate = powerGate

        if !prefs.didOnboard {
            showOnboarding()
        }

        #if DEBUG
        if selfTest {
            // Exercise the windowed UI paths (settings + onboarding) to catch
            // construction crashes without screen interaction, then exit.
            showSettings()
            showOnboarding()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                Log.app.info("selftest OK")
                exit(0)
            }
        }
        #endif
    }

    #if DEBUG
    /// Handles the DEBUG-only CLI verbs (`--snapshot*`, `--read-temp`,
    /// `--test-net`). Returns true when a command took over the launch.
    private func runDebugCommandsIfRequested() -> Bool {
        let args = CommandLine.arguments
        if let base = argumentValue(after: "--snapshot", in: args) {
            SnapshotTool.render(toBase: base)
            exit(0)
        }
        if let base = argumentValue(after: "--snapshot-panels", in: args) {
            SnapshotTool.renderPanels(toBase: base)
            exit(0)
        }
        if let base = argumentValue(after: "--snapshot-onboarding", in: args) {
            SnapshotTool.renderOnboarding(toBase: base)
            exit(0)
        }
        if args.contains("--read-temp") {
            if let smc = SMCConnection() {
                let cpu = smc.averageTemperature(keys: SMCConnection.cpuKeys)
                let gpu = smc.averageTemperature(keys: SMCConnection.gpuKeys)
                smc.close()
                Log.app.info("TEMP cpu=\(cpu.map { String(format: "%.1f", $0) } ?? "nil", privacy: .public) gpu=\(gpu.map { String(format: "%.1f", $0) } ?? "nil", privacy: .public)")
            } else {
                Log.app.info("TEMP smc-open-failed")
            }
            exit(0)
        }
        if args.contains("--test-net") {
            Task {
                let ip = await PublicIP.fetch()
                let latency = await Connectivity.latencyMs()
                Log.app.info("NET ip=\(ip ?? "nil", privacy: .public) latency=\(latency.map { String(format: "%.0fms", $0) } ?? "nil", privacy: .public)")
                exit(0)
            }
            return true
        }
        return false
    }

    private func argumentValue(after flag: String, in args: [String]) -> String? {
        guard let index = args.firstIndex(of: flag), index + 1 < args.count else { return nil }
        return args[index + 1]
    }
    #endif

    func applicationWillTerminate(_ notification: Notification) {
        Log.app.info("Info terminating")
        self.powerGate?.stop()
        self.engine?.stop()
        self.statusController?.tearDown()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Even accessory apps get key-equivalent dispatch through the main menu,
    /// so the shortcuts advertised in the status-item menu (⌘, ⌘Q) — plus ⌘W
    /// to close Settings/Onboarding — actually work whenever a window is key.
    private func installMainMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Info",
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                        keyEquivalent: "")
        appMenu.addItem(.separator())
        let settingsItem = NSMenuItem(title: "Settings…",
                                      action: #selector(openSettingsFromMenu),
                                      keyEquivalent: ",")
        settingsItem.target = self
        appMenu.addItem(settingsItem)
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Info",
                        action: #selector(NSApplication.terminate(_:)),
                        keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Close Window",
                           action: #selector(NSWindow.performClose(_:)),
                           keyEquivalent: "w")
        windowMenu.addItem(withTitle: "Minimize",
                           action: #selector(NSWindow.performMiniaturize(_:)),
                           keyEquivalent: "m")
        windowItem.submenu = windowMenu
        main.addItem(windowItem)

        NSApp.mainMenu = main
    }

    @objc private func openSettingsFromMenu() {
        showSettings()
    }

    // MARK: - Onboarding

    private func showOnboarding() {
        guard let prefs, let state else { return }
        // Closing the window at any step counts as "seen" — onboarding must
        // never nag on every launch.
        let markOnboarded: () -> Void = { [weak self] in
            self?.prefs?.didOnboard = true
        }
        windows.showOnboarding(onClose: markOnboarded) {
            OnboardingView(
                prefs: prefs,
                state: state,
                statusItemsProvider: { [weak self] in self?.statusController?.statusItems ?? [] },
                onMetricsChanged: { [weak self] in
                    guard let self, let prefs = self.prefs else { return }
                    self.engine?.setEnabledMetrics(prefs.enabledMetrics)
                    self.statusController?.setMetrics(prefs.enabledMetrics)
                },
                onFinish: { [weak self] in
                    self?.prefs?.didOnboard = true
                    self?.windows.closeOnboarding()
                })
        }
    }

    // MARK: - Settings

    private func showSettings() {
        guard let prefs, let state else { return }
        windows.showSettings {
            SettingsView(
                prefs: prefs,
                state: state,
                onMetricsChanged: { [weak self] in
                    guard let self, let prefs = self.prefs else { return }
                    self.engine?.setEnabledMetrics(prefs.enabledMetrics)
                    self.statusController?.setMetrics(prefs.enabledMetrics)
                },
                onIntervalChanged: { [weak self] in
                    guard let self, let prefs = self.prefs else { return }
                    self.engine?.setInterval(prefs.updateInterval)
                },
                onStyleChanged: { [weak self] in
                    guard let self, let prefs = self.prefs else { return }
                    self.statusController?.setStyle(prefs.menuBarStyle)
                },
                onAppearanceChanged: { [weak self] in
                    self?.prefs?.appearance.apply()
                }
            )
        }
    }
}
