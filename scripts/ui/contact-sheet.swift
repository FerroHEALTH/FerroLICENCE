// scripts/ui/contact-sheet.swift <folder> <out-folder>
//
// Tiles the screenshot tour's images into one contact sheet per screen, so
// every variant (light and dark, small and large, window and sheet) of a
// screen is reviewed side by side. Run with: swift scripts/ui/contact-sheet.swift

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
guard args.count == 3 else {
    print("usage: contact-sheet.swift <folder> <out-folder>")
    exit(2)
}
let folder = URL(filePath: args[1])
let out = URL(filePath: args[2])
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
    .filter { $0.pathExtension == "png" }
    .sorted { $0.lastPathComponent < $1.lastPathComponent }
let byScreen = Dictionary(grouping: files) { String($0.lastPathComponent.split(separator: "-").first ?? "") }

func image(_ url: URL) -> CGImage? {
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(src, 0, nil)
}

let cell = CGSize(width: 1000, height: 640)
let gap: CGFloat = 16
for (screen, urls) in byScreen.sorted(by: { $0.key < $1.key }) {
    let images = urls.compactMap(image)
    let columns = 2
    let rows = (images.count + columns - 1) / columns
    let width = Int(CGFloat(columns) * cell.width + CGFloat(columns + 1) * gap)
    let height = Int(CGFloat(rows) * cell.height + CGFloat(rows + 1) * gap)
    guard
        let ctx = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { continue }
    ctx.setFillColor(CGColor(gray: 0.5, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    for (i, img) in images.enumerated() {
        let scale = min(cell.width / CGFloat(img.width), cell.height / CGFloat(img.height))
        let w = CGFloat(img.width) * scale, h = CGFloat(img.height) * scale
        let col = CGFloat(i % columns), row = CGFloat(i / columns)
        let x = gap + col * (cell.width + gap)
        let y = CGFloat(height) - gap - (row + 1) * cell.height - row * gap + (cell.height - h)
        ctx.draw(img, in: CGRect(x: x, y: y, width: w, height: h))
    }
    guard let sheet = ctx.makeImage(),
        let dest = CGImageDestinationCreateWithURL(out.appending(path: "\(screen).png") as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { continue }
    CGImageDestinationAddImage(dest, sheet, nil)
    CGImageDestinationFinalize(dest)
    print(out.appending(path: "\(screen).png").path(), images.count)
}
