#!/usr/bin/env swift
import AppKit
import Foundation

// Original 心历 artwork drawn with editable AppKit paths; MIT licensed.
// Explicit bitmap dimensions avoid lockFocus() inheriting the display's Retina scale.
let destination = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "Resources/ChronoCal.iconset")
let resources = destination.deletingLastPathComponent()
let previewURL = URL(fileURLWithPath: CommandLine.arguments.dropFirst(2).first ?? "build/HeartCalendarQA/icon-preview.png")
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: previewURL.deletingLastPathComponent(), withIntermediateDirectories: true)

func rgb(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
}

func rounded(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat, _ radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: NSRect(x: x, y: y, width: width, height: height), xRadius: radius, yRadius: radius)
}

func withShadow(color: NSColor, blur: CGFloat, offset: NSSize, draw: () -> Void) {
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = color
    shadow.shadowBlurRadius = blur
    shadow.shadowOffset = offset
    shadow.set()
    draw()
    NSGraphicsContext.restoreGraphicsState()
}

func drawIcon() {
    let tile = rounded(64, 64, 896, 896, 208)
    withShadow(color: rgb(0.23, 0.31, 0.49, 0.14), blur: 18, offset: NSSize(width: 0, height: -7)) {
        rgb(0.80, 0.85, 0.95).setFill()
        tile.fill()
    }
    NSGradient(colorsAndLocations:
        (rgb(0.78, 0.85, 0.96), 0),
        (rgb(0.85, 0.88, 0.98), 0.48),
        (rgb(0.93, 0.93, 1.00), 1))!.draw(in: tile, angle: 90)

    // A broad, softly lit corner makes the backplate feel like satin glass.
    NSGraphicsContext.saveGraphicsState()
    tile.addClip()
    NSGradient(starting: rgb(1, 1, 1, 0.56), ending: rgb(1, 1, 1, 0))!
        .draw(fromCenter: NSPoint(x: 246, y: 932), radius: 0,
              toCenter: NSPoint(x: 246, y: 932), radius: 800, options: [.drawsAfterEndingLocation])
    NSGraphicsContext.restoreGraphicsState()
    rgb(1, 1, 1, 0.55).setStroke()
    tile.lineWidth = 3
    tile.stroke()

    // A single offset sheet supplies depth without clutter at small sizes.
    let backing = rounded(226, 194, 572, 596, 70)
    withShadow(color: rgb(0.22, 0.32, 0.52, 0.16), blur: 30, offset: NSSize(width: 0, height: -15)) {
        rgb(0.80, 0.84, 0.93).setFill()
        backing.fill()
    }
    let paper = rounded(214, 215, 596, 596, 72)
    withShadow(color: rgb(0.35, 0.44, 0.63, 0.10), blur: 9, offset: NSSize(width: 0, height: -5)) {
        rgb(0.995, 0.995, 1).setFill()
        paper.fill()
    }
    NSGradient(starting: rgb(0.945, 0.962, 0.995), ending: rgb(1, 1, 1))!.draw(in: paper, angle: 90)

    // The translucent calendar header and subtle hairline stay behind the heart.
    NSGraphicsContext.saveGraphicsState()
    paper.addClip()
    NSGradient(starting: rgb(0.90, 0.93, 0.99), ending: rgb(0.965, 0.974, 1))!
        .draw(in: NSRect(x: 214, y: 670, width: 596, height: 141), angle: 90)
    let separator = NSBezierPath()
    separator.move(to: NSPoint(x: 214, y: 670))
    separator.line(to: NSPoint(x: 810, y: 670))
    separator.lineWidth = 3
    rgb(0.72, 0.79, 0.92, 0.42).setStroke()
    separator.stroke()
    NSGraphicsContext.restoreGraphicsState()
    rgb(1, 1, 1, 0.90).setStroke()
    paper.lineWidth = 3
    paper.stroke()

    for x: CGFloat in [368, 656] {
        let socket = rounded(x - 31, 742, 62, 62, 31)
        rgb(0.65, 0.73, 0.89, 0.20).setFill()
        socket.fill()
        let ring = rounded(x - 17, 752, 34, 102, 17)
        withShadow(color: rgb(0.31, 0.43, 0.67, 0.13), blur: 5, offset: NSSize(width: 0, height: -3)) {
            NSGradient(starting: rgb(0.47, 0.61, 0.85), ending: rgb(0.69, 0.77, 0.94))!
                .draw(in: ring, angle: 90)
        }
        let ringLight = rounded(x - 11, 771, 7, 64, 3.5)
        rgb(1, 1, 1, 0.34).setFill()
        ringLight.fill()
    }

    // Two continuous lobes and a soft point: no text or tiny date details.
    let heart = NSBezierPath()
    heart.move(to: NSPoint(x: 512, y: 325))
    heart.curve(to: NSPoint(x: 340, y: 527), controlPoint1: NSPoint(x: 494, y: 343), controlPoint2: NSPoint(x: 340, y: 443))
    heart.curve(to: NSPoint(x: 512, y: 561), controlPoint1: NSPoint(x: 340, y: 611), controlPoint2: NSPoint(x: 440, y: 641))
    heart.curve(to: NSPoint(x: 684, y: 527), controlPoint1: NSPoint(x: 584, y: 641), controlPoint2: NSPoint(x: 684, y: 611))
    heart.curve(to: NSPoint(x: 512, y: 325), controlPoint1: NSPoint(x: 684, y: 443), controlPoint2: NSPoint(x: 530, y: 343))
    heart.close()
    withShadow(color: rgb(0.84, 0.28, 0.35, 0.17), blur: 13, offset: NSSize(width: 0, height: -8)) {
        NSGradient(starting: rgb(0.91, 0.31, 0.39), ending: rgb(1.00, 0.48, 0.48))!.draw(in: heart, angle: 90)
    }
    NSGraphicsContext.saveGraphicsState()
    heart.addClip()
    NSGradient(starting: rgb(1, 0.84, 0.78, 0.42), ending: rgb(1, 0.84, 0.78, 0))!
        .draw(fromCenter: NSPoint(x: 406, y: 601), radius: 0,
              toCenter: NSPoint(x: 406, y: 601), radius: 170, options: [.drawsAfterEndingLocation])
    NSGraphicsContext.restoreGraphicsState()
}

