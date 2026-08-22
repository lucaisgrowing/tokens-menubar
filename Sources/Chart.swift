// Model distribution donut + legend, shown when a usage row in the menu is clicked.

import AppKit

enum ChartMetric {
    case tokens
    case cost

    var titleKey: String { self == .tokens ? "chart.tokens" : "chart.cost" }
}

enum ChartScope {
    case today
    case lifetime

    var titleKey: String { self == .today ? "chart.titleToday" : "chart.titleLifetime" }
}

struct ChartDatum {
    let label: String
    let tokens: Int
    let cost: Double

    func value(_ metric: ChartMetric) -> Double {
        metric == .tokens ? Double(tokens) : cost
    }
}

/// Aggregates per-model rows, sorts by the chosen metric and folds the tail into
/// one "Others" slice. A donut is only legible as part-to-whole at a glance, so
/// the segment count is capped at six.
func chartSlices(_ data: [ChartDatum], metric: ChartMetric, keep: Int = 5) -> [ChartDatum] {
    var merged: [String: (tokens: Int, cost: Double)] = [:]
    for d in data {
        var e = merged[d.label] ?? (0, 0)
        e.tokens += d.tokens
        e.cost += d.cost
        merged[d.label] = e
    }
    let all = merged
        .map { ChartDatum(label: $0.key, tokens: $0.value.tokens, cost: $0.value.cost) }
        .filter { $0.value(metric) > 0 }
        .sorted { $0.value(metric) > $1.value(metric) }
    guard all.count > keep else { return all }
    let head = Array(all.prefix(keep))
    let tail = all.dropFirst(keep)
    let others = ChartDatum(label: t("chart.others"),
                            tokens: tail.reduce(0) { $0 + $1.tokens },
                            cost: tail.reduce(0) { $0 + $1.cost })
    return head + [others]
}

/// Categorical slots in a fixed order — the order itself is the colour-blind
/// safety mechanism, so slots are assigned by entity and never cycled or
/// re-ranked. Each slot carries a step for the light surface and one stepped for
/// the dark surface; both sets are validated against their own surface rather
/// than one being an automatic flip of the other.
private let seriesHexLight = ["2a78d6", "eb6834", "1baf7a", "eda100", "e87ba4",
                              "008300", "4a3aa7", "e34948"]
private let seriesHexDark = ["3987e5", "d95926", "199e70", "c98500", "d55181",
                             "008300", "9085e9", "e66767"]

private func colorFrom(hex: String) -> NSColor {
    var v: UInt64 = 0
    Scanner(string: hex).scanHexInt64(&v)
    return NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255,
                   green: CGFloat((v >> 8) & 0xFF) / 255,
                   blue: CGFloat(v & 0xFF) / 255,
                   alpha: 1)
}

let chartPalette: [NSColor] = (0..<seriesHexLight.count).map { slot in
    NSColor(name: NSColor.Name("tokensbar.series.\(slot)")) { appearance in
        let dark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return colorFrom(hex: dark ? seriesHexDark[slot] : seriesHexLight[slot])
    }
}

final class ChartView: NSView {
    var slices: [ChartDatum] = [] { didSet { needsDisplay = true } }
    var metric: ChartMetric = .tokens { didSet { needsDisplay = true } }

    private let donutDiameter: CGFloat = 168
    private let ringWidth: CGFloat = 26
    private let rowHeight: CGFloat = 22
    private let padding: CGFloat = 18
    private let barHeight: CGFloat = 26

    /// A donut needs enough segments to read as part-to-whole; with one or two it
    /// is just a pie chart of nothing. Those cases get a single 100% bar instead.
    private var usesBar: Bool { slices.count <= 2 }

    /// Height this view needs for the current slice count.
    var fittingHeight: CGFloat {
        let plot = usesBar ? 38 + barHeight + 20 : donutDiameter + 16
        return padding + plot + CGFloat(max(slices.count, 1)) * rowHeight + padding
    }

    private func fmt(_ d: ChartDatum) -> String {
        metric == .tokens ? fmtTokens(d.tokens) : fmtMoney(d.cost)
    }

