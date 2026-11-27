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
    case readToken
    case toggleMenuBarItem(String)
    case editBudget
    case cliUpdate
    case setRank(RankMode)
    case setLanguage(Lang)
    case toggleLogin
    case updates
    case support
    case quit
    /// Stats-card copies: the live embed markdown/URL, or a local PNG image.
    case cardMarkdown
    case cardURL
    case cardImage
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
        case .readToken: return "read-token"
        case .toggleMenuBarItem(let item): return "menubar-item(\(item))"
        case .editBudget: return "edit-budget"
        case .cliUpdate: return "cli-update"
        case .setRank(let mode): return "rank(\(mode.rawValue))"
        case .setLanguage(let lang): return "language(\(lang.rawValue))"
        case .toggleLogin: return "launch-at-login"
        case .updates: return "updates"
        case .support: return "support"
        case .quit: return "quit"
        case .cardMarkdown: return "card-markdown"
        case .cardURL: return "card-url"
        case .cardImage: return "card-image"
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
    var monthTokens = 0
    var monthCost = 0.0
    /// Month-end spend at today's pace; 0 when there is nothing to project.
    var monthProjection = 0.0
    /// The configured daily-spend budget in USD; 0 when off.
    var dailyBudget = 0.0
    /// Lifetime days with usage, as the server counts them.
    var activeDays = 0
    /// Consecutive UTC active-day streaks derived from contributions.
    var currentStreak = 0
    var longestStreak = 0
    /// Today's prompt cache hit ratio (0…1), when reported by the API.
    var todayCacheRate: Double?
    /// Active menu bar readout components, in display order.
    var menuBarItems: [String] = ["tokens", "rank"]
    /// Local `tokens` CLI version, optional newer upstream version, and serve status.
    var cliVersion: String?
    var cliLatestVersion: String?
    var cliServeRunning: Bool?
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
    var serverLoading = false
    var serverError: String?
    var serverFetchedAt: Date?
    var serverAttemptedAt: Date?
    var hasServer = false
    var hasLocal = false
    var modelsAreServer = false
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

    /// How far today's spend is over the budget: 0 = under or off, 1 = past it,
    /// 2 = well past (≥1.5×). Drives the amber/red on the today figure.
    var budgetSeverity: Int {
        guard dailyBudget > 0 else { return 0 }
        let ratio = todayCost / dailyBudget
        return ratio >= 1.5 ? 2 : ratio >= 1 ? 1 : 0
    }
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
        hasServer = server != nil
        hasLocal = local.updatedAt != nil
        modelsAreServer = !(server?.todayModels.isEmpty ?? true)
        localTokens = local.todayTokens
        localCost = local.todayCost
        localFailed = local.failed
        lifetimeTokens = server?.totalTokens ?? 0
        lifetimeCost = server?.totalCost ?? 0
        weekTokens = local.weekTokens
        weekCost = local.weekCost
        monthTokens = local.monthTokens
        monthCost = local.monthCost
        monthProjection = projectMonthEnd(local.monthCost)
        dailyBudget = config.dailyCostBudget
        menuBarItems = config.menuBarItems
        activeDays = server?.activeDays ?? 0
        currentStreak = server?.currentStreak ?? 0
        longestStreak = server?.longestStreak ?? 0
        todayCacheRate = server?.todayDay?.cacheHitRate

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
    var heroSub = NSRect.zero
    var heroValue = NSRect.zero
    var heroCost = NSRect.zero
    var heroLocal = NSRect.zero
    var progressCard = NSRect.zero
    var boardCaption = NSRect.zero
    var boardRank = NSRect.zero
    var boardSwitch = NSRect.zero
    var boardRows: [NSRect] = []
    var boardEmpty = NSRect.zero
    var progressDividerY: CGFloat = 0
    var avgCaption = NSRect.zero
    var avgValue = NSRect.zero
    var avgTrack = NSRect.zero
    var avgSub = NSRect.zero
    /// Left card is the other board, right card is this week.
    var cards: [NSRect] = []
    var weekCard = NSRect.zero
    var weekCaption = NSRect.zero
    var weekValue = NSRect.zero
    /// Full-height columns, so hovering anywhere over a day picks it up.
    var barColumns: [NSRect] = []
    var barArea = NSRect.zero
    var barLabels = NSRect.zero
    var monthCard = NSRect.zero
    /// This month's total, its month-end projection, active days/streak, and over-budget line.
    var monthCaption = NSRect.zero
    var monthValue = NSRect.zero
    var monthProj = NSRect.zero
    var activeLine = NSRect.zero
    var budgetLine = NSRect.zero
    var modelsCard = NSRect.zero
    var modelCaption = NSRect.zero
    var modelValue = NSRect.zero
    var modelRows: [NSRect] = []
    /// What the pointer is over does, or how to use the panel when it is over
    /// nothing.
    var hint = NSRect.zero
    var stamp = NSRect.zero
    var submit = NSRect.zero
    /// The submit outcome badge, when there is one — it takes over the stamp's slot
    /// beside the button rather than adding a row, so the panel never changes
    /// height and the outcome lands where the eye already is after a click.
    var notice = NSRect.zero
    var rules: [CGFloat] = []
}

/// Surfaces the panel paints on. Each is a dynamic colour so the same drawing
/// code follows the system appearance, including in an offscreen render. Shared
/// with the actions page, which paints on the same surfaces.
func panelGrey(_ light: CGFloat, _ dark: CGFloat, _ id: String) -> NSColor {
    NSColor(name: NSColor.Name("tokensbar.panel." + id)) { appearance in
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let contrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        let alpha = isDark ? dark : light
        return NSColor(white: isDark ? 1 : 0,
                       alpha: contrast ? min(0.35, alpha * 1.8) : alpha)
    }
}

let panelTrack = panelGrey(0.09, 0.14, "track")
let panelCard = panelGrey(0.05, 0.08, "card")
let panelHover = panelGrey(0.07, 0.11, "hover")
let panelRule = panelGrey(0.08, 0.11, "rule")

/// Elevated card surface: crisp frosted white in light mode, elevated slate in dark mode.
let panelSurface = NSColor(name: NSColor.Name("tokensbar.panel.surface")) { appearance in
    let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    let contrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
    if isDark {
        return NSColor(white: 1, alpha: contrast ? 0.11 : 0.062)
    }
    return NSColor(white: 1, alpha: contrast ? 0.92 : 0.72)
}

let panelSurfaceHover = NSColor(name: NSColor.Name("tokensbar.panel.surfaceHover")) { appearance in
    let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    return isDark ? NSColor(white: 1, alpha: 0.105) : NSColor(white: 1, alpha: 0.94)
}

let panelBorder = NSColor(name: NSColor.Name("tokensbar.panel.border")) { appearance in
    let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    let contrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
    if isDark {
        return NSColor(white: 1, alpha: contrast ? 0.22 : 0.095)
    }
    return NSColor(white: 0, alpha: contrast ? 0.18 : 0.075)
}

let panelTopHighlight = NSColor(name: NSColor.Name("tokensbar.panel.topHighlight")) { appearance in
    let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    return isDark ? NSColor(white: 1, alpha: 0.07) : NSColor(white: 1, alpha: 0.65)
}

let panelHeroFill = NSColor(name: NSColor.Name("tokensbar.panel.heroFill")) { appearance in
    let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    if isDark {
        return NSColor(srgbRed: 48 / 255, green: 96 / 255, blue: 100 / 255, alpha: 0.24)
    }
    return NSColor(srgbRed: 238 / 255, green: 247 / 255, blue: 247 / 255, alpha: 0.88)
}

let panelHeroHover = NSColor(name: NSColor.Name("tokensbar.panel.heroHover")) { appearance in
    let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    if isDark {
        return NSColor(srgbRed: 56 / 255, green: 112 / 255, blue: 116 / 255, alpha: 0.32)
    }
    return NSColor(srgbRed: 232 / 255, green: 244 / 255, blue: 244 / 255, alpha: 0.98)
}

let panelHeroBorder = NSColor(name: NSColor.Name("tokensbar.panel.heroBorder")) { appearance in
    let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    return isDark
        ? NSColor(srgbRed: 96 / 255, green: 174 / 255, blue: 178 / 255, alpha: 0.30)
        : NSColor(srgbRed: 46 / 255, green: 103 / 255, blue: 107 / 255, alpha: 0.20)
}

/// Secondary brighter teal endpoint for progress/chart gradients (harmonizes with `tokensAccent`).
let tokensAccentBright = NSColor(name: NSColor.Name("tokensbar.accent.bright")) { appearance in
    let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    return isDark
        ? NSColor(srgbRed: 84 / 255, green: 176 / 255, blue: 162 / 255, alpha: 1)
        : NSColor(srgbRed: 56 / 255, green: 138 / 255, blue: 132 / 255, alpha: 1)
}

