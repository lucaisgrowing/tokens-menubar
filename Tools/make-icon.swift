// Regenerates Resources/AppIcon.icns. Run from the repo root:
//
//     swift Tools/make-icon.swift
//
// The .icns is committed, so this only needs running when the artwork changes.
// Each size is drawn from scratch rather than downscaled, so small sizes stay
// crisp.
//
// Artwork: a graphite squircle standing in for a dark menu bar. A lighter strip
// across the top carries the bolt glyph and a token count — the app's actual job
// — and ascending amber bars fill the space below. Detail drops out as the canvas
// shrinks: the count goes first, then the strip, leaving the bolt alone at 32px
// and under, which is the same glyph the menu bar itself uses (SF Symbol
// bolt.fill).

import AppKit
import Foundation

let canvas: [(name: String, px: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

let amberTop = NSColor(srgbRed: 1.00, green: 0.80, blue: 0.29, alpha: 1)
let amberBottom = NSColor(srgbRed: 0.97, green: 0.60, blue: 0.10, alpha: 1)

/// A recoloured SF Symbol, isolated in its own image so the tint fill cannot
/// bleed onto the background it will later be drawn over.
func symbol(_ name: String, pointSize: CGFloat, colour: NSColor) -> NSImage? {
    let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
    guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
        .withSymbolConfiguration(config) else { return nil }
    let out = NSImage(size: base.size)
    out.lockFocus()
    base.draw(in: CGRect(origin: .zero, size: base.size))
    colour.set()
    CGRect(origin: .zero, size: base.size).fill(using: .sourceAtop)
    out.unlockFocus()
    return out
}

func roundedFont(_ pointSize: CGFloat, weight: NSFont.Weight) -> NSFont {
    let base = NSFont.systemFont(ofSize: pointSize, weight: weight)
    guard let descriptor = base.fontDescriptor.withDesign(.rounded) else { return base }
    return NSFont(descriptor: descriptor, size: pointSize) ?? base
}

/// Vertical amber gradient clipped to a rounded rect.
func amberBar(_ cg: CGContext, _ rect: CGRect, radius: CGFloat, alpha: CGFloat) {
    let colours = [amberTop.withAlphaComponent(alpha).cgColor,
                   amberBottom.withAlphaComponent(alpha).cgColor] as CFArray
    guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                    colors: colours, locations: [0, 1]) else { return }
    cg.saveGState()
    cg.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
    cg.clip()
    cg.drawLinearGradient(gradient,
                          start: CGPoint(x: 0, y: rect.maxY),
                          end: CGPoint(x: 0, y: rect.minY),
                          options: [])
    cg.restoreGState()
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

    // Three tiers of detail. Below 64px the strip is a smear and the count is
    // noise, so those sizes fall back to the bolt on its own.
    let showsStrip = px >= 64
    let showsCount = px >= 128

    var barsTop = box.maxY
    if showsStrip {
        let stripHeight = box.height * 0.235
        let strip = CGRect(x: box.minX, y: box.maxY - stripHeight,
                           width: box.width, height: stripHeight)
        barsTop = strip.minY

        // Lift the strip out of the background rather than painting a flat
        // colour over it, so the squircle's own gradient still shows through.
        cg.setFillColor(NSColor(white: 1, alpha: 0.075).cgColor)
        cg.fill(strip)
        cg.setFillColor(NSColor(white: 1, alpha: 0.10).cgColor)
        cg.fill(CGRect(x: strip.minX, y: strip.minY,
                       width: strip.width, height: max(1, size * 0.004)))

        // Bolt and count travel as one centred group, the way they sit together
        // in the real menu bar.
        let glyphPoint = stripHeight * (showsCount ? 0.62 : 0.74)
        let bolt = symbol("bolt.fill", pointSize: glyphPoint, colour: amberTop)
        let boltSize = bolt?.size ?? .zero

        var countText: NSAttributedString?
        if showsCount {
            let pointSize = stripHeight * 0.52
            countText = NSAttributedString(string: "1.2M", attributes: [
                .font: roundedFont(pointSize, weight: .semibold),
                .foregroundColor: NSColor(white: 1, alpha: 0.95),
                .kern: pointSize * 0.01,
            ])
        }
        let textSize = countText?.size() ?? .zero
        let gap = countText == nil ? 0 : stripHeight * 0.14
        let groupWidth = boltSize.width + gap + textSize.width
        var x = strip.midX - groupWidth / 2

        if let bolt {
            bolt.draw(in: CGRect(x: x, y: strip.midY - boltSize.height / 2,
                                 width: boltSize.width, height: boltSize.height))
            x += boltSize.width + gap
        } else {
            FileHandle.standardError.write("warning: bolt.fill unavailable\n".data(using: .utf8)!)
        }
        if let countText {
            // Nudge up off the optical centre: the digits have no descenders.
            countText.draw(at: NSPoint(x: x, y: strip.midY - textSize.height / 2 + size * 0.004))
        }
    }

    if showsStrip {
        // Five ascending bars — a usage trend, and the same shape as the week
        // chart inside the panel.
        let sidePad = box.width * 0.145
        let region = CGRect(x: box.minX + sidePad,
                            y: box.minY + box.height * 0.135,
                            width: box.width - sidePad * 2,
                            height: (barsTop - box.height * 0.085) - (box.minY + box.height * 0.135))
        let heights: [CGFloat] = [0.30, 0.45, 0.61, 0.79, 1.0]
        let alphas: [CGFloat] = [0.62, 0.72, 0.83, 0.92, 1.0]
        let gapRatio: CGFloat = 0.42
        let barWidth = region.width / (CGFloat(heights.count) + gapRatio * CGFloat(heights.count - 1))
        let barRadius = min(barWidth * 0.34, barWidth / 2)

        for (i, fraction) in heights.enumerated() {
            let height = max(barWidth * 0.7, region.height * fraction)
            let rect = CGRect(x: region.minX + CGFloat(i) * (barWidth + barWidth * gapRatio),
                              y: region.minY, width: barWidth, height: height)
            amberBar(cg, rect, radius: barRadius, alpha: alphas[i])
        }
    } else {
        if let bolt = symbol("bolt.fill", pointSize: size * 0.48, colour: amberTop) {
            let s = bolt.size
            cg.saveGState()
            cg.setShadow(offset: CGSize(width: 0, height: -size * 0.01),
                         blur: size * 0.03,
                         color: NSColor(white: 0, alpha: 0.5).cgColor)
            bolt.draw(in: CGRect(x: (size - s.width) / 2, y: (size - s.height) / 2,
                                 width: s.width, height: s.height))
            cg.restoreGState()
        } else {
            FileHandle.standardError.write("warning: bolt.fill unavailable\n".data(using: .utf8)!)
        }
    }

    cg.restoreGState() // release the squircle clip

    // Hairline rim so the icon keeps an edge on dark wallpapers.
    cg.saveGState()
    cg.addPath(squircle)
    cg.setStrokeColor(NSColor(white: 1, alpha: 0.12).cgColor)
    cg.setLineWidth(max(1, size * 0.005))
    cg.strokePath()
    cg.restoreGState()

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

// docs/icon.png is what the READMEs embed; keep it in step with the .icns.
try? fm.copyItem(atPath: "\(iconset)/icon_256x256@2x.png", toPath: root + "/docs/icon.png.new")
if fm.fileExists(atPath: root + "/docs/icon.png.new") {
    _ = try? fm.replaceItemAt(URL(fileURLWithPath: root + "/docs/icon.png"),
                              withItemAt: URL(fileURLWithPath: root + "/docs/icon.png.new"))
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
print("wrote Resources/AppIcon.icns (\(bytes) bytes) and docs/icon.png")
