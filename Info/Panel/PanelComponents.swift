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
        case .unavailable: return .secondary
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
    var title: String = "Usage"
    var displayValue: String?

    var body: some View {
        ZStack {
            Circle().stroke(.quaternary, lineWidth: 6)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, fraction)))
                .stroke(tint ?? Theme.usage(fraction),
                        style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text(displayValue ?? Fmt.percent(fraction))
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
        .accessibilityLabel(title)
        .accessibilityValue(displayValue ?? Fmt.percent(fraction))
    }
}

/// Helpers for turning sample timestamps into human-friendly time-axis labels.
enum TimeAxis {
    static func span(samples: [HistoryPoint]) -> String {
        guard let first = samples.first?.timestamp,
              let last = samples.last?.timestamp else { return "0s" }
        return short(max(0, last.timeIntervalSince(first)))
    }

    static func ago(samplesBack: Int, samples: [HistoryPoint], reference: Date? = nil) -> String {
        guard !samples.isEmpty else { return "now" }
        let index = samples.count - 1 - max(0, samplesBack)
        guard samples.indices.contains(index) else { return "now" }
        let effectiveReference = reference ?? samples.last?.timestamp ?? Date()
        let seconds = max(0, effectiveReference.timeIntervalSince(samples[index].timestamp))
        return seconds <= 0 ? "now" : short(seconds) + " ago"
    }

    private static func short(_ seconds: Double) -> String {
        guard seconds >= 60 else { return "\(Int(seconds.rounded()))s" }
        let minutes = seconds / 60
        return abs(minutes.rounded() - minutes) < 0.05
            ? "\(Int(minutes.rounded()))m"
            : String(format: "%.1fm", minutes)
    }
}

/// Maps a hover location to the nearest sample index within the plot area.
private func hoverSampleIndex(location: CGPoint,
                              proxy: ChartProxy,
                              geometry: GeometryProxy,
                              xValues: [Double]) -> Int? {
    guard xValues.count > 1, let anchor = proxy.plotFrame else { return nil }
    let plot = geometry[anchor]
    let x = location.x - plot.minX
    guard x >= 0, x <= plot.width,
          let raw = proxy.value(atX: x, as: Double.self) else { return nil }
    return xValues.indices.min { left, right in
        abs(xValues[left] - raw) < abs(xValues[right] - raw)
    }
}

/// A thin caption that frames the X axis as a time range ("2m ago … now").
private struct TimeAxisCaption: View {
    let samples: [HistoryPoint]

