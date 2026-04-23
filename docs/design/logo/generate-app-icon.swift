#!/usr/bin/env swift
// Render the Capture mark (Slabbist app icon) to 1024×1024 PNGs.
//
// Usage:
//   swift docs/design/logo/generate-app-icon.swift
//
// Output:
//   ios/slabbist/slabbist/Assets.xcassets/AppIcon.appiconset/AppIcon-Universal.png
//   ios/slabbist/slabbist/Assets.xcassets/AppIcon.appiconset/AppIcon-Dark.png
//   ios/slabbist/slabbist/Assets.xcassets/AppIcon.appiconset/AppIcon-Tinted.png
//
// No rounded corners: iOS applies the superellipse mask. The dark obsidian
// gradient fills the full 1024×1024.

import AppKit
import CoreText
import Foundation

// MARK: - Paths

let repoRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()   // logo/
    .deletingLastPathComponent()   // design/
    .deletingLastPathComponent()   // docs/
    .deletingLastPathComponent()   // <repo root>
let fontURL = repoRoot
    .appendingPathComponent("ios/slabbist/slabbist/Resources/Fonts/InstrumentSerif-Italic.ttf")
let iconsetDir = repoRoot
    .appendingPathComponent("ios/slabbist/slabbist/Assets.xcassets/AppIcon.appiconset")

// MARK: - Font registration

