// The dropdown itself: a drawn panel rather than a text menu. Left-clicking the
// status item opens this; right-clicking (or the gear button) opens the plain
// NSMenu, which keeps the keyboard shortcuts and an accessible text fallback.
//
// Everything is drawn in one view with a layout pass shared by drawing and
// hit-testing, so `--panel-png` renders exactly what the popover shows.

import AppKit

enum PanelAction: Equatable {
    case profile
    /// Turns to the actions page. The menu used to pop over the panel as an
    /// NSMenu, which read as leaving the panel behind; it is a page now.
    case menuPage
    case back
    case history
    case chart(ChartScope)
    case submit
    case refresh
    case setRank(RankMode)
    case setLanguage(Lang)
    case toggleLogin
    case updates
    case support
    /// Pops the plain NSMenu, which still carries every number as text.
    case textMenu
    case quit
}

extension PanelAction: CustomStringConvertible {
    var description: String {
        switch self {
        case .profile: return "profile"
        case .menuPage: return "menu"
        case .back: return "back"
        case .history: return "contributions"
        case .chart(let scope): return scope == .today ? "chart(today)" : "chart(lifetime)"
        case .submit: return "submit"
        case .refresh: return "refresh"
        case .setRank(let mode): return "rank(\(mode.rawValue))"
        case .setLanguage(let lang): return "language(\(lang.rawValue))"
        case .toggleLogin: return "launch-at-login"
        case .updates: return "updates"
        case .support: return "support"
        case .textMenu: return "text-menu"
        case .quit: return "quit"
        }
    }
}

/// How a transient notice reads. A submit outcome gets a banner of its own;
/// anything else stays on the timestamp line where it always was.
enum PanelNotice: Equatable { case info, success, failure }

/// Everything the panel draws, derived once per render so the view holds no
/// opinions about where the numbers come from.
struct PanelData {
    var username = ""
    /// Today, as shown: the server's all-device figure when there is one.
    var todayTokens = 0
    var todayCost = 0.0
    var todayIsServer = false
    var localTokens = 0
    var localCost = 0.0
    var localFailed = false
    var lifetimeTokens = 0
    var lifetimeCost = 0.0
    var weekTokens = 0
    var weekCost = 0.0
    /// The board the menu bar shows, and the other one.
    var primaryMode: RankMode = .today
    var primary: BoardStanding?
    var secondary: BoardStanding?
    /// Trailing seven days, oldest first, gaps filled with zeroes.
    var recent: [ContribDay] = []
    /// Mean daily tokens over the seven days before today.
    var avgTokens = 0.0
    var bestTokens = 0
    /// Today's per-model split, already folded to the chart's slices.
    var models: [ChartDatum] = []
    var localStamp: Date?
    var serverStamp: Date?
    var serverFailed = false
    var isStale = false
    var busy = false
    var transient: String?
    /// How `transient` reads. A submit outcome gets the banner; a background
    /// notice like an update check stays on the timestamp line.
    var noticeKind: PanelNotice = .info
    /// State the actions page shows: everything else is derived from the numbers.
    var loginEnabled = false
    var updateTitle = ""
    var updateWaiting = false
    var canSubmit = true
}

extension PanelData {
    /// Built from the same inputs the menu's `Presenter` reads, so the drawn
    /// panel and the text menu can never disagree about a number.
    init(config: Config, rankMode: RankMode, server: ServerStats?, local: LocalStats,
         serverFailed: Bool, busy: Bool, transient: String?) {
        self.init()
        username = config.username
        primaryMode = rankMode
        primary = server?.standing(rankMode)
        secondary = server?.standing(rankMode == .today ? .allTime : .today)
        // Today prefers the server's all-device figure, exactly as the menu does.
        if let d = server?.todayDay {
            todayTokens = d.tokens
            todayCost = d.cost
            todayIsServer = true
        } else {
            todayTokens = local.todayTokens
            todayCost = local.todayCost
        }
        localTokens = local.todayTokens
        localCost = local.todayCost
        localFailed = local.failed
        lifetimeTokens = server?.totalTokens ?? 0
        lifetimeCost = server?.totalCost ?? 0
        weekTokens = local.weekTokens
        weekCost = local.weekCost

        let all = server?.contribs ?? []
        recent = PanelData.trailing(all, days: 7)
        // The baseline today is compared against: the seven days before it.
        let before = PanelData.trailing(all, days: 8).dropLast()
        avgTokens = before.isEmpty ? 0
            : Double(before.reduce(0) { $0 + $1.tokens }) / Double(before.count)
        bestTokens = all.map(\.tokens).max() ?? 0
        models = todayChartModels(local, server).map {
            ChartDatum(label: $0.model, tokens: $0.tokens, cost: $0.cost)
        }

        localStamp = local.updatedAt
        serverStamp = server?.updatedAt
        self.serverFailed = serverFailed
        isStale = server?.isStale ?? false
        self.busy = busy
        self.transient = transient
    }

    /// The last `days` GMT days ending today, oldest first. Missing days are
    /// filled with zeroes so the bar chart keeps a fixed pitch.
    private static func trailing(_ contribs: [ContribDay], days: Int) -> [ContribDay] {
        let byDay = Dictionary(contribs.map { (dayFormatter.string(from: $0.date), $0) },
                               uniquingKeysWith: { a, _ in a })
        let today = gridCalendar.startOfDay(for: Date())
        return (0..<days).reversed().compactMap { back in
            guard let date = gridCalendar.date(byAdding: .day, value: -back, to: today)
            else { return nil }
            return byDay[dayFormatter.string(from: date)]
                ?? ContribDay(date: date, tokens: 0, cost: 0, messages: 0,
                              level: 0, clients: [], models: [])
        }
    }
}

