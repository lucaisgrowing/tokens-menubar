// The actions page: the same verbs the right-click menu carries, drawn as a
// second page of the panel rather than as a menu on top of it. Clicking ⋯ turns
// the page; the plain NSMenu stays reachable as the keyboard and VoiceOver
// route, with every number in it.

import AppKit

enum PanelPage { case main, menu }

/// What a row offers. `pills` puts its choices on the right, so a setting is one
/// click rather than a submenu; every other row is a single target.
private enum MenuRowKind {
    case action(PanelAction)
    case pills([(label: String, action: PanelAction, on: Bool)])
    case toggle(PanelAction, Bool)
    case separator
}

private struct MenuRow {
    var symbol = ""
    var title = ""
    var kind: MenuRowKind = .separator
    var hint = ""
    var enabled = true
    /// Drawn in the accent when the row is waiting on the user, as an update is.
    var accented = false
}

/// Every rectangle of one render, computed once and read by drawing, hover and
/// hit-testing alike — the same contract the numbers page keeps.
private struct MenuLayout {
    var height: CGFloat = 0
    var back = NSRect.zero
    var title = NSRect.zero
    /// Rounded section cards grouping related rows (macOS Settings style).
    var groups: [NSRect] = []
    /// One entry per row, separators included, so indices line up with the rows.
    var rows: [NSRect] = []
    var pills: [[NSRect]] = []
    var dividers: [NSRect] = []
    var hint = NSRect.zero
    var version = NSRect.zero
}

final class PanelMenuView: NSView {
    var data = PanelData() { didSet { invalidate() } }
    var onAction: ((PanelAction) -> Void)?

    private let pad: CGFloat = 16
    private let rowHeight: CGFloat = 34

    private var cache: MenuLayout?
    /// Filled by `geometry()`, so it is never out of step with the rects.
    private var rows: [MenuRow] = []
    private var hits: [(NSRect, PanelAction, String)] = []
    private var pressedAction: PanelAction?
    private var pressedRect: NSRect?
    private var hovered: Int?

    override var isFlipped: Bool { true }

    private let titleFont = NSFont.systemFont(ofSize: 13.5, weight: .semibold)
    private let rowFont = NSFont.systemFont(ofSize: 12.5, weight: .regular)
    private let pillFont = NSFont.systemFont(ofSize: 11, weight: .medium)
    private let smallFont = NSFont.systemFont(ofSize: 11)

    private func invalidate() {
        cache = nil
        needsDisplay = true
        invalidateIntrinsicContentSize()
    }

    var fittingHeight: CGFloat { geometry().height }

    override var intrinsicContentSize: NSSize {
        NSSize(width: PanelView.width, height: fittingHeight)
    }

    // MARK: Rows

