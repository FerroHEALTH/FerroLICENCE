// swift scripts/release/dmg-background.swift <out-dir>
//
// Draws the background of the disk image's window: the app's teal, a title,
// one line in English and one in Dutch, and an arrow from where Finder shows
// the app to where it shows Applications. Writes background.png (660 by 400)
// and background@2x.png; package.sh joins them into one Retina TIFF. The
// positions here must match the icon positions in package.sh.

import AppKit

let size = CGSize(width: 660, height: 400)
/// Icon centres in Finder's coordinates (from the top left), as package.sh sets them.
let app = CGPoint(x: 170, y: 200)
let applications = CGPoint(x: 490, y: 200)

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: dmg-background.swift <out-dir>\n".utf8))
    exit(2)
}
let out = URL(filePath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(
        srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha)
}

/// The text centred on `x` with its baseline at `y`, both from the top left.
func text(_ string: String, size: CGFloat, weight: NSFont.Weight, color: NSColor, x: CGFloat, y: CGFloat) {
    let attributed = NSAttributedString(
        string: string,
        attributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color, .kern: size > 20 ? -0.3 : 0])
    let width = attributed.size().width
    attributed.draw(at: CGPoint(x: x - width / 2, y: y))
}

func draw(scale: CGFloat, to url: URL) throws {
    guard
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0)
    else { throw CocoaError(.fileWriteUnknown) }
    rep.size = size
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = context
    // Draw from the top left, as Finder places icons.
    let cg = context.cgContext
    cg.translateBy(x: 0, y: size.height)
    cg.scaleBy(x: 1, y: -1)
    let flipped = NSGraphicsContext(cgContext: cg, flipped: true)
    NSGraphicsContext.current = flipped

    // A light wash of the app's teal, deeper towards the bottom.
    NSGradient(colors: [color(0xF6FBFA), color(0xE4F1EF)])!.draw(in: CGRect(origin: .zero, size: size), angle: 90)
    // Two soft discs give the surface some depth without drawing attention.
    color(0x0D7A73, 0.06).setFill()
    NSBezierPath(ovalIn: CGRect(x: 430, y: -170, width: 420, height: 420)).fill()
    color(0x0D7A73, 0.04).setFill()
    NSBezierPath(ovalIn: CGRect(x: -160, y: 250, width: 360, height: 360)).fill()

    text("Install FerroLICENCE", size: 24, weight: .semibold, color: color(0x0B4F4A), x: size.width / 2, y: 38)
    text("Drag the app onto Applications.", size: 13, weight: .regular, color: color(0x47625F), x: size.width / 2, y: 74)

    // The arrow: a gentle curve from the app to Applications, with a head.
    let start = CGPoint(x: app.x + 84, y: app.y)
    let end = CGPoint(x: applications.x - 90, y: applications.y)
    let path = NSBezierPath()
    path.move(to: start)
    let tail = CGPoint(x: end.x - 14, y: end.y - 3)
    path.curve(to: tail, controlPoint1: CGPoint(x: start.x + 50, y: start.y - 26), controlPoint2: CGPoint(x: tail.x - 50, y: tail.y - 24))
    path.lineWidth = 4
    path.lineCapStyle = .round
    let dash: [CGFloat] = [1, 11]
    path.setLineDash(dash, count: dash.count, phase: 0)
    color(0x0D7A73, 0.85).setStroke()
    path.stroke()
    let head = NSBezierPath()
    head.move(to: CGPoint(x: end.x - 13, y: end.y - 11))
    head.line(to: CGPoint(x: end.x + 2, y: end.y))
    head.line(to: CGPoint(x: end.x - 13, y: end.y + 11))
    head.lineWidth = 4
    head.lineCapStyle = .round
    head.lineJoinStyle = .round
    head.stroke()

    text("Sleep de app naar Programma's om te installeren.", size: 12, weight: .regular, color: color(0x6A8481), x: size.width / 2, y: 362)

    NSGraphicsContext.current = nil
    guard let png = rep.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
    try png.write(to: url)
}

try draw(scale: 1, to: out.appending(path: "background.png"))
try draw(scale: 2, to: out.appending(path: "background@2x.png"))
print("dmg-background: \(out.path())background.png and background@2x.png")
