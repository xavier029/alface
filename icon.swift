// Gera icon.png (1024x1024) no gabarito de ícones do macOS: forma de 824 px, cantos de raio 185.
// Alface: verde-alface com a "ilha" preta do notch e uma ondinha de música.
// Uso: swift icon.swift
import AppKit

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024, bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let r = NSRect(x: 100, y: 100, width: 824, height: 824)
NSBezierPath(roundedRect: r, xRadius: 185, yRadius: 185).addClip()
NSGradient(colors: [NSColor(red: 0.62, green: 0.90, blue: 0.38, alpha: 1), NSColor(red: 0.18, green: 0.62, blue: 0.30, alpha: 1)])!
    .draw(in: r, angle: -90)
// ilha do notch
let island = NSRect(x: 512 - 250, y: 600, width: 500, height: 150)
NSColor.black.setFill()
NSBezierPath(roundedRect: island, xRadius: 75, yRadius: 75).fill()
// capa (quadradinho verde) e ondas
NSColor(red: 0.55, green: 0.88, blue: 0.36, alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(x: island.minX + 40, y: island.midY - 38, width: 76, height: 76), xRadius: 20, yRadius: 20).fill()
let heights: [CGFloat] = [40, 78, 56, 90, 48]
var x = island.maxX - 50 - CGFloat(heights.count) * 26
for h in heights {
    NSBezierPath(roundedRect: NSRect(x: x, y: island.midY - h / 2, width: 16, height: h), xRadius: 8, yRadius: 8).fill()
    x += 26
}
// folha
NSColor.white.withAlphaComponent(0.9).setFill()
let leaf = NSBezierPath()
leaf.move(to: NSPoint(x: 512, y: 210))
leaf.curve(to: NSPoint(x: 512, y: 500), controlPoint1: NSPoint(x: 340, y: 280), controlPoint2: NSPoint(x: 380, y: 470))
leaf.curve(to: NSPoint(x: 512, y: 210), controlPoint1: NSPoint(x: 644, y: 470), controlPoint2: NSPoint(x: 684, y: 280))
leaf.fill()
NSColor(red: 0.18, green: 0.62, blue: 0.30, alpha: 1).setStroke()
let vein = NSBezierPath(); vein.move(to: NSPoint(x: 512, y: 230)); vein.line(to: NSPoint(x: 512, y: 470)); vein.lineWidth = 12; vein.lineCapStyle = .round; vein.stroke()
NSGraphicsContext.current = nil
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "icon.png"))
print("ok: icon.png")
