// Renders the TrackIt app icon as a 1024×1024 PNG.
// Usage: swift scripts/make_icon.swift <output.png>
import AppKit

let px = 1024
let size = CGFloat(px)
let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"

guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
    samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
) else { fatalError("bitmap") }

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

let inset: CGFloat = 100
let rect = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
let shape = NSBezierPath(roundedRect: rect, xRadius: 186, yRadius: 186)

// Drop shadow
NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
shadow.shadowBlurRadius = 28
shadow.shadowOffset = NSSize(width: 0, height: -14)
shadow.set()
NSColor.black.setFill()
shape.fill()
NSGraphicsContext.restoreGraphicsState()

// Base gradient: violet → magenta → coral
let base = NSGradient(colors: [
    NSColor(srgbRed: 0.42, green: 0.32, blue: 1.00, alpha: 1),
    NSColor(srgbRed: 0.78, green: 0.33, blue: 0.95, alpha: 1),
    NSColor(srgbRed: 1.00, green: 0.42, blue: 0.55, alpha: 1),
])!
base.draw(in: shape, angle: -50)

// Soft top highlight
let gloss = NSGradient(colors: [
    NSColor.white.withAlphaComponent(0.0),
    NSColor.white.withAlphaComponent(0.22),
])!
gloss.draw(in: shape, angle: 90)

// Inner stroke
NSColor.white.withAlphaComponent(0.18).setStroke()
shape.lineWidth = 4
shape.stroke()

// Glyph
let config = NSImage.SymbolConfiguration(pointSize: 430, weight: .bold)
    .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
if let symbol = NSImage(systemSymbolName: "checklist", accessibilityDescription: nil)?
    .withSymbolConfiguration(config) {
    let s = symbol.size
    symbol.draw(in: NSRect(x: (size - s.width) / 2, y: (size - s.height) / 2 - 6, width: s.width, height: s.height))
}

NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("png") }
try png.write(to: URL(fileURLWithPath: output))
print("wrote \(output)")