/// Every rectangle the panel draws, computed once per render. Drawing and
/// hit-testing read the same struct, so a click always lands on what is on
/// screen.
private struct PanelLayout {
    var height: CGFloat = 0
    var title = NSRect.zero
    var history = NSRect.zero
    var gear = NSRect.zero
    var hero = NSRect.zero
    var heroValue = NSRect.zero
    var heroCost = NSRect.zero
    var heroSub = NSRect.zero
    var heroLocal = NSRect.zero
    var boardCaption = NSRect.zero
    var boardRank = NSRect.zero
    var boardTrack = NSRect.zero
    var boardLabel = NSRect.zero
    var boardPct = NSRect.zero
    var avgCaption = NSRect.zero
    var avgValue = NSRect.zero
    var avgTrack = NSRect.zero
    var avgSub = NSRect.zero
    /// Left card is the other board, right card is this week.
    var cards: [NSRect] = []
    var weekCaption = NSRect.zero
    var weekValue = NSRect.zero
    /// Full-height columns, so hovering anywhere over a day picks it up.
    var barColumns: [NSRect] = []
    /// The card the bars sit in. It is also the click target, so the highlight
    /// never reaches up into the caption above it.
    var weekCard = NSRect.zero
    var barArea = NSRect.zero
    var barLabels = NSRect.zero
    var modelCaption = NSRect.zero
    var modelValue = NSRect.zero
    var modelRows: [NSRect] = []
    /// What the pointer is over does, or how to use the panel when it is over
    /// nothing.
    var hint = NSRect.zero
    var stamp = NSRect.zero
    var submit = NSRect.zero
    /// The submit outcome banner, when there is one. Zero-height means no notice,
    /// so the panel keeps its usual height the rest of the time.
    var notice = NSRect.zero
    var rules: [CGFloat] = []
}

/// Surfaces the panel paints on. Each is a dynamic colour so the same drawing
/// code follows the system appearance, including in an offscreen render. Shared
/// with the actions page, which paints on the same surfaces.
func panelGrey(_ light: CGFloat, _ dark: CGFloat, _ id: String) -> NSColor {
    NSColor(name: NSColor.Name("tokensbar.panel." + id)) { appearance in
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return NSColor(white: isDark ? 1 : 0, alpha: isDark ? dark : light)
    }
}

let panelTrack = panelGrey(0.09, 0.13, "track")
let panelCard = panelGrey(0.05, 0.08, "card")
let panelHover = panelGrey(0.07, 0.10, "hover")
let panelRule = panelGrey(0.09, 0.12, "rule")

/// Drawing primitives both pages use. They live on `NSView` so the drawing code
/// on either page reads the same way.
extension NSView {
    func measure(_ s: String, font: NSFont) -> NSSize {
        NSAttributedString(string: s, attributes: [.font: font]).size()
    }

    func text(_ s: String, in rect: NSRect, font: NSFont,
              colour: NSColor = .labelColor, align: NSTextAlignment = .left) {
        let style = NSMutableParagraphStyle()
        style.alignment = align
        style.lineBreakMode = .byTruncatingTail
        NSAttributedString(string: s, attributes: [
            .font: font, .foregroundColor: colour, .paragraphStyle: style,
        ]).draw(in: rect)
    }

    func fill(_ rect: NSRect, radius: CGFloat, colour: NSColor) {
        colour.setFill()
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
    }

    /// SF Symbols are template images; drawn straight into a view they come out
    /// black, so the glyph is tinted first. `NSImage` already compensates for the
    /// flipped coordinate system, so no transform is needed here.
    func icon(_ name: String, in rect: NSRect, size: CGFloat, colour: NSColor) {
        let config = NSImage.SymbolConfiguration(pointSize: size, weight: .regular)
        guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(config) else { return }
        let tinted = NSImage(size: base.size, flipped: false) { r in
            base.draw(in: r)
            colour.set()
            r.fill(using: .sourceAtop)
            return true
        }
        tinted.draw(in: NSRect(x: rect.midX - base.size.width / 2,
                               y: rect.midY - base.size.height / 2,
                               width: base.size.width, height: base.size.height))
    }

    /// A chevron just after a caption or a name, marking that block as clickable.
    /// The hover highlight and the hint line only speak up once the pointer is
    /// already there, so something has to say so beforehand.
    func chevron(after text: String, font: NSFont, in rect: NSRect,
                 colour: NSColor = .tertiaryLabelColor) {
        let x = min(rect.minX + ceil(measure(text, font: font).width) + 5, rect.maxX - 9)
        icon("chevron.right", in: NSRect(x: x, y: rect.midY - 6, width: 9, height: 12),
             size: 8, colour: colour)
    }
}

/// The dropdown, drawn rather than assembled from menu items.
final class PanelView: NSView {
    var data = PanelData() { didSet { invalidate() } }
    var onAction: ((PanelAction) -> Void)?

    static let width: CGFloat = 340
    private let pad: CGFloat = 18

    private var cache: PanelLayout?
    private var hits: [(NSRect, PanelAction)] = []
    private var hoveredHit: Int?
    private var hoveredDay: Int?

    override var isFlipped: Bool { true }

    private func invalidate() {
        cache = nil
        needsDisplay = true
        invalidateIntrinsicContentSize()
    }

    /// Today's models folded to the donut's slices, so a dot here is the same
    /// colour as that model's segment in the chart popover.
    private var slices: [ChartDatum] { chartSlices(data.models, metric: .tokens) }

    private var hasBoard: Bool { data.primary != nil }
    private var hasWeekBars: Bool { data.recent.contains { $0.tokens > 0 } }

