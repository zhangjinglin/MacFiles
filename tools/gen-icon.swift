#!/usr/bin/env swift
import AppKit
import CoreGraphics

// Draws the 1024x1024 app icon: a blue gradient squircle with a
// two-pane file manager window (folder tree on the left, file rows on the right).

let outputPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources/AppIcon-1024.png"
let canvas: CGFloat = 1024

guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(canvas),
    pixelsHigh: Int(canvas),
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else { fatalError("cannot create bitmap") }

NSGraphicsContext.saveGraphicsState()
let nsContext = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.current = nsContext
let cg = nsContext.cgContext
cg.clear(CGRect(x: 0, y: 0, width: canvas, height: canvas))

let blue = NSColor(srgbRed: 0.23, green: 0.45, blue: 0.98, alpha: 1)
let lightBlue = NSColor(srgbRed: 0.55, green: 0.70, blue: 1.0, alpha: 1)
let paleBlue = NSColor(srgbRed: 0.76, green: 0.84, blue: 1.0, alpha: 1)
let lineGray = NSColor(srgbRed: 0.78, green: 0.83, blue: 0.91, alpha: 1)

// MARK: - Background squircle

let margin: CGFloat = 100
let badge = CGRect(x: margin, y: margin, width: canvas - margin * 2, height: canvas - margin * 2)
let badgeRadius: CGFloat = 188
let badgePath = CGPath(roundedRect: badge, cornerWidth: badgeRadius, cornerHeight: badgeRadius, transform: nil)

cg.saveGState()
cg.setShadow(offset: CGSize(width: 0, height: -14), blur: 34, color: NSColor.black.withAlphaComponent(0.30).cgColor)
cg.addPath(badgePath)
cg.setFillColor(NSColor.white.cgColor)
cg.fillPath()
cg.restoreGState()

cg.saveGState()
cg.addPath(badgePath)
cg.clip()

let backgroundGradient = CGGradient(
    colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: [
        NSColor(srgbRed: 0.20, green: 0.48, blue: 0.99, alpha: 1).cgColor,
        NSColor(srgbRed: 0.42, green: 0.28, blue: 0.92, alpha: 1).cgColor,
    ] as CFArray,
    locations: [0, 1]
)!
cg.drawLinearGradient(
    backgroundGradient,
    start: CGPoint(x: badge.minX, y: badge.maxY),
    end: CGPoint(x: badge.maxX, y: badge.minY),
    options: []
)

let highlight = CGGradient(
    colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: [
        NSColor.white.withAlphaComponent(0.28).cgColor,
        NSColor.white.withAlphaComponent(0.0).cgColor,
    ] as CFArray,
    locations: [0, 1]
)!
cg.drawLinearGradient(
    highlight,
    start: CGPoint(x: 0, y: badge.maxY),
    end: CGPoint(x: 0, y: badge.midY),
    options: []
)
cg.restoreGState()

// Inner rim
cg.saveGState()
cg.addPath(badgePath)
cg.setStrokeColor(NSColor.white.withAlphaComponent(0.18).cgColor)
cg.setLineWidth(3)
cg.strokePath()
cg.restoreGState()

// MARK: - Window card

let card = CGRect(x: 252, y: 300, width: 520, height: 424)
let cardRadius: CGFloat = 46
let cardPath = CGPath(roundedRect: card, cornerWidth: cardRadius, cornerHeight: cardRadius, transform: nil)

cg.saveGState()
cg.setShadow(offset: CGSize(width: 0, height: -10), blur: 26, color: NSColor.black.withAlphaComponent(0.22).cgColor)
cg.addPath(cardPath)
cg.setFillColor(NSColor(srgbRed: 0.985, green: 0.99, blue: 1.0, alpha: 1).cgColor)
cg.fillPath()
cg.restoreGState()

// Divider between the panes
let dividerX = card.minX + 206
cg.setFillColor(lineGray.withAlphaComponent(0.75).cgColor)
cg.fill(CGRect(x: dividerX, y: card.minY + 38, width: 2, height: card.height - 76))

// MARK: - Folder tree (left pane)

func folder(_ rect: CGRect, color: NSColor) {
    let bodyHeight = rect.height * 0.8
    let body = CGPath(
        roundedRect: CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: bodyHeight),
        cornerWidth: rect.height * 0.18,
        cornerHeight: rect.height * 0.18,
        transform: nil
    )
    cg.addPath(body)
    cg.setFillColor(color.cgColor)
    cg.fillPath()

    let tab = CGPath(
        roundedRect: CGRect(
            x: rect.minX,
            y: rect.minY + bodyHeight - rect.height * 0.02,
            width: rect.width * 0.48,
            height: rect.height * 0.30
        ),
        cornerWidth: rect.height * 0.12,
        cornerHeight: rect.height * 0.12,
        transform: nil
    )
    cg.addPath(tab)
    cg.setFillColor(color.cgColor)
    cg.fillPath()
}

let folderRows: [(width: CGFloat, indent: CGFloat, color: NSColor, height: CGFloat)] = [
    (116, 0, blue, 44),
    (94, 22, lightBlue, 36),
    (72, 44, paleBlue, 30),
]

for (index, row) in folderRows.enumerated() {
    let y = card.maxY - 118 - CGFloat(index) * 64 - row.height
    folder(
        CGRect(x: card.minX + 38 + row.indent, y: y, width: row.width, height: row.height),
        color: row.color
    )
}

// MARK: - File rows (right pane)

func fileRow(y: CGFloat, textWidth: CGFloat) {
    let iconRect = CGRect(x: dividerX + 34, y: y, width: 26, height: 32)
    let icon = CGPath(
        roundedRect: iconRect,
        cornerWidth: 5,
        cornerHeight: 5,
        transform: nil
    )
    cg.addPath(icon)
    cg.setFillColor(blue.withAlphaComponent(0.9).cgColor)
    cg.fillPath()

    let bar = CGPath(
        roundedRect: CGRect(x: iconRect.maxX + 16, y: y + 11, width: textWidth, height: 10),
        cornerWidth: 5,
        cornerHeight: 5,
        transform: nil
    )
    cg.addPath(bar)
    cg.setFillColor(lineGray.cgColor)
    cg.fillPath()
}

let fileRows: [(y: CGFloat, width: CGFloat)] = [
    (card.maxY - 116, 156),
    (card.maxY - 178, 130),
    (card.maxY - 240, 168),
    (card.maxY - 302, 112),
]

for row in fileRows {
    fileRow(y: row.y, textWidth: row.width)
}

// MARK: - Write PNG

NSGraphicsContext.restoreGraphicsState()

guard let data = rep.representation(using: .png, properties: [:]) else {
    fatalError("cannot encode PNG")
}
try data.write(to: URL(fileURLWithPath: outputPath))
print("wrote \(outputPath)")
