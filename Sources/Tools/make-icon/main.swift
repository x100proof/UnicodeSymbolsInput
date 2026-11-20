// Draws the menu-bar icon: a backslash-and-lambda template image at 1x and 2x.
// Usage: make-icon <output.tiff>   (Resources/icon.tiff is committed; rerun only to change it)
import Cocoa

let size = NSSize(width: 16, height: 16)
let reps: [NSBitmapImageRep] = [1, 2].map { scale in
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 16 * scale, pixelsHigh: 16 * scale,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let font = NSFont.systemFont(ofSize: 13, weight: .semibold)
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
    let text = "\\λ" as NSString
    let t = text.size(withAttributes: attrs)
    text.draw(at: NSPoint(x: (size.width - t.width) / 2, y: (size.height - t.height) / 2), withAttributes: attrs)
    NSGraphicsContext.restoreGraphicsState()
    return rep
}
let image = NSImage(size: size)
reps.forEach(image.addRepresentation)
guard CommandLine.arguments.count == 2,
      let tiff = image.tiffRepresentation(using: .lzw, factor: 1) else {
    fputs("usage: make-icon <output.tiff>\n", stderr)
    exit(2)
}
try tiff.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
