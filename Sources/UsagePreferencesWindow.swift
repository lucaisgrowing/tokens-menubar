import AppKit
import UserNotifications

private final class UsageFlippedDocument: NSView { override var isFlipped: Bool { true } }

struct PreferencesSnapshot {
    var config: Config
    var comparison: UsageComparison?
    var todayTokens: Int?
    var serverError: String?
    var serverAttempt: Date?
    var serverFetched: Date?
    var submitted: Date?
    var localSuccess: Date?
    var localAttempt: Date?
    var localFailed: Bool
    var localError: String?
    var cliPath: String?
    var hasServer: Bool
    var loading: Bool
}

final class CostNotifications {
    static let shared = CostNotifications()
    private let defaults = UserDefaults.standard
    private var pending = Set<String>()
    private(set) var status = agentText("Notifications off until enabled and allowed by macOS.", "启用且获得 macOS 允许后才会通知。")
    var monthlyThreshold: Double { defaults.double(forKey: "cost.monthThreshold") }
    var interval: TimeInterval { defaults.double(forKey: "cost.notificationInterval") }
    func inspectPermission(_ completion: @escaping () -> Void) {
        guard interval > 0 else { status = agentText("Notifications off; menu-bar colour still works.", "通知已关闭；菜单栏颜色提醒仍生效。"); completion(); return }
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                self.status = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional ? agentText("macOS allows notifications; Focus and system settings may hide them.", "macOS 已允许通知；专注模式和系统设置可能隐藏横幅。") : agentText("macOS has not allowed notifications. Save to request permission, or check System Settings → Notifications.", "macOS 尚未允许通知；保存以请求授权，或查看「系统设置 → 通知」。")
                completion()
            }
        }
    }
    func authorize(_ completion: @escaping () -> Void) {
        guard interval > 0 else { status = agentText("Notifications off; menu-bar colour still works.", "通知已关闭；菜单栏颜色提醒仍生效。"); completion(); return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { allowed, error in
            DispatchQueue.main.async {
                self.status = allowed ? agentText("Allowed by macOS. Delivery still depends on Focus and system settings.", "macOS 已允许；是否显示仍受专注模式与系统设置影响。") : agentText("macOS has not allowed notifications. You can allow TokensBar in System Settings → Notifications.", "macOS 未允许通知；可在「系统设置 → 通知」允许 TokensBar。")
                if error != nil { self.status = agentText("Notification permission could not be checked.", "未能确认通知权限。") }; completion()
            }
        }
    }
    func evaluate(daily: Double?, dailyObserved: Date?, dailyThreshold: Double, projection: Double?, monthObserved: Date?) {
        let rule = CostAlertRule(daily: dailyThreshold, monthly: monthlyThreshold, interval: interval)
        guard interval > 0 else { return }
        let now = Date(), day = dayFormatter.string(from: now)
        for (kind, value, threshold, observed) in [("daily", daily, rule.daily, dailyObserved), ("projection", projection, rule.monthly, monthObserved)] {
            let key = interval >= 86400 ? "cost.accepted.\(day).\(kind)" : "cost.accepted.rolling.\(kind)"
            let previous = defaults.object(forKey: key) as? Date
            guard !pending.contains(key), rule.eligible(value: value, threshold: threshold, observed: observed, now: now, previous: previous) else { continue }
            pending.insert(key)
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { DispatchQueue.main.async { self.pending.remove(key) }; return }
                let content = UNMutableNotificationContent()
                content.title = kind == "daily" ? agentText("Estimated daily spend", "今日估算费用") : agentText("Estimated month-end projection", "月末估算预测")
                content.body = agentText("≈\(fmtMoney(value!)), threshold \(fmtMoney(threshold)). Usage-price estimate, not a bill.", "≈\(fmtMoney(value!))，阈值 \(fmtMoney(threshold))。按用量计价估算，不是实际账单。")
                content.sound = .default
                let request = UNNotificationRequest(identifier: "tokensbar.\(kind).\(UUID().uuidString)", content: content, trigger: nil)
                UNUserNotificationCenter.current().add(request) { error in
                    DispatchQueue.main.async {
                        self.pending.remove(key)
                        if error == nil { self.defaults.set(now, forKey: key); self.status = agentText("Last accepted by macOS at ", "最近被 macOS 接受于 ") + fmtClock(now) + agentText("; display is not confirmed.", "；不代表已经显示。") }
                        else { self.status = agentText("macOS did not accept the notification. It was not recorded as delivered.", "macOS 未接受这条通知，未记为送达。") }
                    }
                }
            }
        }
    }
}

