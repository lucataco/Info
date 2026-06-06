import SwiftUI

/// Routes a `MetricKind` to its detail panel. Hosted in the status-item popover.
struct MetricPanel: View {
    let kind: MetricKind
    @Bindable var state: SamplingState
    let prefs: Preferences

    var body: some View {
        Group {
            switch kind {
            case .cpu: CPUPanel(state: state, prefs: prefs)
            case .gpu: GPUPanel(state: state, prefs: prefs)
            case .memory: MemoryPanel(state: state)
            case .network: NetworkPanel(state: state, prefs: prefs)
            }
        }
        .frame(width: 300)
        .padding(16)
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

            HistoryChart(values: state.cpuHistory.values, tint: Theme.usage(cpu?.total ?? 0))

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
                ProcessList(rows: processes.rows)
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
                         tint: mem.map { Theme.pressure($0.pressure) } ?? .blue)

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
                    DetailRow(label: "Free", value: Fmt.bytes(mem.free), swatch: Color(.tertiaryLabelColor))
                    if mem.swapUsed > 0 {
                        DetailRow(label: "Swap", value: Fmt.bytes(mem.swapUsed))
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                SectionLabel(text: "Top Processes")
                ProcessList(rows: processes.rows)
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
        VStack(alignment: .leading, spacing: 14) {
            PanelHeader(
                title: "GPU", symbol: MetricKind.gpu.symbolName,
                fraction: gpu?.utilization ?? 0,
                trailing: AnyView(
                    Text(gpu?.name ?? "—").font(.caption).foregroundStyle(.secondary).lineLimit(1)))

            HistoryChart(values: state.gpuHistory.values, tint: Theme.usage(gpu?.utilization ?? 0))

            if let gpu {
                VStack(spacing: 6) {
                    DetailRow(label: "Utilization", value: Fmt.percent(gpu.utilization))
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
            } else {
                Text("No GPU data").font(.caption).foregroundStyle(.secondary)
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
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 16) {
                bigRate(symbol: "arrow.down", color: Theme.download,
                        value: net.map { Fmt.rate($0.downloadBytesPerSec) } ?? "—")
                bigRate(symbol: "arrow.up", color: Theme.upload,
                        value: net.map { Fmt.rate($0.uploadBytesPerSec) } ?? "—")
            }

            DualHistoryChart(download: state.netDownHistory.values,
                             upload: state.netUpHistory.values)

            if let net {
                VStack(spacing: 6) {
                    DetailRow(label: "Total ↓", value: Fmt.bytes(net.totalDownloaded), swatch: Theme.download)
                    DetailRow(label: "Total ↑", value: Fmt.bytes(net.totalUploaded), swatch: Theme.upload)
                    DetailRow(label: "Interface", value: net.interface ?? "—")
                    DetailRow(label: "Local IP", value: localIP ?? "—")
                    if prefs.showConnectivity {
                        DetailRow(label: "Latency",
                                  value: extras.latencyMs.map { "\(Int($0)) ms" } ?? "…")
                    }
                    if prefs.showPublicIP {
                        DetailRow(label: "Public IP", value: extras.publicIP ?? "…")
                    }
                }
            }
        }
        .onAppear {
            localIP = NetworkInfo.localIPv4(interface: state.network?.interface)
            extras.start(showIP: prefs.showPublicIP, showLatency: prefs.showConnectivity)
        }
        .onChange(of: prefs.showPublicIP) { _, _ in restartExtras() }
        .onChange(of: prefs.showConnectivity) { _, _ in restartExtras() }
        .onChange(of: state.network?.interface) { _, interface in
            localIP = NetworkInfo.localIPv4(interface: interface)
        }
        .onDisappear { extras.stop() }
    }

    private func restartExtras() {
        extras.stop()
        extras.start(showIP: prefs.showPublicIP, showLatency: prefs.showConnectivity)
    }

    private func bigRate(symbol: String, color: Color, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Image(systemName: symbol).foregroundStyle(color)
            Text(value).font(.system(.title3, design: .rounded)).monospacedDigit()
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
