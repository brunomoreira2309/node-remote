// Draws the Node Remote app icon and writes Resources/AppIcon.icns.
// Usage: swift scripts/make-icon.swift   (needs only the macOS command line tools)
import AppKit

let navy = NSColor(srgbRed: 0, green: 44 / 255, blue: 68 / 255, alpha: 1)
let abyss = NSColor(srgbRed: 0, green: 14 / 255, blue: 23 / 255, alpha: 1)
let cyan = NSColor(srgbRed: 4 / 255, green: 203 / 255, blue: 201 / 255, alpha: 1)
let ice = NSColor(srgbRed: 239 / 255, green: 255 / 255, blue: 255 / 255, alpha: 1)

func drawIcon(size: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = size / 1024
    // macOS icon grid: an 824-point rounded square centred on a 1024 canvas.
    let tile = NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let shape = NSBezierPath(roundedRect: tile, xRadius: 185 * s, yRadius: 185 * s)
    NSGraphicsContext.current?.saveGraphicsState()
    let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.35); shadow.shadowBlurRadius = 24 * s; shadow.shadowOffset = NSSize(width: 0, height: -10 * s)
    shadow.set()
    NSGradient(starting: NSColor(srgbRed: 0, green: 58 / 255, blue: 89 / 255, alpha: 1), ending: abyss)!.draw(in: shape, angle: -90)
    NSGraphicsContext.current?.restoreGraphicsState()
    shape.addClip()
    // Support graphic: data paths ending in nodes.
    cyan.withAlphaComponent(0.22).setStroke()
    let paths: [[CGPoint]] = [
        [CGPoint(x: 100, y: 690), CGPoint(x: 250, y: 690), CGPoint(x: 250, y: 820), CGPoint(x: 330, y: 820)],
        [CGPoint(x: 924, y: 300), CGPoint(x: 780, y: 300), CGPoint(x: 780, y: 180), CGPoint(x: 700, y: 180)],
        [CGPoint(x: 924, y: 640), CGPoint(x: 800, y: 640), CGPoint(x: 800, y: 760)],
        [CGPoint(x: 100, y: 330), CGPoint(x: 220, y: 330), CGPoint(x: 220, y: 230)],
    ]
    for points in paths {
        let path = NSBezierPath(); path.lineWidth = 7 * s; path.lineJoinStyle = .round
        path.move(to: NSPoint(x: points[0].x * s, y: points[0].y * s))
        for point in points.dropFirst() { path.line(to: NSPoint(x: point.x * s, y: point.y * s)) }
        path.stroke()
        let end = points.last!
        let node = NSBezierPath(ovalIn: NSRect(x: (end.x - 16) * s, y: (end.y - 16) * s, width: 32 * s, height: 32 * s))
        abyss.setFill(); node.fill(); node.lineWidth = 7 * s; node.stroke()
    }
    // Soft cyan light behind the remote.
    NSGradient(colors: [cyan.withAlphaComponent(0.32), cyan.withAlphaComponent(0)])!
        .draw(in: NSBezierPath(ovalIn: NSRect(x: 262 * s, y: 222 * s, width: 500 * s, height: 580 * s)), relativeCenterPosition: .zero)
    // The remote, same proportions as the menu bar icon (18-point grid scaled to 1024).
    let unit = 34 * s, originX = 512 * s - 9 * unit, originY = 512 * s - 9 * unit
    func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect { NSRect(x: originX + x * unit, y: originY + y * unit, width: w * unit, height: h * unit) }
    let body = NSBezierPath(roundedRect: r(5, 0.75, 8, 16.5), xRadius: 3.6 * unit, yRadius: 3.6 * unit)
    NSColor(srgbRed: 0, green: 30 / 255, blue: 47 / 255, alpha: 1).setFill(); body.fill()
    ice.setStroke(); body.lineWidth = 0.75 * unit; body.stroke()
    let pad = NSBezierPath(ovalIn: r(6.6, 9.4, 4.8, 4.8)); cyan.setStroke(); pad.lineWidth = 0.6 * unit; pad.stroke()
    cyan.setFill(); NSBezierPath(ovalIn: r(8.2, 11.0, 1.6, 1.6)).fill()
    ice.setFill()
    for y in [6.0, 3.6] as [CGFloat] {
        NSBezierPath(ovalIn: r(6.9, y, 1.5, 1.5)).fill()
        NSBezierPath(ovalIn: r(9.6, y, 1.5, 1.5)).fill()
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon-\(UUID().uuidString).iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: iconset) }
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
        try drawIcon(size: CGFloat(points * scale)).representation(using: .png, properties: [:])!.write(to: iconset.appendingPathComponent(name))
    }
}
let output = root.appendingPathComponent("Resources/AppIcon.icns")
try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try iconutil.run(); iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else { fatalError("iconutil failed") }
if CommandLine.arguments.count > 1 {
    try drawIcon(size: 1024).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
}
print("Icon written to Resources/AppIcon.icns")
