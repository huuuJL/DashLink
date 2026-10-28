import AppKit

let folder = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
for (points, scale) in [(16,1),(16,2),(32,1),(32,2),(128,1),(128,2),(256,1),(256,2),(512,1),(512,2)] {
    let pixels = points * scale
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let transform = AffineTransform(scale: CGFloat(pixels)/1024)
    (transform as NSAffineTransform).concat()
    let background = NSBezierPath(roundedRect: NSRect(x: 54, y: 54, width: 916, height: 916), xRadius: 210, yRadius: 210)
    NSColor(srgbRed: 0.035, green: 0.22, blue: 0.25, alpha: 1).setFill()
    background.fill()
    NSColor(srgbRed: 0.42, green: 0.91, blue: 0.80, alpha: 1).setStroke()
    let screen = NSBezierPath(roundedRect: NSRect(x: 195, y: 335, width: 575, height: 390), xRadius: 65, yRadius: 65)
    screen.lineWidth = 43
    screen.stroke()
    let phone = NSBezierPath(roundedRect: NSRect(x: 590, y: 224, width: 245, height: 386), xRadius: 55, yRadius: 55)
    NSColor(srgbRed: 0.035, green: 0.22, blue: 0.25, alpha: 1).setFill()
    phone.fill()
    NSColor.white.setStroke()
    phone.lineWidth = 43
    phone.stroke()
    let line = NSBezierPath()
    line.move(to: NSPoint(x: 660, y: 281)); line.line(to: NSPoint(x: 763, y: 281))
    line.lineWidth = 20; line.lineCapStyle = .round; line.stroke()
    let stand = NSBezierPath()
    stand.move(to: NSPoint(x: 420, y: 330)); stand.line(to: NSPoint(x: 420, y: 246))
    stand.move(to: NSPoint(x: 335, y: 246)); stand.line(to: NSPoint(x: 505, y: 246))
    NSColor(srgbRed: 0.42, green: 0.91, blue: 0.80, alpha: 1).setStroke()
    stand.lineWidth = 40; stand.lineCapStyle = .round; stand.stroke()
    NSGraphicsContext.restoreGraphicsState()
    let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
    try bitmap.representation(using: .png, properties: [:])!.write(to: folder.appendingPathComponent(name))
}
