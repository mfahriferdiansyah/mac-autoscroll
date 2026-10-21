// Renders the AutoScroll app icon into assets/: icon.png, AppIcon.iconset and AppIcon.icns.
//
// Plain `swift scripts/make-icon.swift` fails on some machines (broken Command Line Tools
// modulemap), so run it through the overlay that build.sh writes:
//   ./build.sh --build-only
//   swift -vfsoverlay build/overlay.yaml scripts/make-icon.swift

import AppKit

let canvas: CGFloat = 1024
let assets = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("assets")
let iconset = assets.appendingPathComponent("AppIcon.iconset")

func hex(_ value: UInt32, alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: alpha)
}

let accent = hex(0x3A2E9E)
let tileGradient = NSGradient(starting: hex(0x6C7BFF), ending: accent)!

/// Draws the icon in a 1024x1024 space with the origin at the bottom left.
func drawIcon() {
    let tile = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 185, yRadius: 185)

    // Tile drop shadow.
    let tileShadow = NSShadow()
    tileShadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
    tileShadow.shadowBlurRadius = 28
    tileShadow.shadowOffset = NSSize(width: 0, height: -12)
    NSGraphicsContext.saveGraphicsState()
    tileShadow.set()
    accent.setFill()
    tile.fill()
    NSGraphicsContext.restoreGraphicsState()

    // Everything else stays inside the tile.
    NSGraphicsContext.saveGraphicsState()
    tile.addClip()

    tileGradient.draw(in: tile, angle: -90)

    // Inner highlight along the tile edge.
    let highlight = NSBezierPath(roundedRect: NSRect(x: 101, y: 101, width: 822, height: 822), xRadius: 184, yRadius: 184)
    highlight.lineWidth = 1
    NSColor.white.withAlphaComponent(0.18).setStroke()
    highlight.stroke()

    // Mouse body.
    let mouseShadow = NSShadow()
    mouseShadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
    mouseShadow.shadowBlurRadius = 20
    mouseShadow.shadowOffset = NSSize(width: 0, height: -8)
    NSGraphicsContext.saveGraphicsState()
    mouseShadow.set()
    NSColor.white.setFill()
    NSBezierPath(roundedRect: NSRect(x: 392, y: 450, width: 240, height: 380), xRadius: 120, yRadius: 120).fill()
    NSGraphicsContext.restoreGraphicsState()

    // Scroll wheel.
    accent.setFill()
    NSBezierPath(roundedRect: NSRect(x: 494, y: 710, width: 36, height: 80), xRadius: 18, yRadius: 18).fill()

    // Motion chevrons, fading downwards.
    for (offset, alpha) in [(CGFloat(0), CGFloat(0.9)), (-70, 0.55), (-140, 0.25)] {
        let chevron = NSBezierPath()
        chevron.move(to: NSPoint(x: 452, y: 400 + offset))
        chevron.line(to: NSPoint(x: 512, y: 350 + offset))
        chevron.line(to: NSPoint(x: 572, y: 400 + offset))
        chevron.lineWidth = 34
        chevron.lineCapStyle = .round
        chevron.lineJoinStyle = .round
        NSColor.white.withAlphaComponent(alpha).setStroke()
        chevron.stroke()
    }

    NSGraphicsContext.restoreGraphicsState()
}

func render(_ size: Int) throws -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let scale = NSAffineTransform()
    scale.scale(by: CGFloat(size) / canvas)
    scale.concat()
    drawIcon()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

var cache: [Int: Data] = [:]
func png(_ size: Int) throws -> Data {
    if let data = cache[size] { return data }
    let data = try render(size)
    cache[size] = data
    return data
}

try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

let variants: [(name: String, size: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for variant in variants {
    try png(variant.size).write(to: iconset.appendingPathComponent("\(variant.name).png"))
}
try png(1024).write(to: assets.appendingPathComponent("icon.png"))

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", assets.appendingPathComponent("AppIcon.icns").path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else { fatalError("iconutil failed") }

try FileManager.default.removeItem(at: iconset)
print("Wrote \(assets.path)/icon.png and AppIcon.icns")
