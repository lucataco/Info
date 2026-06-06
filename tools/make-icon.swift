import AppKit

// Generates the Info app icon at every required size: a white sparkline on a
// blue Liquid-Glass-y squircle. Writes PNGs into the AppIcon.appiconset (with a
// matching Contents.json) and into tools/Info.iconset (for iconutil → .icns).

let entries: [(name: String, size: Int, scale: Int, px: Int)] = [
    ("icon_16x16",      16, 1, 16),
    ("icon_16x16@2x",   16, 2, 32),
    ("icon_32x32",      32, 1, 32),
    ("icon_32x32@2x",   32, 2, 64),
    ("icon_128x128",   128, 1, 128),
    ("icon_128x128@2x",128, 2, 256),
    ("icon_256x256",   256, 1, 256),
    ("icon_256x256@2x",256, 2, 512),
    ("icon_512x512",   512, 1, 512),
    ("icon_512x512@2x",512, 2, 1024),
]

func render(px: Int) -> NSBitmapImageRep {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: s, height: s)

    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = context
    let cg = context.cgContext
    cg.clear(CGRect(x: 0, y: 0, width: s, height: s))

    // Squircle
    let inset = s * 0.105
    let rect = CGRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let radius = rect.width * 0.2237
    let squircle = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)

    // Drop shadow under the squircle (into the transparent margin)
    cg.saveGState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.30)
    shadow.shadowBlurRadius = s * 0.035
    shadow.shadowOffset = NSSize(width: 0, height: -s * 0.014)
    shadow.set()
    let gradient = NSGradient(
        starting: NSColor(srgbRed: 0.27, green: 0.64, blue: 1.00, alpha: 1),
        ending:   NSColor(srgbRed: 0.03, green: 0.34, blue: 0.95, alpha: 1))!
    gradient.draw(in: squircle, angle: -90)
    cg.restoreGState()

    // Soft top highlight for a glassy feel
    cg.saveGState()
    squircle.addClip()
    let highlight = NSGradient(
        colors: [NSColor.white.withAlphaComponent(0.22), NSColor.white.withAlphaComponent(0)])!
    highlight.draw(in: CGRect(x: rect.minX, y: rect.midY, width: rect.width, height: rect.height / 2),
                   angle: -90)
    cg.restoreGState()

    // Sparkline
    cg.saveGState()
    squircle.addClip()
    let pad = rect.width * 0.21
    let inner = rect.insetBy(dx: pad, dy: pad)
    let ys: [CGFloat] = [0.38, 0.52, 0.32, 0.58, 0.28, 0.66, 0.44, 0.82]
    let n = ys.count
    func point(_ i: Int) -> CGPoint {
        CGPoint(x: inner.minX + inner.width * CGFloat(i) / CGFloat(n - 1),
                y: inner.minY + inner.height * ys[i])
    }
    let line = NSBezierPath()
    line.move(to: point(0))
    for i in 1..<n { line.line(to: point(i)) }

    let area = line.copy() as! NSBezierPath
    area.line(to: CGPoint(x: inner.maxX, y: inner.minY))
    area.line(to: CGPoint(x: inner.minX, y: inner.minY))
    area.close()
    NSColor.white.withAlphaComponent(0.16).setFill()
    area.fill()

    NSColor.white.setStroke()
    line.lineWidth = max(1, s * 0.032)
    line.lineJoinStyle = .round
    line.lineCapStyle = .round
    line.stroke()

    // End dot
    let r = s * 0.045
    let last = point(n - 1)
    NSColor.white.setFill()
    NSBezierPath(ovalIn: CGRect(x: last.x - r, y: last.y - r, width: 2 * r, height: 2 * r)).fill()
    cg.restoreGState()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let fm = FileManager.default
let appiconset = "Info/Resources/Assets.xcassets/AppIcon.appiconset"
let iconset = "tools/Info.iconset"
try? fm.createDirectory(atPath: iconset, withIntermediateDirectories: true)

for entry in entries {
    let rep = render(px: entry.px)
    guard let data = rep.representation(using: .png, properties: [:]) else { continue }
    try data.write(to: URL(fileURLWithPath: "\(appiconset)/\(entry.name).png"))
    try data.write(to: URL(fileURLWithPath: "\(iconset)/\(entry.name).png"))
}

// Contents.json for the appiconset
var images: [String] = []
for entry in entries {
    images.append("""
        {
          "filename" : "\(entry.name).png",
          "idiom" : "mac",
          "scale" : "\(entry.scale)x",
          "size" : "\(entry.size)x\(entry.size)"
        }
    """)
}
let contents = """
{
  "images" : [
\(images.joined(separator: ",\n"))
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
"""
try contents.write(toFile: "\(appiconset)/Contents.json", atomically: true, encoding: .utf8)

print("Generated \(entries.count) icon PNGs into \(appiconset) and \(iconset)")
