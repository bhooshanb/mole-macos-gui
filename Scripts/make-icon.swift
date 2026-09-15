#!/usr/bin/env swift
// Generates Resources/AppIcon.icns — the vector Mole silhouette rendered at
// every icon size, composited into a rounded-rect dark tile.
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

    // Warm amber mole silhouette (same geometry as MoleSilhouette in-app).
    let accent = NSColor(red: 0.96, green: 0.62, blue: 0.28, alpha: 1)

    // Body dome with snout to the left.
    let body = NSBezierPath()
    let left = CGPoint(x: s * 0.20, y: s * 0.46)
    let right = CGPoint(x: s * 0.80, y: s * 0.46)
    body.move(to: left)
    body.curve(
        to: right,
        controlPoint1: CGPoint(x: s * 0.23, y: s * 0.80),
        controlPoint2: CGPoint(x: s * 0.68, y: s * 0.82))
    body.line(to: CGPoint(x: s * 0.80, y: s * 0.52))
    body.line(to: CGPoint(x: s * 0.20, y: s * 0.52))
    body.close()
    accent.setFill()
    body.fill()

    // Snout bump.
    let snout = NSBezierPath(
        ovalIn: NSRect(x: s * 0.15, y: s * 0.40, width: s * 0.14, height: s * 0.16))
    snout.fill()

    // Eye.
    let eye = NSBezierPath(
        ovalIn: NSRect(x: s * 0.40, y: s * 0.60, width: s * 0.055, height: s * 0.055))
    NSColor(red: 0.08, green: 0.08, blue: 0.09, alpha: 1).setFill()
    eye.fill()

    // Nose.
    let nose = NSBezierPath(
        ovalIn: NSRect(x: s * 0.165, y: s * 0.445, width: s * 0.035, height: s * 0.035))
    NSColor(red: 0.08, green: 0.08, blue: 0.09, alpha: 0.75).setFill()
    nose.fill()

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
