import SwiftUI
import Charts

enum Theme {
    /// blue -> orange -> red as utilization climbs.
    static func usage(_ fraction: Double) -> Color {
        if fraction >= 0.8 { return .red }
        if fraction >= 0.6 { return .orange }
        return .blue
    }

    static func pressure(_ p: MemoryPressure) -> Color {
        switch p {
        case .normal: return .green
        case .warning: return .orange
        case .critical: return .red
        }
    }

    static let download = Color.blue
    static let upload = Color.green
}

/// Consistent "no data yet" placeholder for panels whose collector hasn't
/// produced a sample (or can't on this machine).
struct NoDataLabel: View {
    var text = "Waiting for data…"
    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A circular gauge with the percentage in the middle.
struct Ring: View {
    let fraction: Double
    var tint: Color?
    var caption: String?

    var body: some View {
        ZStack {
            Circle().stroke(.quaternary, lineWidth: 6)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, fraction)))
                .stroke(tint ?? Theme.usage(fraction),
                        style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text(Fmt.percent(fraction))
                    .font(.system(.headline, design: .rounded)).monospacedDigit()
                    .contentTransition(.numericText())
                if let caption {
                    Text(caption).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: 62, height: 62)
        .animation(.easeOut(duration: 0.25), value: fraction)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Usage")
        .accessibilityValue(Fmt.percent(fraction))
    }
}

/// Helpers for turning sample indices into human-friendly time-axis labels.
/// Samples are stored oldest-first; the newest sample is "now".
enum TimeAxis {
    /// Total span covered by `samples` readings taken `secondsPerSample` apart.
    static func span(samples: Int, secondsPerSample: Double) -> String {
        short(Double(max(0, samples - 1)) * secondsPerSample)
    }

    /// How long ago a sample `samplesBack` from the newest was recorded.
    static func ago(samplesBack: Int, secondsPerSample: Double) -> String {
        let secs = Double(max(0, samplesBack)) * secondsPerSample
        return secs <= 0 ? "now" : short(secs) + " ago"
    }

    private static func short(_ secs: Double) -> String {
        guard secs >= 60 else { return "\(Int(secs.rounded()))s" }
        let minutes = secs / 60
        return abs(minutes.rounded() - minutes) < 0.05
            ? "\(Int(minutes.rounded()))m"
            : String(format: "%.1fm", minutes)
    }
}

/// Maps a hover location to the nearest sample index within the plot area.
private func hoverSampleIndex(location: CGPoint,
                              proxy: ChartProxy,
                              geometry: GeometryProxy,
                              count: Int) -> Int? {
    guard count > 1, let anchor = proxy.plotFrame else { return nil }
    let plot = geometry[anchor]
    let x = location.x - plot.minX
    guard x >= 0, x <= plot.width,
          let raw = proxy.value(atX: x, as: Double.self) else { return nil }
    return min(count - 1, max(0, Int(raw.rounded())))
}

/// A thin caption that frames the X axis as a time range ("2m ago … now").
private struct TimeAxisCaption: View {
    let samples: Int
    let secondsPerSample: Double

    var body: some View {
        HStack {
            Text(TimeAxis.span(samples: samples, secondsPerSample: secondsPerSample) + " ago")
            Spacer()
            Text("now")
        }
        .font(.caption2)
        .foregroundStyle(.tertiary)
    }
}

/// Interactive area+line history chart for a 0...1 series. Hovering reveals the
/// value and how long ago it was sampled; a faint Y axis labels the scale and a
/// caption labels the time span on the X axis.
struct HistoryChart: View {
    let values: [Double]
    var tint: Color = .accentColor
    var height: CGFloat = 54
    var secondsPerSample: Double = 2
    /// Formats a Y value for the readout and axis labels (default: percentage).
    var format: (Double) -> String = { Fmt.percent($0) }
    /// When false, renders a bare sparkline (no readout, axes, or hover) for
    /// compact decorative use such as the onboarding previews.
    var showsDetail: Bool = true

    @State private var hoverIndex: Int?

    private var lastIndex: Int { max(0, values.count - 1) }

    private var hovered: (index: Int, value: Double)? {
        guard let i = hoverIndex, values.indices.contains(i) else { return nil }
        return (i, values[i])
    }