func bitmap(width: Int, height: Int, draw: () -> Void) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                               isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: width * 4, bitsPerPixel: 32)!
    rep.size = NSSize(width: width, height: height)
    let graphics = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphics
    graphics.imageInterpolation = .high
    graphics.cgContext.setShouldAntialias(true)
    graphics.cgContext.clear(CGRect(x: 0, y: 0, width: width, height: height))
    draw()
    graphics.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    precondition(rep.pixelsWide == width && rep.pixelsHigh == height)
    return rep
}

func iconBitmap(_ pixels: Int) -> NSBitmapImageRep {
    bitmap(width: pixels, height: pixels) {
        NSGraphicsContext.current!.cgContext.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
        drawIcon()
    }
}

func save(_ rep: NSBitmapImageRep, to url: URL) throws {
    try rep.representation(using: .png, properties: [:])!.write(to: url, options: .atomic)
}

for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        try save(iconBitmap(pixels), to: destination.appendingPathComponent(name))
        print("generated \(name): \(pixels)×\(pixels) pixels")
    }
}
try save(iconBitmap(1024), to: resources.appendingPathComponent("HeartCalendarIcon.png"))

let preview = bitmap(width: 920, height: 360) {
    rgb(0.955, 0.967, 0.986).setFill()
    NSRect(x: 0, y: 0, width: 920, height: 360).fill()
    let sizes = [16, 32, 64, 128, 256]
    let centers: [CGFloat] = [76, 190, 320, 492, 742]
    for (size, center) in zip(sizes, centers) {
        let rep = iconBitmap(size)
        NSGraphicsContext.current!.cgContext.draw(rep.cgImage!,
            in: CGRect(x: center - CGFloat(size) / 2, y: 195 - CGFloat(size) / 2,
                       width: CGFloat(size), height: CGFloat(size)))
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        ("\(size) × \(size)" as NSString).draw(in: NSRect(x: center - 60, y: 35, width: 120, height: 24),
            withAttributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 14, weight: .medium),
                             .foregroundColor: rgb(0.35, 0.40, 0.50), .paragraphStyle: paragraph])
    }
}
try save(preview, to: previewURL)
print("saved \(resources.appendingPathComponent("HeartCalendarIcon.png").path)")
print("saved \(previewURL.path)")