    override func draw(_ dirtyRect: NSRect) {
        let total = slices.reduce(0.0) { $0 + $1.value(metric) }

        guard total > 0 else {
            drawCentred(t("chart.noData"), at: CGPoint(x: bounds.midX, y: bounds.midY),
                        font: .systemFont(ofSize: 13), color: .secondaryLabelColor)
            return
        }

        var legendTop: CGFloat
        if usesBar {
            let caption = metric == .cost ? t("chart.estimated") : t("chart.total")
            let value = metric == .tokens ? fmtTokens(Int(total)) : fmtMoney(total)
            draw(caption, at: NSRect(x: padding, y: bounds.maxY - padding - 14,
                                    width: bounds.width, height: 14),
                 font: .systemFont(ofSize: 11), colour: .secondaryLabelColor, alignment: .left)
            draw(value, at: NSRect(x: padding, y: bounds.maxY - padding - 34,
                                   width: bounds.width - padding * 2, height: 22),
                 font: .systemFont(ofSize: 21, weight: .semibold),
                 colour: .labelColor, alignment: .left)
            let bar = NSRect(x: padding, y: bounds.maxY - padding - 34 - barHeight - 4,
                             width: bounds.width - padding * 2, height: barHeight)
            drawSplitBar(total: total, in: bar)
            legendTop = bar.minY - 20
        } else {
            let centre = CGPoint(x: bounds.midX, y: bounds.maxY - padding - donutDiameter / 2)
            drawDonut(total: total, centre: centre)
            drawCentreLabel(total: total, centre: centre)
            legendTop = centre.y - donutDiameter / 2 - 20
        }

        for (i, slice) in slices.enumerated() {
            drawLegendRow(slice, colour: chartPalette[i % chartPalette.count],
                          share: slice.value(metric) / total, y: legendTop)
            legendTop -= rowHeight
        }
    }

    /// One 100% bar: rounded outer ends, 2px surface gaps between segments.
    private func drawSplitBar(total: Double, in rect: NSRect) {
        guard let cg = NSGraphicsContext.current?.cgContext else { return }
        let gap: CGFloat = 2
        let radius: CGFloat = 4
        cg.saveGState()
        let clip = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        clip.addClip()
        var x = rect.minX
        for (i, slice) in slices.enumerated() {
            let share = CGFloat(slice.value(metric) / total)
            let full = share * rect.width
            let isLast = i == slices.count - 1
            let w = isLast ? rect.maxX - x : max(full - gap, 1)
            chartPalette[i % chartPalette.count].setFill()
            NSRect(x: x, y: rect.minY, width: w, height: rect.height).fill()
            x += full
        }
        cg.restoreGState()
    }

    private func drawDonut(total: Double, centre: CGPoint) {
        guard let cg = NSGraphicsContext.current?.cgContext else { return }
        let radius = (donutDiameter - ringWidth) / 2
        // A 2px gap in the surface separates touching segments — no track behind
        // them and no stroked border, so the gap is the popover material itself.
        let gap = 2 / radius // radians subtending 2px at the ring
        cg.saveGState()
        cg.setLineWidth(ringWidth)
        cg.setLineCap(.butt)

        var start = CGFloat.pi / 2 // 12 o'clock, clockwise
        for (i, slice) in slices.enumerated() {
            let share = CGFloat(slice.value(metric) / total)
            let sweep = share * .pi * 2
            // Keep a hairline of every non-zero slice visible after the gap.
            let drawn = max(sweep - gap, gap)
            cg.setStrokeColor(chartPalette[i % chartPalette.count].cgColor)
            cg.addArc(center: centre, radius: radius,
                      startAngle: start - gap / 2, endAngle: start - gap / 2 - drawn,
                      clockwise: true)
            cg.strokePath()
            start -= sweep
        }
        cg.restoreGState()
    }

    private func drawCentreLabel(total: Double, centre: CGPoint) {
        let caption = metric == .cost ? t("chart.estimated") : t("chart.total")
        let value = metric == .tokens ? fmtTokens(Int(total)) : fmtMoney(total)
        drawCentred(caption, at: CGPoint(x: centre.x, y: centre.y + 13),
                    font: .systemFont(ofSize: 11), color: .secondaryLabelColor)
        // A standalone hero figure reads better in proportional figures.
        drawCentred(value, at: CGPoint(x: centre.x, y: centre.y - 11),
                    font: .systemFont(ofSize: 21, weight: .semibold),
                    color: .labelColor)
    }

    private func drawLegendRow(_ slice: ChartDatum, colour: NSColor, share: Double, y: CGFloat) {
        let dot = NSRect(x: padding, y: y + 5, width: 9, height: 9)
        colour.setFill()
        NSBezierPath(ovalIn: dot).fill()

        // Names in the UI sans; the numeric columns get tabular figures so they
        // line up. Text always wears ink colours, never the series colour.
        let nameFont = NSFont.systemFont(ofSize: 12)
        let numberFont = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        let percentX = bounds.maxX - padding - 44
        let valueX = percentX - 78

        draw(slice.label, at: NSRect(x: padding + 17, y: y, width: valueX - padding - 23, height: 16),
             font: nameFont, colour: .labelColor, alignment: .left)
        draw(fmt(slice), at: NSRect(x: valueX, y: y, width: 74, height: 16),
             font: numberFont, colour: .labelColor, alignment: .right)
        draw(String(format: "%.1f%%", share * 100),
             at: NSRect(x: percentX, y: y, width: 44, height: 16),
             font: numberFont, colour: .secondaryLabelColor, alignment: .right)
    }