    var body: some View {
        if showsDetail {
            VStack(alignment: .leading, spacing: 3) {
                readout
                chart
                TimeAxisCaption(samples: values.count, secondsPerSample: secondsPerSample)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("History chart")
            .accessibilityValue("\(format(values.last ?? 0)) now, peak \(format(values.peak))")
        } else {
            Chart { marks }
                .chartYScale(domain: 0...1)
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .frame(height: height)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder private var readout: some View {
        HStack(spacing: 6) {
            if let h = hovered {
                Text(format(h.value))
                    .font(.caption.weight(.semibold)).monospacedDigit()
                    .foregroundStyle(tint)
                Text(TimeAxis.ago(samplesBack: lastIndex - h.index, secondsPerSample: secondsPerSample))
                    .font(.caption2).foregroundStyle(.secondary)
            } else {
                Text("Peak \(format(values.peak))")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .frame(height: 13)
    }

    @ChartContentBuilder private var marks: some ChartContent {
        ForEach(Array(values.enumerated()), id: \.offset) { item in
            AreaMark(x: .value("t", Double(item.offset)), y: .value("v", item.element))
                .foregroundStyle(LinearGradient(colors: [tint.opacity(0.25), tint.opacity(0.02)],
                                                startPoint: .top, endPoint: .bottom))
            LineMark(x: .value("t", Double(item.offset)), y: .value("v", item.element))
                .foregroundStyle(tint)
                .interpolationMethod(.monotone)
        }
        if let h = hovered {
            RuleMark(x: .value("t", Double(h.index)))
                .foregroundStyle(.secondary.opacity(0.4))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 2]))
            PointMark(x: .value("t", Double(h.index)), y: .value("v", h.value))
                .foregroundStyle(tint)
                .symbolSize(36)
        }
    }

    private var chart: some View {
        Chart { marks }
        .chartYScale(domain: 0...1)
        .chartXScale(domain: 0...Double(max(1, lastIndex)))
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(position: .leading, values: [0, 0.5, 1.0]) { value in
                AxisGridLine().foregroundStyle(.secondary.opacity(0.12))
                AxisValueLabel {
                    if let d = value.as(Double.self) {
                        Text(format(d)).font(.caption2).foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .frame(height: height)
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            hoverIndex = hoverSampleIndex(location: location, proxy: proxy,
                                                          geometry: geo, count: values.count)
                        case .ended:
                            hoverIndex = nil
                        }
                    }
            }
        }
    }
}

/// Interactive dual line chart for network up/down (bytes/sec, auto-scaled).
/// Hovering reveals the download/upload rate at that moment; the Y axis labels
/// the auto-scaled rate and the caption labels the time span.
struct DualHistoryChart: View {
    let download: [Double]
    let upload: [Double]
    var height: CGFloat = 54
    var secondsPerSample: Double = 2
    /// When false, renders a bare sparkline (no readout, axes, or hover) for
    /// compact decorative use such as the onboarding previews.
    var showsDetail: Bool = true

    @State private var hoverIndex: Int?

    private var count: Int { min(download.count, upload.count) }
    private var lastIndex: Int { max(0, count - 1) }
    private var scale: Double { max(1, (download + upload).max() ?? 1) }

    private var hovered: (index: Int, down: Double, up: Double)? {
        guard let i = hoverIndex, download.indices.contains(i), upload.indices.contains(i) else { return nil }
        return (i, download[i], upload[i])
    }

