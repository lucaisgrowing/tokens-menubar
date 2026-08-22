// Daily token activity as a year-long heat grid, mirroring the contributions
// panel on the site. Data comes straight from the API's `contributions` array.

import AppKit

/// What the grid colours by and what the readout breaks down.
enum ContribMode: Int, CaseIterable {
    case models
    case clients
    case cost

    var titleKey: String {
        switch self {
        case .models: return "heat.models"
        case .clients: return "heat.clients"
        case .cost: return "heat.cost"
        }
    }
}

struct ContribSlice {
    let name: String
    let tokens: Int
    let cost: Double
}

struct ContribDay {
    let date: Date
    let tokens: Int
    let cost: Double
    let messages: Int
    /// 0…4 as the API reports it; any day with tokens is lifted to at least 1 so
    /// "a little" never renders as "nothing".
    let level: Int
    /// Per-client and per-model splits, each biggest-first.
    let clients: [ContribSlice]
    let models: [ContribSlice]

    func slices(_ mode: ContribMode) -> [ContribSlice] {
        switch mode {
        case .clients: return clients
        case .models, .cost: return models
        }
    }
}

/// One hue, light→dark, so the ramp reads as magnitude. Each mode has its own
/// steps: the lightest is allowed to recede toward its surface, and both were
/// checked for lightness monotonicity and step separation against that surface.
private let heatHexLight = ["9be9a8", "40c463", "30a14e", "216e39"]
private let heatHexDark = ["0e4429", "006d32", "26a641", "39d353"]

private func heatColor(level: Int) -> NSColor {
    guard level > 0 else {
        return NSColor(name: NSColor.Name("tokensbar.heat.empty")) { appearance in
            let dark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(white: dark ? 1 : 0, alpha: dark ? 0.07 : 0.08)
        }
    }
    let slot = min(level, 4) - 1
    return NSColor(name: NSColor.Name("tokensbar.heat.\(slot)")) { appearance in
        let dark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return colorFrom(hex: dark ? heatHexDark[slot] : heatHexLight[slot])
    }
}

/// Calendar fixed to GMT so a date-only string maps to exactly one cell.
let gridCalendar: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "GMT") ?? .current
    c.firstWeekday = 2 // Monday, matching the Mon/Wed/Fri row labels
    return c
}()

let dayFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd"
    f.timeZone = TimeZone(identifier: "GMT")
    f.locale = Locale(identifier: "en_US_POSIX")
    return f
}()

func parseDay(_ s: Any?) -> Date? {
    guard let s = s as? String else { return nil }
    return dayFormatter.date(from: s)
}

/// Locale for month names, following the app's language rather than the system's.
func displayLocale() -> Locale {
    Locale(identifier: L10n.current == .zh ? "zh_Hans" : "en_US")
}

final class HeatmapView: NSView {
    /// Days keyed by their GMT midnight, plus the window to render.
    var days: [Date: ContribDay] = [:] {
        didSet { recomputeCostCuts(); needsDisplay = true }
    }
    var mode: ContribMode = .models { didSet { needsDisplay = true } }
    var start = Date() { didSet { needsDisplay = true } }
    var end = Date() { didSet { needsDisplay = true } }

    private let cell: CGFloat = 10
    private let gap: CGFloat = 3
    private let padding: CGFloat = 16
    private let labelColumn: CGFloat = 30
    private let monthRow: CGFloat = 16
    private let readoutHeight: CGFloat = 38
    private var pitch: CGFloat { cell + gap }

    private var hovered: Date?
    /// Quartile cut points over the non-zero daily costs, so the cost view has a
    /// ramp of its own instead of reusing the token intensity.
    private var costCuts: [Double] = []
    /// Week column → x offset, filled while drawing.
    private var firstColumnMonday = Date()
    private var columns = 0

    var neededSize: NSSize {
        recomputeColumns()
        let gridWidth = CGFloat(columns) * pitch - gap
        return NSSize(width: padding * 2 + labelColumn + gridWidth,
                      height: padding * 2 + monthRow + 7 * pitch - gap + 10 + readoutHeight)
    }

    private func recomputeCostCuts() {
        let costs = days.values.map(\.cost).filter { $0 > 0 }.sorted()
        guard costs.count >= 4 else { return costCuts = [] }
        costCuts = [0.25, 0.5, 0.75].map { costs[Int(Double(costs.count - 1) * $0)] }
    }

