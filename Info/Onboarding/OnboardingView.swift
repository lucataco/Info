import SwiftUI
import AppKit

/// First-run onboarding. Lives in its own window. Uses the *real* live
/// `SamplingState`, so the previews animate as the machine is actually sampled —
/// that's the "magic" moment, especially on the Choose-metrics step where the
/// menu bar visibly updates as you toggle.
struct OnboardingView: View {
    // Plain `let`s (not @Bindable): the view still observes `state` because the
    // body reads its @Observable properties; two-way bindings are built manually.
    let prefs: Preferences
    let state: SamplingState
    let statusItemsProvider: () -> [NSStatusItem]
    let onMetricsChanged: () -> Void
    let onFinish: () -> Void

    @State private var step: Int
    @State private var menuBarVisible = false
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var requiresLoginApproval = LaunchAtLogin.requiresApproval
    @State private var loginChangeFailed = false

    private let lastStep = 4

    init(prefs: Preferences,
         state: SamplingState,
         statusItemsProvider: @escaping () -> [NSStatusItem],
         onMetricsChanged: @escaping () -> Void,
         onFinish: @escaping () -> Void,
         initialStep: Int = 0) {
        self.prefs = prefs
        self.state = state
        self.statusItemsProvider = statusItemsProvider
        self.onMetricsChanged = onMetricsChanged
        self.onFinish = onFinish
        self._step = State(initialValue: initialStep)
    }

    var body: some View {
        VStack(spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 36)
                .padding(.top, 44)

            footer
                .padding(20)
        }
        .frame(width: 540, height: 500)
        .background(.background)
        .onAppear(perform: refreshLaunchAtLogin)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshLaunchAtLogin()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case 0: welcome
        case 1: menuBarStep
        case 2: loginStep
        case 3: metricsStep
        default: doneStep
        }
    }

    // MARK: - Steps

    private var welcome: some View {
        VStack(spacing: 18) {
            HeroIcon(symbol: "gauge.open.with.lines.needle.33percent",
                     colors: [.blue, .cyan])
            Text("Welcome to Info")
                .font(.system(.largeTitle, design: .rounded).weight(.bold))
            Text("Your Mac's vitals, at a glance.\nPrivate by design — everything stays on your Mac.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .font(.title3)
        }
    }

    private var menuBarStep: some View {
        VStack(spacing: 18) {
            HeroIcon(symbol: "menubar.arrow.up.rectangle", colors: [.indigo, .purple])
            Text("Look up at your menu bar")
                .font(.system(.title, design: .rounded).weight(.bold))
            Text("Info lives at the top-right of your screen, showing live readings for CPU, GPU, memory, and network.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Image(systemName: menuBarVisible ? "checkmark.circle.fill" : "magnifyingglass")
                    .foregroundStyle(menuBarVisible ? .green : .secondary)
                    .contentTransition(.symbolEffect(.replace))
                Text(menuBarVisible ? "There it is!" : "Looking for Info…")
                    .font(.headline)
            }
            .padding(.top, 4)

            if !menuBarVisible {
                VStack(spacing: 6) {
                    Text("Don't see it? macOS 26 may be hiding it.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Open Menu Bar Settings…") {
                        MenuBarVisibility.openMenuBarSettings()
                    }
                    .controlSize(.small)
                }
            }
        }
        .onReceive(Timer.publish(every: 0.6, on: .main, in: .common).autoconnect()) { _ in
            menuBarVisible = MenuBarVisibility.isLikelyVisible(statusItemsProvider())
        }
    }

    private var loginStep: some View {
        VStack(spacing: 18) {
            HeroIcon(symbol: "power", colors: [.green, .mint])
            Text("Start automatically")
                .font(.system(.title, design: .rounded).weight(.bold))
            Text("Info launches quietly when you log in, so your stats are always there.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            Toggle(isOn: Binding(
                get: { launchAtLogin },
                set: { enabled in
                    loginChangeFailed = !LaunchAtLogin.setEnabled(enabled)
                    refreshLaunchAtLogin()
                }
            )) {
                Text("Launch Info at login")
            }
            .toggleStyle(.switch)
            .padding(.horizontal, 80)
            .padding(.top, 6)

            if loginChangeFailed {
                Text("macOS wouldn’t change the login item. You can also set it later in Settings › General.")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            } else if requiresLoginApproval {
                Text("macOS needs approval in Login Items before Info can launch automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Open Login Items Settings…") {
                    LaunchAtLogin.openSystemSettings()
                }
                .controlSize(.small)
            }
        }
    }

    private func refreshLaunchAtLogin() {
        launchAtLogin = LaunchAtLogin.isEnabled
        requiresLoginApproval = LaunchAtLogin.requiresApproval
    }

    private var metricsStep: some View {
        VStack(spacing: 14) {
            Text("Choose what to monitor")
                .font(.system(.title, design: .rounded).weight(.bold))
            Text("Toggle any metric and watch your menu bar update instantly.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .font(.callout)

            VStack(spacing: 10) {
                ForEach(MetricKind.allCases) { kind in
                    MetricChooserRow(
                        kind: kind, state: state,
                        isOn: Binding(
                            get: { prefs.isEnabled(kind) },
                            set: { prefs.setEnabled(kind, $0); onMetricsChanged() }))
                }
            }
            .padding(.top, 4)
        }
    }

    private var doneStep: some View {
        VStack(spacing: 18) {
            HeroIcon(symbol: "checkmark.seal.fill", colors: [.blue, .green])
            Text("You're all set!")
                .font(.system(.largeTitle, design: .rounded).weight(.bold))
            Text("Click any menu bar item to see its details.\nSettings are a right-click — or the gear in any panel — away.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .font(.title3)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            if step > 0 {
                Button("Back") { withAnimation { step -= 1 } }
                    .controlSize(.large)
            }
            Spacer()
            StepDots(count: lastStep + 1, current: step)
            Spacer()
            if step < lastStep {
                Button("Skip") { onFinish() }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .controlSize(.large)
                    .accessibilityLabel("Skip onboarding")
            }
            Button(step == lastStep ? "Done" : "Continue") {
                if step == lastStep {
                    onFinish()
                } else {
                    withAnimation { step += 1 }
                }
            }
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        }
    }
}