    var body: some View {
        if showsDetail {
            VStack(alignment: .leading, spacing: 3) {
                readout
                chart
                TimeAxisCaption(samples: count, secondsPerSample: secondsPerSample)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Network history chart")
            .accessibilityValue("Download \(Fmt.rate(UInt64(download.last ?? 0))), upload \(Fmt.rate(UInt64(upload.last ?? 0)))")
        } else {
            Chart { marks(scale: scale) }
                .chartYScale(domain: 0...1)
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .frame(height: height)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder private var readout: some View {
        HStack(spacing: 8) {
            if let h = hovered {
                rateLabel(symbol: "arrow.down", color: Theme.download, bytesPerSec: h.down)
                rateLabel(symbol: "arrow.up", color: Theme.upload, bytesPerSec: h.up)
                Text(TimeAxis.ago(samplesBack: lastIndex - h.index, secondsPerSample: secondsPerSample))
                    .font(.caption2).foregroundStyle(.secondary)
            } else {
                Text("Scale \(Fmt.rate(UInt64(scale)))")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .frame(height: 13)
    }

    private func rateLabel(symbol: String, color: Color, bytesPerSec: Double) -> some View {
        HStack(spacing: 2) {
            Image(systemName: symbol).font(.caption2.weight(.bold)).foregroundStyle(color)
            Text(Fmt.rate(UInt64(max(0, bytesPerSec)))).font(.caption2.weight(.semibold)).monospacedDigit()
        }
    }

    @ChartContentBuilder private func marks(scale: Double) -> some ChartContent {
        ForEach(Array(download.enumerated()), id: \.offset) { item in
            AreaMark(x: .value("t", Double(item.offset)), y: .value("v", item.element / scale),
                     series: .value("s", "Download"))
                .foregroundStyle(Theme.download.opacity(0.18))
            LineMark(x: .value("t", Double(item.offset)), y: .value("v", item.element / scale),
                     series: .value("s", "Download"))
                .foregroundStyle(Theme.download)
                .interpolationMethod(.monotone)
        }
        ForEach(Array(upload.enumerated()), id: \.offset) { item in
            LineMark(x: .value("t", Double(item.offset)), y: .value("v", item.element / scale),
                     series: .value("s", "Upload"))
                .foregroundStyle(Theme.upload)
                .interpolationMethod(.monotone)
        }
        if let h = hovered {
            RuleMark(x: .value("t", Double(h.index)))
                .foregroundStyle(.secondary.opacity(0.4))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 2]))
            PointMark(x: .value("t", Double(h.index)), y: .value("v", h.down / scale))
                .foregroundStyle(Theme.download)
                .symbolSize(36)
            PointMark(x: .value("t", Double(h.index)), y: .value("v", h.up / scale))
                .foregroundStyle(Theme.upload)
                .symbolSize(36)
        }
    }

    private var chart: some View {
        let scale = self.scale
        return Chart { marks(scale: scale) }
        .chartYScale(domain: 0...1)
        .chartXScale(domain: 0...Double(max(1, lastIndex)))
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(position: .leading, values: [0, 0.5, 1.0]) { value in
                AxisGridLine().foregroundStyle(.secondary.opacity(0.12))
                AxisValueLabel {
                    if let d = value.as(Double.self) {
                        Text(Fmt.rateShort(UInt64(d * scale)) + "/s")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .frame(height: height)
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            hoverIndex = hoverSampleIndex(location: location, proxy: proxy,
                                                          geometry: geo, count: count)
                        case .ended:
                            hoverIndex = nil
                        }
                    }
            }
        }
    }
}

struct DetailRow: View {
    private static let valueColumnWidth: CGFloat = 190

    let label: String
    let value: String
    var swatch: Color?

    var body: some View {
        HStack(spacing: 6) {
            if let swatch {
                Circle().fill(swatch).frame(width: 7, height: 7)
            }
            Text(label)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(value)
                .monospacedDigit()
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: Self.valueColumnWidth, alignment: .trailing)
        }
        .frame(maxWidth: .infinity)
        .font(.callout)
        .accessibilityElement(children: .combine)
    }
}

struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.caption.weight(.semibold))
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Per-core vertical bars.
struct CoreBars: View {
    let cores: [Double]
    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(cores.indices, id: \.self) { i in
                Capsule()
                    .fill(Theme.usage(cores[i]))
                    .frame(width: 4, height: max(2, CGFloat(cores[i]) * 26))
            }
        }
        .frame(height: 26, alignment: .bottom)
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeOut(duration: 0.25), value: cores)
    }
}

/// Horizontal stacked breakdown bar (e.g. app/wired/compressed/free).
struct StackedBar: View {
    struct Segment: Identifiable { let id = UUID(); let value: Double; let color: Color }
    let segments: [Segment]

    var body: some View {
        GeometryReader { geo in
            let total = max(1, segments.map(\.value).reduce(0, +))
            HStack(spacing: 1) {
                ForEach(segments) { seg in
                    seg.color.frame(width: max(0, geo.size.width * seg.value / total))
                }
            }
            .clipShape(Capsule())
        }
        .frame(height: 8)
    }
}

struct ProcessList: View {
    let rows: [ProcRow]
    /// Whether the first fetch attempt has completed. Empty + loaded means the
    /// source failed or returned nothing — say so instead of spinning forever.
    var loaded = true
    var body: some View {
        VStack(spacing: 4) {
            if rows.isEmpty {
                Text(loaded ? "Unavailable" : "Loading…")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(rows) { row in
                    HStack {
                        Text(row.name).lineLimit(1).truncationMode(.middle)
                        Spacer(minLength: 12)
                        Text(row.detail).monospacedDigit().foregroundStyle(.secondary)
                    }
                    .font(.callout)
                }
            }
        }
    }
}
