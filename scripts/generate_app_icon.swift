import AppKit

let outputPath = "macos/Resources/AppIcon-1024.png"
let canvasSize = NSSize(width: 1024, height: 1024)

func color(_ hex: Int, alpha: CGFloat = 1.0) -> NSColor {
    NSColor(
        calibratedRed: CGFloat((hex >> 16) & 0xff) / 255.0,
        green: CGFloat((hex >> 8) & 0xff) / 255.0,
        blue: CGFloat(hex & 0xff) / 255.0,
        alpha: alpha
    )
}

func roundedRectPath(_ rect: CGRect, radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
}

let image = NSImage(size: canvasSize)
image.lockFocus()
guard let context = NSGraphicsContext.current?.cgContext else {
    fputs("failed to create graphics context\n", stderr)
    exit(1)
}
NSGraphicsContext.current?.imageInterpolation = .high

let fullRect = CGRect(origin: .zero, size: canvasSize)
context.clear(fullRect)

let cardRect = CGRect(x: 64, y: 64, width: 896, height: 896)
let cardPath = roundedRectPath(cardRect, radius: 210)

color(0x15202b).setFill()
cardPath.fill()
color(0x2b3746).setStroke()
cardPath.lineWidth = 4
cardPath.stroke()

let promptAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.monospacedSystemFont(ofSize: 210, weight: .bold),
    .foregroundColor: color(0xe9f3ff)
]
let promptAccentAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.monospacedSystemFont(ofSize: 210, weight: .bold),
    .foregroundColor: color(0x67d5ff)
]
let promptOrigin = CGPoint(x: 350, y: 336)
NSAttributedString(string: ">", attributes: promptAccentAttributes).draw(at: promptOrigin)
NSAttributedString(string: "_", attributes: promptAttributes).draw(at: CGPoint(x: promptOrigin.x + 154, y: promptOrigin.y))

image.unlockFocus()

guard let tiffData = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiffData),
      let pngData = rep.representation(using: .png, properties: [:]) else {
    fputs("failed to encode png\n", stderr)
    exit(1)
}

do {
    try pngData.write(to: URL(fileURLWithPath: outputPath))
    print("wrote \(outputPath)")
} catch {
    fputs("failed to write png: \(error)\n", stderr)
    exit(1)
}