// MARK: - Pieces

private struct HeroIcon: View {
    let symbol: String
    let colors: [Color]
    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 64))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom))
            .frame(height: 90)
    }
}

private struct StepDots: View {
    let count: Int
    let current: Int
    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { i in
                Circle()
                    .fill(i == current ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: 7, height: 7)
            }
        }
    }
}

private struct MetricChooserRow: View {
    let kind: MetricKind
    let state: SamplingState
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            Label(kind.title, systemImage: kind.symbolName)
                .font(.headline)
                .frame(width: 120, alignment: .leading)

            preview
                .frame(width: 130, height: 30)
                .opacity(isOn ? 1 : 0.3)

            Spacer()
            Toggle("", isOn: $isOn).labelsHidden()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 10))
    }

    @ViewBuilder
    private var preview: some View {
        switch kind {
        case .network:
            DualHistoryChart(download: state.netDownHistory.values,
                             upload: state.netUpHistory.values, height: 30, showsDetail: false)
        case .cpu:
            HistoryChart(values: state.cpuHistory.values,
                         tint: Theme.usage(state.cpu?.total ?? 0), height: 30, showsDetail: false)
        case .gpu:
            HistoryChart(values: state.gpuHistory.values,
                         tint: Theme.usage(state.gpu?.utilization ?? 0), height: 30, showsDetail: false)
        case .memory:
            HistoryChart(values: state.memoryHistory.values,
                         tint: state.memory.map { Theme.pressure($0.pressure) } ?? .blue,
                         height: 30, showsDetail: false)
        }
    }
}
