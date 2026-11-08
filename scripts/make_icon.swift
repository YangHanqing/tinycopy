// Reproducible macOS AppIcon artwork. No external fonts, images or drawing libraries.
// Usage: swift scripts/make_icon.swift TinyCopy/Assets.xcassets/AppIcon.appiconset
import AppKit

let outDir = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

func render(_ pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                              bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                              colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    defer { NSGraphicsContext.restoreGraphicsState() }
    let scale = CGFloat(pixels) / 1024
    let transform = NSAffineTransform()
    transform.scale(by: scale)
    transform.concat()

    func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
        NSColor(calibratedRed: r, green: g, blue: b, alpha: a)
    }
    func rounded(_ rect: NSRect, _ radius: CGFloat) -> NSBezierPath {
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    }
    func shadow(_ blur: CGFloat, _ offset: CGFloat, _ opacity: CGFloat) {
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(opacity)
        shadow.shadowBlurRadius = blur
        shadow.shadowOffset = NSSize(width: 0, height: offset)
        shadow.set()
    }
    func gradient(_ path: NSBezierPath, _ top: NSColor, _ bottom: NSColor) {
        NSGradient(starting: bottom, ending: top)!.draw(in: path, angle: 90)
    }

    let tile = rounded(NSRect(x: 100, y: 100, width: 824, height: 824), 185)
    NSGraphicsContext.saveGraphicsState()
    shadow(22, -10, 0.22)
    gradient(tile, color(0.26, 0.74, 0.99), color(0.10, 0.34, 0.85))
    NSGraphicsContext.restoreGraphicsState()
    NSGraphicsContext.saveGraphicsState()
    tile.addClip()
    let sheen = rounded(NSRect(x: 101, y: 101, width: 822, height: 822), 184)
    NSGradient(starting: color(1, 1, 1, 0.28), ending: color(1, 1, 1, 0))!.draw(in: sheen, angle: -55)
    NSGraphicsContext.restoreGraphicsState()
    color(1, 1, 1, 0.25).setStroke()
    tile.lineWidth = 1.5
    tile.stroke()

    // A second sheet is visible behind the board: clipboard history, rather than a text editor.
    let back = rounded(NSRect(x: 315, y: 250, width: 460, height: 550), 48)
    gradient(back, color(0.88, 0.97, 1, 0.66), color(0.70, 0.85, 1, 0.60))
    let board = rounded(NSRect(x: 248, y: 210, width: 484, height: 566), 56)
    NSGraphicsContext.saveGraphicsState()
    shadow(22, -12, 0.25)
    gradient(board, color(1, 1, 1), color(0.86, 0.92, 0.99))
    NSGraphicsContext.restoreGraphicsState()
    color(1, 1, 1, 0.8).setStroke()
    board.lineWidth = 2
    board.stroke()

    let paper = rounded(NSRect(x: 280, y: 242, width: 420, height: 493), 30)
    gradient(paper, color(1, 1, 1), color(0.98, 0.99, 1))
    color(0.55, 0.68, 0.84, 0.25).setStroke()
    paper.lineWidth = 1
    paper.stroke()

    // Three generous strokes remain legible at 16 and 32 pixels.
    for (y, width) in [(622.0, 278.0), (539.0, 236.0), (456.0, 174.0)] {
        let line = rounded(NSRect(x: 326, y: y, width: width, height: 30), 15)
        gradient(line, color(0.27, 0.58, 0.89), color(0.19, 0.43, 0.77))
    }

    let neck = rounded(NSRect(x: 441, y: 783, width: 98, height: 68), 34)
    gradient(neck, color(0.96, 0.98, 1), color(0.71, 0.80, 0.90))
    let clip = rounded(NSRect(x: 367, y: 725, width: 246, height: 104), 25)
    NSGraphicsContext.saveGraphicsState()
    shadow(8, -5, 0.18)
    gradient(clip, color(0.99, 1, 1), color(0.77, 0.85, 0.95))
    NSGraphicsContext.restoreGraphicsState()
    color(1, 1, 1, 0.9).setStroke()
    clip.lineWidth = 2
    clip.stroke()
    let inset = rounded(NSRect(x: 400, y: 756, width: 180, height: 13), 6.5)
    color(0.46, 0.59, 0.73, 0.42).setFill()
    inset.fill()
    return rep.representation(using: .png, properties: [:])!
}

var images: [[String: String]] = []
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        try render(size * scale).write(to: outDir.appendingPathComponent(name))
        images.append(["idiom": "mac", "size": "\(size)x\(size)", "scale": "\(scale)x", "filename": name])
    }
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
    .write(to: outDir.appendingPathComponent("Contents.json"))
print("Wrote \(images.count) AppIcon images.")
