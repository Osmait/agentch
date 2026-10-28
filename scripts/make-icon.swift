// Draws the app icon (a notch with three usage bars on a midnight tile) into
// Agentch/Resources/Assets.xcassets/AppIcon.appiconset at every size macOS needs.
//
//   swift scripts/make-icon.swift
import AppKit

let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let iconSet = root.appendingPathComponent("Agentch/Resources/Assets.xcassets/AppIcon.appiconset")

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

/// Draws the icon on a `pixels`-wide canvas. The artwork is laid out on a 400-unit
/// tile, which fills 824 of every 1024 pixels like Apple's macOS icon grid.
func render(pixels: Int) -> Data {
    let size = CGFloat(pixels)
    let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    // Top-left origin, so coordinates match the design.
    context.translateBy(x: 0, y: size)
    context.scaleBy(x: 1, y: -1)

    let unit = size * 824 / 1024 / 400
    let origin = size * 100 / 1024
    func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
        CGRect(x: origin + x * unit, y: origin + y * unit, width: w * unit, height: h * unit)
    }

    let tile = CGPath(roundedRect: rect(0, 0, 400, 400), cornerWidth: 90 * unit, cornerHeight: 90 * unit, transform: nil)

    // Drop shadow under the tile.
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: 10 * unit), blur: 24 * unit, color: color(0x000000, 0.35))
    context.addPath(tile)
    context.setFillColor(color(0x0A0D1C))
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(tile)
    context.clip()

    // Midnight gradient, lighter at the top left.
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                              colors: [color(0x262E5C), color(0x0A0D1C)] as CFArray, locations: [0, 1])!
    context.drawLinearGradient(gradient, start: CGPoint(x: origin + 130 * unit, y: origin - 20 * unit),
                               end: CGPoint(x: origin + 270 * unit, y: origin + 420 * unit), options: [])

    // Usage bars: track, then fill.
    for (top, fraction, hex) in [(150.0, 0.76, 0xF08A6C), (214.0, 0.52, 0x5FD3A5), (278.0, 0.30, 0xA992FF)] as [(CGFloat, CGFloat, UInt32)] {
        let track = rect(72, top, 256, 30)
        context.addPath(CGPath(roundedRect: track, cornerWidth: 15 * unit, cornerHeight: 15 * unit, transform: nil))
        context.setFillColor(color(0xFFFFFF, 0.12))
        context.fillPath()
        let fill = rect(72, top, 256 * fraction, 30)
        context.addPath(CGPath(roundedRect: fill, cornerWidth: 15 * unit, cornerHeight: 15 * unit, transform: nil))
        context.setFillColor(color(hex))
        context.fillPath()
    }

    // Hairline edge, under the notch so it doesn't cross it.
    context.addPath(CGPath(roundedRect: rect(1, 1, 398, 398), cornerWidth: 89 * unit, cornerHeight: 89 * unit, transform: nil))
    context.setStrokeColor(color(0xFFFFFF, 0.08))
    context.setLineWidth(2 * unit)
    context.strokePath()

    // The notch, hanging from the top edge with rounded lower corners.
    let notch = rect(110, -40, 180, 94)
    context.addPath(CGPath(roundedRect: notch, cornerWidth: 30 * unit, cornerHeight: 30 * unit, transform: nil))
    context.setFillColor(color(0x000000))
    context.fillPath()
    context.restoreGState()

    let image = NSBitmapImageRep(cgImage: context.makeImage()!)
    return image.representation(using: .png, properties: [:])!
}

try FileManager.default.createDirectory(at: iconSet, withIntermediateDirectories: true)
var images: [[String: String]] = []
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        try render(pixels: points * scale).write(to: iconSet.appendingPathComponent(name))
        images.append(["idiom": "mac", "size": "\(points)x\(points)", "scale": "\(scale)x", "filename": name])
    }
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
    .write(to: iconSet.appendingPathComponent("Contents.json"))
print("Wrote \(images.count) icons to \(iconSet.path)")
