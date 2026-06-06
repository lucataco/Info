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

    private var valueFont: NSFont {
        let size = kind.isMirrored ? max(8, style.textSize.points - 2.5) : style.textSize.points
        return .monospacedDigitSystemFont(ofSize: size, weight: .semibold)
    }

    private var labelFont: NSFont {
        .systemFont(ofSize: max(8, style.textSize.points - 1), weight: .semibold)
    }

    private var glyphSize: CGFloat { style.textSize.points + 2 }

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

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        NSBezierPath(rect: bounds).addClip()
        let h = bounds.height
        var x = style.spacing.leadingPad
        var hasContent = false

        if drawLabel(x: &x, height: h) {
            hasContent = true
        }

        if style.showValue {
            if hasContent { x += style.spacing.labelGap }
            drawValue(x: x, width: reservedValueWidth, height: h)
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

    private func drawValue(x: CGFloat, width: CGFloat, height h: CGFloat) {
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
            let lineX = x + max(0, width - string.size().width)
            string.draw(at: NSPoint(x: lineX, y: y))
            y -= lineHeight
        }
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
