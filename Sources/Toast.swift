// A small frosted-glass notice that appears under the menu-bar icon for a few
// seconds and fades out — the ambient, in-app half of a rank move. Width is
// capped and the text wraps to more lines rather than stretching into a long
// strip; no Notification Center, no permission.

import AppKit

final class Toast {
    static let shared = Toast()
    private var panel: NSPanel?
    private var hide: DispatchWorkItem?

    private let maxWidth: CGFloat = 260
    private let hPad: CGFloat = 15
    private let vPad: CGFloat = 11
    private let font = NSFont.systemFont(ofSize: 12.5, weight: .semibold)

    /// Shows a notice under `anchor` (the status-bar button), fades it in, and
    /// clears it after a few seconds. A newer toast replaces the one showing.
    func show(_ message: String, kind: PanelNotice, near anchor: NSView?) {
        let size = fittingSize(for: message)
        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.setContentSize(size)
        panel.contentView = content(message, kind: kind, size: size)
        panel.setFrameOrigin(origin(for: size, near: anchor))

        hide?.cancel()
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.16; panel.animator().alphaValue = 1 }
        let work = DispatchWorkItem { [weak self] in self?.dismiss() }
        hide = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: work)
    }

    private func dismiss() {
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.3; panel.animator().alphaValue = 0 },
                                             completionHandler: { panel.orderOut(nil) })
    }

    /// Wraps the text at the capped width and sizes the box to the result, so a
    /// long message grows downward in lines rather than sideways into a strip.
    private func fittingSize(for message: String) -> NSSize {
        let textMax = maxWidth - hPad * 2
        let bounds = (message as NSString).boundingRect(
            with: NSSize(width: textMax, height: 400),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font])
        let w = min(ceil(bounds.width), textMax) + hPad * 2
        let h = max(34, ceil(bounds.height) + vPad * 2)
        return NSSize(width: w, height: h)
    }

    private func content(_ message: String, kind: PanelNotice, size: NSSize) -> NSView {
        let tint: NSColor = kind == .failure ? .systemRed
            : kind == .success ? .systemGreen : .controlAccentColor

        // Frosted glass: the blur adapts to light/dark on its own, so the notice
        // sits over any wallpaper. Rounded by clipping the effect view's layer.
        let blur = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        blur.material = .popover
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = 12
        blur.layer?.masksToBounds = true
        blur.layer?.borderWidth = 1
        blur.layer?.borderColor = tint.withAlphaComponent(0.5).cgColor

        let isDark = blur.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let ink = isDark ? tint : (tint.blended(withFraction: 0.4, of: .black) ?? tint)

        let label = NSTextField(labelWithString: message)
        label.font = font
        label.textColor = ink
        label.alignment = .center
        label.maximumNumberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.frame = NSRect(x: hPad, y: vPad, width: size.width - hPad * 2, height: size.height - vPad * 2)
        label.autoresizingMask = [.width, .height]
        blur.addSubview(label)
        return blur
    }

    private func makePanel() -> NSPanel {
        let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: true)
        p.isFloatingPanel = true
        p.level = .statusBar
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = true
        p.ignoresMouseEvents = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        return p
    }

    /// Just below the menu bar, its right edge under the status item, clamped to
    /// the screen. The capped width keeps it from reaching far to the left.
    private func origin(for size: NSSize, near anchor: NSView?) -> NSPoint {
        let screen = (anchor?.window?.screen ?? NSScreen.main)?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        var x = screen.maxX - size.width - 8
        var y = screen.maxY - size.height - 6
        if let anchor, let win = anchor.window {
            let r = win.convertToScreen(anchor.convert(anchor.bounds, to: nil))
            x = r.maxX - size.width
            y = r.minY - size.height - 6
        }
        x = min(max(x, screen.minX + 8), screen.maxX - size.width - 8)
        y = min(y, screen.maxY - size.height - 6)
        return NSPoint(x: x, y: y)
    }
}
