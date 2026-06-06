import AppKit

/// One metric's view inside a status-item button. Lays out tightly as
/// `[label/icon] value [sparkline?]` — no big gaps. The label style, text size,
/// and whether the sparkline shows are all configurable. The value occupies a
/// stable reserved width so the item never jiggles as numbers change.
@MainActor
final class MenuBarItemView: NSView {
    let kind: MetricKind
    var style: MenuBarStyle {
        didSet { if style != oldValue { needsDisplay = true } }
    }

    private var single: [Double] = []
    private var mirrorTop: [Double] = []
    private var mirrorBottom: [Double] = []
    private var valueLines: [String] = []

    private lazy var symbol: NSImage? = {
        let image = NSImage(systemSymbolName: kind.symbolName, accessibilityDescription: kind.title)
        image?.isTemplate = true
        return image
    }()

    init(kind: MetricKind, style: MenuBarStyle) {
        self.kind = kind
        self.style = style
        super.init(frame: NSRect(x: 0, y: 0, width: 60, height: NSStatusBar.system.thickness))
        wantsLayer = true
        layer?.masksToBounds = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    // MARK: - Updates (redraw-on-change only)

    func updateSingle(history: [Double], value: String) {
        let lines = [value]
        guard history != single || lines != valueLines else { return }
        single = history
        valueLines = lines
        needsDisplay = true
    }

    func updateMirrored(download: [Double], upload: [Double], lines: [String]) {
        guard download != mirrorTop || upload != mirrorBottom || lines != valueLines else { return }
        mirrorTop = download
        mirrorBottom = upload
        valueLines = lines
        needsDisplay = true
    }

    // MARK: - Fonts & sizing

    /// The layout actually used for drawing. Stacking a label over network's
    /// already two-line value would need a third line that won't fit, so
    /// mirrored metrics fall back to inline when `.stacked` is requested.
    private var effectiveLayout: MenuBarLayout {
        if kind.isMirrored && style.layout == .stacked { return .inline }
        return style.layout
    }

    /// Stacked layouts split the bar's height across two lines, so the type is
    /// shrunk to fit. The configured text size still nudges these sizes.
    private var stackedValueSize: CGFloat {
        switch style.textSize {
        case .small: 9
        case .medium: 10
        case .large: 10.5
        }
    }

    private var stackedLabelSize: CGFloat { stackedValueSize - 1.5 }

    private var valueFont: NSFont {
        let size: CGFloat
        if effectiveLayout == .stacked {
            size = stackedValueSize
        } else {
            size = kind.isMirrored ? max(8, style.textSize.points - 2.5) : style.textSize.points
        }
        return .monospacedDigitSystemFont(ofSize: size, weight: .semibold)
    }

    private var labelFont: NSFont {
        let size = effectiveLayout == .stacked ? stackedLabelSize : max(8, style.textSize.points - 1)
        return .systemFont(ofSize: size, weight: .semibold)
    }

    private var glyphSize: CGFloat {
        effectiveLayout == .stacked ? stackedValueSize + 1 : style.textSize.points + 2
    }

    /// Width reserved for the value — sized to the widest expected string so the
    /// item width is stable (no per-tick jiggle).
    private var reservedValueWidth: CGFloat {
        guard style.showValue else { return 0 }
        let sample = kind.isMirrored ? "\u{2193}99.9M" : "100%"
        return ceil((sample as NSString).size(withAttributes: [.font: valueFont]).width)
    }

    private var labelWidth: CGFloat {
        switch style.label {
        case .none:
            return 0
        case .icon:
            return symbol != nil ? glyphSize
                : ceil((kind.shortLabel as NSString).size(withAttributes: [.font: labelFont]).width)
        case .text:
            return ceil((kind.shortLabel as NSString).size(withAttributes: [.font: labelFont]).width)
        }
    }

    private var sparkWidth: CGFloat { style.spacing.sparkWidth(for: kind) }

    /// The status item should be exactly this wide.
    func preferredWidth() -> CGFloat {
        effectiveLayout == .stacked ? stackedWidth() : inlineWidth()
    }

    private func inlineWidth() -> CGFloat {
        var width = style.spacing.leadingPad
        var hasContent = false
        let lw = labelWidth
        if lw > 0 {
            width += lw
            hasContent = true
        }
        if style.showValue {
            if hasContent { width += style.spacing.labelGap }
            width += reservedValueWidth
            hasContent = true
        }
        if style.showSparkline {
            if hasContent { width += style.spacing.sparkGap }
            width += sparkWidth
            hasContent = true
        }
        if !hasContent { width += 10 }
        width += style.spacing.trailingPad
        return ceil(width)
    }

    /// Stacked items are as wide as their widest line (label or value), with the
    /// sparkline, if any, trailing alongside the stacked text.
    private func stackedWidth() -> CGFloat {
        let column = max(labelWidth, style.showValue ? reservedValueWidth : 0)
        var hasContent = column > 0
        var width = style.spacing.leadingPad + column
        if style.showSparkline {
            if hasContent { width += style.spacing.sparkGap }
            width += sparkWidth
            hasContent = true
        }
        if !hasContent { width += 10 }
        width += style.spacing.trailingPad
        return ceil(width)
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        NSBezierPath(rect: bounds).addClip()
        let h = bounds.height
        if effectiveLayout == .stacked {
            drawStacked(height: h)
        } else {
            drawInline(height: h)
        }
    }

    private func drawInline(height h: CGFloat) {
        var x = style.spacing.leadingPad
        var hasContent = false

        if drawLabel(x: &x, height: h) {
            hasContent = true
        }

        if style.showValue {
            if hasContent { x += style.spacing.labelGap }
            // Tight pulls the value up against the label; Inline right-aligns it
            // within the reserved column (leaving the slack on the left).
            let align: ValueAlignment = effectiveLayout == .tight ? .left : .right
            drawValue(x: x, width: reservedValueWidth, height: h, align: align)
            x += reservedValueWidth
            hasContent = true
        }

        if style.showSparkline {
            if hasContent { x += style.spacing.sparkGap }
            let rect = NSRect(x: x, y: 3, width: sparkWidth, height: h - 6)
            if kind.isMirrored { drawMirrored(in: rect) } else { drawSingle(in: rect) }
            hasContent = true
        }

        if !hasContent {
            drawFallbackDot(height: h)
        }
    }

    /// Label on top, value beneath — each centered within its half of the bar.
    private func drawStacked(height h: CGFloat) {
        let x = style.spacing.leadingPad
        let column = max(labelWidth, style.showValue ? reservedValueWidth : 0)
        let hasLabel = style.label != .none && labelWidth > 0
        let hasValue = style.showValue
        let hasText = column > 0

        if hasLabel && hasValue {
            drawStackedLabel(in: NSRect(x: x, y: h / 2, width: column, height: h / 2))
            drawValueCentered(in: NSRect(x: x, y: 0, width: column, height: h / 2))
        } else if hasLabel {
            drawStackedLabel(in: NSRect(x: x, y: 0, width: column, height: h))
        } else if hasValue {
            drawValueCentered(in: NSRect(x: x, y: 0, width: column, height: h))
        }

        var trailingX = x + column
        if style.showSparkline {
            if hasText { trailingX += style.spacing.sparkGap }
            let rect = NSRect(x: trailingX, y: 3, width: sparkWidth, height: h - 6)
            if kind.isMirrored { drawMirrored(in: rect) } else { drawSingle(in: rect) }
        } else if !hasText {
            drawFallbackDot(height: h)
        }
    }

    private func drawLabel(x: inout CGFloat, height h: CGFloat) -> Bool {
        switch style.label {
        case .none:
            return false
        case .icon where symbol != nil:
            let rect = NSRect(x: x, y: (h - glyphSize) / 2, width: glyphSize, height: glyphSize)
            tintedSymbol(size: glyphSize, color: .labelColor)?.draw(in: rect)
            x += glyphSize
            return true
        default:
            let attrs: [NSAttributedString.Key: Any] = [
                .font: labelFont,
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
            let string = NSAttributedString(string: kind.shortLabel, attributes: attrs)
            string.draw(at: NSPoint(x: x, y: (h - string.size().height) / 2))
            x += labelWidth
            return true
        }
    }

    private func drawFallbackDot(height h: CGFloat) {
        let size: CGFloat = 4
        let rect = NSRect(x: (bounds.width - size) / 2, y: (h - size) / 2, width: size, height: size)
        NSColor.labelColor.withAlphaComponent(0.65).setFill()
        NSBezierPath(ovalIn: rect).fill()
    }

    private enum ValueAlignment { case left, right }

    private func drawValue(x: CGFloat, width: CGFloat, height h: CGFloat, align: ValueAlignment) {
        guard !valueLines.isEmpty else { return }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: valueFont,
            .foregroundColor: NSColor.labelColor,
        ]
        let font = valueFont
        let lineHeight = font.ascender - font.descender
        let total = lineHeight * CGFloat(valueLines.count)
        var y = (h + total) / 2 - lineHeight
        for line in valueLines {
            let string = NSAttributedString(string: line, attributes: attrs)
            let slack = max(0, width - string.size().width)
            let lineX = align == .left ? x : x + slack
            string.draw(at: NSPoint(x: lineX, y: y))
            y -= lineHeight
        }
    }

    // MARK: - Stacked drawing helpers

    private func drawStackedLabel(in rect: NSRect) {
        switch style.label {
        case .none:
            return
        case .icon where symbol != nil:
            let size = glyphSize
            let iconRect = NSRect(x: rect.midX - size / 2, y: rect.midY - size / 2,
                                  width: size, height: size)
            tintedSymbol(size: size, color: .labelColor)?.draw(in: iconRect)
        default:
            drawCenteredString(kind.shortLabel, font: labelFont,
                               color: .secondaryLabelColor, in: rect)
        }
    }

    private func drawValueCentered(in rect: NSRect) {
        guard let line = valueLines.first else { return }
        drawCenteredString(line, font: valueFont, color: .labelColor, in: rect)
    }

    private func drawCenteredString(_ text: String, font: NSFont, color: NSColor, in rect: NSRect) {
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let string = NSAttributedString(string: text, attributes: attrs)
        let size = string.size()
        let origin = NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2)
        string.draw(at: origin)
    }

