import SwiftUI

/// Routes a `MetricKind` to its detail panel. Hosted in the status-item popover.
struct MetricPanel: View {
    static let contentWidth: CGFloat = 320
    static let padding: CGFloat = 16
    static var panelWidth: CGFloat { contentWidth + padding * 2 }

    let kind: MetricKind
    @Bindable var state: SamplingState
    let prefs: Preferences
    /// Invoked by the footer gear. When nil (e.g. snapshots), no footer shows.
    var onOpenSettings: (() -> Void)?
    /// Reports pin toggles so the host can keep the popover open.
    var onPinChanged: ((Bool) -> Void)?

    @State private var pinned = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Group {
                switch kind {
                case .cpu: CPUPanel(state: state, prefs: prefs)
                case .gpu: GPUPanel(state: state, prefs: prefs)
                case .memory: MemoryPanel(state: state, prefs: prefs)
                case .network: NetworkPanel(state: state, prefs: prefs)
                }
            }
            if onOpenSettings != nil {
                footer
            }
        }
        .frame(width: Self.contentWidth)
        .padding(Self.padding)
        .frame(width: Self.panelWidth)
        .clipped()
    }

    /// Discoverability footer: Settings is otherwise reachable only via
    /// right-click on the status item; the pin keeps the panel open while the
    /// user works elsewhere.
    private var footer: some View {
        VStack(spacing: 8) {
            Divider()
            HStack {
                Button {
                    onOpenSettings?()
                } label: {
                    Label("Settings", systemImage: "gearshape")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Open Info settings")
                .accessibilityLabel("Settings")

                Spacer()

                Button {
                    pinned.toggle()
                    onPinChanged?(pinned)
                } label: {
                    Image(systemName: pinned ? "pin.fill" : "pin")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(pinned ? Color.accentColor : Color.secondary)
                .help(pinned ? "Unpin — panel closes when you click away"
                             : "Pin — keep this panel open while you work")
                .accessibilityLabel(pinned ? "Unpin panel" : "Pin panel")
            }
        }
    }
}

private struct PanelHeader: View {
    let title: String
    let symbol: String
    let fraction: Double
    var tint: Color?
    var trailing: AnyView?

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Ring(fraction: fraction, tint: tint)
            VStack(alignment: .leading, spacing: 2) {
                Label(title, systemImage: symbol)
                    .font(.headline)
                if let trailing { trailing }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Spacer()
        }
    }
}

// MARK: - CPU

struct CPUPanel: View {
    @Bindable var state: SamplingState
    let prefs: Preferences
    @State private var processes = TopProcessesModel(kind: .cpu)
    @State private var temperature = TemperatureModel(kind: .cpu)

    var body: some View {
        let cpu = state.cpu
        VStack(alignment: .leading, spacing: 14) {
            PanelHeader(title: "CPU", symbol: "cpu", fraction: cpu?.total ?? 0)

            HistoryChart(values: state.cpuHistory.values,
                         tint: Theme.usage(cpu?.total ?? 0),
                         secondsPerSample: prefs.updateInterval)

            if cpu == nil {
                NoDataLabel()
            }

            if let cpu, !cpu.perCore.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    SectionLabel(text: "Cores (\(cpu.perCore.count))")
                    CoreBars(cores: cpu.perCore)
                }
            }

            if let cpu {
                VStack(spacing: 6) {
                    DetailRow(label: "System", value: Fmt.percent(cpu.system), swatch: .red)
                    DetailRow(label: "User", value: Fmt.percent(cpu.user), swatch: .blue)
                    DetailRow(label: "Idle", value: Fmt.percent(cpu.idle), swatch: .gray)
                    if let t = temperature.celsius {
                        DetailRow(label: "Temperature", value: "\(Int(t))°C")
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                SectionLabel(text: "Top Processes")
                ProcessList(rows: processes.rows, loaded: processes.loaded)
            }
        }
        .onAppear { processes.start(); temperature.start(enabled: prefs.showTemperature) }
        .onChange(of: prefs.showTemperature) { _, enabled in
            enabled ? temperature.start(enabled: true) : temperature.stop()
        }
        .onDisappear { processes.stop(); temperature.stop() }
    }
}

// MARK: - Memory

struct MemoryPanel: View {
    @Bindable var state: SamplingState
    let prefs: Preferences
    @State private var processes = TopProcessesModel(kind: .memory)

