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
/// one "Others" slice so the legend stays readable.
func chartSlices(_ data: [ChartDatum], metric: ChartMetric, keep: Int = 7) -> [ChartDatum] {
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

let chartPalette: [NSColor] = [
    NSColor(srgbRed: 0.20, green: 0.55, blue: 0.98, alpha: 1),
    NSColor(srgbRed: 0.24, green: 0.80, blue: 0.44, alpha: 1),
    NSColor(srgbRed: 0.98, green: 0.68, blue: 0.15, alpha: 1),
    NSColor(srgbRed: 0.95, green: 0.35, blue: 0.30, alpha: 1),
    NSColor(srgbRed: 0.64, green: 0.42, blue: 0.96, alpha: 1),
    NSColor(srgbRed: 0.96, green: 0.40, blue: 0.66, alpha: 1),
    NSColor(srgbRed: 0.20, green: 0.76, blue: 0.79, alpha: 1),
    NSColor(srgbRed: 0.62, green: 0.62, blue: 0.64, alpha: 1),
]

final class ChartView: NSView {
    var slices: [ChartDatum] = [] { didSet { needsDisplay = true } }
    var metric: ChartMetric = .tokens { didSet { needsDisplay = true } }

    private let donutDiameter: CGFloat = 168
    private let ringWidth: CGFloat = 26
    private let rowHeight: CGFloat = 22
    private let padding: CGFloat = 18

    /// Height this view needs for the current slice count.
    var fittingHeight: CGFloat {
        padding + donutDiameter + 16 + CGFloat(max(slices.count, 1)) * rowHeight + padding
    }

    private func fmt(_ d: ChartDatum) -> String {
        metric == .tokens ? fmtTokens(d.tokens) : fmtMoney(d.cost)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.set()
        dirtyRect.fill()

        let total = slices.reduce(0.0) { $0 + $1.value(metric) }
        let centre = CGPoint(x: bounds.midX, y: bounds.maxY - padding - donutDiameter / 2)

        guard total > 0 else {
            drawCentred(t("chart.noData"), at: CGPoint(x: bounds.midX, y: bounds.midY),
                        font: .systemFont(ofSize: 13), color: .secondaryLabelColor)
            return
        }

        drawDonut(total: total, centre: centre)
        drawCentreLabel(total: total, centre: centre)

        var y = centre.y - donutDiameter / 2 - 20
        for (i, slice) in slices.enumerated() {
            drawLegendRow(slice, colour: chartPalette[i % chartPalette.count],
                          share: slice.value(metric) / total, y: y)
            y -= rowHeight
        }
    }

    private func drawDonut(total: Double, centre: CGPoint) {
        guard let cg = NSGraphicsContext.current?.cgContext else { return }
        let radius = (donutDiameter - ringWidth) / 2
        cg.saveGState()
        cg.setLineWidth(ringWidth)
        cg.setLineCap(.butt)

        // Track behind the ring, so tiny slices still read as part of a whole.
        cg.setStrokeColor(NSColor.quaternaryLabelColor.cgColor)
        cg.addArc(center: centre, radius: radius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
        cg.strokePath()

        var start = CGFloat.pi / 2 // 12 o'clock
        for (i, slice) in slices.enumerated() {
            let sweep = CGFloat(slice.value(metric) / total) * .pi * 2
            guard sweep > 0 else { continue }
            cg.setStrokeColor(chartPalette[i % chartPalette.count].cgColor)
            cg.addArc(center: centre, radius: radius,
                      startAngle: start, endAngle: start - sweep, clockwise: true)
            cg.strokePath()
            start -= sweep
        }
        cg.restoreGState()
    }

    private func drawCentreLabel(total: Double, centre: CGPoint) {
        let caption = metric == .cost ? t("chart.estimated") : t("chart.total")
        let value = metric == .tokens ? fmtTokens(Int(total)) : fmtMoney(total)
        drawCentred(caption, at: CGPoint(x: centre.x, y: centre.y + 12),
                    font: .systemFont(ofSize: 11), color: .secondaryLabelColor)
        drawCentred(value, at: CGPoint(x: centre.x, y: centre.y - 12),
                    font: .monospacedDigitSystemFont(ofSize: 19, weight: .semibold),
                    color: .labelColor)
    }

    private func drawLegendRow(_ slice: ChartDatum, colour: NSColor, share: Double, y: CGFloat) {
        let dot = NSRect(x: padding, y: y + 5, width: 9, height: 9)
        colour.setFill()
        NSBezierPath(ovalIn: dot).fill()

        let nameFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        let numberFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        let percentX = bounds.maxX - padding - 46
        let valueX = percentX - 76

        draw(slice.label, at: NSRect(x: padding + 16, y: y, width: valueX - padding - 22, height: 16),
             font: nameFont, colour: .labelColor, alignment: .left)
        draw(fmt(slice), at: NSRect(x: valueX, y: y, width: 72, height: 16),
             font: numberFont, colour: .labelColor, alignment: .right)
        draw(String(format: "%.1f%%", share * 100),
             at: NSRect(x: percentX, y: y, width: 46, height: 16),
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
    func snapshot(scope: ChartScope, data: [ChartDatum], metric: ChartMetric) -> Data? {
        self.scope = scope
        self.data = data
        self.metric = metric
        build()
        localise()
        toggle.selectedSegment = metric == .cost ? 1 : 0
        reload()
        guard let view = popover.contentViewController?.view else { return nil }
        view.frame = NSRect(x: 0, y: 0, width: width, height: headerHeight + chart.fittingHeight)
        view.layoutSubtreeIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep.representation(using: .png, properties: [:])
    }
}


