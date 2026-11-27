// Regenerates Resources/AppIcon.icns and docs/icon.png. Run from the repo root:
//
//     swift Tools/make-icon.swift
//
// Each size is drawn from scratch in sRGB CoreGraphics so small sizes stay razor
// sharp. Zero text inside the icon: a deep obsidian-teal macOS squircle housing
// luminous ascending emerald-teal telemetry bars and a sculpted lightning emblem,
// harmonizing directly with TokensBar's teal/emerald UI identity.

import AppKit
import Foundation

let canvas: [(name: String, px: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

func srgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    NSColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a).cgColor
}

/// Precision lightning bolt path centered in `rect`, with fuller optical weight
/// and subtly rounded vertices so it reads as a sculpted macOS glyph rather than
/// sharp needles.
func boltPath(in rect: CGRect) -> CGPath {
    func pt(_ nx: CGFloat, _ ny: CGFloat) -> CGPoint {
        CGPoint(x: rect.minX + rect.width * nx, y: rect.minY + rect.height * ny)
    }
    let pts = [
        pt(0.60, 0.99),
        pt(0.11, 0.43),
        pt(0.46, 0.43),
        pt(0.38, 0.01),
        pt(0.89, 0.57),
        pt(0.54, 0.57),
    ]
    let cornerR = min(rect.width, rect.height) * 0.065
    let p = CGMutablePath()
    let n = pts.count
    let startMid = CGPoint(x: (pts[n - 1].x + pts[0].x) / 2, y: (pts[n - 1].y + pts[0].y) / 2)
    p.move(to: startMid)
    for i in 0..<n {
        let curr = pts[i]
        let next = pts[(i + 1) % n]
        p.addArc(tangent1End: curr, tangent2End: next, radius: cornerR)
    }
    p.closeSubpath()
    return p
}

func drawRoundedGradientBar(_ cg: CGContext, rect: CGRect, radius: CGFloat,
                            topColor: CGColor, bottomColor: CGColor,
                            glowColor: CGColor?, specularAlpha: CGFloat) {
    let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

    if let glowColor {
        cg.saveGState()
        cg.setShadow(offset: CGSize(width: 0, height: -rect.width * 0.08),
                     blur: rect.width * 0.45, color: glowColor)
        cg.addPath(path)
        cg.setFillColor(bottomColor)
        cg.fillPath()
        cg.restoreGState()
    }

    cg.saveGState()
    cg.addPath(path)
    cg.clip()
    if let grad = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                             colors: [topColor, bottomColor] as CFArray,
                             locations: [0, 1]) {
        cg.drawLinearGradient(grad,
                              start: CGPoint(x: rect.midX, y: rect.maxY),
                              end: CGPoint(x: rect.midX, y: rect.minY),
                              options: [])
    }

    // Subtle glass top-edge highlight on each bar
    if specularAlpha > 0 {
        let shine = CGRect(x: rect.minX, y: rect.maxY - max(1.5, rect.height * 0.12),
                           width: rect.width, height: max(1.5, rect.height * 0.12))
        if let topGrad = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                                    colors: [srgb(255, 255, 255, specularAlpha),
                                             srgb(255, 255, 255, 0)] as CFArray,
                                    locations: [0, 1]) {
            cg.drawLinearGradient(topGrad,
                                  start: CGPoint(x: shine.midX, y: shine.maxY),
                                  end: CGPoint(x: shine.midX, y: shine.minY),
                                  options: [])
        }
    }
    cg.restoreGState()

    // Crisp rim stroke on the bar
    cg.saveGState()
    cg.addPath(path)
    cg.setStrokeColor(srgb(210, 255, 245, 0.22))
    cg.setLineWidth(max(0.75, rect.width * 0.025))
    cg.strokePath()
    cg.restoreGState()
}