    /// Level for a cell: the API's token intensity, or a cost quartile.
    private func level(_ day: ContribDay?) -> Int {
        guard let day else { return 0 }
        guard mode == .cost else { return day.level }
        guard day.cost > 0 else { return 0 }
        guard costCuts.count == 3 else { return 2 }
        if day.cost <= costCuts[0] { return 1 }
        if day.cost <= costCuts[1] { return 2 }
        if day.cost <= costCuts[2] { return 3 }
        return 4
    }

    private func recomputeColumns() {
        let cal = gridCalendar
        let startWeek = cal.dateInterval(of: .weekOfYear, for: start)?.start ?? start
        firstColumnMonday = startWeek
        let weeks = cal.dateComponents([.weekOfYear], from: startWeek, to: end).weekOfYear ?? 0
        columns = max(1, weeks + 1)
    }

    // MARK: Hover

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
        let newValue = date(at: p)
        if newValue != hovered { hovered = newValue; needsDisplay = true }
    }

    override func mouseExited(with event: NSEvent) {
        if hovered != nil { hovered = nil; needsDisplay = true }
    }

    private func gridOrigin() -> CGPoint {
        CGPoint(x: padding + labelColumn, y: bounds.maxY - padding - monthRow - pitch)
    }

    private func date(at point: CGPoint) -> Date? {
        let origin = gridOrigin()
        let col = Int(((point.x - origin.x) / pitch).rounded(.down))
        let rowFromTop = Int(((origin.y + cell - point.y) / pitch).rounded(.down))
        guard col >= 0, col < columns, rowFromTop >= 0, rowFromTop < 7 else { return nil }
        guard let day = gridCalendar.date(byAdding: .day, value: col * 7 + rowFromTop,
                                          to: firstColumnMonday) else { return nil }
        guard day >= gridCalendar.startOfDay(for: start), day <= end else { return nil }
        return day
    }

    override func draw(_ dirtyRect: NSRect) {
        recomputeColumns()
        let origin = gridOrigin()
        let cal = gridCalendar
        let firstDay = cal.startOfDay(for: start)

        drawMonthLabels(origin: origin)
        drawWeekdayLabels(origin: origin)

        for col in 0..<columns {
            for row in 0..<7 {
                guard let day = cal.date(byAdding: .day, value: col * 7 + row,
                                         to: firstColumnMonday) else { continue }
                guard day >= firstDay, day <= end else { continue }
                let rect = NSRect(x: origin.x + CGFloat(col) * pitch,
                                  y: origin.y - CGFloat(row) * pitch,
                                  width: cell, height: cell)
                heatColor(level: level(days[day])).setFill()
                NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2).fill()
                if day == hovered {
                    NSColor.labelColor.setStroke()
                    let ring = NSBezierPath(roundedRect: rect.insetBy(dx: -1.5, dy: -1.5),
                                            xRadius: 3, yRadius: 3)
                    ring.lineWidth = 1.5
                    ring.stroke()
                }
            }
        }

        drawScaleLegend(origin: origin)
        drawReadout()
    }

    private func drawMonthLabels(origin: CGPoint) {
        let f = DateFormatter()
        f.locale = displayLocale()
        f.timeZone = gridCalendar.timeZone
        f.setLocalizedDateFormatFromTemplate("MMM")
        var lastMonth = -1
        for col in 0..<columns {
            guard let day = gridCalendar.date(byAdding: .day, value: col * 7,
                                              to: firstColumnMonday) else { continue }
            let month = gridCalendar.component(.month, from: day)
            guard month != lastMonth else { continue }
            lastMonth = month
            // Only label a month once its first week is a few columns in, so the
            // labels never collide.
            let x = origin.x + CGFloat(col) * pitch
            guard x < bounds.maxX - padding - 24 else { continue }
            drawText(f.string(from: day), at: NSRect(x: x, y: origin.y + pitch + 1,
                                                    width: 40, height: 13),
                     font: .systemFont(ofSize: 10), colour: .secondaryLabelColor, alignment: .left)
        }
    }

    private func drawWeekdayLabels(origin: CGPoint) {
        let f = DateFormatter()
        f.locale = displayLocale()
        f.timeZone = gridCalendar.timeZone
        f.setLocalizedDateFormatFromTemplate("EEE")
        // Mondays, Wednesdays and Fridays only — a label on all seven is noise.
        for row in [0, 2, 4] {
            guard let day = gridCalendar.date(byAdding: .day, value: row,
                                              to: firstColumnMonday) else { continue }
            drawText(f.string(from: day),
                     at: NSRect(x: padding, y: origin.y - CGFloat(row) * pitch - 1,
                                width: labelColumn - 6, height: 13),
                     font: .systemFont(ofSize: 10), colour: .secondaryLabelColor, alignment: .right)
        }
    }

    private func drawScaleLegend(origin: CGPoint) {
        let y = origin.y - 6 * pitch - 22
        let swatch: CGFloat = 9
        var x = bounds.maxX - padding - CGFloat(5) * (swatch + 3) - 62
        drawText(t("heat.low"), at: NSRect(x: x - 34, y: y - 2, width: 30, height: 13),
                 font: .systemFont(ofSize: 10), colour: .secondaryLabelColor, alignment: .right)
        for level in 0...4 {
            heatColor(level: level).setFill()
            NSBezierPath(roundedRect: NSRect(x: x, y: y, width: swatch, height: swatch),
                         xRadius: 2, yRadius: 2).fill()
            x += swatch + 3
        }
        drawText(t("heat.high"), at: NSRect(x: x + 4, y: y - 2, width: 40, height: 13),
                 font: .systemFont(ofSize: 10), colour: .secondaryLabelColor, alignment: .left)
    }

    /// Always-visible readout: the hovered day, or the range summary when the
    /// pointer is elsewhere. Values lead, labels follow.
    private func drawReadout() {
        let y = padding + 16
        guard let hovered, let day = days[hovered] else {
            let f = DateFormatter()
            f.locale = displayLocale()
            f.timeZone = gridCalendar.timeZone
            f.setLocalizedDateFormatFromTemplate("MMM d, yyyy")
            let active = days.values.filter { $0.tokens > 0 }.count
            drawText(t("heat.activeDays", active),
                     at: NSRect(x: padding, y: y, width: bounds.width - padding * 2, height: 16),
                     font: .systemFont(ofSize: 12, weight: .semibold),
                     colour: .labelColor, alignment: .left)
            drawText("\(f.string(from: start)) – \(f.string(from: end))",
                     at: NSRect(x: padding, y: y - 16, width: bounds.width - padding * 2, height: 14),
                     font: .systemFont(ofSize: 11), colour: .secondaryLabelColor, alignment: .left)
            return
        }

        let f = DateFormatter()
        f.locale = displayLocale()
        f.timeZone = gridCalendar.timeZone
        f.setLocalizedDateFormatFromTemplate("EEE, MMM d, yyyy")
        let hero = mode == .cost ? fmtMoney(day.cost)
                                 : "\(fmtTokens(day.tokens))  \(t("heat.tokens"))"
        drawText(hero,
                 at: NSRect(x: padding, y: y, width: bounds.width - padding * 2, height: 16),
                 font: .systemFont(ofSize: 13, weight: .semibold),
                 colour: .labelColor, alignment: .left)

        // Everything else on one secondary line — the scale legend sits above the
        // right end of this row, so nothing is right-aligned here.
        var parts = [f.string(from: day.date)]
        parts.append(mode == .cost ? fmtTokens(day.tokens) + " tokens" : fmtMoney(day.cost))
        if day.messages > 0 { parts.append(t("heat.messages", fmtExact(day.messages))) }
        let top = day.slices(mode)
            .sorted { mode == .cost ? $0.cost > $1.cost : $0.tokens > $1.tokens }
            .prefix(3)
        parts += top.map { slice in
            let value = mode == .cost ? fmtMoney(slice.cost) : fmtTokens(slice.tokens)
            return "\(clipDisplay(slice.name, 14)) \(value)"
        }
        drawText(parts.joined(separator: "  ·  "),
                 at: NSRect(x: padding, y: y - 16, width: bounds.width - padding * 2, height: 14),
                 font: .systemFont(ofSize: 11), colour: .secondaryLabelColor, alignment: .left)
    }

    private func drawText(_ s: String, at rect: NSRect, font: NSFont, colour: NSColor,
                          alignment: NSTextAlignment) {
        let style = NSMutableParagraphStyle()
        style.alignment = alignment
        style.lineBreakMode = .byTruncatingTail
        NSAttributedString(string: s, attributes: [
            .font: font, .foregroundColor: colour, .paragraphStyle: style,
        ]).draw(in: rect)
    }

    /// Forces a hovered day for offscreen renders.
    func setHoverForSnapshot(_ date: Date?) { hovered = date; needsDisplay = true }

}