    var body: some View {
        HStack {
            Text(TimeAxis.span(samples: samples) + " ago")
            Spacer()
            Text("now")
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
}

/// Interactive area+line history chart for a 0...1 series.
struct HistoryChart: View {
    let samples: [HistoryPoint]
    var tint: Color = .accentColor
    var height: CGFloat = 54
    var title: String = "History chart"
    var format: (Double) -> String = { Fmt.percent($0) }
    var showsDetail: Bool = true

    @State private var hoverIndex: Int?

    private var values: [Double] { samples.map(\.value) }
    private var lastIndex: Int { max(0, samples.count - 1) }
    private var xValues: [Double] {
        guard let origin = samples.first?.timestamp else { return [] }
        return samples.map { max(0, $0.timestamp.timeIntervalSince(origin)) }
    }

    private var hovered: (index: Int, value: Double)? {
        guard let index = hoverIndex, values.indices.contains(index) else { return nil }
        return (index, values[index])
    }

    var body: some View {
        if showsDetail {
            VStack(alignment: .leading, spacing: 3) {
                readout
                chart
                TimeAxisCaption(samples: samples)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
            .accessibilityValue(accessibilitySummary)
            .accessibilityHint("Shows the latest value, peak, and average for the visible history.")
        } else {
            Chart { marks }
                .chartYScale(domain: 0...1)
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .frame(height: height)
                .accessibilityHidden(true)
        }
    }

    private var accessibilitySummary: String {
        guard let latest = values.last else { return "No samples available" }
        return "\(format(latest)) now, peak \(format(values.peak)), average \(format(values.mean))"
    }

    @ViewBuilder private var readout: some View {
        HStack(spacing: 6) {
            if let hovered {
                Text(format(hovered.value))
                    .font(.caption.weight(.semibold)).monospacedDigit()
                    .foregroundStyle(tint)
                Text(TimeAxis.ago(samplesBack: lastIndex - hovered.index, samples: samples))
                    .font(.caption2).foregroundStyle(.secondary)
            } else {
                Text("Peak \(format(values.peak))")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .frame(height: 13)
    }

    @ChartContentBuilder private var marks: some ChartContent {
        ForEach(Array(values.enumerated()), id: \.offset) { item in
            let x = xValues[item.offset]
            AreaMark(x: .value("t", x), y: .value("v", item.element))
                .foregroundStyle(LinearGradient(colors: [tint.opacity(0.25), tint.opacity(0.02)],
                                                startPoint: .top, endPoint: .bottom))
            LineMark(x: .value("t", x), y: .value("v", item.element))
                .foregroundStyle(tint)
                .interpolationMethod(.monotone)
        }
        if let hovered {
            RuleMark(x: .value("t", xValues[hovered.index]))
                .foregroundStyle(.secondary.opacity(0.4))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 2]))
            PointMark(x: .value("t", xValues[hovered.index]), y: .value("v", hovered.value))
                .foregroundStyle(tint)
                .symbolSize(36)
        }
    }

    private var chart: some View {
        Chart { marks }
            .chartYScale(domain: 0...1)
            .chartXScale(domain: 0...Double(max(1, xValues.last ?? 1)))
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(position: .leading, values: [0, 0.5, 1.0]) { value in
                    AxisGridLine().foregroundStyle(.secondary.opacity(0.12))
                    AxisValueLabel {
                        if let doubleValue = value.as(Double.self) {
                            Text(format(doubleValue)).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .frame(height: height)
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let location):
                                hoverIndex = hoverSampleIndex(location: location,
                                                              proxy: proxy,
                                                              geometry: geometry,
                                                              xValues: xValues)
                            case .ended:
                                hoverIndex = nil
                            }
                        }
                }
            }
    }
}

/// Interactive dual line chart for network up/down (bytes/sec, auto-scaled).
struct DualHistoryChart: View {
    let downloadSamples: [HistoryPoint]
    let uploadSamples: [HistoryPoint]
    var height: CGFloat = 54
    var showsDetail: Bool = true

    @State private var hoverIndex: Int?

    private var count: Int { min(downloadSamples.count, uploadSamples.count) }
    private var visibleSamples: [HistoryPoint] { Array(downloadSamples.prefix(count)) }
    private var download: [Double] { downloadSamples.prefix(count).map(\.value) }
    private var upload: [Double] { uploadSamples.prefix(count).map(\.value) }
    private var lastIndex: Int { max(0, count - 1) }
    private var scale: Double { max(1, (download + upload).max() ?? 1) }
    private var xValues: [Double] {
        guard let origin = visibleSamples.first?.timestamp else { return [] }
        return visibleSamples.map { max(0, $0.timestamp.timeIntervalSince(origin)) }
    }

    private var hovered: (index: Int, down: Double, up: Double)? {
        guard let index = hoverIndex,
              download.indices.contains(index),
              upload.indices.contains(index) else { return nil }
        return (index, download[index], upload[index])
    }