guard CTFontManagerRegisterFontsForURL(fontURL as CFURL, .process, nil) else {
    let message = "Failed to register \(fontURL.path). Ensure the file exists and is a valid TTF."
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

// MARK: - Colors

extension NSColor {
    static func hex(_ hex: UInt32, alpha: CGFloat = 1.0) -> NSColor {
        NSColor(
            calibratedRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

let ink          = NSColor.hex(0x08080A)
let obsidianTop  = NSColor.hex(0x1A1A1F)
let cream        = NSColor.hex(0xF4F2ED)
let gold         = NSColor.hex(0xE2B765)
let goldDim      = NSColor.hex(0xA47E3D)
let white        = NSColor.hex(0xFFFFFF)
let midGray      = NSColor.hex(0x888888)

// MARK: - Drawing

enum Variant {
    case universal   // full color: obsidian background, gold brackets, cream S
    case dark        // same as universal (obsidian is already dark)
    case tinted      // neutral grayscale, used by iOS 18 for user-tinting
}

/// Draws the Capture mark onto the current graphics context at `size × size`.
/// Coordinates follow a 200×200 design canvas; all SVG pixels are scaled.
func drawCaptureMark(size: CGFloat, variant: Variant) {
    let scale = size / 200.0

    // Colors per variant
    let bgStart: NSColor
    let bgEnd: NSColor
    let strokeColor: NSColor
    let textColor: NSColor
    let scanGlowAlpha: CGFloat
    let scanLineAlpha: CGFloat

    switch variant {
    case .universal, .dark:
        bgStart = obsidianTop
        bgEnd = ink
        strokeColor = gold
        textColor = cream
        scanGlowAlpha = 0.12
        scanLineAlpha = 0.45
    case .tinted:
        // Grayscale template so iOS 18's tinted mode can recolor it cleanly.
        bgStart = NSColor(calibratedWhite: 0.10, alpha: 1)
        bgEnd = NSColor(calibratedWhite: 0.04, alpha: 1)
        strokeColor = NSColor(calibratedWhite: 0.88, alpha: 1)
        textColor = NSColor(calibratedWhite: 0.96, alpha: 1)
        scanGlowAlpha = 0.15
        scanLineAlpha = 0.50
    }

    // 1. Background — full square gradient (no corner radius; iOS applies the mask)
    let bgGradient = NSGradient(starting: bgStart, ending: bgEnd)!
    bgGradient.draw(in: NSRect(x: 0, y: 0, width: size, height: size), angle: -45)

    // Flip SVG y (top-down) into Cocoa y (bottom-up)
    func cy(_ svgY: Double) -> CGFloat { CGFloat(200 - svgY) * scale }

    // 2. Scan line — glow band (6 tall at y=97) + crisp line (2 tall at y=99)
    let scanX: CGFloat = 36 * scale
    let scanW: CGFloat = 128 * scale

    let glow = NSBezierPath(
        roundedRect: NSRect(x: scanX, y: cy(103), width: scanW, height: 6 * scale),
        xRadius: 3 * scale,
        yRadius: 3 * scale
    )
    strokeColor.withAlphaComponent(scanGlowAlpha).setFill()
    glow.fill()

    let line = NSBezierPath(
        roundedRect: NSRect(x: scanX, y: cy(101), width: scanW, height: 2 * scale),
        xRadius: 1 * scale,
        yRadius: 1 * scale
    )
    strokeColor.withAlphaComponent(scanLineAlpha).setFill()
    line.fill()

    // 3. Four L-shaped corner brackets — stroke width 6 on the 200 canvas
    let strokeWidth: CGFloat = 6 * scale
    strokeColor.setStroke()

    let brackets: [(start: (Double, Double), to: [(Double, Double)])] = [
        ((44, 72),  [(44, 44),  (72, 44)]),   // top-left
        ((128, 44), [(156, 44), (156, 72)]),  // top-right
        ((156, 128),[(156, 156),(128, 156)]), // bottom-right
        ((72, 156), [(44, 156), (44, 128)]),  // bottom-left
    ]
    for bracket in brackets {
        let p = NSBezierPath()
        p.move(to: NSPoint(x: bracket.start.0 * scale, y: cy(bracket.start.1)))
        for point in bracket.to {
            p.line(to: NSPoint(x: point.0 * scale, y: cy(point.1)))
        }
        p.lineWidth = strokeWidth
        p.lineCapStyle = .round
        p.lineJoinStyle = .round
        p.stroke()
    }

    // 4. Italic swash S — font size 128 on 200 canvas
    let fontSize = 128 * scale
    let font = NSFont(name: "InstrumentSerif-Italic", size: fontSize)
        ?? NSFont(descriptor: NSFontDescriptor(name: "Georgia", size: fontSize).withSymbolicTraits(.italic), size: fontSize)
        ?? NSFont.systemFont(ofSize: fontSize)

    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center

    let attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: textColor,
        .paragraphStyle: paragraph,
        .kern: -scale * 3,
    ]
    let str = NSAttributedString(string: "S", attributes: attrs)

    // Measure and center — prefer optical center of the glyph bounds over the
    // layout bounding box (italic serifs have generous sidebearings that throw
    // a naive center-of-bounds off).
    let line2 = CTLineCreateWithAttributedString(str)
    let glyphBounds = CTLineGetBoundsWithOptions(line2, .useOpticalBounds)

    let ctx = NSGraphicsContext.current!.cgContext
    ctx.saveGState()
    // Move origin to center, then draw glyph with its optical bounds centered.
    ctx.translateBy(
        x: size / 2 - glyphBounds.midX,
        y: size / 2 - glyphBounds.midY
    )
    CTLineDraw(line2, ctx)
    ctx.restoreGState()
}

func renderVariant(_ variant: Variant, size: CGFloat = 1024) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    drawCaptureMark(size: size, variant: variant)
    image.unlockFocus()
    return image
}

func savePNG(_ image: NSImage, to url: URL) throws {
    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "PNGEncoder", code: 1)
    }
    try png.write(to: url)
    print("wrote \(url.lastPathComponent)  (\(png.count / 1024) KB)")
}

// MARK: - Main

try FileManager.default.createDirectory(at: iconsetDir, withIntermediateDirectories: true)

for (variant, filename) in [
    (Variant.universal, "AppIcon-Universal.png"),
    (Variant.dark,      "AppIcon-Dark.png"),
    (Variant.tinted,    "AppIcon-Tinted.png"),
] {
    let image = renderVariant(variant)
    try savePNG(image, to: iconsetDir.appendingPathComponent(filename))
}

print("done")
