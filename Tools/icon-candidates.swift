// Scratch harness for iterating on app-icon artwork. Renders every candidate at
// several sizes into one contact sheet so they can be compared side by side:
//
//     swift Tools/icon-candidates.swift && open /tmp/iconcand/sheet.png
//
// Nothing here ships. Once a candidate wins, fold its drawing code into
// Tools/make-icon.swift and delete this file.

import AppKit
import Foundation

func srgb(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

/// A recoloured SF Symbol, isolated in its own image so the tint fill cannot
/// bleed onto whatever it is later drawn over.
func symbol(_ name: String, pointSize: CGFloat, weight: NSFont.Weight = .semibold,
            colour: NSColor) -> NSImage? {
    let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
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

func roundedFont(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
    let base = NSFont.systemFont(ofSize: size, weight: weight)
    guard let d = base.fontDescriptor.withDesign(.rounded) else { return base }
    return NSFont(descriptor: d, size: size) ?? base
}

enum Layout {
    case stripBars          // menu bar strip on top, usage bars below
    case stripWordmark      // menu bar strip on top, bolt + "tokens" below
    case stripBigBolt       // menu bar strip on top, bolt filling the rest
    case stripBarsWordmark  // menu bar strip on top, usage bars over "tokens"
    case boltBars           // no strip: bolt over a row of bars
}

struct Style {
    let name: String
    let bgTop: NSColor
    let bgBottom: NSColor
    let bolt: NSColor
    let bar: NSColor
    let layout: Layout
}

let styles: [Style] = [
    Style(name: "1 graphite/amber strip+bars", bgTop: srgb(0x38414D), bgBottom: srgb(0x11151B),
          bolt: srgb(0xFFB830), bar: srgb(0xFFB830), layout: .stripBars),
    Style(name: "2 graphite/white strip+bars", bgTop: srgb(0x38414D), bgBottom: srgb(0x11151B),
          bolt: .white, bar: srgb(0x5B9DFF), layout: .stripBars),
    Style(name: "3 indigo strip+bars", bgTop: srgb(0x6366F1), bgBottom: srgb(0x3B2E8C),
          bolt: .white, bar: NSColor(white: 1, alpha: 0.92), layout: .stripBars),
    Style(name: "4 graphite strip+bigbolt", bgTop: srgb(0x38414D), bgBottom: srgb(0x11151B),
          bolt: srgb(0xFFB830), bar: srgb(0xFFB830), layout: .stripBigBolt),
    Style(name: "5 graphite strip+wordmark", bgTop: srgb(0x38414D), bgBottom: srgb(0x11151B),
          bolt: srgb(0xFFB830), bar: srgb(0xFFB830), layout: .stripWordmark),
    Style(name: "6 amber bolt over bars", bgTop: srgb(0x38414D), bgBottom: srgb(0x11151B),
          bolt: srgb(0xFFB830), bar: srgb(0xFFB830), layout: .boltBars),
    Style(name: "7 graphite strip+bars+wordmark", bgTop: srgb(0x38414D), bgBottom: srgb(0x11151B),
          bolt: srgb(0xFFB830), bar: srgb(0xFFB830), layout: .stripBarsWordmark),
]

func drawIcon(_ style: Style, px: Int) -> CGImage {
    let size = CGFloat(px)
    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
          let cg = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8,
                             bytesPerRow: 0, space: space,
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
    if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                 colors: [style.bgTop.cgColor, style.bgBottom.cgColor] as CFArray,
                                 locations: [0, 1]) {
        cg.drawLinearGradient(gradient, start: CGPoint(x: 0, y: box.maxY),
                              end: CGPoint(x: 0, y: box.minY), options: [])
    }

    // Detail below ~128px turns to mush, so small sizes are glyph-only.
    let detailed = px >= 128

    if detailed {
        switch style.layout {
        case .stripBars, .stripWordmark, .stripBigBolt, .stripBarsWordmark:
            let stripH = box.height * 0.24
            let strip = CGRect(x: box.minX, y: box.maxY - stripH, width: box.width, height: stripH)
            cg.setFillColor(NSColor(white: 1, alpha: 0.10).cgColor)
            cg.fill(strip)
            cg.setFillColor(NSColor(white: 1, alpha: 0.16).cgColor)
            cg.fill(CGRect(x: strip.minX, y: strip.minY, width: strip.width,
                           height: max(1, size * 0.004)))

            // A menu bar extra: bolt then count, sitting at the trailing edge
            // the way the real one does.
            let glyphPt = stripH * 0.60
            let textFont = roundedFont(stripH * 0.46, .semibold)
            let count = NSAttributedString(string: "1.2M", attributes: [
                .font: textFont, .foregroundColor: NSColor(white: 1, alpha: 0.95),
                .kern: stripH * 0.02,
            ])
            let countW = count.size().width
            let bolt = symbol("bolt.fill", pointSize: glyphPt, colour: style.bolt)
            let boltW = bolt?.size.width ?? 0
            let gap = stripH * 0.16
            let trailing = box.width * 0.10
            var x = strip.maxX - trailing - countW
            count.draw(at: NSPoint(x: x, y: strip.midY - count.size().height / 2))
            x -= gap + boltW
            if let bolt {
                bolt.draw(in: CGRect(x: x, y: strip.midY - bolt.size.height / 2,
                                     width: bolt.size.width, height: bolt.size.height))
            }

            let field = CGRect(x: box.minX, y: box.minY, width: box.width,
                               height: strip.minY - box.minY)
            switch style.layout {
            case .stripBars:
                drawBars(cg, in: field.insetBy(dx: box.width * 0.16, dy: field.height * 0.20),
                         colour: style.bar, size: size)
            case .stripBigBolt:
                drawBolt(cg, centre: CGPoint(x: field.midX, y: field.midY),
                         pointSize: size * 0.40, colour: style.bolt, size: size)
            case .stripWordmark:
                drawBolt(cg, centre: CGPoint(x: field.midX, y: field.minY + field.height * 0.60),
                         pointSize: size * 0.30, colour: style.bolt, size: size)
                drawWordmark(in: field, size: size)
            case .stripBarsWordmark:
                // The wordmark claims the bottom third, so the bars stand on top
                // of it instead of being centred in the whole field.
                let base = field.height * 0.36
                let barField = CGRect(x: field.minX, y: field.minY + base,
                                      width: field.width, height: field.height - base)
                drawBars(cg, in: barField.insetBy(dx: box.width * 0.16, dy: barField.height * 0.14),
                         colour: style.bar, size: size)
                drawWordmark(in: field, size: size)
            default: break
            }

        case .boltBars:
            drawBolt(cg, centre: CGPoint(x: box.midX, y: box.minY + box.height * 0.62),
                     pointSize: size * 0.42, colour: style.bolt, size: size)
            let field = CGRect(x: box.minX, y: box.minY + box.height * 0.10,
                               width: box.width, height: box.height * 0.24)
            drawBars(cg, in: field.insetBy(dx: box.width * 0.18, dy: 0),
                     colour: style.bar, size: size)
        }
    } else {
        drawBolt(cg, centre: CGPoint(x: box.midX, y: box.midY),
                 pointSize: size * 0.46, colour: style.bolt, size: size)
    }
    cg.restoreGState()

    // Hairline rim so the icon keeps an edge on dark wallpapers.
    cg.saveGState()
    cg.addPath(squircle)
    cg.setStrokeColor(NSColor(white: 1, alpha: 0.12).cgColor)
    cg.setLineWidth(max(1, size * 0.005))
    cg.strokePath()
    cg.restoreGState()

    NSGraphicsContext.restoreGraphicsState()
    guard let image = cg.makeImage() else { fatalError("cannot snapshot \(px)px") }
    return image
}

func drawBolt(_ cg: CGContext, centre: CGPoint, pointSize: CGFloat, colour: NSColor, size: CGFloat) {
    guard let bolt = symbol("bolt.fill", pointSize: pointSize, colour: colour) else { return }
    let s = bolt.size
    cg.saveGState()
    cg.setShadow(offset: CGSize(width: 0, height: -size * 0.008), blur: size * 0.02,
                 color: NSColor(white: 0, alpha: 0.45).cgColor)
    bolt.draw(in: CGRect(x: centre.x - s.width / 2, y: centre.y - s.height / 2,
                         width: s.width, height: s.height))
    cg.restoreGState()
}

/// Ascending rounded bars — the same shape language as the panel's week row.
func drawBars(_ cg: CGContext, in rect: CGRect, colour: NSColor, size: CGFloat) {
    let ratios: [CGFloat] = [0.34, 0.50, 0.70, 0.86, 1.0]
    let gap = rect.width * 0.07
    let w = (rect.width - gap * CGFloat(ratios.count - 1)) / CGFloat(ratios.count)
    for (i, r) in ratios.enumerated() {
        let h = max(w, rect.height * r)
        let bar = CGRect(x: rect.minX + (w + gap) * CGFloat(i), y: rect.minY, width: w, height: h)
        cg.setFillColor(colour.withAlphaComponent(0.45 + 0.55 * r).cgColor)
        cg.addPath(CGPath(roundedRect: bar, cornerWidth: w / 2, cornerHeight: w / 2, transform: nil))
        cg.fillPath()
    }
}

func drawWordmark(in rect: CGRect, size: CGFloat) {
    let pointSize = size * 0.115
    let text = NSAttributedString(string: "tokens", attributes: [
        .font: roundedFont(pointSize, .semibold),
        .foregroundColor: NSColor(white: 1, alpha: 0.93),
        .kern: pointSize * 0.04,
    ])
    let b = text.size()
    text.draw(at: NSPoint(x: rect.midX - b.width / 2, y: rect.minY + rect.height * 0.10))
}

// ---- contact sheet ----------------------------------------------------------

let previews = [256, 128, 64, 32]
let pad: CGFloat = 28
let labelW: CGFloat = 300
let rowH = CGFloat(previews[0]) + pad
let rowW = labelW + previews.reduce(CGFloat(0)) { $0 + CGFloat($1) + pad }
let sheetW = Int(rowW + pad)
let sheetH = Int(rowH * CGFloat(styles.count) + pad)

guard let space = CGColorSpace(name: CGColorSpace.sRGB),
      let sheet = CGContext(data: nil, width: sheetW, height: sheetH, bitsPerComponent: 8,
                            bytesPerRow: 0, space: space,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
else { fatalError("cannot create sheet context") }

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(cgContext: sheet, flipped: false)
sheet.setFillColor(NSColor(white: 0.52, alpha: 1).cgColor)
sheet.fill(CGRect(x: 0, y: 0, width: sheetW, height: sheetH))

let fm = FileManager.default
let dir = "/tmp/iconcand"
try? fm.removeItem(atPath: dir)
try fm.createDirectory(atPath: dir, withIntermediateDirectories: true)

for (row, style) in styles.enumerated() {
    let top = CGFloat(sheetH) - pad - rowH * CGFloat(row)
    let label = NSAttributedString(string: style.name, attributes: [
        .font: NSFont.systemFont(ofSize: 22, weight: .medium),
        .foregroundColor: NSColor.white,
    ])
    label.draw(at: NSPoint(x: pad, y: top - rowH / 2))

    var x = pad + labelW
    for px in previews {
        let image = drawIcon(style, px: px)
        sheet.draw(image, in: CGRect(x: x, y: top - CGFloat(px), width: CGFloat(px), height: CGFloat(px)))
        x += CGFloat(px) + pad
    }

    let big = drawIcon(style, px: 512)
    let name = style.name.prefix(1)
    if let png = NSBitmapImageRep(cgImage: big).representation(using: .png, properties: [:]) {
        try png.write(to: URL(fileURLWithPath: "\(dir)/cand\(name).png"))
    }
}

NSGraphicsContext.restoreGraphicsState()
guard let out = sheet.makeImage(),
      let png = NSBitmapImageRep(cgImage: out).representation(using: .png, properties: [:])
else { fatalError("cannot encode sheet") }
try png.write(to: URL(fileURLWithPath: "\(dir)/sheet.png"))
print("wrote \(dir)/sheet.png (\(sheetW)x\(sheetH))")