    /// Only a submit outcome earns the banner. A background notice — an update
    /// check, say — stays on the timestamp line, which is where it never
    /// interrupted anything.
    private var hasNotice: Bool { data.transient != nil && data.noticeKind != .info }

    var fittingHeight: CGFloat { geometry().height }

    override var intrinsicContentSize: NSSize {
        NSSize(width: PanelView.width, height: fittingHeight)
    }

    // MARK: Layout

    private func geometry() -> PanelLayout {
        if let cache { return cache }
        // The view's own width, not the constant: if the popover ever hands over a
        // different width, the content still fills it symmetrically instead of
        // hugging the left edge.
        let w = bounds.width > 1 ? bounds.width : PanelView.width
        let inner = w - pad * 2
        var l = PanelLayout()
        var y: CGFloat = 12

        l.gear = NSRect(x: w - pad - 22, y: y - 2, width: 22, height: 22)
        l.history = NSRect(x: l.gear.minX - 26, y: y - 2, width: 22, height: 22)
        l.title = NSRect(x: pad, y: y, width: l.history.minX - pad - 6, height: 18)
        y += 30
        l.rules.append(y)
        y += 13

        // A submit outcome sits directly under the header, above the number it
        // just changed. Without a notice the slot takes no space at all.
        if hasNotice {
            l.notice = NSRect(x: pad, y: y, width: inner, height: 30)
            y += 30 + 13
        }

        l.heroValue = NSRect(x: pad, y: y, width: inner - 96, height: 38)
        l.heroCost = NSRect(x: w - pad - 96, y: y + 13, width: 96, height: 20)
        y += 38
        l.heroSub = NSRect(x: pad, y: y, width: inner, height: 15)
        y += 16
        l.heroLocal = NSRect(x: pad, y: y, width: inner, height: 14)
        y += 14
        l.hero = NSRect(x: pad - 6, y: l.heroValue.minY - 6,
                        width: inner + 12, height: y - l.heroValue.minY + 10)
        y += 13
        l.rules.append(y)
        y += 13

        if hasBoard {
            l.boardCaption = NSRect(x: pad, y: y + 1, width: inner - 118, height: 14)
            l.boardRank = NSRect(x: w - pad - 118, y: y, width: 118, height: 16)
            y += 20
            l.boardTrack = NSRect(x: pad, y: y, width: inner, height: 8)
            y += 12
            l.boardLabel = NSRect(x: pad, y: y, width: inner - 50, height: 14)
            l.boardPct = NSRect(x: w - pad - 50, y: y, width: 50, height: 14)
            y += 22
        }

        l.avgCaption = NSRect(x: pad, y: y, width: inner - 96, height: 13)
        l.avgValue = NSRect(x: w - pad - 96, y: y, width: 96, height: 13)
        y += 15
        l.avgTrack = NSRect(x: pad, y: y, width: inner, height: 6)
        y += 10
        l.avgSub = NSRect(x: pad, y: y, width: inner, height: 13)
        y += 21

        let cardW = (inner - 10) / 2
        l.cards = [NSRect(x: pad, y: y, width: cardW, height: 54),
                   NSRect(x: pad + cardW + 10, y: y, width: cardW, height: 54)]
        y += 54 + 13
        l.rules.append(y)
        y += 13

        if hasWeekBars {
            l.weekCaption = NSRect(x: pad, y: y, width: inner - 150, height: 13)
            l.weekValue = NSRect(x: w - pad - 150, y: y - 1, width: 150, height: 15)
            // 22, not 18: the readout on the right is a size up from the caption, so
            // its descenders reach further down than the caption's do, and the card
            // below has to start clear of them.
            y += 22
            // The bars live in a card of their own, like the two above them. The
            // card is the click target as well, so nothing has to be padded outward
            // into the caption row to make the block hoverable.
            l.weekCard = NSRect(x: pad, y: y, width: inner, height: 68)
            l.barArea = NSRect(x: pad + 10, y: y + 10, width: inner - 20, height: 36)
            l.barLabels = NSRect(x: pad + 10, y: y + 49, width: inner - 20, height: 13)
            let colW = l.barArea.width / 7
            l.barColumns = (0..<7).map {
                NSRect(x: l.barArea.minX + CGFloat($0) * colW, y: y + 4,
                       width: colW, height: 60)
            }
            y += 68 + 13
            l.rules.append(y)
            y += 13
        }

        if !slices.isEmpty {
            l.modelCaption = NSRect(x: pad, y: y, width: inner - 90, height: 13)
            l.modelValue = NSRect(x: w - pad - 90, y: y, width: 90, height: 13)
            y += 17
            l.modelRows = slices.indices.map {
                NSRect(x: pad - 4, y: y + CGFloat($0) * 18, width: inner + 8, height: 18)
            }
            y += CGFloat(slices.count) * 18 + 11
            l.rules.append(y)
            y += 12
        }

        // The hint line gets the full width: it carries the longest string in the
        // panel, so it cannot share a row with the button.
        l.hint = NSRect(x: pad, y: y, width: inner, height: 14)
        y += 18

        let submitTitle = data.busy ? t("panel.submitting") : t("panel.submit")
        let submitW = max(76, ceil(measure(submitTitle, font: buttonFont).width) + 34)
        l.submit = NSRect(x: w - pad - submitW, y: y, width: submitW, height: 24)
        l.stamp = NSRect(x: pad, y: y + 5, width: inner - submitW - 10, height: 14)
        y += 24 + 14

        l.height = y
        cache = l
        return l
    }