    private func draw(_ s: String, at rect: NSRect, font: NSFont, colour: NSColor,
                      alignment: NSTextAlignment) {
        let style = NSMutableParagraphStyle()
        style.alignment = alignment
        style.lineBreakMode = .byTruncatingTail
        NSAttributedString(string: s, attributes: [
            .font: font, .foregroundColor: colour, .paragraphStyle: style,
        ]).draw(in: rect)
    }

    private func drawCentred(_ s: String, at point: CGPoint, font: NSFont, color: NSColor) {
        let text = NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color])
        let size = text.size()
        text.draw(at: NSPoint(x: point.x - size.width / 2, y: point.y - size.height / 2))
    }

}

/// A popover anchored to the status item, so the breakdown reads as part of the
/// menu bar rather than a window that appears in the middle of the screen.
final class ChartPopover: NSObject {
    static let shared = ChartPopover()

    private let popover = NSPopover()
    private let chart = ChartView()
    private let heading = NSTextField(labelWithString: "")
    private var toggle: NSSegmentedControl!
    private var chartHeight: NSLayoutConstraint!
    private var scope: ChartScope = .today
    private var data: [ChartDatum] = []
    private var metric: ChartMetric = .tokens
    private var built = false

    private let width: CGFloat = 380
    private let headerHeight: CGFloat = 44

    func show(scope: ChartScope, data: [ChartDatum], from anchor: NSView?) {
        guard let anchor else { return }
        self.scope = scope
        self.data = data
        build()
        localise()
        reload()
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxY)
    }

    /// Refreshes in place if the popover is already showing this scope.
    func update(scope: ChartScope, data: [ChartDatum]) {
        guard popover.isShown, self.scope == scope else { return }
        self.data = data
        reload()
    }

    /// Called after a language switch so an open popover follows suit.
    func refreshLanguage() {
        guard built else { return }
        localise()
        reload()
    }

    private func build() {
        guard !built else { return }
        built = true

        heading.font = .systemFont(ofSize: 12, weight: .semibold)
        heading.textColor = .secondaryLabelColor
        heading.translatesAutoresizingMaskIntoConstraints = false

        let toggle = NSSegmentedControl(labels: [t("chart.tokens"), t("chart.cost")],
                                        trackingMode: .selectOne,
                                        target: self, action: #selector(metricChanged(_:)))
        toggle.selectedSegment = 0
        toggle.segmentStyle = .capsule
        toggle.controlSize = .small
        toggle.translatesAutoresizingMaskIntoConstraints = false
        self.toggle = toggle

        chart.translatesAutoresizingMaskIntoConstraints = false
        chartHeight = chart.heightAnchor.constraint(equalToConstant: 300)

        let content = NSView(frame: NSRect(x: 0, y: 0, width: width, height: 344))
        content.addSubview(heading)
        content.addSubview(toggle)
        content.addSubview(chart)
        NSLayoutConstraint.activate([
            heading.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 18),
            heading.centerYAnchor.constraint(equalTo: toggle.centerYAnchor),
            toggle.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -18),
            toggle.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
            chart.topAnchor.constraint(equalTo: toggle.bottomAnchor, constant: 6),
            chart.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            chart.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            chartHeight,
        ])

        let vc = NSViewController()
        vc.view = content
        popover.contentViewController = vc
        popover.behavior = .transient
        popover.animates = true
    }

    private func localise() {
        toggle.setLabel(t("chart.tokens"), forSegment: 0)
        toggle.setLabel(t("chart.cost"), forSegment: 1)
        heading.stringValue = t(scope.titleKey)
    }

    private func reload() {
        chart.metric = metric
        chart.slices = chartSlices(data, metric: metric)
        chartHeight.constant = chart.fittingHeight
        popover.contentSize = NSSize(width: width, height: headerHeight + chart.fittingHeight)
    }

    @objc private func metricChanged(_ sender: NSSegmentedControl) {
        metric = sender.selectedSegment == 1 ? .cost : .tokens
        reload()
    }

    /// Renders the popover's own content offscreen, so `--chart-png` shows the
    /// real layout (heading and toggle included) rather than the chart alone.
    /// The content is hosted in an offscreen window: NSControls only draw
    /// properly inside one, and it also gets the display's native pixel density.
    /// `dark` renders the dark-mode steps of the palette.
    func snapshot(scope: ChartScope, data: [ChartDatum], metric: ChartMetric,
                  dark: Bool = false) -> Data? {
        self.scope = scope
        self.data = data
        self.metric = metric
        build()
        localise()
        toggle.selectedSegment = metric == .cost ? 1 : 0
        reload()
        guard let view = popover.contentViewController?.view else { return nil }
        let size = NSSize(width: width, height: headerHeight + chart.fittingHeight)

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
        return rep.representation(using: .png, properties: [:])
    }
}


