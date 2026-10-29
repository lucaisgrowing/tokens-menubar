import AppKit

// Shared native drawing keeps the established ink-green palette independent of
// macOS's accent setting. NSButton retains keyboard, target/action and AX behaviour.
final class UsageSurface: NSView {
    var accented = false
    override func draw(_ dirtyRect: NSRect) {
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let background = accented ? tokensAccent.withAlphaComponent(dark ? 0.14 : 0.055) : NSColor.controlBackgroundColor
        background.setFill()
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 10, yRadius: 10)
        path.fill()
        (accented ? tokensAccent.withAlphaComponent(0.24) : NSColor.separatorColor.withAlphaComponent(0.22)).setStroke()
        path.lineWidth = 1; path.stroke()
    }
}

final class UsageButton: NSButton {
    var primary = false
    var navigation = false
    override func draw(_ dirtyRect: NSRect) {
        let selected = navigation && state == .on
        let filled = primary || selected
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 7, yRadius: 7)
        let fill = filled ? tokensAccent : NSColor.quaternaryLabelColor.withAlphaComponent(isHighlighted ? 0.22 : 0.09)
        (isEnabled ? fill : fill.withAlphaComponent(0.04)).setFill(); path.fill()
        if isHighlighted { NSColor.labelColor.withAlphaComponent(0.08).setFill(); path.fill() }
        let ink: NSColor = isEnabled ? (filled ? .white : (navigation ? .secondaryLabelColor : tokensAccentInk)) : .disabledControlTextColor
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
        let box = NSRect(x: 0, y: (bounds.height - 16) / 2, width: 16, height: 16)
        let path = NSBezierPath(roundedRect: box.insetBy(dx: 0.5, dy: 0.5), xRadius: 4, yRadius: 4)
        (state == .on ? tokensAccent : NSColor.controlBackgroundColor).setFill(); path.fill()
        (state == .on ? tokensAccent : NSColor.separatorColor).setStroke(); path.lineWidth = 1; path.stroke()
        if state == .on {
            NSColor.white.setStroke(); let tick = NSBezierPath(); tick.lineWidth = 1.7; tick.lineCapStyle = .round; tick.lineJoinStyle = .round
            tick.move(to: NSPoint(x: box.minX + 4, y: box.midY)); tick.line(to: NSPoint(x: box.minX + 7, y: box.minY + 4)); tick.line(to: NSPoint(x: box.minX + 12, y: box.minY + 11)); tick.stroke()
        }
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12, weight: .medium), .foregroundColor: NSColor.labelColor]
        let size = (title as NSString).size(withAttributes: attributes)
        (title as NSString).draw(at: NSPoint(x: 25, y: (bounds.height - size.height) / 2), withAttributes: attributes)
        if window?.firstResponder === self { NSColor.keyboardFocusIndicatorColor.setStroke(); path.lineWidth = 2; path.stroke() }
    }
}