    /// Clickable regions, derived from the layout so they always match what was
    /// drawn. Order is the hover index. Each rect is final: the hover highlight
    /// paints it as-is and the hit test uses it as-is, so a target can never light
    /// up an area the layout gave to something else.
    private func regions(_ l: PanelLayout) -> [(NSRect, PanelAction)] {
        var out: [(NSRect, PanelAction)] = []
        /// Text rects are tight around the glyphs, so they get a little air; blocks
        /// that already have a card of their own are taken as they are.
        func add(_ rect: NSRect, _ action: PanelAction, grow: Bool = true) {
            out.append((grow ? rect.insetBy(dx: -4, dy: -3) : rect, action))
        }
        add(l.title, .profile)
        add(l.history, .history, grow: false)
        add(l.gear, .menuPage, grow: false)
        add(l.hero, .chart(.today), grow: false)
        if let card = l.cards.first, data.secondary != nil {
            add(card, .chart(secondaryMode == .allTime ? .lifetime : .today), grow: false)
        }
        if hasWeekBars {
            add(l.weekCard, .history, grow: false)
        }
        if !l.modelRows.isEmpty {
            add(l.modelRows[0].union(l.modelRows[l.modelRows.count - 1]), .chart(.today))
        }
        add(l.submit, .submit, grow: false)
        return out
    }

    private var secondaryMode: RankMode {
        data.primaryMode == .today ? .allTime : .today
    }

    // MARK: Fonts and paint

    private let heroFont = NSFont.monospacedDigitSystemFont(ofSize: 32, weight: .semibold)
    private let titleFont = NSFont.systemFont(ofSize: 13, weight: .semibold)
    private let valueFont = NSFont.monospacedDigitSystemFont(ofSize: 14, weight: .semibold)
    private let cardFont = NSFont.monospacedDigitSystemFont(ofSize: 15, weight: .semibold)
    private let bodyFont = NSFont.systemFont(ofSize: 12)
    private let smallFont = NSFont.systemFont(ofSize: 11)
    private let captionFont = NSFont.systemFont(ofSize: 10, weight: .semibold)
    private let buttonFont = NSFont.systemFont(ofSize: 12, weight: .medium)

    /// Uppercase reads as a label in English; Chinese has no case, so it is left
    /// alone rather than being spaced out artificially.
    private func caption(_ s: String) -> String {
        L10n.current == .zh ? s : s.uppercased()
    }

    /// A track with a filled head. The head keeps a minimum width so a tiny but
    /// non-zero share still reads as progress rather than as nothing.
    private func bar(_ rect: NSRect, progress: CGFloat, colour: NSColor) {
        let r = rect.height / 2
        fill(rect, radius: r, colour: panelTrack)
        let p = min(1, max(0, progress))
        guard p > 0 else { return }
        fill(NSRect(x: rect.minX, y: rect.minY,
                    width: max(rect.height, rect.width * p), height: rect.height),
             radius: r, colour: colour)
    }

    /// The rect under the pointer, so a block that paints its own surface can pick
    /// the hover colour itself.
    private var hoveredRect: NSRect? {
        guard let i = hoveredHit, hits.indices.contains(i) else { return nil }
        return hits[i].0
    }

    /// What clicking the hovered block does, or how to use the panel when nothing
    /// is hovered.
    private var hintText: String {
        guard let i = hoveredHit, hits.indices.contains(i) else { return t("panel.hint") }
        switch hits[i].1 {
        case .profile: return t("hint.profile")
        case .menuPage: return t("hint.menu")
        case .history: return t("hint.contrib")
        case .chart(let scope):
            return scope == .today ? t("hint.chartToday") : t("hint.chartLifetime")
        case .submit: return t("hint.submit")
        default: return t("panel.hint")
        }
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        let l = geometry()
        hits = regions(l)
        let accent = NSColor.controlAccentColor

        if let i = hoveredHit, hits.indices.contains(i) {
            // The submit button and the bars card paint their own surface, so they
            // pick the hover colour themselves rather than being washed over.
            if hits[i].1 != .submit && hits[i].0 != l.weekCard {
                fill(hits[i].0, radius: 7, colour: panelHover)
            }
        }
        for y in l.rules {
            fill(NSRect(x: pad, y: y, width: bounds.width - pad * 2, height: 1),
                 radius: 0.5, colour: panelRule)
        }

        drawHeader(l)
        if hasNotice { drawNotice(l) }
        drawHero(l)
        if hasBoard { drawBoard(l, accent: accent) }
        drawAverage(l, accent: accent)
        drawCards(l)
        if hasWeekBars { drawWeek(l, accent: accent) }
        if !l.modelRows.isEmpty { drawModels(l) }
        drawFooter(l, accent: accent)
    }

    private func drawHeader(_ l: PanelLayout) {
        let name = data.username.isEmpty ? t("state.notLoggedIn") : "@" + data.username
        icon("bolt.fill", in: NSRect(x: l.title.minX, y: l.title.minY + 1, width: 13, height: 15),
             size: 11, colour: .controlAccentColor)
        let nameRect = NSRect(x: l.title.minX + 18, y: l.title.minY,
                              width: l.title.width - 18, height: l.title.height)
        text(name, in: nameRect, font: titleFont)
        chevron(after: name, font: titleFont, in: nameRect)
        icon("calendar", in: l.history, size: 14, colour: .secondaryLabelColor)
        icon("ellipsis.circle", in: l.gear, size: 14, colour: .secondaryLabelColor)
    }