    var body: some View {
        let mem = state.memory
        VStack(alignment: .leading, spacing: 14) {
            PanelHeader(
                title: "Memory", symbol: "memorychip",
                fraction: mem?.usage ?? 0,
                tint: mem.map { Theme.pressure($0.pressure) },
                trailing: AnyView(
                    Text(mem.map { pressureText($0.pressure) } ?? "")
                        .font(.caption).foregroundStyle(.secondary)))

            HistoryChart(values: state.memoryHistory.values,
                         tint: mem.map { Theme.pressure($0.pressure) } ?? .blue,
                         secondsPerSample: prefs.updateInterval)

            if mem == nil {
                NoDataLabel()
            }

            if let mem {
                StackedBar(segments: [
                    .init(value: Double(mem.app), color: .blue),
                    .init(value: Double(mem.wired), color: .orange),
                    .init(value: Double(mem.compressed), color: .purple),
                    .init(value: Double(mem.free), color: Color(.tertiaryLabelColor)),
                ])

                VStack(spacing: 6) {
                    DetailRow(label: "App", value: Fmt.bytes(mem.app), swatch: .blue)
                    DetailRow(label: "Wired", value: Fmt.bytes(mem.wired), swatch: .orange)
                    DetailRow(label: "Compressed", value: Fmt.bytes(mem.compressed), swatch: .purple)
                    DetailRow(label: "Cached", value: Fmt.bytes(mem.cached))
                    DetailRow(label: "Free", value: Fmt.bytes(mem.free), swatch: Color(.tertiaryLabelColor))
                    if mem.swapUsed > 0 {
                        DetailRow(label: "Swap", value: Fmt.bytes(mem.swapUsed))
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                SectionLabel(text: "Top Processes")
                ProcessList(rows: processes.rows, loaded: processes.loaded)
            }
        }
        .onAppear { processes.start() }
        .onDisappear { processes.stop() }
    }

    private func pressureText(_ p: MemoryPressure) -> String {
        switch p {
        case .normal: return "Pressure: Normal"
        case .warning: return "Pressure: Warning"
        case .critical: return "Pressure: Critical"
        }
    }
}

// MARK: - GPU

struct GPUPanel: View {
    @Bindable var state: SamplingState
    let prefs: Preferences
    @State private var temperature = TemperatureModel(kind: .gpu)

    var body: some View {
        let gpu = state.gpu
        let history = state.gpuHistory.values
        VStack(alignment: .leading, spacing: 14) {
            PanelHeader(
                title: "GPU", symbol: MetricKind.gpu.symbolName,
                fraction: gpu?.utilization ?? 0,
                trailing: AnyView(
                    Text(gpu?.name ?? "—")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)))

            HistoryChart(values: history,
                         tint: Theme.usage(gpu?.utilization ?? 0),
                         secondsPerSample: prefs.updateInterval)

            if let gpu {
                VStack(alignment: .leading, spacing: 6) {
                    SectionLabel(text: "Utilization")
                    DetailRow(label: "Device", value: Fmt.percent(gpu.utilization))
                    if let r = gpu.renderUtilization {
                        DetailRow(label: "Renderer", value: Fmt.percent(r))
                    }
                    if let t = gpu.tilerUtilization {
                        DetailRow(label: "Tiler", value: Fmt.percent(t))
                    }
                    if let t = temperature.celsius {
                        DetailRow(label: "Temperature", value: "\(Int(t))°C")
                    }
                }

                if gpu.inUseMemory != nil || gpu.allocatedMemory != nil {
                    VStack(alignment: .leading, spacing: 6) {
                        SectionLabel(text: "Memory")
                        if let alloc = gpu.allocatedMemory, alloc > 0 {
                            let inUse = min(gpu.inUseMemory ?? 0, alloc)
                            StackedBar(segments: [
                                .init(value: Double(inUse), color: .purple),
                                .init(value: Double(alloc - inUse), color: Color(.tertiaryLabelColor)),
                            ])
                        }
                        if let inUse = gpu.inUseMemory {
                            DetailRow(label: "In Use", value: Fmt.bytes(inUse), swatch: .purple)
                        }
                        if let alloc = gpu.allocatedMemory {
                            DetailRow(label: "Allocated", value: Fmt.bytes(alloc),
                                      swatch: Color(.tertiaryLabelColor))
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    SectionLabel(text: "Session")
                    DetailRow(label: "Peak", value: Fmt.percent(history.peak))
                    DetailRow(label: "Average", value: Fmt.percent(history.mean))
                }
            } else {
                NoDataLabel(text: "Waiting for GPU data…")
            }
        }
        .onAppear { temperature.start(enabled: prefs.showTemperature) }
        .onChange(of: prefs.showTemperature) { _, enabled in
            enabled ? temperature.start(enabled: true) : temperature.stop()
        }
        .onDisappear { temperature.stop() }
    }
}

// MARK: - Network

struct NetworkPanel: View {
    @Bindable var state: SamplingState
    let prefs: Preferences
    @State private var localIP: String?
    @State private var extras = NetworkExtrasModel()

    var body: some View {
        let net = state.network
        let downHistory = state.netDownHistory.values
        let upHistory = state.netUpHistory.values
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 16) {
                bigRate(symbol: "arrow.down", color: Theme.download,
                        value: net.map { Fmt.rate($0.downloadBytesPerSec) } ?? "—")
                bigRate(symbol: "arrow.up", color: Theme.upload,
                        value: net.map { Fmt.rate($0.uploadBytesPerSec) } ?? "—")
            }

            DualHistoryChart(download: downHistory, upload: upHistory,
                             secondsPerSample: prefs.updateInterval)

            if let net {
                VStack(alignment: .leading, spacing: 6) {
                    SectionLabel(text: "Session")
                    DetailRow(label: "Peak ↓", value: Fmt.rate(UInt64(downHistory.peak)), swatch: Theme.download)
                    DetailRow(label: "Peak ↑", value: Fmt.rate(UInt64(upHistory.peak)), swatch: Theme.upload)
                    DetailRow(label: "Average ↓", value: Fmt.rate(UInt64(downHistory.mean)), swatch: Theme.download)
                    DetailRow(label: "Average ↑", value: Fmt.rate(UInt64(upHistory.mean)), swatch: Theme.upload)
                    DetailRow(label: "Total ↓", value: Fmt.bytes(net.totalDownloaded), swatch: Theme.download)
                    DetailRow(label: "Total ↑", value: Fmt.bytes(net.totalUploaded), swatch: Theme.upload)
                }

                VStack(alignment: .leading, spacing: 6) {
                    SectionLabel(text: "Connection")
                    DetailRow(label: "Interface", value: net.interface ?? "—")
                    DetailRow(label: "Local IP", value: localIP ?? "—")
                    if prefs.showConnectivity {
                        DetailRow(label: "Latency",
                                  value: extras.latencyMs.map { "\(Int($0)) ms" }
                                      ?? (extras.latencyChecked ? "Unavailable" : "…"))
                    }
                    if prefs.showPublicIP {
                        DetailRow(label: "Public IP",
                                  value: extras.publicIP
                                      ?? (extras.publicIPChecked ? "Unavailable" : "…"))
                    }
                }
            } else {
                NoDataLabel()
            }
        }
        .onAppear {
            refreshLocalIP(for: state.network)
            extras.start(showIP: prefs.showPublicIP, showLatency: prefs.showConnectivity)
        }
        .onChange(of: prefs.showPublicIP) { _, _ in restartExtras() }
        .onChange(of: prefs.showConnectivity) { _, _ in restartExtras() }
        .onChange(of: state.network) { _, network in
            refreshLocalIP(for: network)
        }
        .onDisappear { extras.stop() }
    }

    private func refreshLocalIP(for network: NetworkSample?) {
        localIP = NetworkInfo.localAddress(interface: network?.interface)
    }

    private func restartExtras() {
        extras.stop()
        extras.start(showIP: prefs.showPublicIP, showLatency: prefs.showConnectivity)
    }

    private func bigRate(symbol: String, color: Color, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Image(systemName: symbol).foregroundStyle(color)
            Text(value).font(.system(.title3, design: .rounded)).monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - History stats

/// Lightweight summary stats over a metric's in-memory history series.
extension Array where Element == Double {
    /// Largest observed value (0 when empty).
    var peak: Double { self.max() ?? 0 }

    /// Arithmetic mean (0 when empty).
    var mean: Double { isEmpty ? 0 : reduce(0, +) / Double(count) }
}
