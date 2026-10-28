import AppKit
import UniformTypeIdentifiers

func agentText(_ en: String, _ zh: String) -> String { L10n.current == .zh ? zh : en }
private final class AgentDocumentStack: NSStackView {
    override var isFlipped: Bool { true }
}
private final class AgentBackgroundView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        dirtyRect.fill()
    }
}
private final class AgentButton: NSButton {
    var perform: (() -> Void)?
    convenience init(_ title: String, action: @escaping () -> Void) {
        self.init(title: title, target: nil, action: #selector(invoke))
        bezelStyle = .rounded; font = .systemFont(ofSize: 12)
        contentTintColor = tokensAccentInk; target = self; perform = action
    }
    @objc private func invoke() { perform?() }
}

// The old menu-bar panel stays unchanged. This separate native window is its
// expandable entrance for accounts, periods and providers that do not fit in a popover.
final class AgentUsageWindow: NSObject, NSSearchFieldDelegate {
    static let shared = AgentUsageWindow()
    private var window: NSWindow?
    private let store: AgentUsageStore
    private let router = AgentOpenRouter()
    private var body: NSStackView?
    private var search: NSSearchField?
    private var section: NSSegmentedControl?
    private var category: NSPopUpButton?
    private var diagnostics = false
    private var dayRange = 30
    private var submitted: [AgentClientDay] = []
    private var account = ""
    private var fetchedAt: Date?
    private var submittedAt: Date?
    private var sourceFailed = false
    private var refreshSource: (() -> Void)?
    private var filter = ""
    private var categoryIndex = 0

