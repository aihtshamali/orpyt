import AppKit
import Foundation

struct BackgroundConfig {
    let outputPath: String
    let width: CGFloat
    let height: CGFloat
}

private func drawArrow(in rect: CGRect, color: NSColor) {
    let path = NSBezierPath()
    path.lineWidth = 12
    path.lineCapStyle = .round
    path.lineJoinStyle = .round

    let start = CGPoint(x: rect.minX, y: rect.midY)
    let mid = CGPoint(x: rect.maxX - 28, y: rect.midY)
    let tip = CGPoint(x: rect.maxX, y: rect.midY)
    let upper = CGPoint(x: rect.maxX - 34, y: rect.maxY - 18)
    let lower = CGPoint(x: rect.maxX - 34, y: rect.minY + 18)

    path.move(to: start)
    path.line(to: mid)
    path.move(to: upper)
    path.line(to: tip)
    path.line(to: lower)

    color.setStroke()
    path.stroke()
}

private func drawText(_ text: String, in rect: CGRect, font: NSFont, color: NSColor, alignment: NSTextAlignment = .center) {
    let style = NSMutableParagraphStyle()
    style.alignment = alignment

    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: color,
        .paragraphStyle: style,
    ]

    let attributed = NSAttributedString(string: text, attributes: attributes)
    attributed.draw(in: rect)
}

private func writeBackground(_ config: BackgroundConfig) throws {
    let image = NSImage(size: NSSize(width: config.width, height: config.height))
    image.lockFocus()

    let bounds = CGRect(origin: .zero, size: image.size)
    NSColor(calibratedRed: 0.96, green: 0.97, blue: 0.99, alpha: 1).setFill()
    bounds.fill()

    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.98, green: 0.99, blue: 1.0, alpha: 1),
        NSColor(calibratedRed: 0.93, green: 0.96, blue: 1.0, alpha: 1),
    ])!
    gradient.draw(in: bounds, angle: -22)

    let leftGlow = NSBezierPath(ovalIn: CGRect(x: 60, y: 125, width: 150, height: 150))
    NSColor(calibratedRed: 0.24, green: 0.52, blue: 1.0, alpha: 0.09).setFill()
    leftGlow.fill()

    let rightGlow = NSBezierPath(ovalIn: CGRect(x: config.width - 210, y: 125, width: 150, height: 150))
    NSColor(calibratedRed: 0.29, green: 0.77, blue: 0.95, alpha: 0.09).setFill()
    rightGlow.fill()

    let topLine = NSBezierPath()
    topLine.move(to: CGPoint(x: 0, y: config.height - 1))
    topLine.line(to: CGPoint(x: config.width, y: config.height - 1))
    topLine.lineWidth = 1
    NSColor(calibratedWhite: 1, alpha: 0.72).setStroke()
    topLine.stroke()

    let bottomLine = NSBezierPath()
    bottomLine.move(to: CGPoint(x: 0, y: 1))
    bottomLine.line(to: CGPoint(x: config.width, y: 1))
    bottomLine.lineWidth = 1
    NSColor(calibratedWhite: 0.7, alpha: 0.18).setStroke()
    bottomLine.stroke()

    drawArrow(
        in: CGRect(x: (config.width / 2) - 38, y: 158, width: 76, height: 64),
        color: NSColor(calibratedWhite: 0.18, alpha: 0.92)
    )

    drawText(
        "Drag Orpyt into Applications",
        in: CGRect(x: 0, y: config.height - 74, width: config.width, height: 30),
        font: NSFont.systemFont(ofSize: 28, weight: .semibold),
        color: NSColor(calibratedWhite: 0.15, alpha: 1)
    )

    drawText(
        "Native macOS menu bar clock for people working across time zones.",
        in: CGRect(x: 0, y: config.height - 108, width: config.width, height: 22),
        font: NSFont.systemFont(ofSize: 15, weight: .regular),
        color: NSColor(calibratedWhite: 0.42, alpha: 1)
    )

    drawText(
        "Orpyt",
        in: CGRect(x: 64, y: 88, width: 160, height: 22),
        font: NSFont.systemFont(ofSize: 18, weight: .semibold),
        color: NSColor(calibratedWhite: 0.22, alpha: 1)
    )

    drawText(
        "Applications",
        in: CGRect(x: config.width - 224, y: 88, width: 160, height: 22),
        font: NSFont.systemFont(ofSize: 18, weight: .semibold),
        color: NSColor(calibratedWhite: 0.22, alpha: 1)
    )

    image.unlockFocus()

    guard
        let tiffData = image.tiffRepresentation,
        let bitmap = NSBitmapImageRep(data: tiffData),
        let pngData = bitmap.representation(using: .png, properties: [:])
    else {
        throw NSError(domain: "OrpytDMGBackground", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to encode PNG background"])
    }

    try pngData.write(to: URL(fileURLWithPath: config.outputPath))
}

let args = CommandLine.arguments
guard args.count == 4 else {
    fputs("usage: swift make_dmg_background.swift <output> <width> <height>\n", stderr)
    exit(2)
}

guard let width = Double(args[2]), let height = Double(args[3]) else {
    fputs("width and height must be numbers\n", stderr)
    exit(2)
}

do {
    try writeBackground(
        BackgroundConfig(
            outputPath: args[1],
            width: width,
            height: height
        )
    )
} catch {
    fputs("failed to create dmg background: \(error)\n", stderr)
    exit(1)
}
