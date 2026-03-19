import AppKit
import Foundation

let outDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("icon.iconset")
try? FileManager.default.removeItem(at: outDir)
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    NSColor.clear.setFill()
    rect.fill()

    // base rounded square
    let bgRect = rect.insetBy(dx: size * 0.08, dy: size * 0.08)
    let path = NSBezierPath(roundedRect: bgRect, xRadius: size * 0.2, yRadius: size * 0.2)
    NSColor(calibratedRed: 0.12, green: 0.48, blue: 0.98, alpha: 1).setFill()
    path.fill()

    // highlight blob
    let hi = NSBezierPath(ovalIn: NSRect(x: size * 0.18, y: size * 0.55, width: size * 0.62, height: size * 0.28))
    NSColor.white.withAlphaComponent(0.22).setFill()
    hi.fill()

    // purple blob
    let purple = NSBezierPath(ovalIn: NSRect(x: size * 0.35, y: size * 0.12, width: size * 0.58, height: size * 0.42))
    NSColor(calibratedRed: 0.58, green: 0.28, blue: 1.0, alpha: 0.3).setFill()
    purple.fill()

    // broom handle
    let handle = NSBezierPath(roundedRect: NSRect(x: size * 0.43, y: size * 0.33, width: size * 0.14, height: size * 0.46), xRadius: size * 0.03, yRadius: size * 0.03)
    NSColor.white.withAlphaComponent(0.95).setFill()
    handle.fill()

    // broom head
    let broom = NSBezierPath()
    broom.move(to: NSPoint(x: size * 0.33, y: size * 0.35))
    broom.line(to: NSPoint(x: size * 0.67, y: size * 0.35))
    broom.line(to: NSPoint(x: size * 0.61, y: size * 0.16))
    broom.line(to: NSPoint(x: size * 0.39, y: size * 0.16))
    broom.close()
    NSColor.white.withAlphaComponent(0.95).setFill()
    broom.fill()

    // sparkle
    let star = NSBezierPath()
    let points: [NSPoint] = [
        NSPoint(x: size * 0.78, y: size * 0.72),
        NSPoint(x: size * 0.81, y: size * 0.64),
        NSPoint(x: size * 0.89, y: size * 0.61),
        NSPoint(x: size * 0.81, y: size * 0.58),
        NSPoint(x: size * 0.78, y: size * 0.50),
        NSPoint(x: size * 0.75, y: size * 0.58),
        NSPoint(x: size * 0.67, y: size * 0.61),
        NSPoint(x: size * 0.75, y: size * 0.64)
    ]
    star.move(to: points[0])
    for p in points.dropFirst() { star.line(to: p) }
    star.close()
    NSColor.white.withAlphaComponent(0.92).setFill()
    star.fill()

    image.unlockFocus()
    return image
}

func savePNG(_ image: NSImage, to url: URL) throws {
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let data = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "icon", code: 1)
    }
    try data.write(to: url)
}

let sizes: [(String, CGFloat)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

for (name, sz) in sizes {
    let img = drawIcon(size: sz)
    try savePNG(img, to: outDir.appendingPathComponent(name))
}

print("iconset generated")