    /// The submit outcome, as a tinted strip under the header. It used to share the
    /// footer's timestamp line in plain secondary grey, which is where a panel puts
    /// things nobody needs to read — the one line reporting on a button the user
    /// just pressed should not be the quietest thing on screen.
    private func drawNotice(_ l: PanelLayout) {
        guard let message = data.transient else { return }
        let ok = data.noticeKind == .success
        let tint: NSColor = ok ? .systemGreen : .systemRed
        fill(l.notice, radius: 7, colour: tint.withAlphaComponent(0.14))
        // A bar down the leading edge, so the strip still reads as a notice for
        // anyone who cannot separate the green wash from the red one.
        fill(NSRect(x: l.notice.minX, y: l.notice.minY, width: 3, height: l.notice.height),
             radius: 1.5, colour: tint)
        icon(ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
             in: NSRect(x: l.notice.minX + 13, y: l.notice.midY - 8, width: 16, height: 16),
             size: 12, colour: tint)
        text(message,
             in: NSRect(x: l.notice.minX + 34, y: l.notice.midY - 8,
                        width: l.notice.width - 44, height: 16),
             font: .systemFont(ofSize: 12, weight: .medium), colour: .labelColor)
    }

    private func drawHero(_ l: PanelLayout) {
        text(fmtTokens(data.todayTokens), in: l.heroValue, font: heroFont)
        text(fmtMoney(data.todayCost), in: l.heroCost, font: valueFont,
             colour: .secondaryLabelColor, align: .right)
        let cap = caption(data.todayIsServer ? t("panel.todayAll") : t("panel.todayLocalOnly"))
        text(cap, in: l.heroSub, font: captionFont, colour: .secondaryLabelColor)
        chevron(after: cap, font: captionFont, in: l.heroSub)
        let sub: String
        if data.localFailed {
            sub = t("panel.localFailed")
        } else if data.todayIsServer {
            sub = t("panel.thisMac", fmtTokens(data.localTokens), fmtMoney(data.localCost))
        } else if data.serverFailed {
            sub = t("panel.serverFailedShort")
        } else {
            sub = t("panel.awaitingSubmit")
        }
        // Secondary rather than tertiary: the popover's material is translucent, and
        // tertiary greys all but vanish on a bright wallpaper.
        text(sub, in: l.heroLocal, font: smallFont, colour: .secondaryLabelColor)
    }

    /// The board the menu bar shows, with the gap to the person above as a bar:
    /// the bar is own-total over their total, so a full bar means a tie.
    private func drawBoard(_ l: PanelLayout, accent: NSColor) {
        guard let st = data.primary else { return }
        fill(NSRect(x: l.boardCaption.minX, y: l.boardCaption.minY + 4, width: 6, height: 6),
             radius: 3, colour: accent)
        text(caption(data.primaryMode.label),
             in: NSRect(x: l.boardCaption.minX + 11, y: l.boardCaption.minY,
                        width: l.boardCaption.width - 11, height: l.boardCaption.height),
             font: captionFont, colour: .secondaryLabelColor)
        text(st.rank > 0 ? "#\(st.rank) / \(st.totalUsers)" : t("board.notRanked"),
             in: l.boardRank, font: valueFont, align: .right)

        var progress: CGFloat = 0
        var label: String
        var pct = "—"
        if st.rank == 0 {
            label = t("panel.notSubmitted")
        } else if let above = st.above, above.tokens > 0 {
            progress = CGFloat(min(1, Double(st.tokens) / Double(above.tokens)))
            label = t("panel.toNext", fmtTokens(max(0, above.tokens - st.tokens)),
                      above.rank, above.username)
            pct = "\(Int((progress * 100).rounded()))%"
        } else {
            progress = 1
            label = t("panel.atTop")
            pct = "100%"
        }
        bar(l.boardTrack, progress: progress, colour: accent)
        text(label, in: l.boardLabel, font: smallFont, colour: .secondaryLabelColor)
        text(pct, in: l.boardPct, font: smallFont, colour: .secondaryLabelColor, align: .right)
    }

    /// Today against the seven days before it. The track spans twice the average
    /// so the midpoint tick is "an average day" and passing it is visible.
    private func drawAverage(_ l: PanelLayout, accent: NSColor) {
        let avg = data.avgTokens
        let ratio = avg > 0 ? Double(data.todayTokens) / avg : 0
        text(caption(t("panel.vsAvg")), in: l.avgCaption, font: captionFont,
             colour: .secondaryLabelColor)
        let value: String
        if avg <= 0 { value = "—" }
        else if ratio >= 1 { value = t("panel.avgMultiple", String(format: "%.1f", ratio)) }
        else { value = t("panel.avgPercent", Int((ratio * 100).rounded())) }
        text(value, in: l.avgValue,
             font: .monospacedDigitSystemFont(ofSize: 11, weight: .semibold),
             colour: ratio >= 1 ? accent : .secondaryLabelColor, align: .right)
        bar(l.avgTrack, progress: CGFloat(min(1, ratio / 2)),
            colour: ratio >= 1 ? accent : accent.withAlphaComponent(0.5))
        if avg > 0 {
            fill(NSRect(x: l.avgTrack.midX - 0.5, y: l.avgTrack.minY - 2,
                        width: 1, height: l.avgTrack.height + 4),
                 radius: 0, colour: .tertiaryLabelColor)
        }
        text(t("panel.avgBest", fmtTokens(Int(avg.rounded())), fmtTokens(data.bestTokens)),
             in: l.avgSub, font: smallFont, colour: .secondaryLabelColor)
    }