final class UsagePreferencesWindow: NSObject {
    static let shared = UsagePreferencesWindow()
    private var window: NSWindow?
    private var stack: NSStackView?
        private var snapshot: PreferencesSnapshot?
    private var chosenTab = 0
    private var order: [String] = []
    private var enabled: Set<String> = []
    private var dailyField: NSTextField?
    private var monthlyField: NSTextField?
    private var frequency: NSPopUpButton?
    private var feedback: NSTextField?
    var onChange: (([String], Double) -> Void)?
    var onRefresh: (() -> Void)?
    var onSubmit: (() -> Void)?
    var onReadToken: (() -> Void)?
    func show(_ value: PreferencesSnapshot, tab: Int = 0) {
        snapshot = value; chosenTab = tab
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 550), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            w.title = "TokensBar"; w.isReleasedWhenClosed = false; w.center(); window = w
        }
        configure(); window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    func update(_ value: PreferencesSnapshot) { snapshot = value; if window?.isVisible == true && chosenTab < 2 { configure() } }
    private func label(_ text: String, size: CGFloat = 12, weight: NSFont.Weight = .regular, secondary: Bool = false) -> NSTextField {
        let l = NSTextField(wrappingLabelWithString: text)
        l.font = .systemFont(ofSize: size, weight: weight)
        l.textColor = secondary ? .secondaryLabelColor : .labelColor
        l.maximumNumberOfLines = 0
        l.setContentCompressionResistancePriority(.required, for: .vertical)
        return l
    }
    private func button(_ text: String, _ selector: Selector, tag: Int = 0, primary: Bool = false) -> NSButton {
        let b = UsageButton(title: text, target: self, action: selector)
        b.bezelStyle = .rounded; b.isBordered = false; b.tag = tag; b.primary = primary
        b.heightAnchor.constraint(equalToConstant: 29).isActive = true
        b.widthAnchor.constraint(greaterThanOrEqualToConstant: 34).isActive = true
        return b
    }
    private func configure() {
        guard let window, let snapshot else { return }
        let root = NSView(); window.contentView = root
        let title = label(agentText("Usage & display", "用量与显示"), size: 18, weight: .semibold)
        let subtitle = label(agentText("A clearer view of your usage. A menu bar that fits.", "看清用量，按自己的习惯显示。"), secondary: true)
        let names = [agentText("Trends", "趋势"), agentText("Data health", "数据状态"), agentText("Menu bar", "菜单栏"), agentText("Alerts", "提醒")]
        let navigation = NSStackView(); navigation.orientation = .horizontal; navigation.spacing = 5; navigation.distribution = .fillEqually
        for (i, name) in names.enumerated() {
            let b = button(name, #selector(navigationChanged(_:)), tag: i) as! UsageButton
            b.navigation = true; b.state = chosenTab == i ? .on : .off
            b.setAccessibilityLabel(name); b.setAccessibilityValue(chosenTab == i ? agentText("Selected", "已选择") : agentText("Not selected", "未选择"))
            navigation.addArrangedSubview(b)
        }
        let body = NSStackView(); body.orientation = .vertical; body.alignment = .leading; body.spacing = 12; self.stack = body
        let scroll = NSScrollView(); scroll.drawsBackground = false; scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        let doc = UsageFlippedDocument(); scroll.documentView = doc; body.translatesAutoresizingMaskIntoConstraints = false; doc.addSubview(body)
        for view in [title, subtitle, navigation, scroll] { view.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(view) }
        doc.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 22), title.topAnchor.constraint(equalTo: root.topAnchor, constant: 20),
            subtitle.leadingAnchor.constraint(equalTo: title.leadingAnchor), subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 5), subtitle.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -22),
            navigation.leadingAnchor.constraint(equalTo: title.leadingAnchor), navigation.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -22), navigation.topAnchor.constraint(equalTo: subtitle.bottomAnchor, constant: 15),
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 22), scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -18), scroll.topAnchor.constraint(equalTo: navigation.bottomAnchor, constant: 16), scroll.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -16),
            doc.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor), body.leadingAnchor.constraint(equalTo: doc.leadingAnchor), body.trailingAnchor.constraint(equalTo: doc.trailingAnchor, constant: -4), body.topAnchor.constraint(equalTo: doc.topAnchor), body.bottomAnchor.constraint(equalTo: doc.bottomAnchor, constant: -8)])
        switch chosenTab { case 0: trends(snapshot); case 1: health(snapshot); case 2: display(snapshot); default: alerts(snapshot) }
    }
    private func add(_ text: String, size: CGFloat = 12, weight: NSFont.Weight = .regular, secondary: Bool = false) {
        guard let stack else { return }; let l = label(text, size: size, weight: weight, secondary: secondary)
        stack.addArrangedSubview(l); l.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }
    private func heading(_ text: String) { add(text, size: 12, weight: .semibold) }
    private func card(accented: Bool = false, _ content: () -> Void) {
        guard let outer = stack else { return }
        let surface = UsageSurface(); surface.accented = accented
        let inner = NSStackView(); inner.orientation = .vertical; inner.alignment = .leading; inner.spacing = 9
        inner.translatesAutoresizingMaskIntoConstraints = false; surface.addSubview(inner)
        outer.addArrangedSubview(surface)
        NSLayoutConstraint.activate([surface.widthAnchor.constraint(equalTo: outer.widthAnchor),
            inner.leadingAnchor.constraint(equalTo: surface.leadingAnchor, constant: 14), inner.trailingAnchor.constraint(equalTo: surface.trailingAnchor, constant: -14),
            inner.topAnchor.constraint(equalTo: surface.topAnchor, constant: 14), inner.bottomAnchor.constraint(equalTo: surface.bottomAnchor, constant: -14)])
        stack = inner; content(); stack = outer
    }
    private func row(_ views: [NSView]) {
        guard let stack else { return }
        let row = NSStackView(views: views); row.orientation = .horizontal; row.spacing = 8; row.alignment = .centerY
        stack.addArrangedSubview(row); row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }
    private func stamp(_ date: Date?) -> String {
        guard let date else { return agentText("Not yet", "尚无") }; let f = DateFormatter(); f.dateFormat = "MM-dd HH:mm z"; return f.string(from: date)
    }
    private func timestamp(_ title: String, _ date: Date?) {
        let key = label(title, size: 11, secondary: true), value = label(stamp(date), size: 11, secondary: true)
        value.alignment = .right; value.setContentCompressionResistancePriority(.required, for: .horizontal)
        row([key, NSView(), value])
    }
    private func trends(_ s: PreferencesSnapshot) {
        card(accented: true) {
            heading(agentText("Today vs. previous 7-day mean", "今日与此前 7 日均值"))
            if let c = s.comparison {
                let hero = label(c.changePercent.map { String(format: "%+.1f%%", $0) } ?? agentText("No percentage baseline", "基准为零，无法计算百分比"), size: c.changePercent == nil ? 18 : 30, weight: .semibold)
                hero.textColor = tokensAccentInk; stack?.addArrangedSubview(hero)
                row([label(agentText("Today  ", "今日  ") + fmtTokens(s.todayTokens ?? 0), weight: .medium), NSView(), label(agentText("7-day mean  ", "7 日日均  ") + fmtTokens(Int(c.mean.rounded())), secondary: true)])
                add(agentText("UTC day in progress · latest submitted activity", "UTC 今日尚未结束 · 截至最近提交"), size: 11, secondary: true)
            } else {
                add(agentText("Not enough matching data", "同口径数据不足"), size: 19, weight: .medium)
                add(agentText("Today plus each preceding UTC day is required. Missing records are not zero; local scans are not compared with all-device data.", "需要今日及此前 7 个 UTC 日记录；缺失不算零，本机扫描不与全设备均值混比。"), secondary: true)
            }
        }
        card {
            heading(agentText("Largest model contribution", "变化最多的模型"))
            if let c = s.comparison, let name = c.topModel, let delta = c.topModelDelta {
                let value = label(String(format: "%+.0f token", delta), weight: .medium); value.textColor = tokensAccentInk
                row([label(name, weight: .medium), NSView(), value])
                add(agentText("Difference from this model’s previous 7-day daily mean—not an explanation of why usage changed.", "相对此模型前 7 日日均的差额，不代表使用变化的原因。"), size: 11, secondary: true)
            } else { add(agentText("Daily model detail is incomplete or unchanged; no model attribution.", "每日模型明细不足或没有变化，不归因到具体模型。"), secondary: true) }
        }
        add(agentText("Scope · tokens.ci submitted activity across devices, by UTC calendar day. Token change, not a bill or a final daily total.", "统计口径 · tokens.ci 全设备已提交活动，按 UTC 自然日计算。这是 token 变化，不是账单或最终日总量。"), size: 11, secondary: true)
        timestamp(agentText("Server submission", "服务端提交"), s.submitted)
    }
    private func health(_ s: PreferencesSnapshot) {
        card {
            heading(agentText("tokens.ci · server", "tokens.ci · 服务端"))
            add(s.loading ? agentText("Refreshing…", "正在刷新…") : s.serverError ?? (s.hasServer ? agentText("No refresh error reported", "当前无刷新错误") : agentText("Waiting for the first successful fetch", "等待首次成功读取")), weight: .medium)
            timestamp(agentText("Last attempt", "最近尝试"), s.serverAttempt)
            timestamp(agentText("Successful fetch", "成功读取"), s.serverFetched)
            timestamp(agentText("Server submission", "服务端提交"), s.submitted)
            if let d = s.submitted, Date().timeIntervalSince(d) > 86400 {
                add(agentText("No submission in 24h. Refresh reads the server; it does not upload activity.", "超过 24 小时未提交；刷新只读取服务端，不会上传活动。"), size: 11, secondary: true)
            }
            let retry = button(agentText("Retry refresh", "重试刷新"), #selector(refresh), primary: true); retry.isEnabled = !s.loading
            var actions: [NSView] = [retry]
            if s.cliPath != nil { actions.append(button(agentText("Submit activity", "提交本机活动"), #selector(submit))) }
            if s.serverError != nil { actions.append(button(agentText("Read token…", "读取令牌…"), #selector(readToken))) }
            actions.append(NSView()); row(actions)
        }
        card {
            heading(agentText("This Mac · tokens CLI", "此 Mac · tokens CLI"))
            add(s.localError ?? (s.cliPath == nil ? agentText("CLI not found", "未找到 CLI") : s.localFailed ? agentText("Scan failed; previous values retained", "扫描失败，保留旧数值") : agentText("Today’s local scan is available", "今日本机扫描可用")), weight: .medium)
            timestamp(agentText("Last attempt", "最近尝试"), s.localAttempt)
            timestamp(agentText("Today’s successful scan", "今日成功扫描"), s.localSuccess)
            add(agentText("Check the CLI’s architecture, version and login in Terminal. No silent reinstall; refreshing never submits activity.", "请在终端检查 CLI 架构、版本及登录。不会静默重装，刷新也不等于提交。"), size: 11, secondary: true)
            stack?.addArrangedSubview(button(agentText("Official CLI setup", "官方 CLI 安装说明"), #selector(cliHelp)))
        }
    }
    private func display(_ s: PreferencesSnapshot) {
        order = validMenuItems(s.config.menuBarItems) + ["tokens", "cost", "rank"].filter { !s.config.menuBarItems.contains($0) }; enabled = Set(s.config.menuBarItems)
        card(accented: true) {
            heading(agentText("Menu-bar preview", "菜单栏预览"))
            let parts = order.filter { enabled.contains($0) }.map { key in
                key == "tokens" ? fmtTokens(s.todayTokens ?? 0) : key == "cost" ? "≈$—" : "#—"
            }
            add(parts.joined(separator: "   ·   "), size: 20, weight: .medium)
            add(agentText("Layout preview. Cost and rank are placeholders, not account values.", "仅预览组合与顺序；费用与排名为占位，不是账号数值。"), size: 11, secondary: true)
        }
        card {
            heading(agentText("Show and arrange", "选择内容与顺序"))
            for (i, name) in order.enumerated() {
                let title = name == "tokens" ? agentText("Today’s tokens", "今日 token") : name == "cost" ? agentText("Estimated spend", "估算费用") : agentText("Leaderboard rank", "排名")
                let check = UsageCheck(checkboxWithTitle: title, target: self, action: #selector(toggle(_:)))
                check.tag = i; check.state = enabled.contains(name) ? .on : .off
                check.heightAnchor.constraint(equalToConstant: 30).isActive = true
                check.widthAnchor.constraint(greaterThanOrEqualToConstant: 170).isActive = true
                let up = button("↑", #selector(move(_:)), tag: i * 2); up.isEnabled = i > 0; up.setAccessibilityLabel(agentText("Move \(title) up", "上移\(title)"))
                let down = button("↓", #selector(move(_:)), tag: i * 2 + 1); down.isEnabled = i < 2; down.setAccessibilityLabel(agentText("Move \(title) down", "下移\(title)"))
                row([check, NSView(), up, down])
            }
            add(agentText("Saved immediately on this Mac. Keep at least one item enabled.", "调整立即生效并保存在此 Mac，至少保留一项。"), size: 11, secondary: true)
        }
        add(agentText("Rank follows the existing Today / All-time setting. Estimated cost is not a subscription’s remaining allowance.", "排名沿用已有的今日／累计设置；估算费用不是订阅剩余额度。"), size: 11, secondary: true)
    }
    private func alerts(_ s: PreferencesSnapshot) {
        card {
            heading(agentText("Estimated cost thresholds · USD", "估算费用阈值 · USD"))
            func field(_ title: String, value: Double) -> NSTextField {
                let f = NSTextField(string: String(format: "%.2f", value)); f.alignment = .right; f.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
                f.widthAnchor.constraint(equalToConstant: 100).isActive = true; f.setAccessibilityLabel(title)
                row([label(title), NSView(), f]); return f
            }
            dailyField = field(agentText("Daily estimate", "每日估算阈值"), value: s.config.dailyCostBudget)
            monthlyField = field(agentText("Month-end projection", "月末预测阈值"), value: CostNotifications.shared.monthlyThreshold)
            add(agentText("0 disables a threshold. Daily threshold also controls amber / red menu-bar alerts.", "填 0 关闭对应阈值；每日阈值也控制菜单栏橙／红色提醒。"), size: 11, secondary: true)
        }
        card {
            heading(agentText("Notifications", "通知"))
            let pop = NSPopUpButton(); pop.font = .systemFont(ofSize: 12)
            pop.addItems(withTitles: [agentText("No notifications", "不发通知"), agentText("At most once per UTC day", "每 UTC 日至多一次"), agentText("At most every 6 hours", "至多每 6 小时"), agentText("At most hourly", "至多每小时")])
            let intervals: [Double] = [0, 86400, 21600, 3600]; pop.selectItem(at: intervals.firstIndex(of: CostNotifications.shared.interval) ?? 0); frequency = pop
            row([label(agentText("Per threshold", "每种阈值的频率"), secondary: true), NSView(), pop])
            let f = label(CostNotifications.shared.status, size: 11, secondary: true); feedback = f; stack?.addArrangedSubview(f); f.widthAnchor.constraint(equalTo: stack!.widthAnchor).isActive = true
            CostNotifications.shared.inspectPermission { [weak self] in self?.feedback?.stringValue = CostNotifications.shared.status }
        }
        stack?.addArrangedSubview(button(agentText("Save alert settings", "保存提醒设置"), #selector(saveAlerts), primary: true))
        add(agentText("Month-end projection uses this Mac’s local calendar-month pace, not a bill. Alerts require a successful observation no older than 15 minutes; failures, unknown values and old snapshots never count as new spend. Focus may hide banners.", "月末预测按此 Mac 本地自然月进度估算，不是账单。仅成功获取且 15 分钟内的数据触发提醒；失败、未知值与旧快照不会当作新费用。专注模式可能隐藏横幅。"), size: 11, secondary: true)
    }
    // Disposable CI controls: no live config, notification prompt or data submission.
    func checkNativeDisplayControls(_ fixture: PreferencesSnapshot) {
        let old = onChange
        var result: [String] = []
        onChange = { items, _ in result = items }
        defer { onChange = old }
        show(fixture, tab: 2)
        func buttons(_ view: NSView) -> [NSButton] { (view as? NSButton).map { [$0] } ?? view.subviews.flatMap(buttons) }
        let up = buttons(window!.contentView!).first { $0.title == "↑" && $0.isEnabled }!
        up.performClick(nil)
        precondition(result == ["rank", "tokens"], "native arrow updates visible order")
        let checks = buttons(window!.contentView!).filter { $0.title == agentText("Today’s tokens", "今日 token") || $0.title == agentText("Leaderboard rank", "排名") }
        checks.first { $0.title == agentText("Today’s tokens", "今日 token") }!.performClick(nil)
        precondition(result == ["rank"], "native checkbox updates selected items")
        checks.first { $0.title == agentText("Leaderboard rank", "排名") }!.performClick(nil)
        precondition(result == ["rank"], "last enabled item cannot be removed")
        let domain = "tokensbar-disposable-" + UUID().uuidString
        let store = UserDefaults(suiteName: domain)!
        store.set(result, forKey: "display.menuItems")
        precondition(UserDefaults(suiteName: domain)!.stringArray(forKey: "display.menuItems") == result, "display order persistence")
        store.removePersistentDomain(forName: domain)
        print("PASS: 4 native display reorder/toggle/last-item/persistence checks")
    }
    @objc private func navigationChanged(_ sender: NSButton) { chosenTab = sender.tag; configure() }
    @objc private func toggle(_ sender: NSButton) {
        let key = order[sender.tag]; if sender.state == .on { enabled.insert(key) } else { enabled.remove(key) }
        if enabled.isEmpty { enabled.insert(key); sender.state = .on; NSSound.beep(); return }; applyDisplay(); configure()
    }
    @objc private func move(_ sender: NSButton) { let i = sender.tag / 2, j = i + (sender.tag % 2 == 0 ? -1 : 1); guard order.indices.contains(j) else { return }; order.swapAt(i, j); applyDisplay(); configure() }
    private func applyDisplay() { guard var s = snapshot else { return }; s.config.menuBarItems = order.filter { enabled.contains($0) }; snapshot = s; onChange?(s.config.menuBarItems, s.config.dailyCostBudget) }
    @objc private func saveAlerts() {
        guard var s = snapshot, let daily = Double(dailyField?.stringValue ?? ""), let monthly = Double(monthlyField?.stringValue ?? ""), daily.isFinite, monthly.isFinite, daily >= 0, monthly >= 0 else { feedback?.stringValue = agentText("Enter nonnegative finite amounts (0 turns off).", "请输入非负有效金额，0 为关闭。"); return }
        UserDefaults.standard.set(monthly, forKey: "cost.monthThreshold"); UserDefaults.standard.set([0.0, 86400, 21600, 3600][frequency?.indexOfSelectedItem ?? 0], forKey: "cost.notificationInterval")
        s.config.dailyCostBudget = daily; snapshot = s; onChange?(s.config.menuBarItems, daily)
        CostNotifications.shared.authorize { [weak self] in self?.feedback?.stringValue = CostNotifications.shared.status }
    }
    @objc private func refresh() { onRefresh?() }
    @objc private func submit() { onSubmit?() }
    @objc private func readToken() { onReadToken?() }
    @objc private func cliHelp() { NSWorkspace.shared.open(URL(string: "https://github.com/missuo/tokens#installation")!) }
}
