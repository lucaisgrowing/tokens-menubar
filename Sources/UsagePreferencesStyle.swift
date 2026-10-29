import AppKit

// Opaque, appearance-resolved colours avoid translucent/white patches in native
// offscreen exports as well as inheriting the user's system-blue accent.
// NSButton retains keyboard, target/action and accessibility behaviour.
private func usageDark(_ view: NSView) -> Bool { view.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua }
private func usageRGB(_ hex: Int) -> NSColor { NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: 1) }
func usageGreen(_ dark: Bool) -> NSColor { usageRGB(dark ? 0x38654E : 0x285744) }
func usageInk(_ dark: Bool) -> NSColor { usageRGB(dark ? 0xA0CCAF : 0x285744) }

final class UsageCanvas: NSView {
    override func draw(_ dirtyRect: NSRect) { usageRGB(usageDark(self) ? 0x202321 : 0xF4F6F3).setFill(); dirtyRect.fill() }
}

final class UsageSurface: NSView {
    var accented = false
    override func draw(_ dirtyRect: NSRect) {
        let dark = usageDark(self)
        let background = usageRGB(accented ? (dark ? 0x293A30 : 0xEAF1EB) : (dark ? 0x292E2B : 0xFFFFFF))
        background.setFill()
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 10, yRadius: 10)
        path.fill()
        usageRGB(dark ? 0x414C45 : 0xD6E0D7).setStroke()
        path.lineWidth = 1; path.stroke()
    }
}

final class UsageButton: NSButton {
    var primary = false
    var navigation = false
    override var intrinsicContentSize: NSSize {
        let text = (title as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 12, weight: .semibold)])
        return NSSize(width: max(34, text.width + 24), height: 29)
    }
    override func draw(_ dirtyRect: NSRect) {
        let dark = usageDark(self)
        let selected = navigation && state == .on
        let filled = primary || selected
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 7, yRadius: 7)
        let fill = filled ? usageGreen(dark) : usageRGB(dark ? 0x343F38 : 0xE6ECE6)
        (isEnabled ? fill : usageRGB(dark ? 0x2D332F : 0xEDF0EC)).setFill(); path.fill()
        if isHighlighted { NSColor.black.withAlphaComponent(0.1).setFill(); path.fill() }
        let ink: NSColor = isEnabled ? (filled ? .white : (navigation ? usageRGB(dark ? 0xCCD6CF : 0x526359) : usageInk(dark))) : usageRGB(dark ? 0x69776D : 0x89978D)
        let font = NSFont.systemFont(ofSize: 12, weight: filled ? .semibold : .medium)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: ink]
        let size = (title as NSString).size(withAttributes: attributes)
        (title as NSString).draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2), withAttributes: attributes)
        if window?.firstResponder === self {
            NSColor.keyboardFocusIndicatorColor.setStroke()
            let ring = NSBezierPath(roundedRect: bounds.insetBy(dx: 1.5, dy: 1.5), xRadius: 7, yRadius: 7); ring.lineWidth = 2; ring.stroke()
        }
    }
}

final class UsageCheck: NSButton {
    override func draw(_ dirtyRect: NSRect) {
        let dark = usageDark(self)
        let box = NSRect(x: 0, y: (bounds.height - 16) / 2, width: 16, height: 16)
        let path = NSBezierPath(roundedRect: box.insetBy(dx: 0.5, dy: 0.5), xRadius: 4, yRadius: 4)
        (state == .on ? usageGreen(dark) : usageRGB(dark ? 0x343F38 : 0xFFFFFF)).setFill(); path.fill()
        (state == .on ? usageGreen(dark) : usageRGB(dark ? 0x7D8C82 : 0x84998A)).setStroke(); path.lineWidth = 1; path.stroke()
        if state == .on {
            NSColor.white.setStroke(); let tick = NSBezierPath(); tick.lineWidth = 1.7; tick.lineCapStyle = .round; tick.lineJoinStyle = .round
            tick.move(to: NSPoint(x: box.minX + 4, y: box.midY)); tick.line(to: NSPoint(x: box.minX + 7, y: box.minY + 11)); tick.line(to: NSPoint(x: box.minX + 12, y: box.minY + 4)); tick.stroke()
        }
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12, weight: .medium), .foregroundColor: usageRGB(dark ? 0xF0F3EF : 0x1E2922)]
        let size = (title as NSString).size(withAttributes: attributes)
        (title as NSString).draw(at: NSPoint(x: 25, y: (bounds.height - size.height) / 2), withAttributes: attributes)
        if window?.firstResponder === self { NSColor.keyboardFocusIndicatorColor.setStroke(); path.lineWidth = 2; path.stroke() }
    }
}