/// Drawing primitives both pages use. They live on `NSView` so the drawing code
/// on either page reads the same way.
extension NSView {
    func measure(_ s: String, font: NSFont) -> NSSize {
        NSAttributedString(string: s, attributes: [.font: font]).size()
    }

    func text(_ s: String, in rect: NSRect, font: NSFont,
              colour: NSColor = .labelColor, align: NSTextAlignment = .left,
              wrap: Bool = false) {
        let style = NSMutableParagraphStyle()
        style.alignment = align
        style.lineBreakMode = wrap ? .byWordWrapping : .byTruncatingTail
        NSAttributedString(string: s, attributes: [
            .font: font, .foregroundColor: colour, .paragraphStyle: style,
        ]).draw(in: rect)
    }

    func fill(_ rect: NSRect, radius: CGFloat, colour: NSColor) {
        colour.setFill()
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
    }

    func fillGradient(_ rect: NSRect, radius: CGFloat, from startColor: NSColor,
                      to endColor: NSColor, angle: CGFloat = 0) {
        let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        guard let grad = NSGradient(starting: startColor, ending: endColor) else {
            startColor.setFill()
            path.fill()
            return
        }
        grad.draw(in: path, angle: angle)
    }

    /// Elevated tactile card container used across both the main panel and the
    /// grouped settings page.
    func drawCard(_ rect: NSRect, radius: CGFloat = 11, hovered: Bool = false,
                  hero: Bool = false) {
        let isDark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        if !isDark, let cg = NSGraphicsContext.current?.cgContext {
            cg.saveGState()
            cg.setShadow(offset: CGSize(width: 0, height: -1), blur: 3,
                         color: NSColor(white: 0, alpha: 0.045).cgColor)
            let fillCol = hero ? (hovered ? panelHeroHover : panelHeroFill)
                               : (hovered ? panelSurfaceHover : panelSurface)
            fillCol.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            cg.restoreGState()
        } else {
            let fillCol = hero ? (hovered ? panelHeroHover : panelHeroFill)
                               : (hovered ? panelSurfaceHover : panelSurface)
            fill(rect, radius: radius, colour: fillCol)
        }
        stroke(rect, radius: radius, colour: hero ? panelHeroBorder : panelBorder, width: 0.75)
        // Delicate top inner highlight for native macOS card depth
        let hi = NSRect(x: rect.minX + radius * 0.6, y: rect.minY + 0.75,
                        width: max(0, rect.width - radius * 1.2), height: 0.75)
        fill(hi, radius: 0, colour: panelTopHighlight)
    }

    /// Inset by half the line width, so the stroke lands inside `rect` instead of
    /// straddling its edge and going soft.
    func stroke(_ rect: NSRect, radius: CGFloat, colour: NSColor, width: CGFloat = 1) {
        colour.setStroke()
        let path = NSBezierPath(roundedRect: rect.insetBy(dx: width / 2, dy: width / 2),
                                xRadius: radius, yRadius: radius)
        path.lineWidth = width
        path.stroke()
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
    var data = PanelData() {
        didSet {
            let oldTarget = avgProgress(for: oldValue)
            let newTarget = avgProgress(for: data)
            invalidate()
            if window != nil && abs(newTarget - oldTarget) > 0.002 {
                animateAvg(from: avgDisplayProgress ?? oldTarget, to: newTarget,
                           duration: 0.36, shimmer: newTarget > oldTarget)
            }
        }
    }
    var onAction: ((PanelAction) -> Void)?

    static let width: CGFloat = 360
    private let pad: CGFloat = 16

    private var cache: PanelLayout?
    private var hits: [(NSRect, PanelAction)] = []
    private var hoveredHit: Int?
    private var hoveredDay: Int?
    private var pressedAction: PanelAction?
    private var pressedRect: NSRect?
    private var tooltipStrings: [NSView.ToolTipTag: String] = [:]
    private var weekFormatterLang: Lang?
    private var weekShortFmt = DateFormatter()
    private var weekNarrowFmt = DateFormatter()

    /// Animated progress (0…1) and specular highlight sweep (-1 = idle, 0…1 = sweeping)
    /// for the "today / 7-day avg" progress bar.
    private var avgDisplayProgress: CGFloat?
    private var avgShimmerPhase: CGFloat = -1
    private var avgAnimTimer: Timer?

    deinit { avgAnimTimer?.invalidate() }

    private func avgProgress(for d: PanelData) -> CGFloat {
        let avg = d.todayIsServer ? d.avgTokens : 0
        let ratio = avg > 0 ? Double(d.todayTokens) / avg : 0
        return CGFloat(min(1, max(0, ratio / 2)))
    }

    func animateAvgIn() {
        let target = avgProgress(for: data)
        guard target > 0, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            stopAvgAnimation()
            return
        }
        animateAvg(from: 0, to: target, duration: 0.44, shimmer: true)
    }

    func stopAvgAnimation() {
        avgAnimTimer?.invalidate()
        avgAnimTimer = nil
        avgDisplayProgress = nil
        avgShimmerPhase = -1
        needsDisplay = true
    }

    private func animateAvg(from startVal: CGFloat, to target: CGFloat,
                            duration: TimeInterval, shimmer: Bool) {
        avgAnimTimer?.invalidate()
        avgAnimTimer = nil
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            avgDisplayProgress = target
            avgShimmerPhase = -1
            needsDisplay = true
            return
        }
        let shimmerDelay = duration * 0.72
        let shimmerDur: TimeInterval = shimmer ? 0.42 : 0
        let totalDur = shimmer ? max(duration, shimmerDelay + shimmerDur) : duration
        let t0 = Date()
        avgDisplayProgress = startVal
        avgShimmerPhase = -1
        needsDisplay = true

        avgAnimTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) {
            [weak self] timer in
            guard let self else { return timer.invalidate() }
            if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                self.stopAvgAnimation()
                return
            }
            let elapsed = Date().timeIntervalSince(t0)
            let p = min(1.0, elapsed / duration)
            // Ease-out cubic: brisk launch, smooth deceleration into place.
            let eased = CGFloat(1 - pow(1 - p, 3))
            self.avgDisplayProgress = startVal + (target - startVal) * eased

            if shimmer && elapsed >= shimmerDelay {
                let sp = min(1.0, (elapsed - shimmerDelay) / shimmerDur)
                self.avgShimmerPhase = CGFloat(sp)
            } else {
                self.avgShimmerPhase = -1
            }

            // Redraw only the average bar region for minimal CPU usage.
            let track = self.geometry().avgTrack.insetBy(dx: -4, dy: -4)
            self.setNeedsDisplay(track)

            if elapsed >= totalDur {
                timer.invalidate()
                self.avgAnimTimer = nil
                self.avgDisplayProgress = target
                self.avgShimmerPhase = -1
                self.setNeedsDisplay(track)
            }
        }
    }

    private func ensureWeekFormatters() {
        guard weekFormatterLang != L10n.current else { return }
        weekFormatterLang = L10n.current
        let locale = displayLocale()
        let tz = gridCalendar.timeZone
        weekShortFmt.locale = locale
        weekShortFmt.timeZone = tz
        weekShortFmt.setLocalizedDateFormatFromTemplate("Md")
        weekNarrowFmt.locale = locale
        weekNarrowFmt.timeZone = tz
        weekNarrowFmt.setLocalizedDateFormatFromTemplate("EEEEE")
    }

    @objc func view(_ view: NSView, stringForToolTip tag: NSView.ToolTipTag,
              point: NSPoint, userData: UnsafeMutableRawPointer?) -> String {
        tooltipStrings[tag] ?? ""
    }

    private func tooltip(_ rect: NSRect, _ text: String) {
        let tag = addToolTip(rect, owner: self, userData: nil)
        tooltipStrings[tag] = text
    }

    override var isFlipped: Bool { true }

    private func invalidate() {
        cache = nil
        needsDisplay = true
        invalidateIntrinsicContentSize()
        // Refresh source/status tooltips even when geometry did not change.
        if window != nil { updateTrackingAreas() }
    }

    /// Today's models folded to the donut's slices, so a dot here is the same
    /// colour as that model's segment in the chart popover.
    private var slices: [ChartDatum] { chartSlices(data.models, metric: .tokens) }

    // Keep the existing sections in place while loading/empty, rather than
    // inserting them later and shifting everything under the pointer.
    private var hasBoard: Bool { true }
    private var hasWeekBars: Bool { true }

    /// Only a submit outcome earns the badge. A background notice — an update
    /// check, say — stays on the timestamp line as plain grey text, which is where
    /// it never interrupted anything.
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
        let cardPad: CGFloat = 12
        let cardInner = inner - cardPad * 2
        var l = PanelLayout()
        var y: CGFloat = 14

        // Header: teal bolt badge + @handle on left, two crisp icon buttons on right
        l.gear = NSRect(x: w - pad - 26, y: y - 2, width: 26, height: 26)
        l.history = NSRect(x: l.gear.minX - 32, y: y - 2, width: 26, height: 26)
        l.title = NSRect(x: pad, y: y, width: l.history.minX - pad - 8, height: 22)
        y += 32

        // Hero Telemetry Card
        let heroTop = y
        let hx = pad + cardPad
        l.heroSub = NSRect(x: hx, y: y + 11, width: cardInner - 104, height: 15)
        l.heroCost = NSRect(x: pad + inner - cardPad - 100, y: y + 9, width: 100, height: 20)
        l.heroValue = NSRect(x: hx, y: y + 29, width: cardInner, height: 40)
        l.heroLocal = NSRect(x: hx, y: y + 76, width: cardInner, height: 18)
        l.hero = NSRect(x: pad, y: heroTop, width: inner, height: 102)
        y = l.hero.maxY + 10

        // Progress Card: Mini-Leaderboard Ladder + 7-Day Average in one unified telemetry card
        let progTop = y
        var py = progTop + 10
        let px = pad + cardPad
        if hasBoard {
            let swTitle = data.primaryMode == .today ? t("board.switchToAll") : t("board.switchToToday")
            let swW = max(46, ceil(measure(swTitle, font: NSFont.systemFont(ofSize: 10, weight: .semibold)).width) + 22)
            l.boardSwitch = NSRect(x: px + cardInner - swW, y: py - 1, width: swW, height: 18)
            l.boardCaption = NSRect(x: px, y: py, width: cardInner - swW - 8, height: 16)
            l.boardRank = l.boardCaption
            py += 23

            let rowCount = leaderboardLadderEntries().count
            if rowCount > 0 {
                let rowH: CGFloat = 24
                l.boardRows = (0..<rowCount).map {
                    NSRect(x: pad + 6, y: py + CGFloat($0) * rowH,
                           width: inner - 12, height: rowH - 2)
                }
                py += CGFloat(rowCount) * rowH + 4
            } else {
                l.boardEmpty = NSRect(x: px, y: py, width: cardInner, height: 18)
                py += 22
            }
            l.progressDividerY = py
            py += 9
        }
        l.avgCaption = NSRect(x: px, y: py + 1, width: cardInner - 98, height: 15)
        l.avgValue = NSRect(x: px + cardInner - 98, y: py, width: 98, height: 16)
        py += 19
        l.avgTrack = NSRect(x: px, y: py, width: cardInner, height: 6)
        py += 10
        l.avgSub = NSRect(x: px, y: py, width: cardInner, height: 15)
        py += 23
        l.progressCard = NSRect(x: pad, y: progTop, width: inner, height: py - progTop)
        y = l.progressCard.maxY + 10

        // Dual KPI Cards
        let cardW = (inner - 10) / 2
        l.cards = [NSRect(x: pad, y: y, width: cardW, height: 66),
                   NSRect(x: pad + cardW + 10, y: y, width: cardW, height: 66)]
        y += 66 + 10

        // 7-Day Activity Card (header + chart unified inside one card)
        if hasWeekBars {
            let weekTop = y
            l.weekCaption = NSRect(x: px, y: weekTop + 10, width: cardInner - 150, height: 15)
            l.weekValue = NSRect(x: px + cardInner - 150, y: weekTop + 9, width: 150, height: 16)
            l.barArea = NSRect(x: px, y: weekTop + 34, width: cardInner, height: 42)
            l.barLabels = NSRect(x: px, y: weekTop + 80, width: cardInner, height: 15)
            let colW = l.barArea.width / 7
            l.barColumns = (0..<7).map {
                NSRect(x: l.barArea.minX + CGFloat($0) * colW, y: weekTop + 28,
                       width: colW, height: 69)
            }
            l.weekCard = NSRect(x: pad, y: weekTop, width: inner, height: 104)
            y = l.weekCard.maxY + 10
        }

        // Month & Streak Card
        if data.monthCost > 0 || data.activeDays > 0 {
            let mTop = y
            var my = mTop + 10
            if data.monthCost > 0 {
                l.monthCaption = NSRect(x: px, y: my + 1, width: cardInner - 158, height: 15)
                l.monthValue = NSRect(x: px + cardInner - 158, y: my, width: 158, height: 16)
                my += 19
                if data.monthProjection > 0 {
                    l.monthProj = NSRect(x: px, y: my, width: cardInner, height: 15)
                    my += 19
                }
            }
            if data.activeDays > 0 {
                if data.monthCost > 0 { my += 3 }
                l.activeLine = NSRect(x: px, y: my, width: cardInner, height: 18)
                my += 20
            }
            if data.budgetSeverity > 0 {
                my += 3
                l.budgetLine = NSRect(x: px, y: my, width: cardInner, height: 18)
                my += 20
            }
            my += 7
            l.monthCard = NSRect(x: pad, y: mTop, width: inner, height: my - mTop)
            y = l.monthCard.maxY + 10
        }

        // Today's Models Card (with inline proportional bars)
        do {
            let modTop = y
            l.modelCaption = NSRect(x: px, y: modTop + 10, width: cardInner - 92, height: 15)
            l.modelValue = NSRect(x: px + cardInner - 92, y: modTop + 10, width: 92, height: 15)
            let rowStartY = modTop + 31
            let rowH: CGFloat = 23
            l.modelRows = slices.indices.map {
                NSRect(x: pad + 6, y: rowStartY + CGFloat($0) * rowH,
                       width: inner - 12, height: rowH - 2)
            }
            let contentH = max(1, CGFloat(slices.count)) * rowH
            l.modelsCard = NSRect(x: pad, y: modTop, width: inner, height: 31 + contentH + 8)
            y = l.modelsCard.maxY + 10
        }

        // Footer: subtle hint + timestamp/notice + sleek Submit button
        l.hint = NSRect(x: pad + 2, y: y, width: inner - 4, height: 16)
        y += 22

        let submitTitle = data.busy ? t("panel.submitting") : t("panel.submit")
        let submitW = max(84, ceil(measure(submitTitle, font: buttonFont).width) + 42)
        l.submit = NSRect(x: w - pad - submitW, y: y, width: submitW, height: 26)
        l.stamp = NSRect(x: pad + 2, y: y + 6, width: inner - submitW - 12, height: 14)
        if hasNotice {
            let room = inner - submitW - 10
            let width = min(room, ceil(measure(data.transient ?? "", font: badgeFont).width) + 36)
            l.notice = NSRect(x: pad, y: y + 2, width: width, height: 22)
        }
        y += 26 + 14

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
        func add(_ rect: NSRect, _ action: PanelAction, grow: Bool = true) {
            out.append((grow ? rect.insetBy(dx: -4, dy: -3) : rect, action))
        }
        add(l.title, .profile)
        add(l.history, .history, grow: false)
        add(l.gear, .menuPage, grow: false)
        add(l.hero, .chart(.today), grow: false)
        if hasBoard && l.boardSwitch != .zero {
            add(l.boardSwitch, .setRank(secondaryMode), grow: false)
        }
        if let card = l.cards.first, data.secondary != nil {
            add(card, .chart(secondaryMode == .allTime ? .lifetime : .today), grow: false)
        }
        if hasWeekBars {
            add(l.weekCard, .history, grow: false)
        }
        if !l.modelRows.isEmpty {
            add(l.modelsCard, .chart(.today), grow: false)
        }
        if data.canSubmit && !data.busy { add(l.submit, .submit, grow: false) }
        return out
    }

    private var secondaryMode: RankMode {
        data.primaryMode == .today ? .allTime : .today
    }

    // MARK: Fonts and paint

    private let heroFont = NSFont.monospacedDigitSystemFont(ofSize: 33, weight: .bold)
    private let titleFont = NSFont.systemFont(ofSize: 13.5, weight: .semibold)
    private let valueFont = NSFont.monospacedDigitSystemFont(ofSize: 14, weight: .semibold)
    private let cardFont = NSFont.monospacedDigitSystemFont(ofSize: 15.5, weight: .semibold)
    private let bodyFont = NSFont.systemFont(ofSize: 12, weight: .medium)
    private let smallFont = NSFont.systemFont(ofSize: 11)
    private let captionFont = NSFont.systemFont(ofSize: 10, weight: .semibold)
    private let buttonFont = NSFont.systemFont(ofSize: 12, weight: .semibold)
    /// Semibold, and only a point smaller than the button it sits beside: the line
    /// reporting on a press should not be lighter than the thing that was pressed.
    private let badgeFont = NSFont.systemFont(ofSize: 11, weight: .semibold)

    /// Uppercase reads as a label in English; Chinese has no case, so it is left
    /// alone rather than being spaced out artificially.
    private func caption(_ s: String) -> String {
        L10n.current == .zh ? s : s.uppercased()
    }

    /// A track with a gradient-filled head. The head keeps a minimum width so a
    /// tiny but non-zero share still reads as progress rather than as nothing.
    private func bar(_ rect: NSRect, progress: CGFloat, colour: NSColor,
                     gradientTo endColour: NSColor? = nil) {
        let r = rect.height / 2
        fill(rect, radius: r, colour: panelTrack)
        let p = min(1, max(0, progress))
        guard p > 0 else { return }
        let filled = NSRect(x: rect.minX, y: rect.minY,
                            width: max(rect.height, rect.width * p), height: rect.height)
        if let endColour {
            fillGradient(filled, radius: r, from: colour, to: endColour, angle: 0)
        } else {
            fill(filled, radius: r, colour: colour)
        }
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
        guard let i = hoveredHit, hits.indices.contains(i) else {
            if let error = data.serverError { return error }
            if data.serverLoading { return t(data.hasServer ? "panel.refreshing" : "panel.loading") }
            if data.isStale { return t("stamp.stale") }
            return t("panel.hint")
        }
        switch hits[i].1 {
        case .profile: return t("hint.profile")
        case .menuPage: return t("hint.menu")
        case .history: return t("hint.contrib")
        case .chart(let scope):
            return scope == .today ? t("hint.chartToday") : t("hint.chartLifetime")
        case .setRank: return t("hint.switchBoard")
        case .submit: return t("hint.submit")
        default: return t("panel.hint")
        }
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        let l = geometry()
        hits = regions(l)
        let accent = tokensAccent

        drawHeader(l)
        drawHero(l)
        drawProgressCard(l, accent: accent)
        drawCards(l)
        if hasWeekBars { drawWeek(l, accent: accent) }
        if data.monthCost > 0 || data.activeDays > 0 { drawMonth(l, accent: accent) }
        drawModels(l)
        drawFooter(l, accent: accent)
        // apple-design: instant press feedback; commit remains on release.
        if let rect = pressedRect {
            let r: CGFloat = rect.height > 40 ? 11 : 8
            fill(rect, radius: r, colour: accent.withAlphaComponent(0.14))
            stroke(rect, radius: r, colour: accent.withAlphaComponent(0.42), width: 1)
        }
    }

    private func drawHeader(_ l: PanelLayout) {
        let titleHovered = hoveredRect == l.title.insetBy(dx: -4, dy: -3)
        if titleHovered {
            fill(l.title.insetBy(dx: -4, dy: -3), radius: 8, colour: panelHover)
        }
        let name = data.username.isEmpty ? t("state.notLoggedIn") : "@" + data.username
        // Soft teal rounded badge behind the bolt glyph
        let badge = NSRect(x: l.title.minX, y: l.title.minY, width: 22, height: 22)
        fill(badge, radius: 6, colour: tokensAccent.withAlphaComponent(0.16))
        stroke(badge, radius: 6, colour: tokensAccent.withAlphaComponent(0.28), width: 0.75)
        icon("bolt.fill", in: badge, size: 11, colour: tokensAccentInk)

        let nameRect = NSRect(x: l.title.minX + 29, y: l.title.minY + 2,
                              width: l.title.width - 29, height: 18)
        text(name, in: nameRect, font: titleFont)
        chevron(after: name, font: titleFont, in: nameRect)

        for (rect, sym) in [(l.history, "calendar"), (l.gear, "ellipsis")] {
            let isHov = hoveredRect == rect
            fill(rect, radius: 7, colour: isHov ? panelSurfaceHover : panelSurface)
            stroke(rect, radius: 7, colour: panelBorder, width: 0.75)
            icon(sym, in: rect, size: 12.5,
                 colour: isHov ? .labelColor : .secondaryLabelColor)
        }
    }

    /// The submit outcome, as a tinted pill where the timestamp usually goes.
    private func drawNotice(_ l: PanelLayout) {
        guard let message = data.transient else { return }
        let ok = data.noticeKind == .success
        let tint: NSColor = ok ? .systemGreen : .systemRed
        let isDark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let ink = isDark ? tint : (tint.blended(withFraction: 0.4, of: .black) ?? tint)
        let radius = l.notice.height / 2
        fill(l.notice, radius: radius, colour: tint.withAlphaComponent(0.16))
        stroke(l.notice, radius: radius, colour: ink.withAlphaComponent(0.55), width: 1)
        icon(ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
             in: NSRect(x: l.notice.minX + 8, y: l.notice.midY - 7, width: 14, height: 14),
             size: 11, colour: ink)
        text(message,
             in: NSRect(x: l.notice.minX + 26, y: l.notice.midY - 7,
                        width: l.notice.width - 34, height: 14),
             font: badgeFont, colour: ink)
    }

    private func drawHero(_ l: PanelLayout) {
        drawCard(l.hero, radius: 12, hovered: hoveredRect == l.hero, hero: true)
        let available = data.todayIsServer || (data.hasLocal && !data.localFailed)

        // Top-left caption + chevron
        let cap = caption(data.todayIsServer ? t("panel.todayAll") : t("panel.todayLocalOnly"))
        text(cap, in: l.heroSub, font: captionFont, colour: tokensAccentInk)
        chevron(after: cap, font: captionFont, in: l.heroSub,
                colour: tokensAccentInk.withAlphaComponent(0.7))

        // Top-right cost pill badge (turns amber/red when over daily budget)
        let costText = available ? "≈" + fmtMoney(data.todayCost) : "—"
        let costFont = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        let costW = min(l.heroCost.width, max(44, ceil(measure(costText, font: costFont).width) + 16))
        let costPill = NSRect(x: l.heroCost.maxX - costW, y: l.heroCost.minY,
                              width: costW, height: 20)
        let pillFill: NSColor
        let pillInk: NSColor
        let pillStroke: NSColor
        switch data.budgetSeverity {
        case 2:
            pillFill = NSColor.systemRed.withAlphaComponent(0.16)
            pillInk = .systemRed
            pillStroke = NSColor.systemRed.withAlphaComponent(0.45)
        case 1:
            pillFill = NSColor.systemOrange.withAlphaComponent(0.16)
            pillInk = .systemOrange
            pillStroke = NSColor.systemOrange.withAlphaComponent(0.45)
        default:
            pillFill = panelSurface
            pillInk = .secondaryLabelColor
            pillStroke = panelBorder
        }
        fill(costPill, radius: 10, colour: pillFill)
        stroke(costPill, radius: 10, colour: pillStroke, width: 0.75)
        text(costText, in: NSRect(x: costPill.minX, y: costPill.minY + 2.5,
                                  width: costPill.width, height: 15),
             font: costFont, colour: pillInk, align: .center)

        // Hero big token number
        text(available ? fmtTokens(data.todayTokens) : "—", in: l.heroValue, font: heroFont)

        // Subtle divider above local live strip
        fill(NSRect(x: l.hero.minX + 12, y: l.heroLocal.minY - 5,
                    width: l.hero.width - 24, height: 0.75),
             radius: 0, colour: panelRule)

        // Live local strip + optional cache hit pill on right
        var localRight = l.heroLocal.maxX
        if let hit = data.todayCacheRate, data.todayIsServer {
            let hitStr = t("panel.cacheHit", Int((hit * 100).rounded()))
            let hitFont = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .semibold)
            let hw = ceil(measure(hitStr, font: hitFont).width) + 12
            let hRect = NSRect(x: localRight - hw, y: l.heroLocal.minY + 1, width: hw, height: 16)
            fill(hRect, radius: 8, colour: tokensAccent.withAlphaComponent(0.14))
            text(hitStr, in: NSRect(x: hRect.minX, y: hRect.minY + 1.5, width: hw, height: 13),
                 font: hitFont, colour: tokensAccentInk, align: .center)
            localRight = hRect.minX - 6
        }

        icon("laptopcomputer",
             in: NSRect(x: l.heroLocal.minX, y: l.heroLocal.minY + 2, width: 13, height: 13),
             size: 10, colour: .secondaryLabelColor)
        let sub: String
        if data.localFailed {
            sub = t("panel.localFailed")
        } else if !data.hasLocal {
            sub = t("panel.localLoading")
        } else if data.todayIsServer {
            sub = t("panel.thisMac", fmtTokens(data.localTokens), fmtMoney(data.localCost))
        } else if data.hasServer {
            sub = t("panel.awaitingSubmit")
        } else {
            sub = t("panel.localFallback")
        }
        text(sub, in: NSRect(x: l.heroLocal.minX + 17, y: l.heroLocal.minY + 2,
                             width: max(40, localRight - l.heroLocal.minX - 17), height: 15),
             font: smallFont, colour: .secondaryLabelColor)
    }

    private func drawProgressCard(_ l: PanelLayout, accent: NSColor) {
        drawCard(l.progressCard, radius: 11)
        if hasBoard {
            drawBoard(l, accent: accent)
            fill(NSRect(x: l.progressCard.minX + 12, y: l.progressDividerY,
                        width: l.progressCard.width - 24, height: 0.75),
                 radius: 0, colour: panelRule)
        }
        drawAverage(l, accent: accent)
    }

    private struct LadderEntry {
        let rank: Int
        let username: String
        let tokens: Int
        let delta: Int   // > 0 means ahead of you; < 0 means behind you; 0 = you
        let isSelf: Bool
    }

    private func leaderboardLadderEntries() -> [LadderEntry] {
        guard let st = data.primary, st.rank > 0 else { return [] }
        var out: [LadderEntry] = []
        if let above = st.above {
            out.append(LadderEntry(rank: above.rank, username: above.username,
                                   tokens: above.tokens,
                                   delta: max(0, above.tokens - st.tokens),
                                   isSelf: false))
        }
        out.append(LadderEntry(rank: st.rank,
                               username: data.username.isEmpty ? "you" : data.username,
                               tokens: st.tokens, delta: 0, isSelf: true))
        if let below = st.below {
            out.append(LadderEntry(rank: below.rank, username: below.username,
                                   tokens: below.tokens,
                                   delta: -max(0, st.tokens - below.tokens),
                                   isSelf: false))
        }
        return out
    }

    /// Mini-Leaderboard Ladder: shows the live 3-person race around the user
    /// (target directly above, self highlighted in teal, trailing rival below)
    /// plus percentile badge and a 1-click Today/All-time switcher.
    private func drawBoard(_ l: PanelLayout, accent: NSColor) {
        let st = data.primary
        // Left header: trophy icon + board label + #rank / total + Top XX% pill
        icon("trophy.fill",
             in: NSRect(x: l.boardCaption.minX, y: l.boardCaption.minY + 2, width: 12, height: 12),
             size: 10, colour: tokensAccentInk)
        let title = caption(data.primaryMode.label)
        let titleW = ceil(measure(title, font: captionFont).width)
        text(title,
             in: NSRect(x: l.boardCaption.minX + 16, y: l.boardCaption.minY + 1,
                        width: titleW + 4, height: 14),
             font: captionFont, colour: .secondaryLabelColor)

        var cursorX = l.boardCaption.minX + 16 + titleW + 8
        let rankStr: String
        if let st {
            rankStr = st.rank > 0 ? "#\(st.rank) / \(st.totalUsers)" : t("board.notRanked")
        } else {
            rankStr = "—"
        }
        let rankFont = NSFont.monospacedDigitSystemFont(ofSize: 12.5, weight: .semibold)
        let rankW = ceil(measure(rankStr, font: rankFont).width)
        text(rankStr,
             in: NSRect(x: cursorX, y: l.boardCaption.minY, width: rankW + 4, height: 16),
             font: rankFont, colour: .labelColor)
        cursorX += rankW + 7

        if let st, st.rank > 0, st.totalUsers > 0 {
            let pct = max(1, min(100, Int((Double(st.rank) / Double(st.totalUsers) * 100).rounded(.up))))
            let pctStr = t("board.topPct", pct)
            let pctFont = NSFont.monospacedDigitSystemFont(ofSize: 9.5, weight: .semibold)
            let pw = ceil(measure(pctStr, font: pctFont).width) + 10
            if cursorX + pw <= l.boardSwitch.minX - 6 {
                let pRect = NSRect(x: cursorX, y: l.boardCaption.minY, width: pw, height: 16)
                fill(pRect, radius: 8, colour: accent.withAlphaComponent(0.13))
                text(pctStr, in: NSRect(x: pRect.minX, y: pRect.minY + 2, width: pw, height: 12),
                     font: pctFont, colour: tokensAccentInk, align: .center)
            }
        }

        // Right header: 1-click board switcher pill
        if l.boardSwitch != .zero {
            let isHov = hoveredRect == l.boardSwitch
            let swFont = NSFont.systemFont(ofSize: 10, weight: .semibold)
            let swTitle = data.primaryMode == .today ? t("board.switchToAll") : t("board.switchToToday")
            fill(l.boardSwitch, radius: 9,
                 colour: isHov ? accent.withAlphaComponent(0.18) : panelCard)
            stroke(l.boardSwitch, radius: 9,
                   colour: isHov ? accent.withAlphaComponent(0.45) : panelBorder, width: 0.75)
            icon("arrow.left.arrow.right",
                 in: NSRect(x: l.boardSwitch.minX + 6, y: l.boardSwitch.midY - 5, width: 10, height: 10),
                 size: 8.5, colour: isHov ? tokensAccentInk : .secondaryLabelColor)
            text(swTitle,
                 in: NSRect(x: l.boardSwitch.minX + 17, y: l.boardSwitch.minY + 2.5,
                            width: l.boardSwitch.width - 21, height: 13),
                 font: swFont, colour: isHov ? tokensAccentInk : .secondaryLabelColor, align: .center)
        }

        // Ladder rows or empty state
        let entries = leaderboardLadderEntries()
        guard !entries.isEmpty else {
            let msg: String
            if let st, st.rank == 0 {
                msg = t("panel.notSubmitted")
            } else {
                msg = t(data.hasServer ? "panel.rankUnknown" : "panel.waitingServer")
            }
            text(msg, in: l.boardEmpty, font: smallFont, colour: .secondaryLabelColor)
            return
        }

        let numFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        let selfNumFont = NSFont.monospacedDigitSystemFont(ofSize: 11.5, weight: .semibold)
        let deltaFont = NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .medium)
        let rankColFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold)

        for (idx, entry) in entries.enumerated() where l.boardRows.indices.contains(idx) {
            let row = l.boardRows[idx]
            if entry.isSelf {
                fill(row, radius: 7, colour: accent.withAlphaComponent(0.14))
                stroke(row, radius: 7, colour: accent.withAlphaComponent(0.32), width: 0.75)
                // Crisp left teal accent pill bar marking your position
                fill(NSRect(x: row.minX + 3, y: row.minY + 4, width: 2.5, height: row.height - 8),
                     radius: 1.25, colour: tokensAccentBright)
            }

            // Rank column (#242)
            let rankLabel = entry.rank == 1 && entry.isSelf ? "👑#1" : "#\(entry.rank)"
            text(rankLabel,
                 in: NSRect(x: row.minX + 9, y: row.midY - 7, width: 42, height: 15),
                 font: rankColFont,
                 colour: entry.isSelf ? tokensAccentInk : .secondaryLabelColor)

            // Right-aligned delta badge (+298.7K / 你 / −412K) and tokens column
            let deltaWidth: CGFloat = 58
            let tokWidth: CGFloat = 56
            let deltaRect = NSRect(x: row.maxX - deltaWidth - 6, y: row.midY - 7,
                                   width: deltaWidth, height: 15)
            let tokRect = NSRect(x: deltaRect.minX - tokWidth - 4, y: row.midY - 7,
                                 width: tokWidth, height: 15)
            let nameX = row.minX + 52
            let nameRect = NSRect(x: nameX, y: row.midY - 7.5,
                                  width: max(40, tokRect.minX - nameX - 4), height: 16)

            text("@" + entry.username, in: nameRect,
                 font: NSFont.systemFont(ofSize: 11.5, weight: entry.isSelf ? .semibold : .regular),
                 colour: entry.isSelf ? .labelColor : .secondaryLabelColor)

            text(fmtTokens(entry.tokens), in: tokRect,
                 font: entry.isSelf ? selfNumFont : numFont,
                 colour: entry.isSelf ? .labelColor : .secondaryLabelColor,
                 align: .right)

            if entry.isSelf {
                let you = t("board.you")
                let yFont = NSFont.systemFont(ofSize: 10, weight: .semibold)
                let yw = max(24, ceil(measure(you, font: yFont).width) + 12)
                let yPill = NSRect(x: deltaRect.maxX - yw, y: row.midY - 7.5, width: yw, height: 15)
                fill(yPill, radius: 7.5, colour: accent)
                text(you, in: NSRect(x: yPill.minX, y: yPill.minY + 1, width: yw, height: 13),
                     font: yFont, colour: onAccent(accent), align: .center)
            } else if entry.delta > 0 {
                text("+" + fmtTokens(entry.delta), in: deltaRect,
                     font: deltaFont, colour: .systemOrange, align: .right)
            } else if entry.delta < 0 {
                text("−" + fmtTokens(-entry.delta), in: deltaRect,
                     font: deltaFont, colour: tokensAccentInk.withAlphaComponent(0.85), align: .right)
            } else {
                text("±0", in: deltaRect, font: deltaFont, colour: .tertiaryLabelColor, align: .right)
            }
        }
    }

    /// Today against the seven days before it. The track spans twice the average
    /// so the midpoint tick is "an average day" and passing it is visible.
    private func drawAverage(_ l: PanelLayout, accent: NSColor) {
        let avg = data.todayIsServer ? data.avgTokens : 0
        let ratio = avg > 0 ? Double(data.todayTokens) / avg : 0
        let target = CGFloat(min(1, max(0, ratio / 2)))
        let shown = avgDisplayProgress ?? target

        text(caption(t("panel.vsAvg")), in: l.avgCaption, font: captionFont,
             colour: .secondaryLabelColor)
        let value: String
        if avg <= 0 { value = "—" }
        else if ratio >= 1 { value = t("panel.avgMultiple", String(format: "%.1f", ratio)) }
        else { value = t("panel.avgPercent", Int((ratio * 100).rounded())) }
        text(value, in: l.avgValue,
             font: .monospacedDigitSystemFont(ofSize: 11, weight: .semibold),
             colour: ratio >= 1 ? tokensAccentInk : .secondaryLabelColor, align: .right)

        let startCol = shown >= 0.5 ? accent : accent.withAlphaComponent(0.60)
        let endCol = shown >= 0.5 ? tokensAccentBright : tokensAccentBright.withAlphaComponent(0.85)
        bar(l.avgTrack, progress: shown, colour: startCol, gradientTo: endCol)

        // Animated leading-edge sheen & one-shot specular highlight sweep
        if shown > 0.01, let cg = NSGraphicsContext.current?.cgContext {
            let r = l.avgTrack.height / 2
            let fillW = max(l.avgTrack.height, l.avgTrack.width * shown)
            let filled = NSRect(x: l.avgTrack.minX, y: l.avgTrack.minY,
                                width: fillW, height: l.avgTrack.height)
            cg.saveGState()
            NSBezierPath(roundedRect: filled, xRadius: r, yRadius: r).addClip()
            if avgShimmerPhase >= 0 && avgShimmerPhase <= 1 {
                let bandW = max(24, filled.width * 0.34)
                let sweepX = filled.minX - bandW + (filled.width + bandW * 2) * avgShimmerPhase
                let band = NSRect(x: sweepX, y: filled.minY, width: bandW, height: filled.height)
                if let grad = NSGradient(colors: [
                    NSColor.white.withAlphaComponent(0.0),
                    NSColor.white.withAlphaComponent(0.38),
                    NSColor.white.withAlphaComponent(0.0),
                ]) {
                    grad.draw(in: band, angle: 0)
                }
            }
            // Subtle luminous cap on the moving tip while gliding in
            if avgAnimTimer != nil && avgShimmerPhase < 0 {
                let tipW = min(14, filled.width * 0.4)
                let tip = NSRect(x: filled.maxX - tipW, y: filled.minY,
                                 width: tipW, height: filled.height)
                if let grad = NSGradient(starting: NSColor.white.withAlphaComponent(0.0),
                                         ending: NSColor.white.withAlphaComponent(0.42)) {
                    grad.draw(in: tip, angle: 0)
                }
            }
            cg.restoreGState()
        }

        if avg > 0 {
            fill(NSRect(x: l.avgTrack.midX - 0.75, y: l.avgTrack.minY - 2,
                        width: 1.5, height: l.avgTrack.height + 4),
                 radius: 0.75,
                 colour: shown >= 0.5 ? tokensAccentBright : .tertiaryLabelColor)
        }
        text(avg > 0 ? t("panel.avgBest", fmtTokens(Int(avg.rounded())), fmtTokens(data.bestTokens))
                       : t("panel.avgUnavailable"),
             in: l.avgSub, font: smallFont, colour: .secondaryLabelColor)
    }

    private func card(_ rect: NSRect, symbol: String, caption cap: String, value: String,
                      sub: String, clickable: Bool = false) {
        drawCard(rect, radius: 11, hovered: clickable && hoveredRect == rect)
        let x = rect.minX + 11, w = rect.width - 22
        icon(symbol, in: NSRect(x: x, y: rect.minY + 9, width: 12, height: 12),
             size: 9.5, colour: tokensAccentInk.withAlphaComponent(0.85))
        text(cap, in: NSRect(x: x + 16, y: rect.minY + 8, width: w - (clickable ? 26 : 16), height: 14),
             font: captionFont, colour: .secondaryLabelColor)
        if clickable {
            icon("chevron.right",
                 in: NSRect(x: rect.maxX - 18, y: rect.minY + 9, width: 9, height: 12),
                 size: 8, colour: .tertiaryLabelColor)
        }
        text(value, in: NSRect(x: x, y: rect.minY + 25, width: w, height: 20), font: cardFont)
        text(sub, in: NSRect(x: x, y: rect.minY + 45, width: w, height: 15),
             font: smallFont, colour: .secondaryLabelColor)
    }

    private func drawCards(_ l: PanelLayout) {
        guard l.cards.count == 2 else { return }
        if let st = data.secondary {
            card(l.cards[0], symbol: "trophy.fill", caption: caption(secondaryMode.label),
                 value: st.rank > 0 ? "#\(st.rank) / \(st.totalUsers)" : t("board.notRanked"),
                 sub: fmtTokens(st.tokens), clickable: true)
        } else {
            card(l.cards[0], symbol: "sparkles", caption: caption(t("row.lifetime")),
                 value: data.hasServer ? fmtTokens(data.lifetimeTokens) : "—",
                 sub: data.hasServer ? "≈" + fmtMoney(data.lifetimeCost)
                                     : t("panel.waitingServer"))
        }
        card(l.cards[1], symbol: "clock.fill", caption: caption(t("panel.weekLocal")),
             value: data.localFailed || !data.hasLocal ? "—" : fmtTokens(data.weekTokens),
             sub: data.localFailed ? t("panel.localFailed")
                : !data.hasLocal ? t("panel.localLoading") : "≈" + fmtMoney(data.weekCost))
    }

    /// Month summary, projection, active days + flame streak badge, and budget alert
    /// grouped in one elevated card.
    private func drawMonth(_ l: PanelLayout, accent: NSColor) {
        drawCard(l.monthCard, radius: 11)
        if l.monthCaption != .zero {
            icon("calendar",
                 in: NSRect(x: l.monthCaption.minX, y: l.monthCaption.minY + 1, width: 12, height: 12),
                 size: 9.5, colour: tokensAccentInk.withAlphaComponent(0.85))
            text(caption(t("row.month")),
                 in: NSRect(x: l.monthCaption.minX + 16, y: l.monthCaption.minY,
                            width: l.monthCaption.width - 16, height: l.monthCaption.height),
                 font: captionFont, colour: .secondaryLabelColor)
        }
        if l.monthValue != .zero {
            let value = "\(fmtTokens(data.monthTokens))  ·  ≈\(fmtMoney(data.monthCost))"
            text(value, in: l.monthValue,
                 font: .monospacedDigitSystemFont(ofSize: 11.5, weight: .semibold),
                 colour: .labelColor, align: .right)
        }
        if l.monthProj != .zero {
            icon("chart.line.uptrend.xyaxis",
                 in: NSRect(x: l.monthProj.minX, y: l.monthProj.minY + 1, width: 12, height: 12),
                 size: 9.5, colour: .secondaryLabelColor)
            let raw = t("month.projected", fmtMoney(data.monthProjection))
                .replacingOccurrences(of: "↳ ", with: "")
            text(raw,
                 in: NSRect(x: l.monthProj.minX + 16, y: l.monthProj.minY,
                            width: l.monthProj.width - 16, height: l.monthProj.height),
                 font: smallFont, colour: .secondaryLabelColor)
        }
        if l.activeLine != .zero {
            if data.monthCost > 0 {
                fill(NSRect(x: l.monthCard.minX + 12, y: l.activeLine.minY - 4,
                            width: l.monthCard.width - 24, height: 0.75),
                     radius: 0, colour: panelRule)
            }
            icon("checkmark.seal.fill",
                 in: NSRect(x: l.activeLine.minX, y: l.activeLine.minY + 2, width: 12, height: 12),
                 size: 10, colour: tokensAccentInk)
            let activeOnly = t("panel.activeDays", data.activeDays)
            var rightBound = l.activeLine.maxX
            if data.currentStreak >= 2 {
                let streakText = L10n.current == .zh
                    ? "连续 \(data.currentStreak) 天"
                    : "\(data.currentStreak)d streak"
                let sFont = NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .semibold)
                let sw = ceil(measure(streakText, font: sFont).width) + 26
                let pill = NSRect(x: rightBound - sw, y: l.activeLine.minY, width: sw, height: 18)
                let flameOrange = NSColor.systemOrange
                fill(pill, radius: 9, colour: flameOrange.withAlphaComponent(0.14))
                stroke(pill, radius: 9, colour: flameOrange.withAlphaComponent(0.35), width: 0.75)
                icon("flame.fill",
                     in: NSRect(x: pill.minX + 6, y: pill.minY + 3, width: 11, height: 11),
                     size: 9.5, colour: flameOrange)
                text(streakText,
                     in: NSRect(x: pill.minX + 19, y: pill.minY + 2, width: sw - 24, height: 14),
                     font: sFont, colour: flameOrange)
                rightBound = pill.minX - 6
            }
            text(activeOnly,
                 in: NSRect(x: l.activeLine.minX + 16, y: l.activeLine.minY + 2,
                            width: max(40, rightBound - l.activeLine.minX - 16), height: 15),
                 font: smallFont, colour: .secondaryLabelColor)
        }
        if l.budgetLine != .zero {
            let tint: NSColor = data.budgetSeverity >= 2 ? .systemRed : .systemOrange
            fill(l.budgetLine, radius: 6, colour: tint.withAlphaComponent(0.12))
            text(t("budget.over", fmtMoney(data.todayCost), fmtMoney(data.dailyBudget)),
                 in: NSRect(x: l.budgetLine.minX + 8, y: l.budgetLine.minY + 2,
                            width: l.budgetLine.width - 16, height: 14),
                 font: .systemFont(ofSize: 11, weight: .medium), colour: tint)
        }
    }

    private func drawWeek(_ l: PanelLayout, accent: NSColor) {
        let days = data.recent
        guard days.count == l.barColumns.count else { return }
        drawCard(l.weekCard, radius: 11, hovered: hoveredRect == l.weekCard)

        let cap = caption(t("panel.last7UTC"))
        text(cap, in: l.weekCaption, font: captionFont, colour: .secondaryLabelColor)
        chevron(after: cap, font: captionFont, in: l.weekCaption)

        ensureWeekFormatters()
        let short = weekShortFmt
        let narrow = weekNarrowFmt

        let summary: String
        if let i = hoveredDay, days.indices.contains(i) {
            let d = days[i]
            summary = "\(short.string(from: d.date))  ·  \(fmtTokens(d.tokens))  ·  \(fmtMoney(d.cost))"
        } else {
            summary = "\(fmtTokens(days.reduce(0) { $0 + $1.tokens }))  ·  "
                + fmtMoney(days.reduce(0.0) { $0 + $1.cost })
        }
        text(data.hasServer ? summary : "—", in: l.weekValue,
             font: .monospacedDigitSystemFont(ofSize: 11, weight: .semibold),
             colour: hoveredDay != nil ? tokensAccentInk : .secondaryLabelColor, align: .right)

        // Subtle mid & baseline reference lines
        fill(NSRect(x: l.barArea.minX, y: l.barArea.midY, width: l.barArea.width, height: 0.5),
             radius: 0, colour: panelCard)
        fill(NSRect(x: l.barArea.minX, y: l.barArea.maxY, width: l.barArea.width, height: 0.75),
             radius: 0, colour: panelRule)

        let peak = max(1, days.map(\.tokens).max() ?? 1)
        for (i, day) in days.enumerated() {
            let col = l.barColumns[i]
            let isToday = i == days.count - 1
            let hovering = hoveredDay == i
            if hovering {
                fill(col.insetBy(dx: 2, dy: 0), radius: 6, colour: panelHover)
            }
            let barW = min(22, col.width - 10)
            let h = day.tokens > 0 ? max(4, l.barArea.height * CGFloat(day.tokens) / CGFloat(peak)) : 2
            let barRect = NSRect(x: col.midX - barW / 2, y: l.barArea.maxY - h, width: barW, height: h)
            if day.tokens == 0 {
                fill(barRect, radius: 1, colour: panelTrack)
            } else if hovering || isToday {
                fillGradient(barRect, radius: 4, from: tokensAccentBright, to: accent, angle: 90)
            } else {
                fillGradient(barRect, radius: 4,
                             from: tokensAccentBright.withAlphaComponent(0.55),
                             to: accent.withAlphaComponent(0.38), angle: 90)
            }

            if isToday {
                let pill = NSRect(x: col.midX - 11, y: l.barLabels.minY, width: 22, height: 14)
                fill(pill, radius: 7, colour: accent.withAlphaComponent(0.16))
                text(narrow.string(from: day.date),
                     in: NSRect(x: pill.minX, y: pill.minY + 1, width: pill.width, height: 12),
                     font: .systemFont(ofSize: 9, weight: .semibold),
                     colour: tokensAccentInk, align: .center)
            } else {
                text(narrow.string(from: day.date),
                     in: NSRect(x: col.minX, y: l.barLabels.minY + 1, width: col.width, height: 13),
                     font: .systemFont(ofSize: 9, weight: hovering ? .semibold : .regular),
                     colour: hovering ? .labelColor : .secondaryLabelColor,
                     align: .center)
            }
        }
        if !data.hasServer || !data.recent.contains(where: { $0.tokens > 0 }) {
            text(t(data.hasServer ? "panel.emptyWeek" : "panel.waitingServer"),
                 in: l.barArea, font: smallFont, colour: .secondaryLabelColor, align: .center)
        }
    }

    private func drawModels(_ l: PanelLayout) {
        drawCard(l.modelsCard, radius: 11, hovered: hoveredRect == l.modelsCard)
        let s = slices
        let total = max(1.0, s.reduce(0.0) { $0 + Double($1.tokens) })
        let peak = max(1.0, s.map { Double($0.tokens) }.max() ?? 1.0)
        let cap = caption(t("panel.modelsToday"))
        text(cap, in: l.modelCaption, font: captionFont, colour: .secondaryLabelColor)
        chevron(after: cap, font: captionFont, in: l.modelCaption)
        text(caption(data.modelsAreServer ? t("panel.allDevices") : t("panel.thisMacOnly")),
             in: l.modelValue, font: captionFont, colour: .tertiaryLabelColor, align: .right)
        if s.isEmpty {
            text(t(data.hasServer ? "panel.noModels" : "panel.waitingServer"),
                 in: NSRect(x: l.modelCaption.minX, y: l.modelCaption.maxY + 8,
                            width: l.modelCaption.width + l.modelValue.width, height: 16),
                 font: smallFont, colour: .secondaryLabelColor)
        }
        for (i, slice) in s.enumerated() where l.modelRows.indices.contains(i) {
            let row = l.modelRows[i]
            let color = chartPalette[i % chartPalette.count]
            // Subtle proportional backdrop bar tinted by this model's palette color
            let shareW = max(18, row.width * CGFloat(Double(slice.tokens) / peak))
            fill(NSRect(x: row.minX, y: row.minY, width: shareW, height: row.height),
                 radius: 6, colour: color.withAlphaComponent(0.10))
            fill(NSRect(x: row.minX + 6, y: row.midY - 3.5, width: 7, height: 7),
                 radius: 3.5, colour: color)
            text(slice.label,
                 in: NSRect(x: row.minX + 20, y: row.midY - 8,
                            width: row.width - 130, height: 16),
                 font: bodyFont)
            text(fmtTokens(slice.tokens),
                 in: NSRect(x: row.maxX - 106, y: row.midY - 7, width: 60, height: 15),
                 font: .monospacedDigitSystemFont(ofSize: 11, weight: .regular),
                 colour: .secondaryLabelColor, align: .right)
            text(fmtShare(slice.tokens, total: total),
                 in: NSRect(x: row.maxX - 44, y: row.midY - 7, width: 38, height: 15),
                 font: .monospacedDigitSystemFont(ofSize: 11, weight: .semibold),
                 colour: .labelColor, align: .right)
        }
    }

    /// Foreground for the fixed dark-green accent fill.
    private func onAccent(_ accent: NSColor) -> NSColor {
        guard let rgb = accent.usingColorSpace(.sRGB) else { return .white }
        let luma = 0.2126 * rgb.redComponent + 0.7152 * rgb.greenComponent
            + 0.0722 * rgb.blueComponent
        return luma > 0.62 ? .black : .white
    }

    private func drawFooter(_ l: PanelLayout, accent: NSColor) {
        let hovering = hoveredHit.map { hits.indices.contains($0) } ?? false
        text(hintText, in: l.hint, font: smallFont,
             colour: hovering ? .labelColor
                : data.serverFailed ? .systemOrange : .secondaryLabelColor, wrap: false)

        if hasNotice {
            drawNotice(l)
        } else {
            let stamp: String
            if let transient = data.transient {
                stamp = transient
            } else {
                var bits: [String] = []
                if let d = data.serverFetchedAt { bits.append(t("stamp.fetched", fmtClock(d))) }
                else if let d = data.serverStamp { bits.append(t("stamp.server", fmtClock(d))) }
                if data.serverFailed { bits.append(t("panel.keptData")) }
                else if data.serverLoading { bits.append(t("panel.refreshingShort")) }
                else { bits.append(t("panel.estimated")) }
                stamp = bits.joined(separator: "  ·  ")
            }
            // Subtle pill backing keeps the footer stamp crisp on translucent popovers
            // even over dark or busy wallpapers.
            let sw = min(l.stamp.width, ceil(measure(stamp, font: smallFont).width) + 16)
            let pill = NSRect(x: l.stamp.minX - 2, y: l.stamp.minY - 3, width: sw, height: 20)
            fill(pill, radius: 10, colour: panelSurface)
            stroke(pill, radius: 10, colour: panelBorder, width: 0.5)
            text(stamp, in: NSRect(x: pill.minX + 8, y: pill.minY + 3, width: sw - 16, height: 14),
                 font: smallFont, colour: .secondaryLabelColor)
        }

        let onSubmit = hoveredHit.map { hits.indices.contains($0) && hits[$0].1 == .submit }
            ?? false
        let enabled = !data.busy && data.canSubmit
        if enabled {
            let top = onSubmit ? tokensAccentBright : accent
            let bot = onSubmit ? accent : accent
            fillGradient(l.submit, radius: 8, from: top, to: bot, angle: 90)
            stroke(l.submit, radius: 8, colour: NSColor.white.withAlphaComponent(0.18), width: 0.75)
        } else {
            fill(l.submit, radius: 8, colour: panelSurface)
            stroke(l.submit, radius: 8, colour: panelBorder, width: 0.75)
        }
        let fg = enabled ? onAccent(accent) : .secondaryLabelColor
        let title = data.busy ? t("panel.submitting") : t("panel.submit")
        let tw = ceil(measure(title, font: buttonFont).width)
        let groupW = 14 + 4 + tw
        let sx = l.submit.midX - groupW / 2
        icon(data.busy ? "arrow.triangle.2.circlepath" : "arrow.up.circle.fill",
             in: NSRect(x: sx, y: l.submit.midY - 6.5, width: 13, height: 13),
             size: 11, colour: fg)
        text(title,
             in: NSRect(x: sx + 17, y: l.submit.midY - 8, width: tw + 4, height: 16),
             font: buttonFont, colour: fg, align: .left)
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
        removeAllToolTips()
        tooltipStrings.removeAll()
        let l = geometry()
        var heroTip = t("panel.sourceDetail")
        if let hit = data.todayCacheRate {
            heroTip += "\n" + t("panel.cacheHit", Int((hit * 100).rounded()))
        }
        tooltip(l.hero, heroTip)
        var rankTip = t("panel.rankDetail")
        if let st = data.primary, let below = st.below, st.tokens >= below.tokens {
            rankTip += "\n" + t("panel.behindYou", below.rank, below.username,
                                fmtTokens(max(0, st.tokens - below.tokens)))
        }
        if let first = l.boardRows.first, let last = l.boardRows.last {
            tooltip(first.union(last), rankTip)
        }
        tooltip(l.avgTrack.union(l.avgSub), t("panel.avgDetail"))
        var status: [String] = []
        if let error = data.serverError { status.append(error) }
        if let d = data.serverAttemptedAt { status.append(t("stamp.attempted", fmtClock(d))) }
        if let d = data.serverFetchedAt { status.append(t("stamp.fetched", fmtClock(d))) }
        if let d = data.serverStamp { status.append(t("stamp.submitted", fmtClock(d))) }
        if let d = data.localStamp { status.append(t("stamp.local", fmtClock(d))) }
        tooltip(l.stamp.union(l.hint), status.joined(separator: "\n"))
        for (index, row) in l.modelRows.enumerated() where slices.indices.contains(index) {
            tooltip(row, slices[index].label)
        }
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

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let hit = regions(geometry()).first { $0.0.contains(p) }
        pressedAction = hit?.1
        pressedRect = hit?.0
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        // Dragging away cancels the highlight; returning restores it.
        pressedRect = regions(geometry()).first {
            $0.1 == pressedAction && $0.0.contains(p)
        }?.0
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let hit = regions(geometry()).first { $0.0.contains(p) }
        let action = pressedAction
        pressedAction = nil
        pressedRect = nil
        needsDisplay = true
        guard let hit, hit.1 == action else { return }
        if hit.1 == .submit && (data.busy || !data.canSubmit) { return }
        onAction?(hit.1)
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
    private var accessibilityObserver: NSObjectProtocol?

    override func draw(_ dirtyRect: NSRect) {
        // Native equivalent of reduced-transparency/contrast media queries.
        if NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
            || NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast {
            NSColor.windowBackgroundColor.setFill()
            bounds.fill()
        }
    }

    deinit {
        if let observer = accessibilityObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }

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
        accessibilityObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil, queue: .main) { [weak self] _ in
                self?.needsDisplay = true
                self?.main.needsDisplay = true
                self?.actions.needsDisplay = true
            }
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

    private var noticeOverlay: NSView?
    private var noticeHide: DispatchWorkItem?

    /// A frosted notice pinned to the top of the panel, over whatever page is
    /// showing, that fades out on its own after a few seconds. It sits inside the
    /// panel — not a window of its own — and may cover a little content while up.
    func flashNotice(_ message: String, kind: PanelNotice) {
        noticeHide?.cancel()
        noticeOverlay?.removeFromSuperview()

        let tint: NSColor = kind == .failure ? .systemRed
            : kind == .success ? .systemGreen : tokensAccentInk
        let isDark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let ink = isDark ? tint : (tint.blended(withFraction: 0.4, of: .black) ?? tint)
        let font = NSFont.systemFont(ofSize: 12.5, weight: .semibold)
        let hPad: CGFloat = 14, vPad: CGFloat = 10, margin: CGFloat = 10
        let textMax = bounds.width - margin * 2 - hPad * 2
        let b = (message as NSString).boundingRect(
            with: NSSize(width: textMax, height: 400),
            options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font])
        let w = min(ceil(b.width), textMax) + hPad * 2
        let h = max(30, ceil(b.height) + vPad * 2)

        let blur = NSVisualEffectView(frame: NSRect(x: (bounds.width - w) / 2, y: 8, width: w, height: h))
        blur.material = .popover
        let reducedMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
            || NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast {
            blur.blendingMode = .withinWindow
            blur.wantsLayer = true
            blur.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        }
        blur.blendingMode = .withinWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = 10
        blur.layer?.masksToBounds = true
        blur.layer?.borderWidth = 1
        blur.layer?.borderColor = tint.withAlphaComponent(0.5).cgColor

        let label = NSTextField(labelWithString: message)
        label.font = font
        label.textColor = ink
        label.alignment = .center
        label.maximumNumberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.frame = NSRect(x: hPad, y: vPad, width: w - hPad * 2, height: h - vPad * 2)
        label.autoresizingMask = [.width, .height]
        blur.addSubview(label)

        addSubview(blur, positioned: .above, relativeTo: nil)
        noticeOverlay = blur
        blur.alphaValue = reducedMotion ? 1 : 0
        if !reducedMotion {
            NSAnimationContext.runAnimationGroup { $0.duration = 0.16; blur.animator().alphaValue = 1 }
        }

        let work = DispatchWorkItem { [weak self, weak blur] in
            guard let blur else { return }
            NSAnimationContext.runAnimationGroup({
                $0.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.3
                blur.animator().alphaValue = 0
            },
                completionHandler: {
                    blur.removeFromSuperview()
                    if self?.noticeOverlay === blur { self?.noticeOverlay = nil }
                })
        }
        noticeHide = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: work)
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
        if page == .main { view.main.animateAvgIn() }
    }

    /// A transient notice inside the panel, if it is open. No-op when closed —
    /// the caller shows the menu-bar chip instead for that case.
    func flashNotice(_ message: String, kind: PanelNotice) {
        guard popover.isShown else { return }
        view.flashNotice(message, kind: kind)
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
        view.main.animateAvgIn()
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
        view.main.stopAvgAnimation()
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
        view.main.stopAvgAnimation()
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

        // Use a 2x backing bitmap, retaining the original point-size layout.
        // This renders the actual native view rather than enlarging a 1x image.
        let scale: CGFloat = 2
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                         pixelsWide: Int(ceil(view.bounds.width * scale)),
                                         pixelsHigh: Int(ceil(view.bounds.height * scale)),
                                         bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        rep.size = view.bounds.size
        view.cacheDisplay(in: view.bounds, to: rep)
        view.layer?.backgroundColor = nil
        host.contentView = nil // hand the view back to the popover
        popover.contentViewController?.view = view
        view.setHoverForSnapshot(hit: nil, day: nil)
        return rep.representation(using: .png, properties: [:])
    }
}

extension DropdownPanel: NSPopoverDelegate {
    func popoverDidClose(_ notification: Notification) {
        closedAt = Date()
        view.main.stopAvgAnimation()
    }
}

