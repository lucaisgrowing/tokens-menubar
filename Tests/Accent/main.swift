import AppKit

var checks = 0
func expect(_ value: Bool, _ message: String) {
    precondition(value, message)
    checks += 1
}
func luminance(_ c: NSColor) -> CGFloat {
    let c = c.usingColorSpace(.sRGB)!
    func linear(_ v: CGFloat) -> CGFloat { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
    return linear(c.redComponent) * 0.2126 + linear(c.greenComponent) * 0.7152 + linear(c.blueComponent) * 0.0722
}
func contrast(_ a: NSColor, _ b: NSColor) -> CGFloat {
    let x = luminance(a), y = luminance(b)
    return (max(x, y) + 0.05) / (min(x, y) + 0.05)
}
// Deliberately choose blue. The app palette must not inherit it.
UserDefaults.standard.set(4, forKey: "AppleAccentColor")
for (name, bytes) in [(NSAppearance.Name.aqua, [46, 103, 107]), (.darkAqua, [66, 126, 130])] {
    let appearance = NSAppearance(named: name)!
    appearance.performAsCurrentDrawingAppearance {
        let fill = tokensAccent.usingColorSpace(.sRGB)!
        let ink = tokensAccentInk.usingColorSpace(.sRGB)!
        for (actual, wanted) in zip([fill.redComponent, fill.greenComponent, fill.blueComponent], bytes) {
            expect(abs(actual * 255 - CGFloat(wanted)) < 0.6, "Original green palette: \(name)")
        }
        expect(contrast(fill, .white) >= 4.5, "White text on green button: \(name)")
        let background = name == .darkAqua ? NSColor(white: 32 / 255, alpha: 1) : .white
        expect(contrast(ink, background) >= 4.5, "Small green foreground contrast: \(name)")
        print("\(name.rawValue): button contrast \(contrast(fill, .white)), ink contrast \(contrast(ink, background))")
    }
}
print("PASS: \(checks) native accent checks with blue system preference")
