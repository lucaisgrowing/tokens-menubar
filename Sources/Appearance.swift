import AppKit

// Match the pre-1.11 README screenshots at 38c5479. Their embedded Display P3
// profile was converted to sRGB: the solid rank bars are #2E676B / #427E82.
// Keep the app's identity independent of the user's macOS accent preference.
let tokensAccent = NSColor(name: NSColor.Name("tokensbar.accent")) { appearance in
    let dark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    return dark
        ? NSColor(srgbRed: 66 / 255, green: 126 / 255, blue: 130 / 255, alpha: 1)
        : NSColor(srgbRed: 46 / 255, green: 103 / 255, blue: 107 / 255, alpha: 1)
}

// On dark surfaces the original fill is good for white button text, but too
// subdued for small accent text. Lift only foreground ink, retaining its hue.
let tokensAccentInk = NSColor(name: NSColor.Name("tokensbar.accent.ink")) { appearance in
    var resolved: NSColor = .black
    appearance.performAsCurrentDrawingAppearance {
        let dark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        resolved = dark
            ? (tokensAccent.blended(withFraction: 0.16, of: .white) ?? tokensAccent)
            : tokensAccent
    }
    return resolved
}
