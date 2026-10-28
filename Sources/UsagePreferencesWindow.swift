import AppKit
import UserNotifications

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
    private var tabs: NSSegmentedControl?
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
        let l = NSTextField(wrappingLabelWithString: text); l.font = .systemFont(ofSize: size, weight: weight); l.textColor = secondary ? .secondaryLabelColor : .labelColor; l.maximumNumberOfLines = 0; return l
    }
    private func button(_ text: String, _ selector: Selector, tag: Int = 0) -> NSButton {
        let b = NSButton(title: text, target: self, action: selector); b.bezelStyle = .rounded; b.tag = tag; b.contentTintColor = tokensAccentInk; return b
    }
    private func configure() {
        guard let window, let snapshot else { return }
        let root = NSView(); root.wantsLayer = true; root.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor; window.contentView = root
        let title = label(agentText("Make it yours", "让用量一目了然"), size: 22, weight: .bold)
        let subtitle = label(agentText("Your data, clear boundaries. Your menu bar, your way.", "看清数据口径，按自己的习惯显示。"), secondary: true)
        let tabs = NSSegmentedControl(labels: [agentText("Trends", "趋势"), agentText("Data health", "数据状态"), agentText("Menu bar", "菜单栏"), agentText("Alerts", "提醒")], trackingMode: .selectOne, target: self, action: #selector(tabChanged(_:)))
        tabs.selectedSegment = chosenTab; self.tabs = tabs
        let body = NSStackView(); body.orientation = .vertical; body.alignment = .leading; body.spacing = 14; self.stack = body
        let scroll = NSScrollView(); scroll.drawsBackground = false; scroll.hasVerticalScroller = true
        let doc = AgentFlippedView(); scroll.documentView = doc; body.translatesAutoresizingMaskIntoConstraints = false; doc.addSubview(body)
        for view in [title, subtitle, tabs, scroll] { view.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(view) }
        doc.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 22), title.topAnchor.constraint(equalTo: root.topAnchor, constant: 22),
            subtitle.leadingAnchor.constraint(equalTo: title.leadingAnchor), subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 7), subtitle.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -22),
            tabs.leadingAnchor.constraint(equalTo: title.leadingAnchor), tabs.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -22), tabs.topAnchor.constraint(equalTo: subtitle.bottomAnchor, constant: 18),
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 22), scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -22), scroll.topAnchor.constraint(equalTo: tabs.bottomAnchor, constant: 20), scroll.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -18),
            doc.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor), body.leadingAnchor.constraint(equalTo: doc.leadingAnchor), body.trailingAnchor.constraint(equalTo: doc.trailingAnchor, constant: -8), body.topAnchor.constraint(equalTo: doc.topAnchor), body.bottomAnchor.constraint(equalTo: doc.bottomAnchor, constant: -10)])
        switch chosenTab { case 0: trends(snapshot); case 1: health(snapshot); case 2: display(snapshot); default: alerts(snapshot) }
    }
    private func add(_ text: String, size: CGFloat = 12, weight: NSFont.Weight = .regular, secondary: Bool = false) { guard let stack else { return }; let l = label(text, size: size, weight: weight, secondary: secondary); stack.addArrangedSubview(l); l.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
    private func heading(_ text: String) { add(text, size: 13, weight: .semibold) }
    private func stamp(_ date: Date?) -> String { guard let date else { return agentText("not yet", "尚无") }; let f = DateFormatter(); f.dateFormat = "MM-dd HH:mm:ss z"; return f.string(from: date) }
    private func trends(_ s: PreferencesSnapshot) {
        heading(agentText("Today vs. the previous 7 days", "今日与此前 7 日均值"))
        if let c = s.comparison {
            add(c.changePercent.map { String(format: "%+.1f%%", $0) } ?? agentText("No percentage baseline", "基准为零，无法计算百分比"), size: 30, weight: .semibold)
            add(agentText("Today ", "今日 ") + fmtTokens(s.todayTokens ?? 0) + agentText(" · daily mean ", " · 日均 ") + fmtTokens(Int(c.mean.rounded())))
            if let name = c.topModel, let delta = c.topModelDelta { heading(agentText("Largest model contribution to the change", "对变化贡献最大的模型")); add(name + String(format: " · %+.0f token", delta)); add(agentText("Versus that model’s previous seven-day daily mean; not a causal explanation.", "相对此模型前 7 日均值的差额；不推断使用变化的原因。"), secondary: true) }
            else { add(agentText("Per-day model detail is incomplete or unchanged; no model attribution is made.", "每日模型明细不足或没有变化，不归因到具体模型。"), secondary: true) }
        } else { add(agentText("Not enough matching submitted data", "同口径已提交数据不足"), size: 20, weight: .semibold); add(agentText("Requires today plus each of the previous seven UTC days. Missing records are not counted as zero. A local scan is never compared with the all-device average.", "需要今日及此前每个 UTC 日的记录；缺失不算零。本机扫描不会与全设备均值混比。"), secondary: true) }
        add(agentText("UTC calendar days · tokens.ci submitted activity across devices. Today is still in progress and reflects only the last submission, not a final daily total. Token change, not billing change.", "UTC 自然日 · tokens.ci 全设备已提交活动。今日尚未结束，数值截至最近提交，不是最终日总量；这是 token 变化，不是账单变化。"), secondary: true)
        add(agentText("Submitted: ", "服务端提交：") + stamp(s.submitted), secondary: true)
    }
    private func health(_ s: PreferencesSnapshot) {
        heading(agentText("tokens.ci", "tokens.ci 服务端"))
        add(s.loading ? agentText("Refreshing…", "正在刷新…") : s.serverError ?? (s.hasServer ? agentText("No refresh error reported", "当前无刷新错误") : agentText("Waiting for the first successful fetch", "等待首次成功读取")), weight: .medium)
        add(agentText("Last attempt: ", "最近尝试：") + stamp(s.serverAttempt) + "\n" + agentText("Last successful fetch: ", "成功读取：") + stamp(s.serverFetched) + "\n" + agentText("Server submission: ", "服务端提交：") + stamp(s.submitted), secondary: true)
        if let d = s.submitted, Date().timeIntervalSince(d) > 86400 { add(agentText("No recent submission in over 24 hours. Refreshing reads the server; it does not upload local activity.", "服务端已超过 24 小时未提交。刷新只读取服务器，不会上传本机活动。"), weight: .medium) }
        let row = NSStackView(views: [button(agentText("Retry refresh", "重试刷新"), #selector(refresh)), button(agentText("Submit local activity", "提交本机活动"), #selector(submit))]); row.spacing = 8; row.views.last?.isHidden = s.cliPath == nil; stack?.addArrangedSubview(row)
        if s.serverError != nil { stack?.addArrangedSubview(button(agentText("Read token settings…", "读取令牌设置…"), #selector(readToken))) }
        heading(agentText("This Mac · tokens CLI", "此 Mac · tokens CLI"))
        add(s.localError ?? (s.cliPath == nil ? agentText("CLI not found", "未找到 CLI") : s.localFailed ? agentText("Today’s CLI scan failed; prior values are retained", "今日 CLI 扫描失败，保留旧数值") : agentText("Today’s local scan is available", "今日本机扫描可用")), weight: .medium)
        add(agentText("Last attempt: ", "最近尝试：") + stamp(s.localAttempt) + "\n" + agentText("Today’s last successful scan: ", "今日成功扫描：") + stamp(s.localSuccess), secondary: true)
        add(agentText("If installed but unable to run, check the CLI’s architecture/version and its own login in Terminal. TokensBar never silently reinstalls it or submits on refresh.", "若已安装但无法运行，请在终端检查 CLI 架构、版本及其登录。TokensBar 不会静默重装；刷新也不等于提交。"), secondary: true)
        stack?.addArrangedSubview(button(agentText("Official CLI setup", "官方 CLI 安装说明"), #selector(cliHelp)))
    }
    private func display(_ s: PreferencesSnapshot) {
        order = validMenuItems(s.config.menuBarItems) + ["tokens", "cost", "rank"].filter { !s.config.menuBarItems.contains($0) }; enabled = Set(s.config.menuBarItems)
        heading(agentText("Show and arrange", "选择内容与顺序")); add(agentText("Changes apply immediately and are remembered on this Mac. Keep at least one item.", "立即生效，并在此 Mac 记住；至少保留一项。"), secondary: true)
        for (i, name) in order.enumerated() {
            let title = name == "tokens" ? agentText("Today’s tokens", "今日 token") : name == "cost" ? agentText("Estimated spend", "估算费用") : agentText("Leaderboard rank", "排名")
            let check = NSButton(checkboxWithTitle: title, target: self, action: #selector(toggle(_:))); check.tag = i; check.state = enabled.contains(name) ? .on : .off
            let up = button("↑", #selector(move(_:)), tag: i * 2); up.isEnabled = i > 0; up.setAccessibilityLabel(agentText("Move \(title) up", "上移\(title)"))
            let down = button("↓", #selector(move(_:)), tag: i * 2 + 1); down.isEnabled = i < 2; down.setAccessibilityLabel(agentText("Move \(title) down", "下移\(title)"))
            let row = NSStackView(views: [check, NSView(), up, down]); row.spacing = 7; stack?.addArrangedSubview(row); row.widthAnchor.constraint(equalTo: stack!.widthAnchor).isActive = true
        }
        add(agentText("Rank still follows the existing Today / All-time setting. Estimated cost is never presented as the subscription’s remaining allowance.", "排名沿用已有的今日／累计设置；估算费用不当作订阅剩余额度。"), secondary: true)
    }
    private func alerts(_ s: PreferencesSnapshot) {
        heading(agentText("Estimated cost thresholds · USD", "估算费用阈值 · USD"))
        add(agentText("Daily threshold also controls amber / red menu-bar colour. Set 0 to turn a threshold off. Month-end projection remains based on this Mac’s local calendar-month pace, not an invoice.", "每日阈值同时控制菜单栏橙／红色提醒；填 0 关闭该阈值。月末预测仍按此 Mac 本地自然月进度估算，不是账单。"), secondary: true)
        func field(_ title: String, value: Double) -> NSTextField {
            let f = NSTextField(string: String(format: "%.2f", value)); f.alignment = .right; f.widthAnchor.constraint(equalToConstant: 110).isActive = true; f.setAccessibilityLabel(title)
            let row = NSStackView(views: [label(title), NSView(), f]); row.spacing = 10; stack?.addArrangedSubview(row); row.widthAnchor.constraint(equalTo: stack!.widthAnchor).isActive = true; return f
        }
        dailyField = field(agentText("Today’s estimate", "今日估算"), value: s.config.dailyCostBudget)
        monthlyField = field(agentText("Month-end projection", "月末预测"), value: CostNotifications.shared.monthlyThreshold)
        let pop = NSPopUpButton(); pop.addItems(withTitles: [agentText("No notifications", "不发通知"), agentText("At most once per UTC day", "每 UTC 日至多一次"), agentText("At most every 6 hours", "至多每 6 小时"), agentText("At most hourly", "至多每小时")]); let intervals: [Double] = [0, 86400, 21600, 3600]; pop.selectItem(at: intervals.firstIndex(of: CostNotifications.shared.interval) ?? 0); frequency = pop
        heading(agentText("Notification frequency · per threshold", "通知频率 · 每种阈值")); stack?.addArrangedSubview(pop)
        stack?.addArrangedSubview(button(agentText("Save thresholds", "保存阈值"), #selector(saveAlerts)))
        let f = label(CostNotifications.shared.status, secondary: true); feedback = f; stack?.addArrangedSubview(f); f.widthAnchor.constraint(equalTo: stack!.widthAnchor).isActive = true
        CostNotifications.shared.inspectPermission { [weak self] in self?.feedback?.stringValue = CostNotifications.shared.status }
        add(agentText("Only a successful, recent (≤15 min) observation can trigger an alert. Failed refreshes, unknown values and old snapshots never count as a new spend. Focus can suppress banners.", "仅成功获取且 15 分钟内的数据触发提醒；刷新失败、未知值及旧快照不会当作新费用。专注模式可能隐藏横幅。"), secondary: true)
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
    @objc private func tabChanged(_ sender: NSSegmentedControl) { chosenTab = sender.selectedSegment; configure() }
    @objc private func toggle(_ sender: NSButton) {
        let key = order[sender.tag]; if sender.state == .on { enabled.insert(key) } else { enabled.remove(key) }
        if enabled.isEmpty { enabled.insert(key); sender.state = .on; NSSound.beep(); return }; applyDisplay()
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
