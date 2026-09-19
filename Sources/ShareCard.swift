// A shareable "flex card" — a standalone image of your standing, rendered with
// the same offscreen trick the popover snapshots use. Copied to the clipboard
// from the menu, or written to a file with `--share-png`.
//
// The card is deliberately not the panel: it is a fixed-size, solid-surface
// graphic that reads well pasted into a chat, so it uses its own layout and a
// fixed accent (not the system one) so everyone's card looks the same.

import AppKit

/// Consecutive days up to today with usage, from the contributions grid. Today
/// not yet having a submission does not break the streak — it counts from
/// yesterday in that case, so an unsubmitted morning is not a reset.
func currentStreak(_ contribs: [ContribDay]) -> Int {
    let active = Set(contribs.filter { $0.tokens > 0 }.map { dayFormatter.string(from: $0.date) })
    guard !active.isEmpty else { return 0 }
    var day = Date()
    if !active.contains(dayFormatter.string(from: day)) {
        day = day.addingTimeInterval(-86_400) // start from yesterday
    }
    var streak = 0
    while active.contains(dayFormatter.string(from: day)) {
        streak += 1
        day = day.addingTimeInterval(-86_400)
    }
    return streak
}

final class ShareCardView: NSView {
    var config = Config(username: "")
    var server: ServerStats?
    var local = LocalStats()
    var dark = true

    override var isFlipped: Bool { true } // top-down layout math

    static let size = NSSize(width: 660, height: 380)

    private let accent = NSColor(srgbRed: 0.29, green: 0.62, blue: 0.98, alpha: 1)

    override func draw(_ dirty: NSRect) {
        let bg = dark ? NSColor(srgbRed: 0.10, green: 0.10, blue: 0.11, alpha: 1)
                      : NSColor(srgbRed: 0.97, green: 0.97, blue: 0.98, alpha: 1)
        bg.setFill()
        bounds.fill()

        let primary = dark ? NSColor.white : NSColor(white: 0.10, alpha: 1)
        let secondary = (dark ? NSColor.white : NSColor.black).withAlphaComponent(0.5)
        let pad: CGFloat = 40
        let w = bounds.width

        // Header: bolt + handle on the left, wordmark on the right.
        let name = config.username.isEmpty ? "tokens" : "@" + config.username
        text("⚡ " + name, in: NSRect(x: pad, y: 30, width: w - pad * 2, height: 30),
             font: .systemFont(ofSize: 22, weight: .semibold), colour: primary)
        text("tokens.ci", in: NSRect(x: w - pad - 200, y: 36, width: 200, height: 20),
             font: .systemFont(ofSize: 13, weight: .medium), colour: secondary, align: .right)

        // Hero: the all-time rank, big, with the field size beside it.
        let all = server?.allTime
        text(L10n.current == .zh ? "总榜排名" : "ALL-TIME RANK",
             in: NSRect(x: pad, y: 96, width: 320, height: 16),
             font: .systemFont(ofSize: 12, weight: .semibold), colour: secondary)
        let rankStr = (all?.rank ?? 0) > 0 ? "#\(all!.rank)" : "#—"
        let heroFont = NSFont.monospacedDigitSystemFont(ofSize: 66, weight: .bold)
        let heroW = measure(rankStr, font: heroFont).width
        text(rankStr, in: NSRect(x: pad - 2, y: 112, width: heroW + 8, height: 78),
             font: heroFont, colour: accent)
        if let a = all, a.rank > 0 {
            text("/ \(a.totalUsers)", in: NSRect(x: pad + heroW + 8, y: 150, width: 200, height: 30),
                 font: .monospacedDigitSystemFont(ofSize: 24, weight: .medium), colour: secondary)
        }

        // Today's rank, upper right, as the second headline.
        if let td = server?.today, td.rank > 0 {
            let badge = L10n.current == .zh ? "今日 今#\(td.rank)" : "TODAY  D#\(td.rank)"
            text(badge, in: NSRect(x: w - pad - 260, y: 150, width: 260, height: 28),
                 font: .monospacedDigitSystemFont(ofSize: 22, weight: .semibold),
                 colour: primary, align: .right)
        }

        // A row of stat tiles along the bottom.
        let tiles: [(String, String)] = [
            (L10n.current == .zh ? "累计 tokens" : "LIFETIME",
             fmtTokens(server?.totalTokens ?? 0)),
            (L10n.current == .zh ? "累计花费" : "SPENT",
             fmtMoney(server?.totalCost ?? 0)),
            (L10n.current == .zh ? "连续天数" : "STREAK",
             "\(currentStreak(server?.contribs ?? []))" + (L10n.current == .zh ? " 天" : "d")),
        ]
        let gap: CGFloat = 16
        let tileW = (w - pad * 2 - gap * CGFloat(tiles.count - 1)) / CGFloat(tiles.count)
        let tileY: CGFloat = 236
        let tileH: CGFloat = 84
        let card = (dark ? NSColor.white : NSColor.black).withAlphaComponent(dark ? 0.06 : 0.04)
        for (i, tile) in tiles.enumerated() {
            let x = pad + (tileW + gap) * CGFloat(i)
            fill(NSRect(x: x, y: tileY, width: tileW, height: tileH), radius: 14, colour: card)
            text(tile.0, in: NSRect(x: x + 16, y: tileY + 16, width: tileW - 32, height: 16),
                 font: .systemFont(ofSize: 11, weight: .semibold), colour: secondary)
            text(tile.1, in: NSRect(x: x + 16, y: tileY + 38, width: tileW - 32, height: 32),
                 font: .monospacedDigitSystemFont(ofSize: 24, weight: .semibold), colour: primary)
        }

        // Footer wordmark.
        text(L10n.current == .zh ? "由 TokensBar 生成 · tokens.ci" : "via TokensBar · tokens.ci",
             in: NSRect(x: pad, y: 344, width: w - pad * 2, height: 16),
             font: .systemFont(ofSize: 11, weight: .medium), colour: secondary)
    }

    /// Renders a card offscreen to PNG data, the same hosting trick the popover
    /// snapshots use.
    static func render(config: Config, server: ServerStats?, local: LocalStats,
                       dark: Bool = true) -> Data? {
        let view = ShareCardView(frame: NSRect(origin: .zero, size: size))
        view.config = config; view.server = server; view.local = local; view.dark = dark
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
