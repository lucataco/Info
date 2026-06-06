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
                    Text(caption).font(.system(size: 8)).foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: 62, height: 62)
        .animation(.easeOut(duration: 0.25), value: fraction)
    }
}

/// Area+line history chart for a 0...1 series.
struct HistoryChart: View {
    let values: [Double]
    var tint: Color = .accentColor
    var height: CGFloat = 54

    var body: some View {
        Chart(Array(values.enumerated()), id: \.offset) { item in
            AreaMark(x: .value("t", item.offset), y: .value("v", item.element))
                .foregroundStyle(LinearGradient(colors: [tint.opacity(0.25), tint.opacity(0.02)],
                                                startPoint: .top, endPoint: .bottom))
            LineMark(x: .value("t", item.offset), y: .value("v", item.element))
                .foregroundStyle(tint)
                .interpolationMethod(.monotone)
        }
        .chartYScale(domain: 0...1)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .frame(height: height)
    }
}

/// Mirror-free dual line chart for network up/down (bytes/sec, auto-scaled).
struct DualHistoryChart: View {
    let download: [Double]
    let upload: [Double]
    var height: CGFloat = 54

    var body: some View {
        let scale = max(1, (download + upload).max() ?? 1)
        Chart {
            ForEach(Array(download.enumerated()), id: \.offset) { item in
                AreaMark(x: .value("t", item.offset), y: .value("v", item.element / scale),
                         series: .value("s", "Download"))
                    .foregroundStyle(Theme.download.opacity(0.18))
                LineMark(x: .value("t", item.offset), y: .value("v", item.element / scale),
                         series: .value("s", "Download"))
                    .foregroundStyle(Theme.download)
                    .interpolationMethod(.monotone)
            }
            ForEach(Array(upload.enumerated()), id: \.offset) { item in
                LineMark(x: .value("t", item.offset), y: .value("v", item.element / scale),
                         series: .value("s", "Upload"))
                    .foregroundStyle(Theme.upload)
                    .interpolationMethod(.monotone)
            }
        }
        .chartYScale(domain: 0...1)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .frame(height: height)
    }
}

struct DetailRow: View {
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
            Text(value)
                .monospacedDigit()
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(maxWidth: .infinity)
        .font(.callout)
    }
}

struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
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
    var body: some View {
        VStack(spacing: 4) {
            if rows.isEmpty {
                Text("Loading…").font(.caption).foregroundStyle(.secondary)
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
