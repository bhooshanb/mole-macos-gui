#!/usr/bin/env swift
// Generates Resources/AppIcon.icns — the SparkClean four-point sparkle burst
// rendered at every icon size, composited into a rounded-rect dark tile.
import AppKit

let sizes = [16, 32, 64, 128, 256, 512, 1024]

func drawIcon(_ size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    let s = size
    // Rounded dark tile with subtle gradient (macOS icon style).
    let tileRect = NSRect(x: s * 0.05, y: s * 0.05, width: s * 0.9, height: s * 0.9)
    let tilePath = NSBezierPath(roundedRect: tileRect, xRadius: s * 0.185, yRadius: s * 0.185)

    let gradient = NSGradient(
        starting: NSColor(red: 0.13, green: 0.135, blue: 0.155, alpha: 1),
        ending: NSColor(red: 0.07, green: 0.075, blue: 0.09, alpha: 1))
    gradient?.draw(in: tilePath, angle: -90)

    // SparkClean brand electric blue-violet (same as SparkCleanTheme.accent).
    let accent = NSGradient(
        starting: NSColor(red: 0.62, green: 0.55, blue: 1.0, alpha: 1),
        ending: NSColor(red: 0.42, green: 0.36, blue: 0.98, alpha: 1))

    // Four-point sparkle path: convex points joined by concave curves.
    func sparklePath(center: CGPoint, radius: CGFloat) -> NSBezierPath {
        let pinch = radius * 0.22
        let path = NSBezierPath()
        path.move(to: CGPoint(x: center.x, y: center.y - radius))
        path.curve(
            to: CGPoint(x: center.x + radius, y: center.y),
            controlPoint1: CGPoint(x: center.x + pinch, y: center.y - pinch),
            controlPoint2: CGPoint(x: center.x + pinch, y: center.y - pinch))
        path.curve(
            to: CGPoint(x: center.x, y: center.y + radius),
            controlPoint1: CGPoint(x: center.x + pinch, y: center.y + pinch),
            controlPoint2: CGPoint(x: center.x + pinch, y: center.y + pinch))
        path.curve(
            to: CGPoint(x: center.x - radius, y: center.y),
            controlPoint1: CGPoint(x: center.x - pinch, y: center.y + pinch),
            controlPoint2: CGPoint(x: center.x - pinch, y: center.y + pinch))
        path.curve(
            to: CGPoint(x: center.x, y: center.y - radius),
            controlPoint1: CGPoint(x: center.x - pinch, y: center.y - pinch),
            controlPoint2: CGPoint(x: center.x - pinch, y: center.y - pinch))
        path.close()
        return path
    }

    // Primary sparkle, centered, with a soft glow behind it.
    let glowRect = NSRect(x: s * 0.2, y: s * 0.2, width: s * 0.6, height: s * 0.6)
    let glow = NSGradient(
        starting: NSColor(red: 0.55, green: 0.45, blue: 1.0, alpha: 0.35),
        ending: NSColor(red: 0.55, green: 0.45, blue: 1.0, alpha: 0.0))
    glow?.draw(in: NSBezierPath(ovalIn: glowRect), angle: -90)

    accent?.draw(
        in: sparklePath(center: CGPoint(x: s * 0.5, y: s * 0.5), radius: s * 0.3),
        angle: -90)

    // Upper-right satellite sparkle (NSImage is flipped: y grows downward).
    accent?.draw(
        in: sparklePath(center: CGPoint(x: s * 0.76, y: s * 0.28), radius: s * 0.13),
        angle: -90)

    // Lower-left satellite sparkle.
    accent?.draw(
        in: sparklePath(center: CGPoint(x: s * 0.26, y: s * 0.74), radius: s * 0.1),
        angle: -90)

    image.unlockFocus()
    return image
}

let iconsetPath = "build/AppIcon.iconset"
try? FileManager.default.createDirectory(
    atPath: iconsetPath, withIntermediateDirectories: true)

for size in sizes {
    let image = drawIcon(CGFloat(size))
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write(Data("icon render failed at \(size)\n".utf8))
        continue
    }
    let name = size <= 512 ? "icon_\(size)x\(size).png" : "icon_512x512@2x.png"
    if size == 1024 { continue }
    try? png.write(to: URL(fileURLWithPath: "\(iconsetPath)/\(name)"))
    if size <= 256 {
        let retinaName = "icon_\(size / 2)x\(size / 2)@2x.png"
        try? png.write(to: URL(fileURLWithPath: "\(iconsetPath)/\(retinaName)"))
    }
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconsetPath, "-o", "Resources/AppIcon.icns"]
try? process.run()
process.waitUntilExit()

if process.terminationStatus == 0 {
    print("Wrote Resources/AppIcon.icns")
} else {
    FileHandle.standardError.write(Data("iconutil failed\n".utf8))
}
