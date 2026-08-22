// Generates a QR code PNG. Used for the donation addresses in the README:
//
//     swift Tools/make-qr.swift <text> <out.png>
//
// CoreImage does the encoding, so there is no third-party dependency. The
// output is black on opaque white with a quiet zone, which is what scanners
// expect — a transparent background reads badly on dark GitHub themes.

import AppKit
import CoreImage

let args = CommandLine.arguments
guard args.count >= 3 else {
    FileHandle.standardError.write("usage: make-qr.swift <text> <out.png>\n".data(using: .utf8)!)
    exit(2)
}
let text = args[1]
let outPath = args[2]
let side: CGFloat = 480
let quietZone: CGFloat = 24

guard let filter = CIFilter(name: "CIQRCodeGenerator") else {
    FileHandle.standardError.write("CIQRCodeGenerator unavailable\n".data(using: .utf8)!)
    exit(1)
}
filter.setValue(text.data(using: .ascii) ?? Data(text.utf8), forKey: "inputMessage")
// M tolerates ~15% damage; plenty for a screen or a printed sticker.
filter.setValue("M", forKey: "inputCorrectionLevel")

guard let code = filter.outputImage else {
    FileHandle.standardError.write("encoding failed\n".data(using: .utf8)!)
    exit(1)
}

// Nearest-neighbour scaling keeps the module edges crisp.
let inner = side - quietZone * 2
let scale = inner / code.extent.width
let scaled = code
    .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    .samplingNearest()

let canvas = NSImage(size: NSSize(width: side, height: side))
canvas.lockFocus()
NSColor.white.setFill()
NSRect(x: 0, y: 0, width: side, height: side).fill()
NSImage(size: NSSize(width: inner, height: inner), flipped: false) { rect in
    NSCIImageRep(ciImage: scaled).draw(in: rect)
    return true
}.draw(in: NSRect(x: quietZone, y: quietZone, width: inner, height: inner))
canvas.unlockFocus()

guard let tiff = canvas.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:])
else {
    FileHandle.standardError.write("png encoding failed\n".data(using: .utf8)!)
    exit(1)
}
try png.write(to: URL(fileURLWithPath: outPath))
print("wrote \(outPath) (\(Int(side))×\(Int(side)), \(text.count) chars)")
