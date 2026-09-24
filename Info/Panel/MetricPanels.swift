import SwiftUI

/// Routes a `MetricKind` to its detail panel. Hosted in the status-item popover.
struct MetricPanel: View {
    static let contentWidth: CGFloat = 320
    static let padding: CGFloat = 16
    static var panelWidth: CGFloat { contentWidth + padding * 2 }

    let kind: MetricKind
    @Bindable var state: SamplingState
    let prefs: Preferences
    let activity: AppActivityState
    /// Invoked by the footer gear. When nil (e.g. snapshots), no footer shows.
    var onOpenSettings: (() -> Void)?
    /// Reports pin toggles so the host can keep the popover open.
    var onPinChanged: ((Bool) -> Void)?

    @State private var pinned = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Group {
                switch kind {
                case .cpu: CPUPanel(state: state, prefs: prefs, activity: activity)
                case .gpu: GPUPanel(state: state, prefs: prefs, activity: activity)
                case .memory: MemoryPanel(state: state, prefs: prefs, activity: activity)
                case .network: NetworkPanel(state: state, prefs: prefs, activity: activity)
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

private struct NetworkHeader: View {
    let status: MetricStatus

    private var statusText: String {
        switch status.availability {
        case .disabled: return "Disabled"
        case .loading: return "Loading"
        case .live: return "Live"
        case .stale: return "Stale"
        case .unavailable: return "Unavailable"
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Label("Network", systemImage: "network")
                .font(.headline)
            Spacer()
            Text(statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Network status")
        .accessibilityValue(statusText)
    }
}

private func staleDescription(_ status: MetricStatus) -> String {
    guard let updatedAt = status.updatedAt else { return "Showing the last available reading" }
    let seconds = max(0, Date().timeIntervalSince(updatedAt))
    if seconds < 60 { return "Showing the last reading \(Int(seconds.rounded()))s ago" }
    let minutes = Int((seconds / 60).rounded())
    return "Showing the last reading \(minutes)m ago"
}

private struct PanelHeader: View {
    let title: String
    let symbol: String
    let fraction: Double
    var tint: Color?
    var displayValue: String?
    var trailing: AnyView?

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Ring(fraction: fraction, tint: tint, title: title, displayValue: displayValue)
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
    let activity: AppActivityState
    @State private var processes = TopProcessesModel(kind: .cpu)
    @State private var temperature = TemperatureModel(kind: .cpu)

    var body: some View {
        let cpu = state.cpu
        let status = state.cpuStatus
        let displayValue = cpu == nil ? (status.isUnavailable ? "N/A" : "—") : nil
        VStack(alignment: .leading, spacing: 14) {
            PanelHeader(title: "CPU", symbol: "cpu", fraction: cpu?.total ?? 0,
                        displayValue: displayValue)

            HistoryChart(samples: state.cpuHistory.values,
                         tint: Theme.usage(cpu?.total ?? 0),
                         title: "CPU history")

            if cpu == nil {
                NoDataLabel(text: status.isLoading ? "Waiting for CPU data…" : "CPU data unavailable")
            } else if status.isStale {
                NoDataLabel(text: staleDescription(status))
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
                    if temperature.availability == .available, let t = temperature.celsius {
                        DetailRow(label: "Temperature", value: "\(Int(t))°C")
                    } else if temperature.availability == .loading {
                        DetailRow(label: "Temperature", value: "…")
                    } else if temperature.availability == .unavailable {
                        DetailRow(label: "Temperature", value: "Unavailable")
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                SectionLabel(text: "Top Processes")
                ProcessList(rows: processes.rows, loaded: processes.loaded)
            }
        }
        .onAppear {
            guard activity.shouldRunOptionalWork else { return }
            processes.start()
            temperature.start(enabled: prefs.showTemperature)
        }
        .onChange(of: prefs.showTemperature) { _, enabled in
            guard activity.shouldRunOptionalWork else {
                temperature.stop()
                return
            }
            if enabled {
                temperature.start(enabled: true)
            } else {
                temperature.stop()
            }
        }
        .onChange(of: activity.shouldRunOptionalWork) { _, allowed in
            if allowed {
                processes.start()
                temperature.start(enabled: prefs.showTemperature)
            } else {
                processes.stop()
                temperature.stop()
            }
        }
        .onDisappear { processes.stop(); temperature.stop() }
    }
}

// MARK: - Memory

struct MemoryPanel: View {
    @Bindable var state: SamplingState
    let prefs: Preferences
    let activity: AppActivityState
    @State private var processes = TopProcessesModel(kind: .memory)

    var body: some View {
        let memory = state.memory
        let status = state.memoryStatus
        let displayValue = memory == nil ? (status.isUnavailable ? "N/A" : "—") : nil
        VStack(alignment: .leading, spacing: 14) {
            PanelHeader(
                title: "Memory", symbol: "memorychip",
                fraction: memory?.usage ?? 0,
                tint: memory.map { Theme.pressure($0.pressure) },
                displayValue: displayValue,
                trailing: AnyView(
                    Text(memory.map { pressureText($0.pressure) } ?? (status.isLoading ? "Loading" : "Unavailable"))
                        .font(.caption).foregroundStyle(.secondary)))

            HistoryChart(samples: state.memoryHistory.values,
                         tint: memory.map { Theme.pressure($0.pressure) } ?? .blue,
                         title: "Memory history")

            if memory == nil {
                NoDataLabel(text: status.isLoading ? "Waiting for memory data…" : "Memory data unavailable")
            } else if status.isStale {
                NoDataLabel(text: staleDescription(status))
            }

            if let memory {
                StackedBar(segments: [
                    .init(value: Double(memory.app), color: .blue),
                    .init(value: Double(memory.wired), color: .orange),
                    .init(value: Double(memory.compressed), color: .purple),
                    .init(value: Double(memory.cached), color: .cyan),
                    .init(value: Double(memory.free), color: Color(.tertiaryLabelColor)),
                ])

                VStack(spacing: 6) {
                    DetailRow(label: "App", value: Fmt.bytes(memory.app), swatch: .blue)
                    DetailRow(label: "Wired", value: Fmt.bytes(memory.wired), swatch: .orange)
                    DetailRow(label: "Compressed", value: Fmt.bytes(memory.compressed), swatch: .purple)
                    DetailRow(label: "Cached", value: Fmt.bytes(memory.cached), swatch: .cyan)
                    DetailRow(label: "Free", value: Fmt.bytes(memory.free), swatch: Color(.tertiaryLabelColor))
                    if memory.swapUsed > 0 {
                        DetailRow(label: "Swap", value: Fmt.bytes(memory.swapUsed))
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                SectionLabel(text: "Top Processes")
                ProcessList(rows: processes.rows, loaded: processes.loaded)
            }
        }
        .onAppear {
            if activity.shouldRunOptionalWork { processes.start() }
        }
        .onChange(of: activity.shouldRunOptionalWork) { _, allowed in
            if allowed { processes.start() } else { processes.stop() }
        }
        .onDisappear { processes.stop() }
    }

    private func pressureText(_ pressure: MemoryPressure) -> String {
        switch pressure {
        case .normal: return "Pressure: Normal"
        case .warning: return "Pressure: Warning"
        case .critical: return "Pressure: Critical"
        case .unavailable: return "Pressure: Unavailable"
        }
    }
}

// MARK: - GPU

struct GPUPanel: View {
    @Bindable var state: SamplingState
    let prefs: Preferences
    let activity: AppActivityState
    @State private var temperature = TemperatureModel(kind: .gpu)

    var body: some View {
        let gpu = state.gpu
        let status = state.gpuStatus
        let history = state.gpuHistory.values
        let displayValue = gpu == nil ? (status.isUnavailable ? "N/A" : "—") : nil
        VStack(alignment: .leading, spacing: 14) {
            PanelHeader(
                title: "GPU", symbol: MetricKind.gpu.symbolName,
                fraction: gpu?.utilization ?? 0,
                displayValue: displayValue,
                trailing: AnyView(
                    Text(gpu?.name ?? (status.isLoading ? "Loading" : "Unavailable"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)))

            HistoryChart(samples: history,
                         tint: Theme.usage(gpu?.utilization ?? 0),
                         title: "GPU history")

            if let gpu {
                VStack(alignment: .leading, spacing: 6) {
                    SectionLabel(text: "Utilization")
                    DetailRow(label: "Device", value: Fmt.percent(gpu.utilization))
                    if let renderer = gpu.renderUtilization {
                        DetailRow(label: "Renderer", value: Fmt.percent(renderer))
                    }
                    if let tiler = gpu.tilerUtilization {
                        DetailRow(label: "Tiler", value: Fmt.percent(tiler))
                    }
                    if temperature.availability == .available, let celsius = temperature.celsius {
                        DetailRow(label: "Temperature", value: "\(Int(celsius))°C")
                    } else if temperature.availability == .loading {
                        DetailRow(label: "Temperature", value: "…")
                    } else if temperature.availability == .unavailable {
                        DetailRow(label: "Temperature", value: "Unavailable")
                    }
                }

                if gpu.inUseMemory != nil || gpu.allocatedMemory != nil {
                    VStack(alignment: .leading, spacing: 6) {
                        SectionLabel(text: "Memory")
                        if let allocation = gpu.allocatedMemory, allocation > 0 {
                            let inUse = min(gpu.inUseMemory ?? 0, allocation)
                            StackedBar(segments: [
                                .init(value: Double(inUse), color: .purple),
                                .init(value: Double(allocation - inUse), color: Color(.tertiaryLabelColor)),
                            ])
                        }
                        if let inUse = gpu.inUseMemory {
                            DetailRow(label: "In Use", value: Fmt.bytes(inUse), swatch: .purple)
                        }
                        if let allocation = gpu.allocatedMemory {
                            DetailRow(label: "Allocated", value: Fmt.bytes(allocation),
                                      swatch: Color(.tertiaryLabelColor))
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    SectionLabel(text: "Recent samples")
                    DetailRow(label: "Peak", value: Fmt.percent(history.map(\.value).peak))
                    DetailRow(label: "Average", value: Fmt.percent(history.map(\.value).mean))
                }
            } else {
                NoDataLabel(text: status.isLoading ? "Waiting for GPU data…" : "GPU data unavailable")
            }
        }
        .onAppear {
            if activity.shouldRunOptionalWork { temperature.start(enabled: prefs.showTemperature) }
        }
        .onChange(of: prefs.showTemperature) { _, enabled in
            guard activity.shouldRunOptionalWork else {
                temperature.stop()
                return
            }
            if enabled {
                temperature.start(enabled: true)
            } else {
                temperature.stop()
            }
        }
        .onChange(of: activity.shouldRunOptionalWork) { _, allowed in
            if allowed {
                temperature.start(enabled: prefs.showTemperature)
            } else {
                temperature.stop()
            }
        }
        .onDisappear { temperature.stop() }
    }
}

// MARK: - Network

struct NetworkPanel: View {
    @Bindable var state: SamplingState
    let prefs: Preferences
    let activity: AppActivityState
    @State private var localIP: String?
    @State private var extras = NetworkExtrasModel()

    var body: some View {
        let network = state.network
        let status = state.networkStatus
        let downloadHistory = state.netDownHistory.values
        let uploadHistory = state.netUpHistory.values
        VStack(alignment: .leading, spacing: 14) {
            NetworkHeader(status: status)

            if status.isStale {
                NoDataLabel(text: staleDescription(status))
            }

            HStack(spacing: 16) {
                bigRate(title: "Download rate", symbol: "arrow.down", color: Theme.download,
                        value: network.map { Fmt.rate($0.downloadBytesPerSec) } ?? "—")
                bigRate(title: "Upload rate", symbol: "arrow.up", color: Theme.upload,
                        value: network.map { Fmt.rate($0.uploadBytesPerSec) } ?? "—")
            }

            DualHistoryChart(downloadSamples: downloadHistory,
                             uploadSamples: uploadHistory)

            if let network {
                VStack(alignment: .leading, spacing: 6) {
                    SectionLabel(text: "Recent samples")
                    DetailRow(label: "Peak ↓", value: Fmt.rate(UInt64(downloadHistory.map(\.value).peak)), swatch: Theme.download)
                    DetailRow(label: "Peak ↑", value: Fmt.rate(UInt64(uploadHistory.map(\.value).peak)), swatch: Theme.upload)
                    DetailRow(label: "Average ↓", value: Fmt.rate(UInt64(downloadHistory.map(\.value).mean)), swatch: Theme.download)
                    DetailRow(label: "Average ↑", value: Fmt.rate(UInt64(uploadHistory.map(\.value).mean)), swatch: Theme.upload)
                    DetailRow(label: "Total ↓", value: Fmt.bytes(network.totalDownloaded), swatch: Theme.download)
                    DetailRow(label: "Total ↑", value: Fmt.bytes(network.totalUploaded), swatch: Theme.upload)
                }

                VStack(alignment: .leading, spacing: 6) {
                    SectionLabel(text: "Connection")
                    DetailRow(label: "Interface", value: network.interface ?? "—")
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
                NoDataLabel(text: status.isLoading ? "Waiting for network data…" : "Network data unavailable")
            }
        }
        .onAppear {
            refreshLocalIP(for: network)
            if activity.shouldRunOptionalWork {
                extras.start(showIP: prefs.showPublicIP, showLatency: prefs.showConnectivity)
            }
        }
        .onChange(of: prefs.showPublicIP) { _, _ in restartExtras() }
        .onChange(of: prefs.showConnectivity) { _, _ in restartExtras() }
        .onChange(of: state.network?.interface) { _, _ in
            refreshLocalIP(for: state.network)
        }
        .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { _ in
            refreshLocalIP(for: state.network)
        }
        .onChange(of: activity.shouldRunOptionalWork) { _, allowed in
            if allowed {
                extras.start(showIP: prefs.showPublicIP, showLatency: prefs.showConnectivity)
            } else {
                extras.stop()
            }
        }
        .onDisappear { extras.stop() }
    }

    private func refreshLocalIP(for network: NetworkSample?) {
        localIP = NetworkInfo.localAddress(interface: network?.interface)
    }

    private func restartExtras() {
        extras.stop()
        if activity.shouldRunOptionalWork {
            extras.start(showIP: prefs.showPublicIP, showLatency: prefs.showConnectivity)
        }
    }

    private func bigRate(title: String, symbol: String, color: Color, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Image(systemName: symbol).foregroundStyle(color)
            Text(value).font(.system(.title3, design: .rounded)).monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(value)
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