/// Popover for the contributions grid, anchored to the status item like the
/// chart one.
final class ContribPopover: NSObject {
    static let shared = ContribPopover()

    private let popover = NSPopover()
    private let grid = HeatmapView()
    private let heading = NSTextField(labelWithString: "")
    private var toggle: NSSegmentedControl!
    private var built = false

    func show(days: [ContribDay], start: Date, end: Date, from anchor: NSView?) {
        guard let anchor else { return }
        build()
        load(days: days, start: start, end: end)
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxY)
    }

    func update(days: [ContribDay], start: Date, end: Date) {
        guard popover.isShown else { return }
        load(days: days, start: start, end: end)
    }

    func refreshLanguage() {
        guard built else { return }
        localise()
        grid.needsDisplay = true
    }

    private func localise() {
        heading.stringValue = t("heat.title")
        for mode in ContribMode.allCases {
            toggle.setLabel(t(mode.titleKey), forSegment: mode.rawValue)
        }
        toggle.sizeToFit()
    }

    @objc private func modeChanged(_ sender: NSSegmentedControl) {
        grid.mode = ContribMode(rawValue: sender.selectedSegment) ?? .models
    }

    private func load(days: [ContribDay], start: Date, end: Date) {
        grid.days = Dictionary(days.map { (gridCalendar.startOfDay(for: $0.date), $0) },
                               uniquingKeysWith: { a, _ in a })
        grid.start = start
        grid.end = end
        localise()
        let size = grid.neededSize
        grid.frame = NSRect(origin: .zero, size: size)
        popover.contentSize = NSSize(width: size.width, height: size.height + 40)
    }

    private func build() {
        guard !built else { return }
        built = true
        heading.font = .systemFont(ofSize: 12, weight: .semibold)
        heading.textColor = .secondaryLabelColor
        heading.translatesAutoresizingMaskIntoConstraints = false
        grid.translatesAutoresizingMaskIntoConstraints = false

        let toggle = NSSegmentedControl(
            labels: ContribMode.allCases.map { t($0.titleKey) },
            trackingMode: .selectOne, target: self, action: #selector(modeChanged(_:)))
        toggle.selectedSegment = ContribMode.models.rawValue
        toggle.segmentStyle = .capsule
        toggle.controlSize = .small
        toggle.translatesAutoresizingMaskIntoConstraints = false
        self.toggle = toggle

        let content = NSView()
        content.addSubview(heading)
        content.addSubview(toggle)
        content.addSubview(grid)
        NSLayoutConstraint.activate([
            heading.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 18),
            heading.centerYAnchor.constraint(equalTo: toggle.centerYAnchor),
            toggle.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -18),
            toggle.topAnchor.constraint(equalTo: content.topAnchor, constant: 10),
            grid.topAnchor.constraint(equalTo: toggle.bottomAnchor, constant: 2),
            grid.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            grid.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            grid.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])

        let vc = NSViewController()
        vc.view = content
        popover.contentViewController = vc
        popover.behavior = .transient
        popover.animates = true
    }

    /// Offscreen render for `--contrib-png`, same trick as the chart popover.
    func snapshot(days: [ContribDay], start: Date, end: Date,
                  dark: Bool = false, hover: Date? = nil,
                  mode: ContribMode = .models) -> Data? {
        build()
        load(days: days, start: start, end: end)
        grid.mode = mode
        toggle.selectedSegment = mode.rawValue
        guard let view = popover.contentViewController?.view else { return nil }
        let size = popover.contentSize
        let host = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                            styleMask: [.borderless], backing: .buffered, defer: false)
        host.isReleasedWhenClosed = false
        host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        host.contentView = view
        view.frame = NSRect(origin: .zero, size: size)
        view.wantsLayer = true
        view.layer?.backgroundColor = colorFrom(hex: dark ? "2a2a2a" : "ececec").cgColor
        view.layoutSubtreeIfNeeded()
        grid.setHoverForSnapshot(hover)
        view.display()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        view.layer?.backgroundColor = nil
        host.contentView = nil
        popover.contentViewController?.view = view
        return rep.representation(using: .png, properties: [:])
    }
}


