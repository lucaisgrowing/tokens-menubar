// A small floating notice that drops under the menu-bar icon for a few seconds
// and fades out — the ambient, in-app half of a rank move. No system permission,
// no Notification Center: it shows whether or not the panel is open, then leaves.

import AppKit

private final class ToastView: NSView {
    let message: String
    let kind: PanelNotice

    init(_ message: String, _ kind: PanelNotice) {
        self.message = message
        self.kind = kind
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { nil }

    private let font = NSFont.systemFont(ofSize: 12.5, weight: .semibold)
    static let height: CGFloat = 34
    static let hPad: CGFloat = 16

    func fittingWidth() -> CGFloat {
        measure(message, font: font).width + Self.hPad * 2
    }

    override func draw(_ dirty: NSRect) {
        let tint: NSColor = kind == .failure ? .systemRed
            : kind == .success ? .systemGreen : .controlAccentColor
        let isDark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let ink = isDark ? tint : (tint.blended(withFraction: 0.4, of: .black) ?? tint)
        // A near-opaque capsule so the notice reads over any wallpaper.
        let base = isDark ? NSColor(white: 0.16, alpha: 0.98)
                          : NSColor(white: 0.99, alpha: 0.98)
        let radius = bounds.height / 2
        fill(bounds, radius: radius, colour: base)
        stroke(bounds, radius: radius, colour: ink.withAlphaComponent(0.55), width: 1)
        text(message,
             in: NSRect(x: Self.hPad, y: bounds.midY - 8, width: bounds.width - Self.hPad * 2, height: 16),
             font: font, colour: ink, align: .center)
    }
}

final class Toast {
    static let shared = Toast()
    private var panel: NSPanel?
    private var hide: DispatchWorkItem?

    /// Drops a notice under `anchor` (the status-bar button), fades it in, and
    /// clears it after a few seconds. A newer toast replaces the one showing.
    func show(_ message: String, kind: PanelNotice, near anchor: NSView?) {
        let view = ToastView(message, kind)
        let width = min(max(view.fittingWidth(), 120), 460)
        let size = NSSize(width: width, height: ToastView.height)

        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.setContentSize(size)
        view.frame = NSRect(origin: .zero, size: size)
        panel.contentView = view

        panel.setFrameOrigin(origin(for: size, near: anchor))
        hide?.cancel()
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.16
            panel.animator().alphaValue = 1
        }
        let work = DispatchWorkItem { [weak self] in self?.dismiss() }
        hide = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: work)
    }

    private func dismiss() {
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.3
            panel.animator().alphaValue = 0
        }, completionHandler: { panel.orderOut(nil) })
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
    /// the screen so a narrow item near the corner does not push it off-screen.
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
