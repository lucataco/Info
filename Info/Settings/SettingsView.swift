import SwiftUI

/// Tabbed settings modal (Stats-style): pick which metrics show, customize the
/// menu bar look, and manage general app behavior like launch-at-login.
struct SettingsView: View {
    @Bindable var prefs: Preferences
    let state: SamplingState
    var onMetricsChanged: () -> Void
    var onIntervalChanged: () -> Void
    var onStyleChanged: () -> Void
    var onAppearanceChanged: () -> Void

    var body: some View {
        TabView {
            MetricsTab(prefs: prefs, onMetricsChanged: onMetricsChanged)
                .tabItem { Label("Metrics", systemImage: "square.grid.2x2") }

            MenuBarTab(prefs: prefs, state: state, onStyleChanged: onStyleChanged)
                .tabItem { Label("Menu Bar", systemImage: "menubar.rectangle") }

            GeneralTab(prefs: prefs,
                       onIntervalChanged: onIntervalChanged,
                       onAppearanceChanged: onAppearanceChanged)
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
                    .accessibilityLabel("Show \(kind.title) in menu bar")
                }
            }

            Section {
                Toggle(isOn: $prefs.showTemperature) {
                    Text("CPU & GPU temperature")
                    Text("Reads the SMC. Uses a little more power.")
                }
                .accessibilityLabel("CPU and GPU temperature")
                Toggle(isOn: $prefs.showConnectivity) {
                    Text("Connectivity latency")
                    Text("Measures ping only while the Network panel is open.")
                }
                .accessibilityLabel("Connectivity latency")
                Toggle(isOn: $prefs.showPublicIP) {
                    Text("Public IP address")
                    Text("Makes one external request when the Network panel opens.")
                }
                .accessibilityLabel("Public IP address")
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
    let state: SamplingState
    var onStyleChanged: () -> Void

    var body: some View {
        Form {
            Section {
                MenuBarPreviewStrip(prefs: prefs, state: state)
            } header: {
                Text("Preview")
            } footer: {
                Text("Live preview of your menu bar items. Click any real item for full charts and details.")
            }

            Section("Appearance") {
                Picker("Label", selection: Binding(
                    get: { prefs.menuBarLabel },
                    set: { prefs.menuBarLabel = $0; onStyleChanged() }
                )) {
                    ForEach(MenuBarLabelStyle.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)

                VStack(alignment: .leading, spacing: 4) {
                    Picker("Layout", selection: Binding(
                        get: { prefs.menuBarLayout },
                        set: { prefs.menuBarLayout = $0; onStyleChanged() }
                    )) {
                        ForEach(MenuBarLayout.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .disabled(!prefs.showMenuBarValue)

                    if !prefs.showMenuBarValue {
                        Text("Layout arranges the value, so it applies when “Show value” is on.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else if prefs.menuBarLayout == .stacked && prefs.isEnabled(.network) {
                        Text("The Network item stays inline so both rates fit in the bar.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

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
                .accessibilityLabel("Show value")

                Toggle(isOn: Binding(
                    get: { prefs.showMenuBarSparkline },
                    set: { prefs.showMenuBarSparkline = $0; onStyleChanged() }
                )) {
                    Text("Show graph")
                    Text("Wide graph items may not fit on crowded menu bars.")
                }
                .accessibilityLabel("Show graph")
            }
        }
        .formStyle(.grouped)
    }
}

/// Renders the *real* `MenuBarItemView`s with live sampling data on a
/// menu-bar-like strip, so every appearance option shows its effect instantly.
private struct MenuBarPreviewStrip: View {
    @Bindable var prefs: Preferences
    let state: SamplingState

    var body: some View {
        HStack(spacing: 14) {
            if prefs.enabledMetrics.isEmpty {
                Text("No metrics enabled — turn one on in the Metrics tab.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(prefs.enabledMetrics) { kind in
                    MenuBarItemPreview(kind: kind,
                                       style: prefs.menuBarStyle,
                                       data: MenuBarItemData.current(for: kind, state: state))
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity)
        .background(.quaternary.opacity(0.6), in: .rect(cornerRadius: 8))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Menu bar preview")
    }
}

/// Hosts one AppKit `MenuBarItemView` (the same class the status bar uses).
private struct MenuBarItemPreview: NSViewRepresentable {
    let kind: MetricKind
    let style: MenuBarStyle
    let data: MenuBarItemData

    func makeNSView(context: Context) -> MenuBarItemView {
        let view = MenuBarItemView(kind: kind, style: style)
        view.apply(data)
        return view
    }

    func updateNSView(_ view: MenuBarItemView, context: Context) {
        view.style = style
        view.apply(data)
    }

    func sizeThatFits(_ proposal: ProposedViewSize,
                      nsView: MenuBarItemView,
                      context: Context) -> CGSize? {
        CGSize(width: nsView.preferredWidth(), height: NSStatusBar.system.thickness)
    }
}

// MARK: - General

private struct GeneralTab: View {
    @Bindable var prefs: Preferences
    var onIntervalChanged: () -> Void
    var onAppearanceChanged: () -> Void
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var requiresLoginApproval = LaunchAtLogin.requiresApproval
    @State private var loginChangeFailed = false

    private static let privacyURL = URL(string: "https://github.com/lucataco/Info/blob/main/PRIVACY.md")!
    private static let catacolabsURL = URL(string: "https://catacolabs.com")!

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Theme", selection: Binding(
                    get: { prefs.appearance },
                    set: { prefs.appearance = $0; onAppearanceChanged() }
                )) {
                    ForEach(AppearanceMode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Text("System follows your macOS light or dark setting.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Startup") {
                Toggle("Launch Info at login", isOn: $launchAtLogin)
                    .accessibilityLabel("Launch Info at login")
                    .onChange(of: launchAtLogin) { _, on in
                        guard on != LaunchAtLogin.isEnabled else { return }
                        loginChangeFailed = !LaunchAtLogin.setEnabled(on)
                        launchAtLogin = LaunchAtLogin.isEnabled
                        requiresLoginApproval = LaunchAtLogin.requiresApproval
                    }
                if loginChangeFailed {
                    Text("macOS wouldn’t change the login item. Try again, or manage it in Login Items settings.")
                        .font(.caption).foregroundStyle(.red)
                    Button("Open Login Items Settings…") {
                        LaunchAtLogin.openSystemSettings()
                    }
                } else if requiresLoginApproval {
                    Text("macOS needs approval in Login Items.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Open Login Items Settings…") {
                        LaunchAtLogin.openSystemSettings()
                    }
                }
            }

            Section("Refresh rate") {
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
                LabeledContent("Made by") {
                    Link("Catacolabs", destination: Self.catacolabsURL)
                }
                Link("Privacy — everything stays on your Mac", destination: Self.privacyURL)
                    .font(.callout)
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