    private func card(_ rect: NSRect, caption cap: String, value: String, sub: String,
                      clickable: Bool = false) {
        fill(rect, radius: 8, colour: panelCard)
        let x = rect.minX + 10, w = rect.width - 20
        text(cap, in: NSRect(x: x, y: rect.minY + 7, width: w, height: 13),
             font: captionFont, colour: .secondaryLabelColor)
        if clickable {
            icon("chevron.right",
                 in: NSRect(x: rect.maxX - 17, y: rect.minY + 7, width: 9, height: 13),
                 size: 8, colour: .tertiaryLabelColor)
        }
        text(value, in: NSRect(x: x, y: rect.minY + 20, width: w, height: 19), font: cardFont)
        text(sub, in: NSRect(x: x, y: rect.minY + 38, width: w, height: 13),
             font: smallFont, colour: .secondaryLabelColor)
    }

    private func drawCards(_ l: PanelLayout) {
        guard l.cards.count == 2 else { return }
        // Left: the board the menu bar is not showing, so both ranks stay visible.
        if let st = data.secondary {
            card(l.cards[0], caption: caption(secondaryMode.label),
                 value: st.rank > 0 ? "#\(st.rank) / \(st.totalUsers)" : t("board.notRanked"),
                 sub: fmtTokens(st.tokens), clickable: true)
        } else {
            card(l.cards[0], caption: caption(t("row.lifetime")),
                 value: data.serverFailed ? "—" : fmtTokens(data.lifetimeTokens),
                 sub: data.serverFailed ? t("panel.serverFailedShort")
                                        : fmtMoney(data.lifetimeCost))
        }
        card(l.cards[1], caption: caption(t("row.week")),
             value: data.localFailed ? "—" : fmtTokens(data.weekTokens),
             sub: data.localFailed ? t("panel.localFailed") : fmtMoney(data.weekCost))
    }

    private func drawWeek(_ l: PanelLayout, accent: NSColor) {
        let days = data.recent
        guard days.count == l.barColumns.count else { return }
        let cap = caption(t("panel.last7"))
        text(cap, in: l.weekCaption, font: captionFont, colour: .secondaryLabelColor)
        chevron(after: cap, font: captionFont, in: l.weekCaption)

        let short = DateFormatter()
        short.locale = displayLocale()
        short.timeZone = gridCalendar.timeZone
        short.setLocalizedDateFormatFromTemplate("Md")
        let narrow = DateFormatter()
        narrow.locale = displayLocale()
        narrow.timeZone = gridCalendar.timeZone
        narrow.setLocalizedDateFormatFromTemplate("EEEEE")

        let summary: String
        if let i = hoveredDay, days.indices.contains(i) {
            let d = days[i]
            summary = "\(short.string(from: d.date))  ·  \(fmtTokens(d.tokens))  ·  \(fmtMoney(d.cost))"
        } else {
            summary = "\(fmtTokens(days.reduce(0) { $0 + $1.tokens }))  ·  "
                + fmtMoney(days.reduce(0.0) { $0 + $1.cost })
        }
        text(summary, in: l.weekValue,
             font: .monospacedDigitSystemFont(ofSize: 11, weight: .medium),
             colour: .secondaryLabelColor, align: .right)

        let peak = max(1, days.map(\.tokens).max() ?? 1)
        fill(l.weekCard, radius: 8, colour: hoveredRect == l.weekCard ? panelHover : panelCard)
        for (i, day) in days.enumerated() {
            let col = l.barColumns[i]
            let barW = min(20, col.width - 8)
            let h = max(3, l.barArea.height * CGFloat(day.tokens) / CGFloat(peak))
            let isToday = i == days.count - 1
            let hovering = hoveredDay == i
            let colour = hovering ? accent
                : accent.withAlphaComponent(isToday ? 0.9 : 0.42)
            fill(NSRect(x: col.midX - barW / 2, y: l.barArea.maxY - h, width: barW, height: h),
                 radius: 3, colour: colour)
            text(narrow.string(from: day.date),
                 in: NSRect(x: col.minX, y: l.barLabels.minY, width: col.width, height: 13),
                 font: .systemFont(ofSize: 9, weight: hovering || isToday ? .semibold : .regular),
                 colour: hovering || isToday ? .labelColor : .secondaryLabelColor,
                 align: .center)
        }
    }

    private func drawModels(_ l: PanelLayout) {
        let s = slices
        let total = max(1.0, s.reduce(0.0) { $0 + Double($1.tokens) })
        let cap = caption(t("panel.modelsToday"))
        text(cap, in: l.modelCaption, font: captionFont, colour: .secondaryLabelColor)
        chevron(after: cap, font: captionFont, in: l.modelCaption)
        text(caption(data.todayIsServer ? t("panel.allDevices") : t("panel.thisMacOnly")),
             in: l.modelValue, font: captionFont, colour: .secondaryLabelColor, align: .right)
        for (i, slice) in s.enumerated() where l.modelRows.indices.contains(i) {
            let row = l.modelRows[i]
            fill(NSRect(x: row.minX + 4, y: row.minY + 6, width: 7, height: 7),
                 radius: 3.5, colour: chartPalette[i % chartPalette.count])
            text(slice.label,
                 in: NSRect(x: row.minX + 19, y: row.minY + 1,
                            width: row.width - 150, height: 15),
                 font: bodyFont)
            text(fmtTokens(slice.tokens),
                 in: NSRect(x: row.maxX - 118, y: row.minY + 2, width: 62, height: 14),
                 font: .monospacedDigitSystemFont(ofSize: 11, weight: .regular),
                 colour: .secondaryLabelColor, align: .right)
            text(String(format: "%.0f%%", Double(slice.tokens) / total * 100),
                 in: NSRect(x: row.maxX - 48, y: row.minY + 2, width: 44, height: 14),
                 font: .monospacedDigitSystemFont(ofSize: 11, weight: .medium),
                 colour: .secondaryLabelColor, align: .right)
        }
    }