    /// The page's contents, rebuilt on every layout pass: titles are localised and
    /// three of the rows show live state.
    private func buildRows() -> [MenuRow] {
        var out: [MenuRow] = []
        out.append(MenuRow(symbol: "arrow.up.circle",
                           title: data.busy ? t("action.submitting") : t("action.submit"),
                           kind: .action(.submit), hint: t("hint.submit"),
                           enabled: data.canSubmit && !data.busy))
        out.append(MenuRow(symbol: "arrow.clockwise", title: t("action.refresh"),
                           kind: .action(.refresh), hint: t("hint.refresh")))
        out.append(MenuRow(symbol: "key", title: t("action.readToken"),
                           kind: .action(.readToken), hint: t("token.hint")))
        out.append(MenuRow())
        out.append(MenuRow(symbol: "list.number", title: t("action.rankMode"),
                           kind: .pills([RankMode.allTime, .today].map {
                               (label: $0.label, action: .setRank($0),
                                on: $0 == data.primaryMode)
                           }),
                           hint: t("hint.rank")))
        out.append(MenuRow(symbol: "menubar.rectangle", title: t("action.menuBarItems"),
                           kind: .pills([
                               (label: t("item.tokens"), action: .toggleMenuBarItem("tokens"),
                                on: data.menuBarItems.contains("tokens")),
                               (label: t("item.cost"), action: .toggleMenuBarItem("cost"),
                                on: data.menuBarItems.contains("cost")),
                               (label: t("item.rank"), action: .toggleMenuBarItem("rank"),
                                on: data.menuBarItems.contains("rank")),
                           ]),
                           hint: t("hint.menuBarItems")))
        let budgetTitle = data.dailyBudget > 0
            ? t("action.budgetWith", fmtMoney(data.dailyBudget))
            : t("action.budget") + " · " + t("budget.off")
        out.append(MenuRow(symbol: "dollarsign.circle", title: budgetTitle,
                           kind: .action(.editBudget), hint: t("hint.budget")))
        out.append(MenuRow(symbol: "globe", title: t("action.language"),
                           kind: .pills(Lang.allCases.map {
                               (label: $0.displayName, action: .setLanguage($0),
                                on: $0 == L10n.current)
                           }),
                           hint: t("hint.language")))
        out.append(MenuRow(symbol: "power", title: t("action.launchAtLogin"),
                           kind: .toggle(.toggleLogin, data.loginEnabled),
                           hint: t("hint.login")))
        out.append(MenuRow())
        out.append(MenuRow(symbol: "person.crop.circle", title: t("action.openProfile"),
                           kind: .action(.profile), hint: t("hint.profile")))
        out.append(MenuRow(symbol: "square.and.arrow.up", title: t("action.shareCard"),
                           kind: .pills([
                               (label: t("card.pill.md"), action: .cardMarkdown, on: false),
                               (label: t("card.pill.url"), action: .cardURL, on: false),
                               (label: t("card.pill.img"), action: .cardImage, on: false),
                           ]),
                           hint: t("hint.card"),
                           enabled: !data.username.isEmpty))
        out.append(MenuRow(
            symbol: data.updateWaiting ? "arrow.down.circle.fill" : "arrow.down.circle",
            title: data.updateTitle.isEmpty ? t("action.checkUpdates") : data.updateTitle,
            kind: .action(.updates), hint: t("hint.updates"), accented: data.updateWaiting))
        if let cliLatest = data.cliLatestVersion, !cliLatest.isEmpty {
            out.append(MenuRow(symbol: "terminal.fill",
                               title: t("cli.updateAvailable", cliLatest),
                               kind: .action(.cliUpdate),
                               hint: t("cli.hintUpdate"), accented: true))
        }
        out.append(MenuRow(symbol: "cup.and.saucer.fill", title: t("action.support"),
                           kind: .action(.support), hint: t("hint.support")))
        out.append(MenuRow())
        out.append(MenuRow(symbol: "xmark.circle", title: t("action.quit"),
                           kind: .action(.quit), hint: t("hint.quit")))
        return out
    }

    // MARK: Layout

    private func geometry() -> MenuLayout {
        if let cache { return cache }
        let w = bounds.width > 1 ? bounds.width : PanelView.width
        let inner = w - pad * 2
        var l = MenuLayout()
        var y: CGFloat = 14

        l.back = NSRect(x: pad, y: y - 2, width: 26, height: 26)
        l.title = NSRect(x: pad + 34, y: y + 2, width: inner - 34, height: 18)
        y += 34

        rows = buildRows()
        var groupStart: CGFloat? = nil
        var prevWasRow = false

        func closeGroup() {
            if let start = groupStart {
                l.groups.append(NSRect(x: pad, y: start, width: inner, height: y - start))
                groupStart = nil
            }
            prevWasRow = false
        }

        for row in rows {
            if case .separator = row.kind {
                closeGroup()
                l.rows.append(.zero)
                l.pills.append([])
                y += 10
                continue
            }
            if groupStart == nil { groupStart = y }
            if prevWasRow {
                l.dividers.append(NSRect(x: pad + 38, y: y, width: inner - 48, height: 0.75))
            }
            let rect = NSRect(x: pad, y: y, width: inner, height: rowHeight)
            l.rows.append(rect)
            if case .pills(let choices) = row.kind {
                var pills: [NSRect] = []
                var x = rect.maxX - 10
                for choice in choices.reversed() {
                    let width = ceil(measure(choice.label, font: pillFont).width) + 16
                    x -= width
                    pills.insert(NSRect(x: x, y: rect.minY + 6, width: width, height: 22), at: 0)
                    x -= 5
                }
                l.pills.append(pills)
            } else {
                l.pills.append([])
            }
            y += rowHeight
            prevWasRow = true
        }
        closeGroup()

        y += 12
        l.hint = NSRect(x: pad + 2, y: y, width: inner - 4, height: 14)
        y += 18
        l.version = NSRect(x: pad + 2, y: y, width: inner - 4, height: 13)
        y += 13 + 14

        l.height = y
        cache = l
        return l
    }

