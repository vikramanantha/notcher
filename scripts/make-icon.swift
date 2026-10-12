// Draws the Notcher app icon and writes Resources/AppIcon.png (1024px) and Resources/AppIcon.icns.
// Usage: swift scripts/make-icon.swift   (from the notcher folder)
//
// Follows the macOS icon grid: an 824pt rounded square centered on a 1024pt canvas, with a
// soft drop shadow. The base color is Sunsetter's launcher green (#306C52).

import AppKit

let canvas: CGFloat = 1024
let body = NSRect(x: 100, y: 100, width: 824, height: 824)
let cornerRadius: CGFloat = 185

func color(_ hex: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}

let base = color(0x306C52)
let top = color(0x3F8A68)
let bottom = color(0x22513C)

func drawIcon() {
    let squircle = NSBezierPath(roundedRect: body, xRadius: cornerRadius, yRadius: cornerRadius)

    // Drop shadow under the tile.
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowOffset = NSSize(width: 0, height: -12)
    shadow.shadowBlurRadius = 28
    shadow.set()
    base.setFill()
    squircle.fill()
    NSGraphicsContext.restoreGraphicsState()

    // Vertical gradient: lighter at the top, deeper at the bottom.
    NSGradient(colors: [top, base, bottom], atLocations: [0, 0.55, 1], colorSpace: .sRGB)!
        .draw(in: squircle, angle: -90)

    // Soft sheen across the upper half.
    NSGraphicsContext.saveGraphicsState()
    squircle.addClip()
    let sheen = NSBezierPath(ovalIn: NSRect(x: body.minX - 200, y: body.midY + 40, width: body.width + 400, height: body.height))
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.14), NSColor.white.withAlphaComponent(0)])!
        .draw(in: sheen, angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    // Thin inner highlight along the edge.
    NSGraphicsContext.saveGraphicsState()
    squircle.addClip()
    let rim = NSBezierPath(roundedRect: body.insetBy(dx: 2, dy: 2), xRadius: cornerRadius - 2, yRadius: cornerRadius - 2)
    rim.lineWidth = 4
    NSColor.white.withAlphaComponent(0.12).setStroke()
    rim.stroke()
    NSGraphicsContext.restoreGraphicsState()

    // The menu bar symbol, in white.
    // Tint the template by hand: palette colors would also fill in the hollow screen.
    let config = NSImage.SymbolConfiguration(pointSize: 400, weight: .medium)
    guard let template = NSImage(systemSymbolName: "macbook", accessibilityDescription: nil)?
        .withSymbolConfiguration(config) else { fatalError("macbook symbol not found") }
    let symbol = NSImage(size: template.size, flipped: false) { r in
        template.draw(in: r)
        NSColor.white.set()
        r.fill(using: .sourceAtop)
        return true
    }
    let maxWidth: CGFloat = 560
    let scale = maxWidth / symbol.size.width
    let size = NSSize(width: symbol.size.width * scale, height: symbol.size.height * scale)
    let rect = NSRect(x: body.midX - size.width / 2, y: body.midY - size.height / 2 - 6,
                      width: size.width, height: size.height)

    NSGraphicsContext.saveGraphicsState()
    let symbolShadow = NSShadow()
    symbolShadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
    symbolShadow.shadowOffset = NSSize(width: 0, height: -8)
    symbolShadow.shadowBlurRadius = 16
    symbolShadow.set()
    symbol.draw(in: rect)
    NSGraphicsContext.restoreGraphicsState()
}

func png(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: canvas, height: canvas)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    drawIcon()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let fm = FileManager.default
let resources = URL(fileURLWithPath: fm.currentDirectoryPath).appendingPathComponent("Resources")
let iconset = fm.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? fm.removeItem(at: iconset)
try fm.createDirectory(at: iconset, withIntermediateDirectories: true)

for points in [16, 32, 128, 256, 512] {
    try png(pixels: points).write(to: iconset.appendingPathComponent("icon_\(points)x\(points).png"))
    try png(pixels: points * 2).write(to: iconset.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}
try png(pixels: 1024).write(to: resources.appendingPathComponent("AppIcon.png"))

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", resources.appendingPathComponent("AppIcon.icns").path]
try iconutil.run()
iconutil.waitUntilExit()
print(iconutil.terminationStatus == 0 ? "Wrote Resources/AppIcon.png and Resources/AppIcon.icns" : "iconutil failed")