func drawIcon(px: Int) -> Data {
    let size = CGFloat(px)
    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
          let cg = CGContext(data: nil, width: px, height: px,
                             bitsPerComponent: 8, bytesPerRow: 0, space: space,
                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { fatalError("cannot create context at \(px)px") }

    cg.setAllowsAntialiasing(true)
    cg.setShouldAntialias(true)

    // macOS Big Sur / Sonoma / Sequoia standard icon canvas: 824/1024 box, 185.4/1024 radius.
    let inset = size * (100.0 / 1024.0)
    let box = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let radius = size * (185.4 / 1024.0)
    let squircle = CGPath(roundedRect: box, cornerWidth: radius, cornerHeight: radius, transform: nil)

    // Soft macOS dock drop shadow outside the squircle
    if px >= 64 {
        cg.saveGState()
        cg.setShadow(offset: CGSize(width: 0, height: -size * 0.018),
                     blur: size * 0.036,
                     color: srgb(0, 0, 0, 0.36))
        cg.addPath(squircle)
        cg.setFillColor(srgb(12, 26, 30, 1))
        cg.fillPath()
        cg.restoreGState()
    }

    // Clip to squircle interior
    cg.saveGState()
    cg.addPath(squircle)
    cg.clip()

    // 1. Deep obsidian-teal base gradient
    if let bgGrad = CGGradient(colorsSpace: space,
                               colors: [srgb(24, 52, 58), srgb(13, 30, 35), srgb(7, 17, 20)] as CFArray,
                               locations: [0.0, 0.52, 1.0]) {
        cg.drawLinearGradient(bgGrad,
                              start: CGPoint(x: box.midX, y: box.maxY),
                              end: CGPoint(x: box.midX, y: box.minY),
                              options: [])
    }

    // 2. Ambient emerald/teal radial glow behind the telemetry bars
    if let glow = CGGradient(colorsSpace: space,
                             colors: [srgb(52, 208, 172, 0.32),
                                      srgb(36, 134, 132, 0.12),
                                      srgb(10, 26, 30, 0.0)] as CFArray,
                             locations: [0.0, 0.45, 1.0]) {
        cg.drawRadialGradient(glow,
                              startCenter: CGPoint(x: box.midX + box.width * 0.08, y: box.midY + box.height * 0.04),
                              startRadius: 0,
                              endCenter: CGPoint(x: box.midX, y: box.midY),
                              endRadius: box.width * 0.62,
                              options: [.drawsAfterEndLocation])
    }

    // 3. Subtle top glass specular arc (gives authentic macOS tactile depth)
    if let sheen = CGGradient(colorsSpace: space,
                              colors: [srgb(190, 250, 240, 0.14),
                                       srgb(190, 250, 240, 0.03),
                                       srgb(190, 250, 240, 0.0)] as CFArray,
                              locations: [0.0, 0.45, 1.0]) {
        cg.drawLinearGradient(sheen,
                              start: CGPoint(x: box.midX, y: box.maxY),
                              end: CGPoint(x: box.midX, y: box.maxY - box.height * 0.42),
                              options: [])
    }

    // 4. Subtle recessed glass telemetry tray (for >= 64px)
    if px >= 64 {
        let trayInset = box.width * 0.115
        let tray = CGRect(x: box.minX + trayInset,
                          y: box.minY + box.height * 0.135,
                          width: box.width - trayInset * 2,
                          height: box.height * 0.73)
        let trayR = box.width * 0.155
        let trayPath = CGPath(roundedRect: tray, cornerWidth: trayR, cornerHeight: trayR, transform: nil)
        cg.saveGState()
        cg.addPath(trayPath)
        cg.setFillColor(srgb(255, 255, 255, 0.035))
        cg.fillPath()
        cg.addPath(trayPath)
        cg.setStrokeColor(srgb(160, 245, 232, 0.10))
        cg.setLineWidth(max(1, size * 0.003))
        cg.strokePath()
        cg.restoreGState()

        // Delicate horizontal micro-grid lines inside tray
        if px >= 128 {
            cg.saveGState()
            cg.setStrokeColor(srgb(170, 240, 230, 0.06))
            cg.setLineWidth(max(1, size * 0.0025))
            for frac in [0.28, 0.50, 0.72] as [CGFloat] {
                let y = tray.minY + tray.height * frac
                cg.move(to: CGPoint(x: tray.minX + tray.width * 0.08, y: y))
                cg.addLine(to: CGPoint(x: tray.maxX - tray.width * 0.08, y: y))
            }
            cg.strokePath()
            cg.restoreGState()
        }
    }

    // 5. Telemetry Bars (5 bars at >= 64px, simplified bold 3 bars + bolt at <= 32px)
    let small = px <= 32
    if !small {
        let barAreaX = box.minX + box.width * 0.195
        let barAreaW = box.width * 0.61
        let barBottom = box.minY + box.height * 0.215
        let maxBarH = box.height * 0.45

        let heights: [CGFloat] = [0.28, 0.44, 0.60, 0.78, 1.00]
        let gapRatio: CGFloat = 0.36
        let count = CGFloat(heights.count)
        let barW = barAreaW / (count + gapRatio * (count - 1))
        let barR = barW * 0.38

        // Colour ramp from deep ocean teal → vibrant emerald-mint (echoing the app's heatmap & accent)
        let palettes: [(top: CGColor, bot: CGColor, glow: CGColor?)] = [
            (srgb(52, 134, 138, 0.85), srgb(32, 86, 92, 0.82), nil),
            (srgb(58, 158, 154, 0.90), srgb(36, 102, 106, 0.88), nil),
            (srgb(66, 184, 166, 0.95), srgb(40, 122, 120, 0.92), nil),
            (srgb(82, 214, 178, 0.98), srgb(44, 146, 132, 0.96), srgb(64, 214, 174, 0.22)),
            (srgb(138, 250, 210, 1.00), srgb(48, 182, 152, 1.00), srgb(100, 245, 200, 0.40)),
        ]

        for (i, hFrac) in heights.enumerated() {
            let h = max(barW * 0.9, maxBarH * hFrac)
            let x = barAreaX + CGFloat(i) * (barW * (1 + gapRatio))
            let rect = CGRect(x: x, y: barBottom, width: barW, height: h)
            drawRoundedGradientBar(cg, rect: rect, radius: barR,
                                   topColor: palettes[i].top,
                                   bottomColor: palettes[i].bot,
                                   glowColor: palettes[i].glow,
                                   specularAlpha: i == 4 ? 0.38 : 0.18)
        }

        // 6. Sculpted luminous lightning bolt hovering cleanly in upper-left optical balance
        let boltW = box.width * 0.255
        let boltH = box.height * 0.34
        let boltRect = CGRect(x: box.minX + box.width * 0.205,
                              y: box.maxY - box.height * 0.165 - boltH,
                              width: boltW, height: boltH)
        let bolt = boltPath(in: boltRect)

        // Warm-ivory / soft-mint luminous glow + crisp metallic fill
        cg.saveGState()
        cg.setShadow(offset: CGSize(width: 0, height: -size * 0.012),
                     blur: size * 0.045,
                     color: srgb(115, 255, 215, 0.55))
        cg.addPath(bolt)
        cg.setFillColor(srgb(245, 255, 250, 1))
        cg.fillPath()
        cg.restoreGState()

        cg.saveGState()
        cg.addPath(bolt)
        cg.clip()
        if let boltGrad = CGGradient(colorsSpace: space,
                                     colors: [srgb(255, 255, 255),
                                              srgb(218, 255, 244),
                                              srgb(138, 240, 210)] as CFArray,
                                     locations: [0.0, 0.55, 1.0]) {
            cg.drawLinearGradient(boltGrad,
                                  start: CGPoint(x: boltRect.midX, y: boltRect.maxY),
                                  end: CGPoint(x: boltRect.midX, y: boltRect.minY),
                                  options: [])
        }
        cg.restoreGState()
    } else {
        // Ultra-crisp small-size glyph (16px / 32px): bold luminous bolt centered
        let boltW = box.width * 0.54
        let boltH = box.height * 0.68
        let boltRect = CGRect(x: box.midX - boltW / 2, y: box.midY - boltH / 2,
                              width: boltW, height: boltH)
        let bolt = boltPath(in: boltRect)
        cg.saveGState()
        cg.addPath(bolt)
        cg.clip()
        if let boltGrad = CGGradient(colorsSpace: space,
                                     colors: [srgb(248, 255, 252),
                                              srgb(122, 242, 206)] as CFArray,
                                     locations: [0, 1]) {
            cg.drawLinearGradient(boltGrad,
                                  start: CGPoint(x: boltRect.midX, y: boltRect.maxY),
                                  end: CGPoint(x: boltRect.midX, y: boltRect.minY),
                                  options: [])
        }
        cg.restoreGState()
    }

    cg.restoreGState() // release squircle clip

    // 7. Outer precision bevel rim (brighter at top, softer at bottom)
    cg.saveGState()
    cg.addPath(squircle)
    cg.setLineWidth(max(1, size * 0.006))
    cg.setStrokeColor(srgb(175, 245, 232, 0.22))
    cg.strokePath()
    cg.restoreGState()

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
