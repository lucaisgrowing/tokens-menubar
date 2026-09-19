// A shareable stats card, drawn to match tokens.ci's own `</> embed` card so the
// image pasted into a chat and the live card in a README look like siblings.
//
// The menu offers both: the official embed (markdown / image URL, a live SVG the
// site renders and keeps current) for a README, and this locally-drawn PNG for
// pasting straight into a chat. This file draws the PNG; the embed links are
// plain strings built in the controller.
//
// Layout and palette follow the site's 2-D embed (a 680×186 strip: handle and
// "updated" line up top, a row of Tokens / Cost / Rank / Active-days below),
// rendered at 2× for a crisp image. Rendered offscreen, the popover's trick.

import AppKit

enum Embed {
    static let base = "https://tokens.ci"

    /// The live-card image URL, with the view and theme the site's dialog sets.
    static func imageURL(user: String, dark: Bool, view3D: Bool = false) -> String {
        let u = user.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? user
        return "\(base)/api/embed/\(u)/svg?view=\(view3D ? "3d" : "2d")&theme=\(dark ? "dark" : "light")"
    }

    static func profileURL(user: String) -> String {
        let u = user.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? user
        return "\(base)/u/\(u)"
    }

    /// The README snippet the site's dialog copies: the image linked to the profile.
    static func markdown(user: String, dark: Bool, view3D: Bool = false) -> String {
        "[![Tokens Stats](\(imageURL(user: user, dark: dark, view3D: view3D)))](\(profileURL(user: user)))"
    }
}

final class ShareCardView: NSView {
    var config = Config(username: "")
    var server: ServerStats?
    var dark = true

    override var isFlipped: Bool { true }

    private static let scale: CGFloat = 2
    static let size = NSSize(width: 680 * scale, height: 186 * scale)

    override func draw(_ dirty: NSRect) {
        let s = Self.scale
        // Palette lifted from the site's embed so the two cards match.
        let bg = dark ? hex("141414") : hex("FFFFFF")
        let primary = dark ? hex("F4F7FB") : hex("18181B")
        let secondary = hex("A1A1AA")
        let accent = hex("2F8FFF")
        let rule = (dark ? NSColor.white : NSColor.black).withAlphaComponent(0.10)

        bg.setFill()
        bounds.fill()
        if !dark { stroke(bounds.insetBy(dx: 0.5, dy: 0.5), radius: 0, colour: rule) }

        let pad: CGFloat = 28 * s
        let w = bounds.width
        let user = config.username.isEmpty ? "tokens" : "@" + config.username

        // Header: handle left, profile path right.
        text(user, in: NSRect(x: pad, y: 22 * s, width: w * 0.6, height: 26 * s),
             font: .systemFont(ofSize: 20 * s, weight: .bold), colour: primary)
        text("tokens.ci/u/\(config.username)",
             in: NSRect(x: w * 0.4 - pad, y: 26 * s, width: w * 0.6, height: 18 * s),
             font: .systemFont(ofSize: 12 * s, weight: .medium), colour: secondary, align: .right)

        // Sub-line: when it was last refreshed and the span the numbers cover.
        text("Updated \(utcStamp(server?.updatedAt ?? Date())) (UTC)",
             in: NSRect(x: pad, y: 50 * s, width: w * 0.6, height: 16 * s),
             font: .systemFont(ofSize: 11 * s, weight: .regular), colour: secondary)
        if let a = server?.contribStart, let b = server?.contribEnd {
            text("\(dayStamp(a)) → \(dayStamp(b))",
                 in: NSRect(x: w * 0.4 - pad, y: 50 * s, width: w * 0.6, height: 16 * s),
                 font: .systemFont(ofSize: 11 * s, weight: .regular), colour: secondary, align: .right)
        }

        fill(NSRect(x: pad, y: 82 * s, width: w - pad * 2, height: 1), radius: 0, colour: rule)

        // Stat row: label above, value below, tokens in the accent like the site.
        let stats: [(String, String, NSColor)] = [
            ("Tokens", fmtExact(server?.totalTokens ?? 0), accent),
            ("Cost", fmtMoney(server?.totalCost ?? 0), primary),
            ("Rank", (server?.allTime?.rank ?? 0) > 0 ? "#\(server!.allTime!.rank)" : "#—", primary),
            ("Active days", "\(server?.activeDays ?? 0)", primary),
        ]
        let colW = (w - pad * 2) / CGFloat(stats.count)
        for (i, stat) in stats.enumerated() {
            let x = pad + colW * CGFloat(i)
            text(stat.0, in: NSRect(x: x, y: 110 * s, width: colW - 12 * s, height: 16 * s),
                 font: .systemFont(ofSize: 11 * s, weight: .semibold), colour: secondary)
            text(stat.1, in: NSRect(x: x, y: 130 * s, width: colW - 12 * s, height: 30 * s),
                 font: .monospacedDigitSystemFont(ofSize: 22 * s, weight: .semibold), colour: stat.2)
        }

        // Footer wordmark.
        text("⚡ via TokensBar",
             in: NSRect(x: pad, y: 164 * s, width: w - pad * 2, height: 14 * s),
             font: .systemFont(ofSize: 10 * s, weight: .medium), colour: secondary, align: .right)
    }

    private func hex(_ h: String) -> NSColor {
        var v: UInt64 = 0; Scanner(string: h).scanHexInt64(&v)
        return NSColor(srgbRed: CGFloat((v >> 16) & 0xff) / 255,
                       green: CGFloat((v >> 8) & 0xff) / 255,
                       blue: CGFloat(v & 0xff) / 255, alpha: 1)
    }

    private func utcStamp(_ d: Date) -> String { Self.stamp(d, "MMM d, yyyy") }
    private func dayStamp(_ d: Date) -> String { Self.stamp(d, "MMM d, yyyy") }
    private static func stamp(_ d: Date, _ fmt: String) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = fmt
        return f.string(from: d)
    }

    /// Renders a card offscreen to PNG data — the popover's hosting trick.
    static func render(config: Config, server: ServerStats?, dark: Bool = true) -> Data? {
        let view = ShareCardView(frame: NSRect(origin: .zero, size: size))
        view.config = config; view.server = server; view.dark = dark
        let host = NSWindow(contentRect: view.frame, styleMask: [.borderless],
                            backing: .buffered, defer: false)
        host.isReleasedWhenClosed = false
        host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        host.contentView = view
        view.layoutSubtreeIfNeeded()
        view.display()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep.representation(using: .png, properties: [:])
    }
}
