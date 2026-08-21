// Regenerates Resources/AppIcon.icns. Run from the repo root:
//
//     swift Tools/make-icon.swift
//
// The .icns is committed, so this only needs running when the artwork changes.
// Each size is drawn from scratch rather than downscaled, so small sizes stay
// crisp. Artwork: graphite squircle, white bolt — the same glyph the menu bar
// uses (SF Symbol bolt.fill).

import AppKit
import Foundation

let canvas: [(name: String, px: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

/// A white version of an SF Symbol, isolated in its own image so the tint fill
/// cannot bleed onto the background it will later be drawn over.
func whiteSymbol(_ name: String, pointSize: CGFloat) -> NSImage? {
    let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
    guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
        .withSymbolConfiguration(config) else { return nil }
    let out = NSImage(size: base.size)
    out.lockFocus()
    base.draw(in: CGRect(origin: .zero, size: base.size))
    NSColor.white.set()
    CGRect(origin: .zero, size: base.size).fill(using: .sourceAtop)
    out.unlockFocus()
    return out
}

func drawIcon(px: Int) -> Data {
    let size = CGFloat(px)
    // Draw into an explicitly sRGB context. An untagged bitmap gets colour-shifted
    // by consumers that guess the space (NSWorkspace's icon cache, for one).
    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
          let cg = CGContext(data: nil, width: px, height: px,
                             bitsPerComponent: 8, bytesPerRow: 0, space: space,
                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { fatalError("cannot create context at \(px)px") }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: false)

    // macOS app icon geometry: 824/1024 content box, 185.4/1024 corner radius.
    let inset = size * (100.0 / 1024.0)
    let box = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let radius = size * (185.4 / 1024.0)
    let squircle = CGPath(roundedRect: box, cornerWidth: radius, cornerHeight: radius, transform: nil)

    cg.saveGState()
    cg.addPath(squircle)
    cg.clip()
    let top = NSColor(srgbRed: 0.22, green: 0.24, blue: 0.28, alpha: 1).cgColor
    let bottom = NSColor(srgbRed: 0.07, green: 0.08, blue: 0.10, alpha: 1).cgColor
    if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                colors: [top, bottom] as CFArray, locations: [0, 1]) {
        cg.drawLinearGradient(gradient,
                              start: CGPoint(x: 0, y: box.maxY),
                              end: CGPoint(x: 0, y: box.minY),
                              options: [])
    }
    cg.restoreGState()

    // Hairline rim so the icon keeps an edge on dark wallpapers.
    cg.saveGState()
    cg.addPath(squircle)
    cg.setStrokeColor(NSColor(white: 1, alpha: 0.12).cgColor)
    cg.setLineWidth(max(1, size * 0.005))
    cg.strokePath()
    cg.restoreGState()

    if let bolt = whiteSymbol("bolt.fill", pointSize: size * 0.46) {
        let s = bolt.size
        let target = CGRect(x: (size - s.width) / 2, y: (size - s.height) / 2,
                            width: s.width, height: s.height)
        cg.saveGState()
        cg.setShadow(offset: CGSize(width: 0, height: -size * 0.008),
                     blur: size * 0.02,
                     color: NSColor(white: 0, alpha: 0.45).cgColor)
        bolt.draw(in: target)
        cg.restoreGState()
    } else {
        FileHandle.standardError.write("warning: bolt.fill unavailable\n".data(using: .utf8)!)
    }

    NSGraphicsContext.restoreGraphicsState()
    guard let image = cg.makeImage(),
          let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    else { fatalError("cannot encode png at \(px)px") }
    return png
}

let fm = FileManager.default
let root = fm.currentDirectoryPath
let iconset = root + "/build/AppIcon.iconset"
try? fm.removeItem(atPath: iconset)
try fm.createDirectory(atPath: iconset, withIntermediateDirectories: true)

for entry in canvas {
    try drawIcon(px: entry.px).write(to: URL(fileURLWithPath: "\(iconset)/\(entry.name).png"))
}

try fm.createDirectory(atPath: root + "/Resources", withIntermediateDirectories: true)
let out = root + "/Resources/AppIcon.icns"
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset, "-o", out]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else { exit(iconutil.terminationStatus) }

try? fm.removeItem(atPath: root + "/build")
let bytes = ((try? fm.attributesOfItem(atPath: out)[.size]) as? Int) ?? 0
print("wrote Resources/AppIcon.icns (\(bytes) bytes)")
