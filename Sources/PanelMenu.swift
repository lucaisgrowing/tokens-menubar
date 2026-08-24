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
    /// One entry per row, separators included, so indices line up with the rows.
    var rows: [NSRect] = []
    var pills: [[NSRect]] = []
    var rules: [CGFloat] = []
    var hint = NSRect.zero
    var version = NSRect.zero
}

final class PanelMenuView: NSView {
    var data = PanelData() { didSet { invalidate() } }
    var onAction: ((PanelAction) -> Void)?

    private let pad: CGFloat = 18
    private let rowHeight: CGFloat = 30

    private var cache: MenuLayout?
    /// Filled by `geometry()`, so it is never out of step with the rects.
    private var rows: [MenuRow] = []
    private var hits: [(NSRect, PanelAction, String)] = []
    private var hovered: Int?

    override var isFlipped: Bool { true }

    private let titleFont = NSFont.systemFont(ofSize: 13, weight: .semibold)
    private let rowFont = NSFont.systemFont(ofSize: 12.5)
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
        out.append(MenuRow())
        out.append(MenuRow(symbol: "list.number", title: t("action.rankMode"),
                           kind: .pills([RankMode.allTime, .today].map {
                               (label: $0.label, action: .setRank($0),
                                on: $0 == data.primaryMode)
                           }),
                           hint: t("hint.rank")))
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
        out.append(MenuRow(
            symbol: data.updateWaiting ? "arrow.down.circle.fill" : "arrow.down.circle",
            title: data.updateTitle.isEmpty ? t("action.checkUpdates") : data.updateTitle,
            kind: .action(.updates), hint: t("hint.updates"), accented: data.updateWaiting))
        out.append(MenuRow(symbol: "cup.and.saucer.fill", title: t("action.support"),
                           kind: .action(.support), hint: t("hint.support")))
        out.append(MenuRow(symbol: "text.alignleft", title: t("action.numbers"),
                           kind: .action(.textMenu), hint: t("hint.numbers")))
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
        var y: CGFloat = 12

        l.back = NSRect(x: pad - 3, y: y - 1, width: 18, height: 20)
        l.title = NSRect(x: pad + 19, y: y + 1, width: inner - 19, height: 18)
        y += 30
        l.rules.append(y)
        y += 9

        rows = buildRows()
        for row in rows {
            if case .separator = row.kind {
                l.rows.append(NSRect(x: pad, y: y + 6, width: inner, height: 1))
                l.pills.append([])
                l.rules.append(y + 6)
                y += 13
                continue
            }
            let rect = NSRect(x: pad - 6, y: y, width: inner + 12, height: rowHeight)
            l.rows.append(rect)
            if case .pills(let choices) = row.kind {
                // Laid out from the right edge inwards, so the widest label decides
                // the group's width rather than the group deciding the label.
                var pills: [NSRect] = []
                var x = rect.maxX - 6
                for choice in choices.reversed() {
                    let width = ceil(measure(choice.label, font: pillFont).width) + 18
                    x -= width
                    pills.insert(NSRect(x: x, y: rect.minY + 4, width: width, height: 22), at: 0)
                    x -= 5
                }
                l.pills.append(pills)
            } else {
                l.pills.append([])
            }
            y += rowHeight
        }

        y += 8
        l.rules.append(y)
        y += 10
        l.hint = NSRect(x: pad, y: y, width: inner, height: 14)
        y += 17
        l.version = NSRect(x: pad, y: y, width: inner, height: 13)
        y += 13 + 12

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
        let accent = NSColor.controlAccentColor

        // Pills paint their own surface, so they pick the hover colour themselves
        // rather than being washed over twice.
        let pillRects = l.pills.flatMap { $0 }
        if let rect = hoveredRect, !pillRects.contains(rect) {
            fill(rect, radius: 7, colour: panelHover)
        }
        for y in l.rules {
            fill(NSRect(x: pad, y: y, width: bounds.width - pad * 2, height: 1),
                 radius: 0.5, colour: panelRule)
        }

        icon("chevron.left", in: l.back, size: 11, colour: .secondaryLabelColor)
        text(t("menu.title"), in: l.title, font: titleFont)

        for (i, row) in rows.enumerated() where l.rows.indices.contains(i) {
            if case .separator = row.kind { continue }
            drawRow(row, in: l.rows[i], pills: l.pills[i], accent: accent)
        }

        text(hintText, in: l.hint, font: smallFont,
             colour: hovered == nil ? .secondaryLabelColor : .labelColor)
        text(t("menu.version", Updates.currentVersion), in: l.version, font: smallFont,
             colour: .tertiaryLabelColor)
    }

    private func drawRow(_ row: MenuRow, in rect: NSRect, pills: [NSRect], accent: NSColor) {
        let dim = !row.enabled
        let glyph: NSColor = dim ? .tertiaryLabelColor
            : (row.accented ? accent : .secondaryLabelColor)
        icon(row.symbol, in: NSRect(x: rect.minX + 8, y: rect.midY - 9, width: 18, height: 18),
             size: 13, colour: glyph)

        // The title stops where the row's own control begins, so a long localised
        // title truncates instead of running under the pills.
        let right = pills.first?.minX ?? (rect.maxX - (row.isToggle ? 46 : 8))
        let x = rect.minX + 32
        text(row.title,
             in: NSRect(x: x, y: rect.midY - 8, width: max(40, right - 8 - x), height: 16),
             font: rowFont, colour: dim ? .tertiaryLabelColor
                 : (row.accented ? accent : .labelColor))

        switch row.kind {
        case .pills(let choices):
            for (j, choice) in choices.enumerated() where pills.indices.contains(j) {
                let r = pills[j]
                // An off pill on hover goes a step darker than its resting card, not
                // the row wash: the two surfaces are 2% apart and would not read.
                let surface = choice.on ? accent
                    : (hoveredRect == r ? panelTrack : panelCard)
                fill(r, radius: 7, colour: surface)
                text(choice.label,
                     in: NSRect(x: r.minX, y: r.midY - 7, width: r.width, height: 15),
                     font: pillFont,
                     colour: choice.on ? onAccent(accent) : .secondaryLabelColor,
                     align: .center)
            }
        case .toggle(_, let on):
            let track = NSRect(x: rect.maxX - 38, y: rect.midY - 8, width: 30, height: 16)
            fill(track, radius: 8, colour: on ? accent : panelTrack)
            fill(NSRect(x: on ? track.maxX - 15 : track.minX + 1, y: track.minY + 1,
                        width: 14, height: 14),
                 radius: 7, colour: on ? onAccent(accent) : .secondaryLabelColor)
        default:
            break
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

    override func mouseUp(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        guard let hit = regions(geometry()).first(where: { $0.0.contains(p) }) else { return }
        onAction?(hit.1)
    }

    /// Right-clicking still pops the plain menu, as it does on the numbers page.
    override func rightMouseUp(with event: NSEvent) {
        onAction?(.textMenu)
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