    var body: some View {
        if showsDetail {
            VStack(alignment: .leading, spacing: 3) {
                readout
                chart
                TimeAxisCaption(samples: visibleSamples)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Network history chart")
            .accessibilityValue(accessibilitySummary)
            .accessibilityHint("Shows the latest download and upload rates, peaks, and averages.")
        } else {
            Chart { marks(scale: scale) }
                .chartYScale(domain: 0...1)
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .frame(height: height)
                .accessibilityHidden(true)
        }
    }

    private var accessibilitySummary: String {
        guard let latestDownload = download.last, let latestUpload = upload.last else {
            return "No network samples available"
        }
        return "Download \(Fmt.rate(UInt64(latestDownload))), upload \(Fmt.rate(UInt64(latestUpload))), download peak \(Fmt.rate(UInt64(download.peak))), upload peak \(Fmt.rate(UInt64(upload.peak))), download average \(Fmt.rate(UInt64(download.mean))), upload average \(Fmt.rate(UInt64(upload.mean)))"
    }

    @ViewBuilder private var readout: some View {
        HStack(spacing: 8) {
            if let hovered {
                rateLabel(symbol: "arrow.down", color: Theme.download, bytesPerSec: hovered.down)
                rateLabel(symbol: "arrow.up", color: Theme.upload, bytesPerSec: hovered.up)
                Text(TimeAxis.ago(samplesBack: lastIndex - hovered.index,
                                   samples: visibleSamples))
                    .font(.caption2).foregroundStyle(.secondary)
            } else {
                Text("Scale \(Fmt.rate(UInt64(scale)))")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .frame(height: 13)
    }

    private func rateLabel(symbol: String, color: Color, bytesPerSec: Double) -> some View {
        HStack(spacing: 2) {
            Image(systemName: symbol).font(.caption2.weight(.bold)).foregroundStyle(color)
            Text(Fmt.rate(UInt64(max(0, bytesPerSec))))
                .font(.caption2.weight(.semibold)).monospacedDigit()
        }
    }

    @ChartContentBuilder private func marks(scale: Double) -> some ChartContent {
        ForEach(Array(download.enumerated()), id: \.offset) { item in
            let x = xValues[item.offset]
            AreaMark(x: .value("t", x), y: .value("v", item.element / scale),
                     series: .value("s", "Download"))
                .foregroundStyle(Theme.download.opacity(0.18))
            LineMark(x: .value("t", x), y: .value("v", item.element / scale),
                     series: .value("s", "Download"))
                .foregroundStyle(Theme.download)
                .interpolationMethod(.monotone)
        }
        ForEach(Array(upload.enumerated()), id: \.offset) { item in
            let x = xValues[item.offset]
            LineMark(x: .value("t", x), y: .value("v", item.element / scale),
                     series: .value("s", "Upload"))
                .foregroundStyle(Theme.upload)
                .interpolationMethod(.monotone)
        }
        if let hovered {
            let x = xValues[hovered.index]
            RuleMark(x: .value("t", x))
                .foregroundStyle(.secondary.opacity(0.4))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 2]))
            PointMark(x: .value("t", x), y: .value("v", hovered.down / scale))
                .foregroundStyle(Theme.download)
                .symbolSize(36)
            PointMark(x: .value("t", x), y: .value("v", hovered.up / scale))
                .foregroundStyle(Theme.upload)
                .symbolSize(36)
        }
    }

    private var chart: some View {
        let scale = self.scale
        return Chart { marks(scale: scale) }
            .chartYScale(domain: 0...1)
            .chartXScale(domain: 0...Double(max(1, xValues.last ?? 1)))
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(position: .leading, values: [0, 0.5, 1.0]) { value in
                    AxisGridLine().foregroundStyle(.secondary.opacity(0.12))
                    AxisValueLabel {
                        if let doubleValue = value.as(Double.self) {
                            Text(Fmt.rateShort(UInt64(doubleValue * scale)) + "/s")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .frame(height: height)
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let location):
                                hoverIndex = hoverSampleIndex(location: location,
                                                              proxy: proxy,
                                                              geometry: geometry,
                                                              xValues: xValues)
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
            .foregroundStyle(.secondary)
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
                    .accessibilityElement()
                    .accessibilityLabel("Core \(i + 1)")
                    .accessibilityValue(Fmt.percent(cores[i]))
            }
        }
        .frame(height: 26, alignment: .bottom)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Per-core CPU usage")
        .animation(.easeOut(duration: 0.25), value: cores)
    }
}

/// Horizontal stacked breakdown bar (e.g. app/wired/compressed/free).
struct StackedBar: View {
    struct Segment {
        let value: Double
        let color: Color
    }

    let segments: [Segment]

    var body: some View {
        GeometryReader { geo in
            let total = max(1, segments.map(\.value).reduce(0, +))
            HStack(spacing: 1) {
                ForEach(segments.indices, id: \.self) { index in
                    let segment = segments[index]
                    segment.color.frame(width: max(0, geo.size.width * segment.value / total))
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
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(row.name), \(row.detail)")
                }
            }
        }
    }
}