    /// Clickable regions in hover order. Each rect is final: the highlight paints
    /// it as-is and the hit test reads it as-is.
    private func regions(_ l: MenuLayout) -> [(NSRect, PanelAction, String)] {
        var out: [(NSRect, PanelAction, String)] = [
            (l.back.union(l.title), .back, t("hint.back")),
        ]
        for (i, row) in rows.enumerated() where l.rows.indices.contains(i) {
            guard row.enabled else { continue }
            switch row.kind {
            case .separator:
                continue
            case .action(let action), .toggle(let action, _):
                out.append((l.rows[i], action, row.hint))
            case .pills(let choices):
                for (j, choice) in choices.enumerated() where l.pills[i].indices.contains(j) {
                    out.append((l.pills[i][j], choice.action, row.hint))
                }
            }
        }
        return out
    }

    /// What clicking the hovered row does, or what this page is when the pointer is
    /// over nothing.
    private var hintText: String {
        guard let i = hovered, hits.indices.contains(i) else { return t("hint.menu") }
        return hits[i].2
    }

    private var hoveredRect: NSRect? {
        guard let i = hovered, hits.indices.contains(i) else { return nil }
        return hits[i].0
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        let l = geometry()
        hits = regions(l)
        let accent = tokensAccent
        defer {
            if let rect = pressedRect {
                fill(rect.insetBy(dx: 2, dy: 2), radius: 8, colour: accent.withAlphaComponent(0.14))
                stroke(rect.insetBy(dx: 2, dy: 2), radius: 8, colour: accent.withAlphaComponent(0.38))
            }
        }

        // Back button + title
        let backHov = hoveredRect == l.back.union(l.title)
        fill(l.back, radius: 7, colour: backHov ? panelSurfaceHover : panelSurface)
        stroke(l.back, radius: 7, colour: panelBorder, width: 0.75)
        icon("chevron.left", in: l.back, size: 11,
             colour: backHov ? .labelColor : .secondaryLabelColor)
        text(t("menu.title"), in: l.title, font: titleFont)

        // Elevated inset grouped cards
        for group in l.groups {
            drawCard(group, radius: 11)
        }
        for div in l.dividers {
            fill(div, radius: 0, colour: panelRule)
        }

        // Row hover highlight (clipped inside the group softly)
        let pillRects = l.pills.flatMap { $0 }
        if let rect = hoveredRect, !pillRects.contains(rect), rect != l.back.union(l.title) {
            fill(rect.insetBy(dx: 3, dy: 2), radius: 8, colour: panelHover)
        }

        for (i, row) in rows.enumerated() where l.rows.indices.contains(i) {
            if case .separator = row.kind { continue }
            drawRow(row, in: l.rows[i], pills: l.pills[i], accent: accent)
        }

        text(hintText, in: l.hint, font: smallFont,
             colour: hovered == nil ? .secondaryLabelColor : .labelColor)
        let versionLine: String
        if let cliVer = data.cliVersion, !cliVer.isEmpty {
            if let serve = data.cliServeRunning {
                versionLine = t("menu.versionCLIServe", Updates.currentVersion, cliVer,
                                t(serve ? "cli.serveOn" : "cli.serveOff"))
            } else {
                versionLine = t("menu.versionCLI", Updates.currentVersion, cliVer)
            }
        } else {
            versionLine = t("menu.version", Updates.currentVersion)
        }
        text(versionLine, in: l.version, font: smallFont,
             colour: .tertiaryLabelColor)
    }

