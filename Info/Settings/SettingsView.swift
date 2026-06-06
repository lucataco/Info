import SwiftUI

/// Tabbed settings modal (Stats-style): pick which metrics show, customize the
/// menu bar look, and manage general app behavior like launch-at-login.
struct SettingsView: View {
    @Bindable var prefs: Preferences
    var onMetricsChanged: () -> Void
    var onIntervalChanged: () -> Void
    var onStyleChanged: () -> Void

    var body: some View {
        TabView {
            MetricsTab(prefs: prefs, onMetricsChanged: onMetricsChanged)
                .tabItem { Label("Metrics", systemImage: "square.grid.2x2") }

            MenuBarTab(prefs: prefs, onStyleChanged: onStyleChanged)
                .tabItem { Label("Menu Bar", systemImage: "menubar.rectangle") }

            GeneralTab(prefs: prefs, onIntervalChanged: onIntervalChanged)
                .tabItem { Label("General", systemImage: "gearshape") }
        }
        .frame(width: 440, height: 480)
    }
}

// MARK: - Metrics

private struct MetricsTab: View {
    @Bindable var prefs: Preferences
    var onMetricsChanged: () -> Void

    var body: some View {
        Form {
            Section("Show in menu bar") {
                ForEach(MetricKind.allCases) { kind in
                    Toggle(isOn: Binding(
                        get: { prefs.isEnabled(kind) },
                        set: { prefs.setEnabled(kind, $0); onMetricsChanged() }
                    )) {
                        Label(kind.title, systemImage: kind.symbolName)
                    }
                }
            }

            Section {
                Toggle(isOn: $prefs.showTemperature) {
                    Text("CPU & GPU temperature")
                    Text("Reads the SMC. Uses a little more power.")
                }
                Toggle(isOn: $prefs.showConnectivity) {
                    Text("Connectivity latency")
                    Text("Measures ping only while the Network panel is open.")
                }
                Toggle(isOn: $prefs.showPublicIP) {
                    Text("Public IP address")
                    Text("Makes one external request when the Network panel opens.")
                }
            } header: {
                Text("Extras")
            } footer: {
                Text("All off by default. These only run while a panel is open.")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Menu Bar

private struct MenuBarTab: View {
    @Bindable var prefs: Preferences
    var onStyleChanged: () -> Void

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Label", selection: Binding(
                    get: { prefs.menuBarLabel },
                    set: { prefs.menuBarLabel = $0; onStyleChanged() }
                )) {
                    ForEach(MenuBarLabelStyle.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)

                Picker("Text size", selection: Binding(
                    get: { prefs.menuBarTextSize },
                    set: { prefs.menuBarTextSize = $0; onStyleChanged() }
                )) {
                    ForEach(MenuBarTextSize.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)

                Picker("Spacing", selection: Binding(
                    get: { prefs.menuBarSpacing },
                    set: { prefs.menuBarSpacing = $0; onStyleChanged() }
                )) {
                    ForEach(MenuBarSpacing.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)

                Toggle(isOn: Binding(
                    get: { prefs.showMenuBarValue },
                    set: { prefs.showMenuBarValue = $0; onStyleChanged() }
                )) {
                    Text("Show value")
                    Text("Displays percentage or network speed in the menu bar.")
                }

                Toggle(isOn: Binding(
                    get: { prefs.showMenuBarSparkline },
                    set: { prefs.showMenuBarSparkline = $0; onStyleChanged() }
                )) {
                    Text("Show graph")
                    Text("Opt-in. Wide graph items may not fit on crowded menu bars.")
                }
            }

            Section {
                Text("Tip: use Compact spacing to match native menu extras. Keep graph off for the most reliable menu bar fit; click any item for full charts and details.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - General

private struct GeneralTab: View {
    @Bindable var prefs: Preferences
    var onIntervalChanged: () -> Void
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var requiresLoginApproval = LaunchAtLogin.requiresApproval

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Launch Info at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in
                        LaunchAtLogin.setEnabled(on)
                        launchAtLogin = LaunchAtLogin.isEnabled
                        requiresLoginApproval = LaunchAtLogin.requiresApproval
                    }
                if requiresLoginApproval {
                    Text("macOS needs approval in Login Items.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Open Login Items Settings…") {
                        LaunchAtLogin.openSystemSettings()
                    }
                }
            }

            Section("Updates") {
                Picker("Refresh every", selection: Binding(
                    get: { prefs.updateInterval },
                    set: { prefs.updateInterval = $0; onIntervalChanged() }
                )) {
                    Text("1 second").tag(1.0)
                    Text("2 seconds").tag(2.0)
                    Text("3 seconds").tag(3.0)
                    Text("5 seconds").tag(5.0)
                }
                Text("Slower updates use less power.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("Version", value: appVersion)
                HStack {
                    Spacer()
                    Button("Quit Info") { NSApplication.shared.terminate(nil) }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: refreshLaunchAtLogin)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshLaunchAtLogin()
        }
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        return "v\(v)"
    }

    private func refreshLaunchAtLogin() {
        launchAtLogin = LaunchAtLogin.isEnabled
        requiresLoginApproval = LaunchAtLogin.requiresApproval
    }
}