    /// Renders the SF Symbol into a transparent scratch image and tints it there,
    /// so the result is correct regardless of the destination's background
    /// (sourceAtop over an opaque backdrop would otherwise fill the whole rect).
    private func tintedSymbol(size: CGFloat, color: NSColor) -> NSImage? {
        guard let symbol else { return nil }
        let config = NSImage.SymbolConfiguration(pointSize: size, weight: .regular)
        let configured = symbol.withSymbolConfiguration(config) ?? symbol

        let out = NSImage(size: NSSize(width: size, height: size))
        out.lockFocus()
        let bounds = NSRect(origin: .zero, size: out.size)
        // aspect-fit the symbol within the square
        let natural = configured.size
        if natural.width > 0, natural.height > 0 {
            let scale = min(bounds.width / natural.width, bounds.height / natural.height)
            let w = natural.width * scale, h = natural.height * scale
            configured.draw(in: NSRect(x: bounds.midX - w / 2, y: bounds.midY - h / 2, width: w, height: h))
        } else {
            configured.draw(in: bounds)
        }
        color.set()
        bounds.fill(using: .sourceAtop)
        out.unlockFocus()
        return out
    }

    private func drawSingle(in rect: NSRect) {
        guard single.count > 1 else { return }
        let stepX = rect.width / CGFloat(single.count - 1)
        func point(_ i: Int) -> NSPoint {
            let v = min(1, max(0, single[i]))
            return NSPoint(x: rect.minX + CGFloat(i) * stepX, y: rect.minY + v * rect.height)
        }

        let points = single.indices.map(point)
        let line = NSBezierPath()
        let area = NSBezierPath()
        line.move(to: points[0])
        area.move(to: points[0])
        for point in points.dropFirst() {
            line.line(to: point)
            area.line(to: point)
        }

        area.line(to: NSPoint(x: rect.maxX, y: rect.minY))
        area.line(to: NSPoint(x: rect.minX, y: rect.minY))
        area.close()
        NSColor.labelColor.withAlphaComponent(0.16).setFill()
        area.fill()

        line.lineWidth = 1.25
        line.lineJoinStyle = .round
        NSColor.labelColor.withAlphaComponent(0.7).setStroke()
        line.stroke()
    }

    private func drawMirrored(in rect: NSRect) {
        let mid = rect.midY
        let scale = max(1.0, (mirrorTop + mirrorBottom).max() ?? 1.0)
        func fillArea(_ series: [Double], up: Bool) {
            guard series.count > 1 else { return }
            let path = NSBezierPath()
            let stepX = rect.width / CGFloat(series.count - 1)
            let half = rect.height / 2
            path.move(to: NSPoint(x: rect.minX, y: mid))
            for i in 0..<series.count {
                let frac = min(1, max(0, series[i] / scale))
                let y = up ? mid + frac * half : mid - frac * half
                path.line(to: NSPoint(x: rect.minX + CGFloat(i) * stepX, y: y))
            }
            path.line(to: NSPoint(x: rect.maxX, y: mid))
            path.close()
            path.fill()
        }
        NSColor.labelColor.withAlphaComponent(0.32).setFill()
        fillArea(mirrorTop, up: true)
        NSColor.secondaryLabelColor.withAlphaComponent(0.32).setFill()
        fillArea(mirrorBottom, up: false)
    }
}
