// SPDX-License-Identifier: Apache-2.0
// Draws the app icon and writes Resources/AppIcon.icns.
// Run with: swift Scripts/make-icon.swift
import AppKit

func render(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    let s = size
    let inset = s * 0.07
    let rect = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let tile = NSBezierPath(roundedRect: rect, xRadius: s * 0.2, yRadius: s * 0.2)
    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.20, green: 0.27, blue: 0.62, alpha: 1),
        NSColor(calibratedRed: 0.09, green: 0.60, blue: 0.68, alpha: 1),
    ])!
    gradient.draw(in: tile, angle: -60)

    func bud(x: CGFloat, mirrored: Bool) {
        let head = NSBezierPath(ovalIn: NSRect(x: x - s * 0.11, y: s * 0.46, width: s * 0.22, height: s * 0.22))
        NSColor.white.withAlphaComponent(0.95).setFill()
        head.fill()
        let stem = NSBezierPath()
        stem.lineWidth = s * 0.075
        stem.lineCapStyle = .round
        stem.move(to: NSPoint(x: x + (mirrored ? -1 : 1) * s * 0.03, y: s * 0.47))
        stem.line(to: NSPoint(x: x + (mirrored ? -1 : 1) * s * 0.09, y: s * 0.28))
        NSColor.white.withAlphaComponent(0.95).setStroke()
        stem.stroke()
        let tip = NSBezierPath(
            ovalIn: NSRect(
                x: x - s * 0.05 + (mirrored ? -1 : 1) * s * 0.03, y: s * 0.49, width: s * 0.1, height: s * 0.1))
        NSColor(calibratedRed: 0.20, green: 0.27, blue: 0.62, alpha: 0.35).setFill()
        tip.fill()
    }
    bud(x: s * 0.36, mirrored: true)
    bud(x: s * 0.64, mirrored: false)
    image.unlockFocus()
    return image
}

func png(_ image: NSImage, pixels: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    render(size: CGFloat(pixels)).draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try png(render(size: CGFloat(base)), pixels: base).write(
        to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try png(render(size: CGFloat(base * 2)), pixels: base * 2).write(
        to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
let output = root.appendingPathComponent("Resources/AppIcon.icns")
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try task.run()
task.waitUntilExit()
print(task.terminationStatus == 0 ? "Wrote \(output.path)" : "iconutil failed")
