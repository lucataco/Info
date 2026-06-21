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
        if let i = CommandLine.arguments.firstIndex(of: "--snapshot"), i + 1 < CommandLine.arguments.count {
            SnapshotTool.render(toBase: CommandLine.arguments[i + 1])
            exit(0)
        }
        if let i = CommandLine.arguments.firstIndex(of: "--snapshot-panels"), i + 1 < CommandLine.arguments.count {
            SnapshotTool.renderPanels(toBase: CommandLine.arguments[i + 1])
            exit(0)
        }
        if let i = CommandLine.arguments.firstIndex(of: "--snapshot-onboarding"), i + 1 < CommandLine.arguments.count {
            SnapshotTool.renderOnboarding(toBase: CommandLine.arguments[i + 1])
            exit(0)
        }
        if CommandLine.arguments.contains("--read-temp") {
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
        if CommandLine.arguments.contains("--test-net") {
            Task {
                let ip = await PublicIP.fetch()
                let latency = await Connectivity.latencyMs()
                Log.app.info("NET ip=\(ip ?? "nil", privacy: .public) latency=\(latency.map { String(format: "%.0fms", $0) } ?? "nil", privacy: .public)")
                exit(0)
            }
            return
        }
        let selfTest = CommandLine.arguments.contains("--selftest")
        #endif

        Log.app.info("Info launched (pid \(ProcessInfo.processInfo.processIdentifier))")

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

    func applicationWillTerminate(_ notification: Notification) {
        Log.app.info("Info terminating")
        self.powerGate?.stop()
        self.engine?.stop()
        self.statusController?.tearDown()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    // MARK: - Onboarding

    private func showOnboarding() {
        guard let prefs, let state else { return }
        windows.showOnboarding(onClose: {}) {
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
        guard let prefs else { return }
        windows.showSettings {
            SettingsView(
                prefs: prefs,
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