    private func drawRow(_ row: MenuRow, in rect: NSRect, pills: [NSRect], accent: NSColor) {
        let dim = !row.enabled
        let isQuit: Bool = {
            if case .action(.quit) = row.kind { return true }
            return false
        }()
        let badgeRect = NSRect(x: rect.minX + 10, y: rect.midY - 11, width: 22, height: 22)
        let badgeTint: NSColor = dim ? panelCard
            : isQuit ? NSColor.systemRed.withAlphaComponent(0.13)
            : row.accented ? accent.withAlphaComponent(0.18)
            : accent.withAlphaComponent(0.11)
        let glyph: NSColor = dim ? .tertiaryLabelColor
            : isQuit ? .systemRed
            : (row.accented ? tokensAccentInk : tokensAccentInk.withAlphaComponent(0.92))
        fill(badgeRect, radius: 6, colour: badgeTint)
        icon(row.symbol, in: badgeRect, size: 11.5, colour: glyph)

        // The title stops where the row's own control begins, so a long localised
        // title truncates instead of running under the pills.
        let right = pills.first?.minX ?? (rect.maxX - (row.isToggle ? 50 : 12))
        let x = rect.minX + 39
        text(row.title,
             in: NSRect(x: x, y: rect.midY - 8, width: max(40, right - 8 - x), height: 16),
             font: rowFont, colour: dim ? .tertiaryLabelColor
                 : isQuit ? .systemRed
                 : (row.accented ? tokensAccentInk : .labelColor))

        switch row.kind {
        case .pills(let choices):
            for (j, choice) in choices.enumerated() where pills.indices.contains(j) {
                let r = pills[j]
                if choice.on {
                    fillGradient(r, radius: 7, from: tokensAccentBright, to: accent, angle: 90)
                } else {
                    fill(r, radius: 7, colour: hoveredRect == r ? panelTrack : panelCard)
                    stroke(r, radius: 7, colour: panelBorder, width: 0.5)
                }
                text(choice.label,
                     in: NSRect(x: r.minX, y: r.midY - 7, width: r.width, height: 15),
                     font: pillFont,
                     colour: choice.on ? onAccent(accent) : .secondaryLabelColor,
                     align: .center)
            }
        case .toggle(_, let on):
            let track = NSRect(x: rect.maxX - 42, y: rect.midY - 9, width: 32, height: 18)
            if on {
                fillGradient(track, radius: 9, from: tokensAccentBright, to: accent, angle: 0)
            } else {
                fill(track, radius: 9, colour: panelTrack)
                stroke(track, radius: 9, colour: panelBorder, width: 0.5)
            }
            let knob = NSRect(x: on ? track.maxX - 16 : track.minX + 2, y: track.minY + 2,
                              width: 14, height: 14)
            if let cg = NSGraphicsContext.current?.cgContext {
                cg.saveGState()
                cg.setShadow(offset: CGSize(width: 0, height: -0.5), blur: 1.5,
                             color: NSColor(white: 0, alpha: 0.22).cgColor)
                NSColor.white.setFill()
                NSBezierPath(ovalIn: knob).fill()
                cg.restoreGState()
            } else {
                fill(knob, radius: 7, colour: .white)
            }
        default:
            break
        }
    }

    /// Foreground for the fixed dark-green accent fill.
    private func onAccent(_ accent: NSColor) -> NSColor {
        guard let rgb = accent.usingColorSpace(.sRGB) else { return .white }
        let luma = 0.2126 * rgb.redComponent + 0.7152 * rgb.greenComponent
            + 0.0722 * rgb.blueComponent
        return luma > 0.62 ? .black : .white
    }

    // MARK: Interaction

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
        let hit = regions(geometry()).firstIndex { $0.0.contains(p) }
        guard hit != hovered else { return }
        hovered = hit
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        guard hovered != nil else { return }
        hovered = nil
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
        onAction?(hit.1)
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        for (rect, _, _) in regions(geometry()) { addCursorRect(rect, cursor: .pointingHand) }
    }

    /// Forces a hover state for offscreen renders.
    func setHoverForSnapshot(hit: Int?) {
        hovered = hit
        needsDisplay = true
    }

    func hitMap() -> [(NSRect, PanelAction)] { regions(geometry()).map { ($0.0, $0.1) } }
}

private extension MenuRow {
    var isToggle: Bool {
        if case .toggle = kind { return true }
        return false
    }
}

