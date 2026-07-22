#!/usr/bin/swift
import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
    fputs("usage: generate-app-icon.swift OUTPUT.iconset\n", stderr)
    exit(2)
}

let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

let variants: [(name: String, pixels: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for variant in variants {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: variant.pixels,
        pixelsHigh: variant.pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else { throw CocoaError(.fileWriteUnknown) }
    bitmap.size = NSSize(width: variant.pixels, height: variant.pixels)
    NSGraphicsContext.saveGraphicsState()
    guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw CocoaError(.fileWriteUnknown)
    }
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    let scale = CGFloat(variant.pixels) / 1024
    let transform = NSAffineTransform()
    transform.scaleX(by: scale, yBy: scale)
    transform.concat()

    let tile = NSBezierPath(roundedRect: NSRect(x: 56, y: 56, width: 912, height: 912), xRadius: 205, yRadius: 205)
    NSGraphicsContext.saveGraphicsState()
    tile.addClip()
    NSGradient(colors: [
        NSColor(calibratedRed: 0.10, green: 0.39, blue: 0.88, alpha: 1),
        NSColor(calibratedRed: 0.03, green: 0.64, blue: 0.55, alpha: 1)
    ])?.draw(in: tile, angle: -42)
    NSGraphicsContext.restoreGraphicsState()

    let page = NSBezierPath(roundedRect: NSRect(x: 228, y: 164, width: 568, height: 696), xRadius: 76, yRadius: 76)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.18)
    shadow.shadowOffset = NSSize(width: 0, height: -24)
    shadow.shadowBlurRadius = 38
    shadow.set()
    NSColor.white.withAlphaComponent(0.97).setFill()
    page.fill()
    NSGraphicsContext.restoreGraphicsState()

    let fold = NSBezierPath()
    fold.move(to: NSPoint(x: 650, y: 860))
    fold.line(to: NSPoint(x: 796, y: 714))
    fold.line(to: NSPoint(x: 650, y: 714))
    fold.close()
    NSColor(calibratedRed: 0.82, green: 0.91, blue: 0.98, alpha: 1).setFill()
    fold.fill()

    let code = "{ }" as NSString
    let codeAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedSystemFont(ofSize: 230, weight: .semibold),
        .foregroundColor: NSColor(calibratedRed: 0.08, green: 0.33, blue: 0.68, alpha: 1)
    ]
    let codeSize = code.size(withAttributes: codeAttributes)
    code.draw(at: NSPoint(x: 512 - codeSize.width / 2, y: 425), withAttributes: codeAttributes)

    let leaf = NSBezierPath()
    leaf.move(to: NSPoint(x: 540, y: 248))
    leaf.curve(to: NSPoint(x: 758, y: 394), controlPoint1: NSPoint(x: 580, y: 390), controlPoint2: NSPoint(x: 704, y: 430))
    leaf.curve(to: NSPoint(x: 540, y: 248), controlPoint1: NSPoint(x: 746, y: 292), controlPoint2: NSPoint(x: 650, y: 232))
    leaf.close()
    NSColor(calibratedRed: 0.19, green: 0.72, blue: 0.35, alpha: 1).setFill()
    leaf.fill()
    let vein = NSBezierPath()
    vein.move(to: NSPoint(x: 548, y: 252))
    vein.curve(to: NSPoint(x: 716, y: 365), controlPoint1: NSPoint(x: 604, y: 278), controlPoint2: NSPoint(x: 664, y: 334))
    vein.lineWidth = 13
    vein.lineCapStyle = .round
    NSColor.white.withAlphaComponent(0.75).setStroke()
    vein.stroke()

    NSGraphicsContext.restoreGraphicsState()
    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
    }
    try png.write(to: output.appendingPathComponent(variant.name), options: .atomic)
}