    init(store: AgentUsageStore = AgentUsageStore()) {
        self.store = store
        super.init()
        router.changed = { [weak self] in self?.rebuild() }
    }
    func show(server: ServerStats?, username: String, fetched: Date?, failed: Bool,
              refresh: @escaping () -> Void) {
        refreshSource = refresh
        update(server: server, username: username, fetched: fetched, failed: failed)
        if window == nil { makeWindow() }
        rebuild()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        router.refresh()
    }
    func update(server: ServerStats?, username: String, fetched: Date?, failed: Bool) {
        account = username; fetchedAt = fetched; submittedAt = server?.updatedAt; sourceFailed = failed
        submitted = server?.contribs.flatMap { day in
            day.clients.map { AgentClientDay(date: day.date, client: $0.name,
                                             tokens: $0.tokens, estimatedUSD: $0.cost) }
        } ?? []
        if window?.isVisible == true { rebuild() }
    }
    private func makeWindow() {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 660),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable],
                         backing: .buffered, defer: false)
        w.title = agentText("TokensBar · Agent usage", "TokensBar · Agent 用量")
        w.isReleasedWhenClosed = false; w.minSize = NSSize(width: 660, height: 520)
        w.center(); w.contentView = AgentBackgroundView(frame: NSRect(x: 0, y: 0, width: 760, height: 660))
        let root = NSStackView(); root.orientation = .vertical; root.alignment = .leading; root.spacing = 12
        root.translatesAutoresizingMaskIntoConstraints = false
        w.contentView?.addSubview(root)
        guard let content = w.contentView else { return }
        NSLayoutConstraint.activate([root.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 22),
            root.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -22),
            root.topAnchor.constraint(equalTo: content.topAnchor, constant: 18),
            root.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16)])
        root.addArrangedSubview(label(agentText("Agent usage", "Agent 用量"), size: 22, weight: .semibold))
        root.addArrangedSubview(label(agentText("One entrance. Separate units, accounts and shared pools.",
            "统一入口，保留每家的单位、账号与共享额度。"), size: 12, secondary: true))
        let controls = NSStackView(); controls.orientation = .horizontal; controls.spacing = 8
        let segments = NSSegmentedControl(labels: [agentText("My usage", "我的用量"), agentText("Service catalog", "服务目录")],
            trackingMode: .selectOne, target: self, action: #selector(changeSection(_:)))
        segments.selectedSegment = 0; segments.controlSize = .small
        controls.addArrangedSubview(segments); section = segments
        let spacer = NSView(); spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        controls.addArrangedSubview(spacer)
        controls.addArrangedSubview(AgentButton(agentText("Add record", "添加记录")) { [weak self] in self?.edit(nil) })
        controls.addArrangedSubview(AgentButton(agentText("Import", "导入")) { [weak self] in self?.importFile() })
        controls.addArrangedSubview(AgentButton(agentText("Export", "导出")) { [weak self] in self?.exportFile() })
        root.addArrangedSubview(controls); controls.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        let filters = NSStackView(); filters.orientation = .horizontal; filters.spacing = 8
        let field = NSSearchField(); field.placeholderString = agentText("Search services, accounts or notes", "搜索服务、账号或备注")
        field.delegate = self; field.setAccessibilityLabel(field.placeholderString)
        filters.addArrangedSubview(field); search = field
        let picker = NSPopUpButton(); picker.addItems(withTitles: [agentText("All services", "全部服务"),
            agentText("Personal agents", "个人 Agent"), agentText("Coding agents", "编码 Agent"), "API"])
        picker.target = self; picker.action = #selector(changeCategory(_:)); category = picker
        filters.addArrangedSubview(picker); picker.widthAnchor.constraint(equalToConstant: 160).isActive = true
        root.addArrangedSubview(filters); filters.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.drawsBackground = false
        let stack = AgentDocumentStack(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false; scroll.documentView = stack
        root.addArrangedSubview(scroll); scroll.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 250).isActive = true
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentView.topAnchor)])
        body = stack; window = w
        root.addArrangedSubview(label(agentText("Local records stay on this Mac. Unknown is not zero. No cross-service grand total.",
            "手动记录仅保存在这台 Mac；未知不等于零，不跨服务混算总量。"), size: 11, secondary: true))
    }
    @objc private func changeSection(_ sender: NSSegmentedControl) { rebuild() }
    @objc private func changeCategory(_ sender: NSPopUpButton) { categoryIndex = sender.indexOfSelectedItem; rebuild() }
    func controlTextDidChange(_ obj: Notification) { filter = search?.stringValue ?? ""; rebuild() }
    private func matches(_ provider: AgentProvider?, extra: String = "") -> Bool {
        let cats = ["", "personal", "coding", "api"]
        if categoryIndex > 0 && provider?.category != cats[categoryIndex] { return false }
        return filter.isEmpty || ((provider?.name ?? "") + " " + extra)
            .localizedCaseInsensitiveContains(filter)
    }
    private func label(_ text: String, size: CGFloat = 12, weight: NSFont.Weight = .regular,
                       secondary: Bool = false) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: text)
        field.font = .systemFont(ofSize: size, weight: weight)
        field.textColor = secondary ? .secondaryLabelColor : .labelColor
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }
    private func card(_ title: String, _ lines: [String], buttons: [AgentButton] = [], accent: Bool = false) {
        guard let body else { return }
        let box = NSBox(); box.boxType = .custom; box.cornerRadius = 10
        box.fillColor = .controlBackgroundColor; box.borderColor = accent ? tokensAccent.withAlphaComponent(0.55) : .separatorColor
        box.borderWidth = 1; box.contentViewMargins = NSSize(width: 14, height: 12)
        let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 7
        stack.translatesAutoresizingMaskIntoConstraints = false
        box.contentView?.addSubview(stack)
        if let content = box.contentView {
            NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
                stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
                stack.topAnchor.constraint(equalTo: content.topAnchor), stack.bottomAnchor.constraint(equalTo: content.bottomAnchor)])
        }
        stack.addArrangedSubview(label(title, size: 14, weight: .semibold))
        for line in lines { let l = label(line, secondary: true); stack.addArrangedSubview(l)
            l.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        if !buttons.isEmpty {
            let row = NSStackView(views: buttons); row.spacing = 8; stack.addArrangedSubview(row)
        }
        body.addArrangedSubview(box); box.widthAnchor.constraint(equalTo: body.widthAnchor).isActive = true
    }
    private func rebuild() {
        guard let body else { return }
        body.arrangedSubviews.forEach { body.removeArrangedSubview($0); $0.removeFromSuperview() }
        if let error = store.loadError {
            card(agentText("Existing records could not be read", "现有记录无法读取"),
                 [error.localizedDescription, agentText("The original file is preserved. New saves/imports are disabled until it is repaired.", "已保留原文件；修复前不会覆盖或导入新记录。")])
        }
        if section?.selectedSegment == 1 { catalog(); return }
        if (categoryIndex == 0 || categoryIndex == 2) && (filter.isEmpty || ("tokens.ci clients Tokens CLI " + submitted.map { $0.client }.joined(separator: " ")).localizedCaseInsensitiveContains(filter)) { clientCard() }
        if !diagnostics && matches(AgentCatalog.all.first { $0.id == "openrouter" }) { routerCard() }
        let records = store.records.filter { record in
            matches(AgentCatalog.all.first { $0.id == record.providerID }, extra: record.account + " " + record.metric + " " + record.note)
        }.sorted { $0.observedAt > $1.observedAt }
        let title = label(agentText("Manual & imported snapshots · \(records.count)", "手动与导入快照 · \(records.count)"), size: 13, weight: .medium)
        body.addArrangedSubview(title)
        if records.isEmpty {
            card(agentText("Track what the service actually reports", "记录服务实际显示的数据"),
                [agentText("Add a snapshot for remaining allowance, consumption, tokens or cost. Leave unavailable fields blank. Each snapshot has its own unit, period and reset.",
                 "可记录剩余额度、已用量、token 或费用；不知道的字段留空，每条记录保留独立单位、周期与重置时间。"),
                 agentText("Browse the catalog for supported source types and shared-pool caveats. Listing a service never connects your account.",
                 "在服务目录查看数据来源与共享额度边界；列出服务不代表账号已连接。")],
                buttons: [AgentButton(agentText("Browse services", "浏览服务")) { [weak self] in self?.section?.selectedSegment = 1; self?.rebuild() }])
        }
        for record in records {
            let provider = AgentCatalog.all.first { $0.id == record.providerID }
            var title = provider?.name ?? record.providerID
            if !record.account.isEmpty { title += " · " + record.account }
            let state = record.origin == .imported ? agentText("Imported", "文件导入") : agentText("Manual", "手动记录")
            let stale = record.isStale(at: Date()) ? agentText(" · stale snapshot", " · 旧快照") : ""
            var lines = [state + stale + " · " + agentText("Observed ", "记录于 ") + date(record.observedAt)]
            if !record.metric.isEmpty { lines.append(record.metric) }
            lines.append(agentText("Used ", "已用 ") + agentNumber(record.used) + " / " + agentNumber(record.allowance)
                         + " " + record.unit + " · " + agentText("Remaining ", "剩余 ") + agentNumber(record.remaining))
            if let overage = record.overage, overage > 0 { lines.append(agentText("Over allowance: ", "超出额度：") + agentNumber(overage) + " " + record.unit) }
            if record.tokens != nil || record.cost != nil { lines.append("Token: " + agentNumber(record.tokens) + " · "
                + agentText("Cost: ", "费用：") + agentNumber(record.cost) + (record.cost == nil ? "" : " " + record.currency)) }
            lines.append(date(record.periodStart) + " → " + date(record.periodEnd) + agentText(" (end exclusive)", "（不含结束时刻）"))
            if let reset = record.resetAt { lines.append(agentText("Reset ", "重置 ") + date(reset)) }
            if !record.sharedPool.isEmpty { lines.append(agentText("Shared pool: ", "共享池：") + record.sharedPool + agentText(" · do not add this pool twice", " · 不重复加总此池")) }
            if !record.note.isEmpty { lines.append(record.note) }
            card(title, lines, buttons: [AgentButton(agentText("Edit", "编辑")) { [weak self] in self?.edit(record) },
                AgentButton(agentText("Delete", "删除")) { [weak self] in self?.remove(record) }])
        }
    }
    private func date(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm zzz"; return f.string(from: date)
    }
    private func clientCard() {
        var utc = Calendar(identifier: .gregorian); utc.timeZone = TimeZone(secondsFromGMT: 0)!
        let end = utc.date(byAdding: .day, value: 1, to: utc.startOfDay(for: Date()))!
        let start = utc.date(byAdding: .day, value: -dayRange, to: end)!
        let totals = agentSubmittedTotals(submitted, start: start, end: end)
        var lines = [agentText("Automatic · configured tokens.ci account: ", "自动来源 · 当前 tokens.ci 账号：") + (account.isEmpty ? agentText("not configured", "未配置") : account),
                     agentText("\(dayRange) UTC calendar days including today. Submitted client activity only; not subscription balance. Cost is an estimate.",
                      "含今天的 \(dayRange) 个 UTC 自然日。仅统计已提交的客户端活动，不是订阅余额；费用为估算值。")]
        if let fetchedAt { lines.append(agentText("Last fetched ", "上次获取 ") + date(fetchedAt)) }
        if let submittedAt { lines.append(agentText("Account submission updated ", "账号提交更新于 ") + date(submittedAt)) }
        if sourceFailed { lines.append(agentText("Latest refresh failed; retained records may be old.", "最近一次刷新失败，保留记录可能已过期。")) }
        if totals.isEmpty { lines.append(agentText("No client-day records in the returned period. This does not mean zero use or that the client is unsupported.", "返回数据在此区间没有客户端明细；不表示没有使用或客户端不受支持。")) }
        for item in totals { lines.append("\(item.client)   \(agentNumber(Double(item.tokens))) token   ≈\(agentNumber(item.estimatedUSD)) USD") }
        lines.append(agentText("Local totals and provider/API bills are not added to these rows. Services without client-day data remain separate.",
                               "本机总量及供应商/API 账单不叠加到这些行；未返回每日客户端数据的服务单独保留。"))
        let ranges = [1, 7, 30].map { days in AgentButton(days == 1 ? agentText("Today", "今天") : agentText("\(days) days", "\(days) 天")) { [weak self] in self?.dayRange = days; self?.rebuild() } }
        card(agentText("Submitted coding activity", "已提交的编码活动"), lines, buttons: ranges + [AgentButton(agentText("Refresh", "刷新")) { [weak self] in self?.refreshSource?() }], accent: true)
    }
    private func routerCard() {
        var lines = [agentText("Optional official per-key API · never your full account balance or a subscription quota.", "可选官方单 key 接口，不代表整个账户余额或订阅额度。")]
        var buttons: [AgentButton] = []
        if router.connected {
            lines.append(router.busy ? agentText("Refreshing…", "正在刷新…") : agentText("Connected · refreshed on open, at most once every five minutes", "已连接 · 打开时刷新，最多每五分钟一次"))
            if let s = router.snapshot {
                lines.append(agentText("Lifetime spend ", "累计费用 ") + agentNumber(s.lifetimeUSD) + " USD")
                lines.append(agentText("UTC today / week / month: ", "UTC 今日 / 本周 / 本月：") + [s.dailyUSD, s.weeklyUSD, s.monthlyUSD].map { agentNumber($0) }.joined(separator: " / ") + " USD")
                lines.append(agentText("Key cap ", "Key 上限 ") + agentNumber(s.keyLimitUSD) + " USD · " + agentText("Key remaining ", "Key 剩余 ") + agentNumber(s.keyRemainingUSD) + " USD")
                lines.append(agentText("Cap reset rule: ", "上限重置规则：") + (s.limitReset ?? agentText("not reported", "未返回")))
                if let include = s.includeBYOK { lines.append("BYOK: " + (include ? agentText("included in key limit", "计入 key 上限") : agentText("not included in key limit", "不计入 key 上限"))) }
                lines.append(agentText("Observed ", "获取于 ") + date(s.observedAt))
            }
            if let error = router.lastError { lines.append(error) }
            buttons = [AgentButton(agentText("Refresh key", "刷新 key")) { [weak self] in self?.router.refresh() },
                       AgentButton(agentText("Disconnect", "断开连接")) { [weak self] in self?.disconnectRouter() }]
        } else {
            lines.append(agentText("No key is connected. Optional connection reads one key’s spend and cap; it makes no model calls. That key can still spend elsewhere: use a dedicated low-limit key.",
                "未连接密钥。可选连接只读取一个 key 的费用与上限，不调用模型；该 key 在其他地方仍可消费，建议使用专门的低限额 key。"))
            buttons = [AgentButton(agentText("Connect optional key…", "可选连接 key…")) { [weak self] in self?.connectRouter() }]
        }
        card("OpenRouter", lines, buttons: buttons)
    }
    private func catalog() {
        body?.addArrangedSubview(label(agentText("\(AgentCatalog.all.count) researched entries · checked \(AgentCatalog.checkedOn). Representative, not exhaustive.",
            "\(AgentCatalog.all.count) 项服务 · 核对于 \(AgentCatalog.checkedOn)，广泛覆盖但非穷尽。"), size: 12, secondary: true))
        for provider in AgentCatalog.all.filter({ matches($0, extra: $0.note) }) {
            let type = provider.upstreamClient ? agentText("Upstream coding client · actual submitted records only", "上游编码客户端 · 仅实际提交记录可自动展示")
                : provider.id == "openrouter" ? agentText("Optional official connector · not connected by catalog inclusion", "可选官方接口 · 列入目录不代表已连接")
                : agentText("Manual / import available · account not connected", "可手动 / 导入 · 未连接账户")
            card(provider.name, [type, provider.note], buttons: [
                AgentButton(agentText("Record usage", "记录用量")) { [weak self] in self?.edit(nil, providerID: provider.id) },
                AgentButton(agentText("Source documentation", "来源文档")) { if let url = URL(string: provider.documentation) { NSWorkspace.shared.open(url) } }])
        }
    }
    private func message(_ title: String, _ detail: String) { let a = NSAlert(); a.messageText = title; a.informativeText = detail; a.runModal() }
    private func remove(_ record: AgentUsageRecord) {
        let a = NSAlert(); a.messageText = agentText("Delete this local snapshot?", "删除此本地快照？")
        a.informativeText = agentText("This does not alter your provider account.", "不会修改服务商账号。")
        a.addButton(withTitle: agentText("Delete", "删除")); a.addButton(withTitle: agentText("Cancel", "取消"))
        guard a.runModal() == .alertFirstButtonReturn else { return }
        do { try store.remove(id: record.id); rebuild() } catch { message(agentText("Could not delete", "删除失败"), error.localizedDescription) }
    }
    private func importFile() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            guard (attributes[.size] as? NSNumber)?.intValue ?? Int.max <= 5_000_000 else { throw AgentUsageError.tooLarge }
            let data = try Data(contentsOf: url)
            let parsed = try AgentUsageStore.decode(data, importing: true)
            let alert = NSAlert(); alert.messageText = agentText("Import \(parsed.count) snapshots?", "导入 \(parsed.count) 条快照？")
            alert.informativeText = agentText("Matching IDs replace the same local snapshot; other records are kept. All imported values are labelled imported, not automatic.", "相同 ID 会更新对应本地快照，其余记录保留；所有数据标为文件导入，不冒充自动来源。")
            alert.addButton(withTitle: agentText("Import", "导入")); alert.addButton(withTitle: agentText("Cancel", "取消"))
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            try store.importData(data); rebuild()
        } catch { message(agentText("Nothing imported", "未导入数据"), error.localizedDescription) }
    }
    private func exportFile() {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "TokensBar-agent-usage.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try store.exportData().write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch { message(agentText("Could not export", "导出失败"), error.localizedDescription) }
    }
    private func connectRouter() {
        let alert = NSAlert(); alert.messageText = agentText("Connect an OpenRouter key", "连接 OpenRouter key")
        alert.informativeText = agentText("Optional. Saved only in macOS Keychain, never exported or sent to tokens.ci. Calls only GET /api/v1/key. A normal API key is not read-only and can authorize charges elsewhere; use a dedicated low-limit key. No management key is needed.",
            "可选。仅保存在 macOS 钥匙串，不导出、不上传 tokens.ci；只查询 GET /api/v1/key。普通 API key 并非只读，在其他地方可能产生费用，建议专用低限额 key；无需管理密钥。")
        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 390, height: 24))
        field.placeholderString = "OpenRouter API key"; field.setAccessibilityLabel("OpenRouter API key")
        alert.accessoryView = field
        alert.addButton(withTitle: agentText("Save in Keychain & read", "存入钥匙串并读取")); alert.addButton(withTitle: agentText("Cancel", "取消"))
        guard alert.runModal() == .alertFirstButtonReturn else { field.stringValue = ""; return }
        do { try router.connect(key: field.stringValue) } catch { message(agentText("Connection not saved", "连接未保存"), error.localizedDescription) }
        field.stringValue = ""
    }
    private func disconnectRouter() {
        let a = NSAlert(); a.messageText = agentText("Remove the saved key from this Mac?", "从此 Mac 删除保存的 key？")
        a.informativeText = agentText("This disconnects TokensBar. It does not revoke the key at OpenRouter.", "仅断开 TokensBar，不会在 OpenRouter 撤销此 key。")
        a.addButton(withTitle: agentText("Disconnect", "断开")); a.addButton(withTitle: agentText("Cancel", "取消"))
        guard a.runModal() == .alertFirstButtonReturn else { return }
        do { try router.disconnect() } catch { message(agentText("Could not disconnect", "断开失败"), error.localizedDescription) }
    }

    // Isolated diagnostic: synthetic records, no Keychain read or network refresh.
    static func renderDiagnostics(to directory: String, dark: Bool, catalog: Bool) throws {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let store = AgentUsageStore(url: temporary.appendingPathComponent("demo.json"))
        let now = Date()
        var sample = AgentUsageRecord(providerID: "muse", periodStart: now.addingTimeInterval(-86400), periodEnd: now.addingTimeInterval(6 * 86400))
        sample.account = agentText("Demo account", "演示账号")
        sample.metric = agentText("DEMO · weekly allowance", "演示数据 · 每周额度")
        sample.unit = "Muse tokens"; sample.used = 240; sample.allowance = 1000
        sample.observedAt = now; sample.resetAt = sample.periodEnd
        sample.note = agentText("Synthetic values, not a connected account.", "虚构演示数值，不是已连接账号。")
        try store.save(sample)
        NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let controller = AgentUsageWindow(store: store)
        controller.diagnostics = true
        controller.account = "demo-user"
        controller.submitted = [AgentClientDay(date: now, client: "Claude Code", tokens: 125000, estimatedUSD: 1.25)]
        controller.fetchedAt = now
        controller.makeWindow()
        guard let window = controller.window, let content = window.contentView else { throw AgentUsageError.invalidText }
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.setContentSize(NSSize(width: 900, height: 940))
        // Remove the optional router card from diagnostic content so no real saved key is read.
        controller.filter = ""
        controller.search?.stringValue = controller.filter
        controller.section?.selectedSegment = catalog ? 1 : 0
        controller.rebuild()
        content.layoutSubtreeIfNeeded()
        // Exercise the actual native search/category/section event paths. No account access.
        controller.section?.selectedSegment = 1
        controller.changeSection(controller.section!)
        precondition(controller.body?.arrangedSubviews.count == AgentCatalog.all.count + 1)
        controller.search?.stringValue = "a-service-that-does-not-exist"
        controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
        precondition(controller.body?.arrangedSubviews.count == 1, "Empty catalog search must hide services")
        controller.search?.stringValue = ""
        controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
        controller.category?.selectItem(at: 3)
        controller.changeCategory(controller.category!)
        precondition(controller.body?.arrangedSubviews.count == AgentCatalog.all.filter { $0.category == "api" }.count + 1)
        controller.category?.selectItem(at: 0)
        controller.changeCategory(controller.category!)
        controller.section?.selectedSegment = 0
        controller.changeSection(controller.section!)
        precondition(controller.body?.arrangedSubviews.count == 3, "Demo must show submitted activity, snapshot title and one manual record")
        controller.dayRange = 7; controller.rebuild()
        precondition(controller.body?.arrangedSubviews.count == 3)
        controller.dayRange = 30
        controller.section?.selectedSegment = catalog ? 1 : 0
        controller.rebuild()
        print("PASS: 5 native Agent control-path checks")
        content.layoutSubtreeIfNeeded()
        // Fixed content surface, no synthetic substitute drawing or post-export upscaling.
        let scale: CGFloat = 2
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
            pixelsWide: Int(content.bounds.width * scale), pixelsHigh: Int(content.bounds.height * scale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { throw AgentUsageError.invalidText }
        rep.size = content.bounds.size
        content.cacheDisplay(in: content.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { throw AgentUsageError.invalidText }
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        let name = "agent-\(catalog ? "catalog" : "usage")-\(L10n.current.rawValue)-\(dark ? "dark" : "light").png"
        try data.write(to: URL(fileURLWithPath: directory).appendingPathComponent(name))
        print("native agent view \(name): \(rep.pixelsWide)x\(rep.pixelsHigh), cards=\(controller.body?.arrangedSubviews.count ?? 0)")
        window.close()
    }

    private func edit(_ original: AgentUsageRecord?, providerID: String? = nil) {
        guard store.loadError == nil else { return }
        let alert = NSAlert(); alert.messageText = agentText("Usage snapshot", "用量快照")
        alert.informativeText = agentText("Read values from the official dashboard. Blank = unknown. Used, allowance and remaining must share one unit and pool. Dates use this Mac’s time zone; period end is exclusive.",
            "从官方用量页抄录；空白表示未知。已用、额度与剩余必须属于同一单位、同一共享池。时间按这台 Mac 的时区，周期不含结束时刻。")
        let form = NSStackView(); form.orientation = .vertical; form.alignment = .leading; form.spacing = 6
        form.translatesAutoresizingMaskIntoConstraints = false
        form.widthAnchor.constraint(equalToConstant: 480).isActive = true
        let providers = AgentCatalog.all.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        let provider = NSPopUpButton(); provider.addItems(withTitles: providers.map { $0.name } + [agentText("Other / custom service", "其他 / 自定义服务")])
        if let id = original?.providerID ?? providerID, let index = providers.firstIndex(where: { $0.id == id }) { provider.selectItem(at: index) }
        else { provider.selectItem(at: providers.count) }
        func row(_ title: String, _ input: NSView) {
            let row = NSStackView(); row.orientation = .horizontal; row.spacing = 10
            let text = label(title, size: 11); text.widthAnchor.constraint(equalToConstant: 132).isActive = true
            row.addArrangedSubview(text); row.addArrangedSubview(input); form.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: form.widthAnchor).isActive = true
            input.setAccessibilityLabel(title)
        }
        func text(_ title: String, _ value: String, _ placeholder: String = "") -> NSTextField {
            let f = NSTextField(string: value); f.placeholderString = placeholder; f.font = .systemFont(ofSize: 12); row(title, f); return f
        }
        func numeric(_ title: String, _ value: Double?) -> NSTextField { text(title, value.map { String($0) } ?? "", agentText("Unknown", "未知")) }
        row(agentText("Service", "服务"), provider)
        let custom = text(agentText("Custom service name", "自定义服务名"), original.flatMap { record in providers.contains(where: { $0.id == record.providerID }) ? nil : record.providerID } ?? "")
        let accountField = text(agentText("Account label", "账号标签"), original?.account ?? "", agentText("Optional; no credentials", "可选，不填凭据"))
        let metric = text(agentText("Metric / window", "指标 / 窗口"), original?.metric ?? "", agentText("e.g. weekly allowance", "例如：每周额度"))
        let initialProvider = providers.indices.contains(provider.indexOfSelectedItem) ? providers[provider.indexOfSelectedItem] : nil
        let unit = text(agentText("Exact unit", "实际单位"), original?.unit ?? (initialProvider?.unit == "service-reported units" ? "" : initialProvider?.unit) ?? "", "credits / % / requests / …")
        let used = numeric(agentText("Used", "已用"), original?.used)
        let allowance = numeric(agentText("Allowance", "额度"), original?.allowance)
        let remaining = numeric(agentText("Reported remaining", "页面显示剩余"), original?.remainingReported)
        let tokens = numeric("Token", original?.tokens)
        let cost = numeric(agentText("Cost", "费用"), original?.cost)
        let currency = text(agentText("Currency", "货币代码"), original?.currency ?? "USD")
        func datePicker(_ title: String, _ date: Date) -> NSDatePicker {
            let picker = NSDatePicker(); picker.datePickerStyle = .textFieldAndStepper
            picker.datePickerElements = [.yearMonthDay, .hourMinute]; picker.dateValue = date
            row(title, picker); return picker
        }
        let startDate = Calendar.current.startOfDay(for: Date())
        let endDate = Calendar.current.date(byAdding: .day, value: 7, to: startDate)!
        let start = datePicker(agentText("Period start", "周期开始"), original?.periodStart ?? startDate)
        let end = datePicker(agentText("Period end", "周期结束"), original?.periodEnd ?? endDate)
        let observed = datePicker(agentText("Observed at", "记录时间"), original?.observedAt ?? Date())
        let resetOn = NSButton(checkboxWithTitle: agentText("Reset time known", "已知重置时间"), target: nil, action: nil)
        resetOn.state = original?.resetAt == nil ? .off : .on; form.addArrangedSubview(resetOn)
        let reset = datePicker(agentText("Next reset", "下次重置"), original?.resetAt ?? endDate)
        let pool = text(agentText("Shared pool label", "共享池标签"), original?.sharedPool ?? "", agentText("e.g. Claude app + Code", "例如：Claude 应用 + Code"))
        let note = text(agentText("Notes", "备注"), original?.note ?? "")
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 500, height: 400)); scroll.hasVerticalScroller = true
        let holder = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: 680)); holder.addSubview(form)
        NSLayoutConstraint.activate([form.leadingAnchor.constraint(equalTo: holder.leadingAnchor),
            form.topAnchor.constraint(equalTo: holder.topAnchor), form.bottomAnchor.constraint(equalTo: holder.bottomAnchor)])
        scroll.documentView = holder; alert.accessoryView = scroll
        alert.addButton(withTitle: agentText("Save snapshot", "保存快照")); alert.addButton(withTitle: agentText("Cancel", "取消"))
        while alert.runModal() == .alertFirstButtonReturn {
            do {
                func number(_ field: NSTextField) throws -> Double? {
                    let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    if text.isEmpty { return nil }
                    guard let value = Double(text), value.isFinite, value >= 0 else { throw AgentUsageError.invalidNumber }
                    return value
                }
                let id = providers.indices.contains(provider.indexOfSelectedItem) ? providers[provider.indexOfSelectedItem].id : custom.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                var record = AgentUsageRecord(providerID: id, periodStart: start.dateValue, periodEnd: end.dateValue)
                if let original { record.id = original.id }
                record.account = accountField.stringValue; record.metric = metric.stringValue; record.unit = unit.stringValue
                record.used = try number(used); record.allowance = try number(allowance); record.remainingReported = try number(remaining)
                record.tokens = try number(tokens); record.cost = try number(cost); record.currency = currency.stringValue.uppercased()
                record.observedAt = observed.dateValue; record.resetAt = resetOn.state == .on ? reset.dateValue : nil
                record.sharedPool = pool.stringValue; record.note = note.stringValue; record.origin = .manual
                try store.save(record); rebuild(); return
            } catch { message(agentText("Not saved", "未保存"), error.localizedDescription) }
        }
    }
}
