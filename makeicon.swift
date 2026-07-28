// Renders KeepAwake.icns from an SF Symbol on a rounded-square gradient.
// Run: swift makeicon.swift <output-dir>
import AppKit

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
let iconset = "\(outDir)/KeepAwake.iconset"
try? FileManager.default.createDirectory(atPath: iconset, withIntermediateDirectories: true)

func render(_ px: Int) -> Data {
    let size = CGFloat(px)
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.setShouldAntialias(true)

    // macOS "squircle"-ish rounded rect with a small inset, per Apple icon grid.
    let inset = size * 0.085
    let rect = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let path = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.225, yRadius: rect.width * 0.225)

    ctx.saveGState()
    path.addClip()
    let gradient = NSGradient(colors: [
        NSColor(srgbRed: 0.36, green: 0.42, blue: 0.95, alpha: 1),
        NSColor(srgbRed: 0.19, green: 0.24, blue: 0.72, alpha: 1),
    ])!
    gradient.draw(in: rect, angle: -90)
    ctx.restoreGState()

    // Glyph
    let config = NSImage.SymbolConfiguration(pointSize: size * 0.46, weight: .medium)
    if let symbol = NSImage(systemSymbolName: "cup.and.saucer.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(config) {
        let tinted = NSImage(size: symbol.size)
        tinted.lockFocus()
        NSColor.white.set()
        NSRect(origin: .zero, size: symbol.size).fill(using: .sourceOver)
        symbol.draw(at: .zero, from: .zero, operation: .destinationIn, fraction: 1)
        tinted.unlockFocus()

        let w = symbol.size.width, h = symbol.size.height
        tinted.draw(in: CGRect(x: (size - w) / 2, y: (size - h) / 2 + size * 0.01, width: w, height: h))
    }

    image.unlockFocus()

    let tiff = image.tiffRepresentation!
    return NSBitmapImageRep(data: tiff)!.representation(using: .png, properties: [:])!
}

// Apple's required iconset matrix.
let variants: [(Int, String)] = [
    (16, "icon_16x16.png"), (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"), (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"), (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"), (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"), (1024, "icon_512x512@2x.png"),
]

for (px, name) in variants {
    try! render(px).write(to: URL(fileURLWithPath: "\(iconset)/\(name)"))
}
print("wrote \(iconset)")
