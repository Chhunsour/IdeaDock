import AppKit
import ImageIO
import UniformTypeIdentifiers

// An original, restrained folded note mark, drawn with native vectors.
let destination = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
for size in [16, 32, 64, 128, 256, 512, 1024] {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
    context.cgContext.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
    let surface = NSBezierPath(roundedRect: NSRect(x: 80, y: 80, width: 864, height: 864), xRadius: 190, yRadius: 190)
    NSColor(calibratedRed: 0.075, green: 0.08, blue: 0.09, alpha: 1).setFill(); surface.fill()
    NSColor(calibratedWhite: 1, alpha: 0.07).setStroke(); surface.lineWidth = 3; surface.stroke()
    let note = NSBezierPath()
    note.move(to: NSPoint(x: 346, y: 277)); note.line(to: NSPoint(x: 651, y: 277))
    note.curve(to: NSPoint(x: 699, y: 325), controlPoint1: NSPoint(x: 683, y: 277), controlPoint2: NSPoint(x: 699, y: 292))
    note.line(to: NSPoint(x: 699, y: 600)); note.line(to: NSPoint(x: 569, y: 730)); note.line(to: NSPoint(x: 346, y: 730))
    note.curve(to: NSPoint(x: 299, y: 683), controlPoint1: NSPoint(x: 314, y: 730), controlPoint2: NSPoint(x: 299, y: 715))
    note.line(to: NSPoint(x: 299, y: 325)); note.curve(to: NSPoint(x: 346, y: 277), controlPoint1: NSPoint(x: 299, y: 293), controlPoint2: NSPoint(x: 314, y: 277))
    note.close(); NSColor(calibratedRed: 0.988, green: 0.431, blue: 0, alpha: 1).setStroke(); note.lineWidth = 34; note.lineJoinStyle = .round; note.stroke()
    let fold = NSBezierPath(); fold.move(to: NSPoint(x: 568, y: 730)); fold.line(to: NSPoint(x: 568, y: 600)); fold.line(to: NSPoint(x: 699, y: 600)); fold.lineWidth = 28; fold.lineJoinStyle = .round; fold.stroke()
    NSColor(calibratedWhite: 0.94, alpha: 1).setStroke()
    for (y, width) in [(510.0, 195.0), (427.0, 133.0)] {
        let line = NSBezierPath(); line.move(to: NSPoint(x: 393, y: y)); line.line(to: NSPoint(x: 393 + width, y: y)); line.lineWidth = 29; line.lineCapStyle = .round; line.stroke()
    }
    NSGraphicsContext.restoreGraphicsState()
    let data = bitmap.representation(using: .png, properties: [:])!
    if [16, 32, 128, 256, 512].contains(size) { try data.write(to: destination.appendingPathComponent("icon_\(size)x\(size).png")) }
    if [16, 32, 128, 256, 512].contains(size / 2) { let half = size / 2; try data.write(to: destination.appendingPathComponent("icon_\(half)x\(half)@2x.png")) }
}