    /// White or black on the accent fill, whichever the accent can carry — the
    /// system accent can be a light yellow.
    private func onAccent(_ accent: NSColor) -> NSColor {
        guard let rgb = accent.usingColorSpace(.sRGB) else { return .white }
        let luma = 0.2126 * rgb.redComponent + 0.7152 * rgb.greenComponent
            + 0.0722 * rgb.blueComponent
        return luma > 0.62 ? .black : .white
    }

    private func drawFooter(_ l: PanelLayout, accent: NSColor) {
        // What the pointer is over does, or — when it is over nothing — how the
        // panel is meant to be used at all.
        let hovering = hoveredHit.map { hits.indices.contains($0) } ?? false
        text(hintText, in: l.hint, font: smallFont,
             colour: hovering ? .labelColor : .secondaryLabelColor)

        let stamp: String
        // A submit outcome has the banner up top now; repeating it here would say
        // the same thing twice. Background notices still land on this line.
        if let transient = data.transient, !hasNotice {
            stamp = transient
        } else {
            var bits: [String] = []
            if let d = data.localStamp { bits.append(t("stamp.local", fmtClock(d))) }
            if let d = data.serverStamp { bits.append(t("stamp.server", fmtClock(d))) }
            if data.serverFailed { bits.append(t("panel.serverFailedShort")) }
            if data.isStale { bits.append("⚠") }
            stamp = bits.joined(separator: "  ·  ")
        }
        text(stamp, in: l.stamp, font: smallFont, colour: .secondaryLabelColor)

        let onSubmit = hoveredHit.map { hits.indices.contains($0) && hits[$0].1 == .submit }
            ?? false
        let enabled = !data.busy
        fill(l.submit, radius: 7,
             colour: enabled ? accent.withAlphaComponent(onSubmit ? 1 : 0.88) : panelCard)
        text(data.busy ? t("panel.submitting") : t("panel.submit"),
             in: NSRect(x: l.submit.minX, y: l.submit.minY + 4,
                        width: l.submit.width, height: 16),
             font: buttonFont, colour: enabled ? onAccent(accent) : .secondaryLabelColor,
             align: .center)
    }

    // MARK: Interaction

    /// The layout is width-dependent, so a resize has to throw the cache away.
    override func setFrameSize(_ newSize: NSSize) {
        let changed = abs(newSize.width - frame.width) > 0.5
        super.setFrameSize(newSize)
        if changed { invalidate() }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self))
    }

    override func mouseMoved(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let l = geometry()
        let hit = regions(l).firstIndex { $0.0.contains(p) }
        let day = hasWeekBars ? l.barColumns.firstIndex { $0.contains(p) } : nil
        guard hit != hoveredHit || day != hoveredDay else { return }
        hoveredHit = hit
        hoveredDay = day
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        guard hoveredHit != nil || hoveredDay != nil else { return }
        hoveredHit = nil
        hoveredDay = nil
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        guard let hit = regions(geometry()).first(where: { $0.0.contains(p) }) else { return }
        if hit.1 == .submit && data.busy { return }
        onAction?(hit.1)
    }

    /// Right-clicking anywhere in the panel opens the plain menu, matching the
    /// status item — that is still the route to the numbers as text.
    override func rightMouseUp(with event: NSEvent) {
        onAction?(.textMenu)
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        for (rect, _) in regions(geometry()) { addCursorRect(rect, cursor: .pointingHand) }
    }

    /// Forces a hover state for offscreen renders.
    func setHoverForSnapshot(hit: Int?, day: Int?) {
        hoveredHit = hit
        hoveredDay = day
        needsDisplay = true
    }

    /// The clickable map, for `--panel-png` to print alongside the render: where
    /// a click lands is the one thing a static image cannot show.
    func hitMap() -> [(NSRect, PanelAction)] { regions(geometry()) }
}

/// Holds both pages and shows one at a time. The popover keeps the same content
/// view across a page turn — swapping the view controller's view while shown
/// loses the tracking areas — so the two pages are siblings and one is hidden.
final class PanelContainer: NSView {
    let main = PanelView()
    let actions = PanelMenuView()
    var onAction: ((PanelAction) -> Void)?

    var page: PanelPage = .main { didSet { applyPage() } }
    var data = PanelData() {
        didSet {
            main.data = data
            actions.data = data
        }
    }

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(main)
        addSubview(actions)
        main.onAction = { [weak self] in self?.onAction?($0) }
        actions.onAction = { [weak self] in self?.onAction?($0) }
        applyPage()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not loaded from a nib") }

    private func applyPage() {
        main.isHidden = page != .main
        actions.isHidden = page != .menu
        needsLayout = true
    }

    var fittingHeight: CGFloat {
        page == .main ? main.fittingHeight : actions.fittingHeight
    }

    override func layout() {
        super.layout()
        main.frame = bounds
        actions.frame = bounds
    }

    func setHoverForSnapshot(hit: Int?, day: Int?) {
        switch page {
        case .main: main.setHoverForSnapshot(hit: hit, day: day)
        case .menu: actions.setHoverForSnapshot(hit: hit)
        }
    }

    func hitMap() -> [(NSRect, PanelAction)] {
        page == .main ? main.hitMap() : actions.hitMap()
    }
}

/// Hosts the panel in a popover anchored to the status item, so the dropdown
/// still reads as part of the menu bar.
final class DropdownPanel: NSObject {
    static let shared = DropdownPanel()

    private let popover = NSPopover()
    private let view = PanelContainer(
        frame: NSRect(x: 0, y: 0, width: PanelView.width, height: 200))
    private var built = false
    private var closedAt: Date?
    /// The last data applied, so a page turn can resize without waiting for the
    /// next refresh to hand the numbers over again.
    private var current = PanelData()

