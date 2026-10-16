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

    // One bud: a rounded head with a flat blade stem in front of it, the Buds 3 and 4 shape.
    func bud(x: CGFloat, mirrored: Bool) {
        let dir: CGFloat = mirrored ? -1 : 1
        let tilt = NSAffineTransform()
        tilt.translateX(by: x, yBy: s * 0.60)
        tilt.rotate(byDegrees: -8 * dir)
        tilt.translateX(by: -x, yBy: -s * 0.60)

        let head = NSBezierPath(ovalIn: NSRect(x: x - s * 0.135, y: s * 0.49, width: s * 0.27, height: s * 0.22))
        head.transform(using: tilt as AffineTransform)
        NSColor.white.withAlphaComponent(0.96).setFill()
        head.fill()

        let stemRect = NSRect(x: x - s * 0.052, y: s * 0.16, width: s * 0.104, height: s * 0.46)
        let stem = NSBezierPath(roundedRect: stemRect, xRadius: s * 0.034, yRadius: s * 0.034)
        let lean = NSAffineTransform()
        lean.translateX(by: x, yBy: s * 0.60)
        lean.rotate(byDegrees: -5 * dir)
        lean.translateX(by: -x, yBy: -s * 0.60)
        stem.transform(using: lean as AffineTransform)
        NSGradient(colors: [
            NSColor(calibratedWhite: 0.90, alpha: 1),
            NSColor(calibratedWhite: 0.70, alpha: 1),
        ])!.draw(in: stem, angle: mirrored ? 20 : 160)
        NSColor(calibratedWhite: 0.55, alpha: 0.5).setStroke()
        stem.lineWidth = max(1, s * 0.006)
        stem.stroke()

        let grille = NSBezierPath(ovalIn: NSRect(x: x - s * 0.03, y: s * 0.555, width: s * 0.06, height: s * 0.06))
        grille.transform(using: lean as AffineTransform)
        NSColor(calibratedRed: 0.20, green: 0.27, blue: 0.62, alpha: 0.55).setFill()
        grille.fill()
    }
    bud(x: s * 0.35, mirrored: true)
    bud(x: s * 0.65, mirrored: false)
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