    var onAction: ((PanelAction) -> Void)?
    var isShown: Bool { popover.isShown }
    /// A click on the status item dismisses the transient popover before the
    /// action runs, so "still closing" counts as open — otherwise the click that
    /// closes the panel would immediately reopen it.
    var justClosed: Bool { closedAt.map { Date().timeIntervalSince($0) < 0.3 } ?? false }

    private func build() {
        guard !built else { return }
        built = true
        // Paging is the panel's own business: the controller only hears the verbs.
        view.onAction = { [weak self] action in
            guard let self else { return }
            switch action {
            case .menuPage: self.turn(to: .menu)
            case .back: self.turn(to: .main)
            default: self.onAction?(action)
            }
        }
        let vc = NSViewController()
        vc.view = view
        popover.contentViewController = vc
        popover.behavior = .transient
        popover.animates = false
        popover.delegate = self
    }

    /// Turns to a page and resizes the popover to it, since the two pages are
    /// different heights. Internal so `--panel-probe` can turn the page on a live
    /// popover — resizing a shown popover is the part a static render cannot show.
    func turn(to page: PanelPage) {
        view.page = page
        apply(current)
    }

    private func apply(_ data: PanelData) {
        current = data
        view.data = data
        let size = NSSize(width: PanelView.width, height: view.fittingHeight)
        // Only position the view ourselves when the popover is not holding it.
        // While shown, the popover insets the content view inside its frame (13 pt
        // for the border and arrow); assigning `frame` here would move the content
        // back to the frame's corner, and the panel would sit visibly off-centre
        // from the next refresh onwards. Resizing goes through `contentSize`.
        if view.window == nil {
            view.frame = NSRect(origin: .zero, size: size)
        }
        if popover.contentSize != size { popover.contentSize = size }
        view.layoutSubtreeIfNeeded()
    }

    func show(_ data: PanelData, from anchor: NSView?) {
        guard let anchor else { return }
        build()
        // Opening always lands on the numbers, whatever page it closed on.
        view.page = .main
        apply(data)
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxY)
    }

    /// Refreshes in place; a refresh landing while the panel is open should move
    /// the numbers, not close it.
    func update(_ data: PanelData) {
        guard popover.isShown else { return }
        apply(data)
    }

    func close() {
        guard popover.isShown else { return }
        popover.performClose(nil)
    }

    /// Live geometry, for `--panel-probe`: what the popover actually hands the
    /// view can differ from the size asked for, which is how the content ends up
    /// off-centre.
    func probe() -> String {
        var lines = ["contentSize \(popover.contentSize)",
                     "view.frame  \(view.frame)",
                     "view.bounds \(view.bounds)"]
        var node: NSView? = view.superview
        var depth = 1
        while let v = node {
            lines.append("super[\(depth)] \(type(of: v))  \(v.frame)")
            node = v.superview
            depth += 1
        }
        if let w = view.window {
            lines.append("window \(w.frame)  \(type(of: w))")
        }
        return lines.joined(separator: "\n  ")
    }

    /// Captures the popover window itself, material and all — our own window, so
    /// no screen-recording prompt is involved.
    func captureWindow(to path: String) -> String {
        guard let window = view.window else { return "capture failed: no window" }
        let id = CGWindowID(window.windowNumber)
        guard let image = CGWindowListCreateImage(
            .null, .optionIncludingWindow, id, [.boundsIgnoreFraming, .bestResolution])
        else { return "capture failed: no image" }
        let rep = NSBitmapImageRep(cgImage: image)
        guard let png = rep.representation(using: .png, properties: [:]) else {
            return "capture failed: no png"
        }
        try? png.write(to: URL(fileURLWithPath: path))
        return "wrote \(path) (\(image.width)×\(image.height))"
    }

    /// One line per clickable region, in hit order.
    func hitMap(_ data: PanelData, page: PanelPage = .main) -> [String] {
        build()
        view.page = page
        apply(data)
        return view.hitMap().map { rect, action in
            padDisplay("\(action)", 16)
                + String(format: "x %3.0f  y %4.0f  %3.0f×%.0f",
                         rect.minX, rect.minY, rect.width, rect.height)
        }
    }

    /// Offscreen render for `--panel-png`, the same hosting trick the chart and
    /// contributions popovers use.
    func snapshot(_ data: PanelData, dark: Bool = false, page: PanelPage = .main,
                  hoverDay: Int? = nil, hoverHit: Int? = nil) -> Data? {
        build()
        view.page = page
        apply(data)
        view.setHoverForSnapshot(hit: hoverHit, day: hoverDay)
        let size = view.frame.size
        let host = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                            styleMask: [.borderless], backing: .buffered, defer: false)
        host.isReleasedWhenClosed = false
        host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        host.contentView = view
        view.frame = NSRect(origin: .zero, size: size)
        // The popover supplies its own material at runtime; stand in the surface
        // the palette was validated against so the PNG is not transparent.
        view.wantsLayer = true
        view.layer?.backgroundColor = colorFrom(hex: dark ? "2a2a2a" : "ececec").cgColor
        view.layoutSubtreeIfNeeded()
        view.display()

        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        view.layer?.backgroundColor = nil
        host.contentView = nil // hand the view back to the popover
        popover.contentViewController?.view = view
        view.setHoverForSnapshot(hit: nil, day: nil)
        return rep.representation(using: .png, properties: [:])
    }
}

extension DropdownPanel: NSPopoverDelegate {
    func popoverDidClose(_ notification: Notification) { closedAt = Date() }
}

