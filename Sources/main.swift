// TokensBar — macOS menu bar readout for tokens.ci usage.
//
// Menu bar line:  ⚡ <today tokens>  #<rank>
// Data sources:
//   - tokens.ci REST API  → rank, lifetime totals, model split, neighbour gap
//   - local `tokens` CLI  → today / this week, live (not yet submitted)
//
// Build: ./build.sh   Run: open TokensBar.app
//
// MIT licensed. Usage data comes from the `tokens` CLI and the tokens.ci public
// read-only API — see https://github.com/missuo/tokens (a fork of
// https://github.com/junhoyeo/tokscale). No affiliation with tokens.ci.

import AppKit
import Foundation

// MARK: - Config

struct Config {
    var username: String
    var apiBase = "https://tokens.ci"
    var apiRefreshSeconds: TimeInterval = 300
    var localRefreshSeconds: TimeInterval = 120
    var topModels = 5
    /// Which rank the menu bar shows by default; the menu can override it.
    var menuBarRank: RankMode = .allTime

    static let configPath = NSHomeDirectory() + "/.config/tokens-menubar/config.json"
    static let credentialsPath = NSHomeDirectory() + "/.config/tokens/credentials.json"

    static func load() -> Config {
        // Username comes from the tokens CLI credentials by default so the app
        // follows whichever account is logged in.
        var name = jsonString(atPath: credentialsPath, key: "username") ?? ""
        var cfg = Config(username: name)
        guard let data = FileManager.default.contents(atPath: configPath),
              let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return cfg }
        if let v = o["username"] as? String, !v.isEmpty { name = v }
        cfg.username = name
        if let v = o["apiBase"] as? String, !v.isEmpty { cfg.apiBase = v }
        if let v = (o["apiRefreshSeconds"] as? NSNumber)?.doubleValue, v >= 30 { cfg.apiRefreshSeconds = v }
        if let v = (o["localRefreshSeconds"] as? NSNumber)?.doubleValue, v >= 30 { cfg.localRefreshSeconds = v }
        if let v = (o["topModels"] as? NSNumber)?.intValue, v >= 0 { cfg.topModels = v }
        if let v = o["menuBarRank"] as? String, let m = RankMode(rawValue: v) { cfg.menuBarRank = m }
        return cfg
    }

    private static func jsonString(atPath path: String, key: String) -> String? {
        guard let data = FileManager.default.contents(atPath: path),
              let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return o[key] as? String
    }
}

// MARK: - Formatting

func fmtTokens(_ n: Int) -> String {
    let d = Double(n)
    if d >= 1e12 { return String(format: "%.2fT", d / 1e12) }
    if d >= 1e9 { return String(format: "%.2fB", d / 1e9) }
    if d >= 1e6 { return String(format: "%.1fM", d / 1e6) }
    if d >= 1e3 { return String(format: "%.1fK", d / 1e3) }
    return String(n)
}

let moneyFormatter: NumberFormatter = {
    let f = NumberFormatter()
    f.numberStyle = .decimal
    f.minimumFractionDigits = 2
    f.maximumFractionDigits = 2
    return f
}()

func fmtMoney(_ v: Double) -> String {
    "$" + (moneyFormatter.string(from: NSNumber(value: v)) ?? String(format: "%.2f", v))
}

let groupedFormatter: NumberFormatter = {
    let f = NumberFormatter()
    f.numberStyle = .decimal
    return f
}()

func fmtExact(_ n: Int) -> String {
    groupedFormatter.string(from: NSNumber(value: n)) ?? String(n)
}

/// Right-pads without ever truncating (String.padding(toLength:) truncates).
func pad(_ s: String, _ width: Int) -> String {
    let n = s.count
    return n >= width ? s : s + String(repeating: " ", count: width - n)
}

/// One layout for value rows, shared by the menu and `--dump`.
func rowText(_ label: String, _ value: String, _ trailing: String?) -> String {
    let v = pad(value, 11)
    guard let trailing else { return label + "   " + v }
    return label + "   " + v + (v.hasSuffix(" ") ? "" : " ") + trailing
}

func fmtClock(_ date: Date) -> String {
    let f = DateFormatter()
    f.dateFormat = "HH:mm"
    return f.string(from: date)
}

// MARK: - Models

struct ModelSlice {
    let model: String
    let tokens: Int
    /// The API's `percentage` field is a share of *cost*, not tokens.
    let costShare: Double
}

struct Neighbour {
    let rank: Int
    let username: String
    let tokens: Int
}

/// Where the user sits on one leaderboard (all-time or today).
struct BoardStanding {
    /// 0 means "not on this board" — e.g. nothing submitted yet today.
    var rank: Int
    var totalUsers: Int
    /// Own period total as this board reports it, so the gap uses one source.
    var tokens: Int
    var above: Neighbour?
}

enum RankMode: String {
    case allTime = "all"
    case today = "today"

    var label: String { self == .today ? "今日榜" : "累计榜" }
    /// Menu bar prefix — "今" disambiguates a daily rank from a lifetime one.
    var badge: String { self == .today ? "今#" : "#" }
}

struct ServerStats {
    var rank: Int
    var totalTokens: Int
    var totalCost: Double
    var activeDays: Int
    var updatedAt: Date?
    var isStale: Bool
    var models: [ModelSlice]
    var allTime: BoardStanding?
    var today: BoardStanding?

    func standing(_ mode: RankMode) -> BoardStanding? {
        mode == .today ? today : allTime
    }
}

struct LocalStats {
    var todayTokens = 0
    var todayCost = 0.0
    var weekTokens = 0
    var weekCost = 0.0
    var updatedAt: Date?
    var failed = false
}

// MARK: - JSON helpers

func num(_ o: [String: Any]?, _ key: String) -> NSNumber? { o?[key] as? NSNumber }
func int(_ o: [String: Any]?, _ key: String) -> Int { num(o, key)?.intValue ?? 0 }
func dbl(_ o: [String: Any]?, _ key: String) -> Double { num(o, key)?.doubleValue ?? 0 }

let iso8601: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
}()

func parseDate(_ s: Any?) -> Date? {
    guard let s = s as? String else { return nil }
    return iso8601.date(from: s) ?? ISO8601DateFormatter().date(from: s)
}

// MARK: - Local CLI

enum CLI {
    static let candidates = [
        "/usr/local/bin/tokens",
        "/opt/homebrew/bin/tokens",
        NSHomeDirectory() + "/.cargo/bin/tokens",
        "/usr/bin/tokens",
    ]

    /// GUI apps do not inherit the shell PATH, so probe the known install sites.
    static func binary() -> String? {
        candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Runs the CLI and returns (stdout, exitCode). stderr is drained on a
    /// separate queue so a chatty CLI cannot deadlock the pipe.
    static func run(_ args: [String], timeout: TimeInterval = 120) -> (Data, Int32)? {
        guard let bin = binary() else { return nil }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: bin)
        p.arguments = args
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        p.standardInput = FileHandle.nullDevice
        do { try p.run() } catch { return nil }

        DispatchQueue.global(qos: .utility).async {
            _ = try? err.fileHandleForReading.readToEnd()
        }
        let killer = DispatchWorkItem { if p.isRunning { p.terminate() } }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: killer)

        let data = (try? out.fileHandleForReading.readToEnd()) ?? Data()
        p.waitUntilExit()
        killer.cancel()
        return (data, p.terminationStatus)
    }

    /// `tokens --json` totals: the site counts input+output+cacheRead+cacheWrite+reasoning.
    /// reasoning has no top-level total, so it is summed from the entries.
    static func report(_ extraArgs: [String]) -> (tokens: Int, cost: Double)? {
        guard let (data, status) = run(extraArgs + ["--json", "--no-spinner"]), status == 0,
              let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        let entries = o["entries"] as? [[String: Any]] ?? []
        let reasoning = entries.reduce(0) { $0 + int($1, "reasoning") }
        let total = int(o, "totalInput") + int(o, "totalOutput")
            + int(o, "totalCacheRead") + int(o, "totalCacheWrite") + reasoning
        return (total, dbl(o, "totalCost"))
    }
}

// MARK: - tokens.ci API

final class API {
    let config: Config
    private let session: URLSession

    init(config: Config) {
        self.config = config
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 25
        c.timeoutIntervalForResource = 40
        session = URLSession(configuration: c)
    }

    private func getJSON(_ path: String, _ done: @escaping ([String: Any]?) -> Void) {
        guard let url = URL(string: config.apiBase + path) else { return done(nil) }
        var req = URLRequest(url: url)
        req.setValue("TokensBar/1.0", forHTTPHeaderField: "User-Agent")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        session.dataTask(with: req) { data, resp, _ in
            guard let data, (resp as? HTTPURLResponse)?.statusCode == 200,
                  let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return done(nil) }
            done(o)
        }.resume()
    }

    /// Fetches the profile plus both leaderboards (all-time and today) so either
    /// rank can be shown. Calls back on `queue` (main by default).
    func fetch(on queue: DispatchQueue = .main, _ done: @escaping (ServerStats?) -> Void) {
        let user = config.username
        guard !user.isEmpty,
              let escaped = user.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
        else { return queue.async { done(nil) } }

        getJSON("/api/users/\(escaped)") { [weak self] o in
            guard let self, let o else { return queue.async { done(nil) } }
            let u = o["user"] as? [String: Any]
            let s = o["stats"] as? [String: Any]
            let fresh = o["submissionFreshness"] as? [String: Any]
            let models = (o["modelUsage"] as? [[String: Any]] ?? []).map {
                ModelSlice(model: $0["model"] as? String ?? "?",
                           tokens: int($0, "tokens"),
                           costShare: dbl($0, "percentage"))
            }
            var stats = ServerStats(
                rank: int(u, "rank"),
                totalTokens: int(s, "totalTokens"),
                totalCost: dbl(s, "totalCost"),
                activeDays: int(s, "activeDays"),
                updatedAt: parseDate(o["updatedAt"]) ?? parseDate(fresh?["lastUpdated"]),
                isStale: (fresh?["isStale"] as? Bool) ?? false,
                models: models,
                allTime: nil,
                today: nil)

            // `/api/users/<name>?period=today` ignores the period (it echoes
            // "all"), so a daily rank has to come from the daily board itself.
            let group = DispatchGroup()
            group.enter()
            self.findOnBoard(period: "all", username: user, fromPage: 1) {
                stats.allTime = $0
                group.leave()
            }
            group.enter()
            self.findOnBoard(period: "today", username: user, fromPage: 1) {
                stats.today = $0
                group.leave()
            }
            group.notify(queue: queue) { done(stats) }
        }
    }

    /// Walks leaderboard pages until the user turns up, so both the rank and the
    /// entry directly above it come from the same ordered list.
    private func findOnBoard(period: String, username: String, fromPage page: Int,
                             maxPages: Int = 6,
                             _ done: @escaping (BoardStanding?) -> Void) {
        getJSON("/api/leaderboard?period=\(period)&limit=100&page=\(page)") { [weak self] o in
            guard let o else { return done(nil) }
            let pg = o["pagination"] as? [String: Any]
            let totalUsers = int(pg, "totalUsers")
            let users = (o["users"] as? [[String: Any]] ?? []).map {
                Neighbour(rank: int($0, "rank"),
                          username: $0["username"] as? String ?? "?",
                          tokens: int($0, "totalTokens"))
            }
            if let i = users.firstIndex(where: { $0.username == username }) {
                return done(BoardStanding(rank: users[i].rank,
                                          totalUsers: totalUsers,
                                          tokens: users[i].tokens,
                                          above: i > 0 ? users[i - 1] : nil))
            }
            let hasNext = (pg?["hasNext"] as? Bool) ?? false
            if let self, hasNext, page < maxPages {
                self.findOnBoard(period: period, username: username,
                                 fromPage: page + 1, maxPages: maxPages, done)
            } else {
                // Absent from this board: rank 0 renders as 未上榜.
                done(BoardStanding(rank: 0, totalUsers: totalUsers, tokens: 0, above: nil))
            }
        }
    }
}

// MARK: - Launch at login (LaunchAgent, works for unsigned builds)

enum LoginItem {
    static let label = "ci.tokens.menubar"
    static var plistPath: String {
        NSHomeDirectory() + "/Library/LaunchAgents/\(label).plist"
    }

    static var isEnabled: Bool { FileManager.default.fileExists(atPath: plistPath) }

    static func set(_ enabled: Bool) {
        let fm = FileManager.default
        let dir = NSHomeDirectory() + "/Library/LaunchAgents"
        try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let target = "gui/\(getuid())"

        if enabled {
            let exe = Bundle.main.executablePath ?? CommandLine.arguments[0]
            let plist: [String: Any] = [
                "Label": label,
                "ProgramArguments": [exe],
                "RunAtLoad": true,
                "KeepAlive": false,
                "ProcessType": "Interactive",
            ]
            guard let data = try? PropertyListSerialization.data(
                fromPropertyList: plist, format: .xml, options: 0) else { return }
            try? data.write(to: URL(fileURLWithPath: plistPath))
            launchctl(["bootout", "\(target)/\(label)"])
            launchctl(["bootstrap", target, plistPath])
        } else {
            launchctl(["bootout", "\(target)/\(label)"])
            try? fm.removeItem(atPath: plistPath)
        }
    }

    @discardableResult
    private static func launchctl(_ args: [String]) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return -1 }
        p.waitUntilExit()
        return p.terminationStatus
    }
}

// MARK: - Presenter (pure text layer, shared by the menu and `--dump`)

enum Line {
    case header(String)
    case row(String, String, String?)
    case note(String)
    case small(String)
    case separator
}

struct Presenter {
    let config: Config
    let rankMode: RankMode
    let server: ServerStats?
    let local: LocalStats
    let serverFailed: Bool
    let transient: String?

    var title: String {
        var parts = [local.failed ? "—" : fmtTokens(local.todayTokens)]
        if let st = server?.standing(rankMode) {
            parts.append(st.rank > 0 ? "\(rankMode.badge)\(st.rank)" : "\(rankMode.badge)—")
        } else if serverFailed {
            parts.append("#?")
        }
        return parts.joined(separator: "  ")
    }

    var tooltip: String {
        var bits = [local.failed ? "找不到 tokens CLI 或本地扫描失败"
                                 : "今日 \(fmtExact(local.todayTokens)) tokens"]
        if let s = server {
            if let a = s.allTime, a.rank > 0 { bits.append("累计榜 第 \(a.rank) / \(a.totalUsers) 名") }
            if let t = s.today { bits.append(t.rank > 0 ? "今日榜 第 \(t.rank) / \(t.totalUsers) 名"
                                                       : "今日榜 未上榜") }
        }
        return bits.joined(separator: "\n")
    }

    private func standingRow(_ mode: RankMode) -> Line? {
        guard let st = server?.standing(mode) else { return nil }
        let value = st.rank > 0 ? "#\(st.rank) / \(st.totalUsers)" : "未上榜"
        return .row(mode.label, value, mode == rankMode ? "· 菜单栏" : nil)
    }

    private var gapLine: Line? {
        guard let st = server?.standing(rankMode) else { return nil }
        if st.rank == 0 {
            return .note("\(rankMode.label) 未上榜 —— 今天还没有提交记录")
        }
        guard let above = st.above else {
            return st.rank == 1 ? .note("\(rankMode.label) 已经是第 1 名") : nil
        }
        let gap = max(0, above.tokens - st.tokens)
        return .note("\(rankMode.label) 距 #\(above.rank) @\(above.username) 还差 \(fmtTokens(gap))")
    }

    var lines: [Line] {
        var out: [Line] = []
        out.append(.header(config.username.isEmpty ? "未登录" : "@" + config.username))
        out.append(.separator)

        if server != nil {
            if let l = standingRow(.allTime) { out.append(l) }
            if let l = standingRow(.today) { out.append(l) }
            out.append(.note("#名次 / 榜上总人数；今日榜只算当天提交过的人"))
            out.append(.separator)
        }

        if let s = server {
            out.append(.row("累计", fmtTokens(s.totalTokens), fmtMoney(s.totalCost)))
        } else if serverFailed {
            out.append(.note("累计   服务端读取失败（检查代理 / tokens.ci 可达性）"))
        } else {
            out.append(.note("累计   载入中…"))
        }

        if local.failed {
            out.append(.note("今日   本地扫描失败（找不到 tokens CLI？）"))
        } else {
            out.append(.row("今日", fmtTokens(local.todayTokens), fmtMoney(local.todayCost)))
            out.append(.row("本周", fmtTokens(local.weekTokens), fmtMoney(local.weekCost)))
        }

        if let l = gapLine {
            out.append(.separator)
            out.append(l)
        }

        if config.topModels > 0, let s = server, !s.models.isEmpty {
            out.append(.separator)
            let denom = Double(max(1, s.totalTokens))
            for m in s.models.sorted(by: { $0.tokens > $1.tokens }).prefix(config.topModels) {
                let n = m.model.count > 22 ? String(m.model.prefix(21)) + "…" : m.model
                let share = Double(m.tokens) / denom * 100
                out.append(.small("\(pad(n, 24))\(String(format: "%5.1f%%", share))  \(fmtTokens(m.tokens))"))
            }
        }

        out.append(.separator)
        if let transient {
            out.append(.note(transient))
        } else {
            var bits: [String] = []
            if let d = local.updatedAt { bits.append("本地 \(fmtClock(d))") }
            if let d = server?.updatedAt { bits.append("服务端 \(fmtClock(d))") }
            if server?.isStale == true { bits.append("⚠ 服务端数据偏旧") }
            if !bits.isEmpty { out.append(.note(bits.joined(separator: "  ·  "))) }
        }
        return out
    }
}

// MARK: - Controller

final class Controller: NSObject, NSMenuDelegate {
    private let config = Config.load()
    private lazy var api = API(config: config)
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()

    private var server: ServerStats?
    private var local = LocalStats()
    private var serverFailed = false
    private var rankMode: RankMode = .allTime
    private var transient: String?
    private var busy = false
    private var lastServerFetch: Date?
    private var apiTimer: Timer?
    private var localTimer: Timer?
    private let workQueue = DispatchQueue(label: "ci.tokens.menubar.cli", qos: .utility)

    private let monoFont = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)
    private let rowFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)

    /// config.json sets the default; flipping it in the menu wins from then on.
    private static let rankModeKey = "menuBarRank"

    override init() {
        super.init()
        let stored = UserDefaults.standard.string(forKey: Controller.rankModeKey)
        rankMode = stored.flatMap(RankMode.init(rawValue:)) ?? config.menuBarRank
    }

    func start() {
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: "Tokens")
            button.image?.isTemplate = true
            button.imagePosition = .imageLeading
        }
        menu.delegate = self
        statusItem.menu = menu
        render()

        refreshLocal()
        refreshServer()
        apiTimer = Timer.scheduledTimer(withTimeInterval: config.apiRefreshSeconds, repeats: true) {
            [weak self] _ in self?.refreshServer()
        }
        localTimer = Timer.scheduledTimer(withTimeInterval: config.localRefreshSeconds, repeats: true) {
            [weak self] _ in self?.refreshLocal()
        }
    }

    // MARK: Data

    private func refreshServer() {
        api.fetch { [weak self] stats in
            guard let self else { return }
            self.lastServerFetch = Date()
            if let stats { self.server = stats; self.serverFailed = false }
            else { self.serverFailed = true }
            self.render()
        }
    }

    private func refreshLocal() {
        workQueue.async { [weak self] in
            let today = CLI.report(["--today"])
            let week = CLI.report(["--week"])
            DispatchQueue.main.async {
                guard let self else { return }
                if today == nil && week == nil {
                    self.local.failed = true
                } else {
                    self.local.failed = false
                    if let today { self.local.todayTokens = today.tokens; self.local.todayCost = today.cost }
                    if let week { self.local.weekTokens = week.tokens; self.local.weekCost = week.cost }
                    self.local.updatedAt = Date()
                }
                self.render()
            }
        }
    }

    // MARK: Rendering

    private var presenter: Presenter {
        Presenter(config: config, rankMode: rankMode, server: server, local: local,
                  serverFailed: serverFailed, transient: transient)
    }

    private func render() {
        let p = presenter
        statusItem.button?.attributedTitle = NSAttributedString(
            string: " " + p.title, attributes: [.font: monoFont])
        statusItem.button?.toolTip = p.tooltip
        rebuildMenu()
    }

    func menuNeedsUpdate(_ menu: NSMenu) { rebuildMenu() }

    func menuWillOpen(_ menu: NSMenu) {
        // Opening the menu is an explicit request for current numbers.
        refreshLocal()
        if let fetched = lastServerFetch, Date().timeIntervalSince(fetched) < 60 { return }
        refreshServer()
    }

    private func item(_ line: Line) -> NSMenuItem? {
        switch line {
        case .separator:
            return .separator()
        case .header(let text):
            let it = NSMenuItem(title: text, action: #selector(openProfile), keyEquivalent: "")
            it.attributedTitle = NSAttributedString(string: text, attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .semibold)])
            it.target = self
            return it
        case .row(let label, let value, let trailing):
            return disabledItem(rowText(label, value, trailing), font: rowFont, dim: false)
        case .note(let text):
            return disabledItem(text, font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular), dim: true)
        case .small(let text):
            return disabledItem(text, font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular), dim: false)
        }
    }

    private func disabledItem(_ text: String, font: NSFont, dim: Bool) -> NSMenuItem {
        let it = NSMenuItem(title: text, action: nil, keyEquivalent: "")
        var attrs: [NSAttributedString.Key: Any] = [.font: font]
        if dim { attrs[.foregroundColor] = NSColor.secondaryLabelColor }
        it.attributedTitle = NSAttributedString(string: text, attributes: attrs)
        it.isEnabled = false
        return it
    }

    private func rebuildMenu() {
        menu.removeAllItems()
        for line in presenter.lines {
            if let it = item(line) { menu.addItem(it) }
        }
        addFooter()
    }

    private func addFooter() {
        menu.addItem(.separator())

        let submit = NSMenuItem(title: busy ? "提交中…" : "立即提交 (tokens submit)",
                                action: #selector(submitNow), keyEquivalent: "s")
        submit.target = self
        submit.isEnabled = !busy && CLI.binary() != nil
        menu.addItem(submit)

        let refresh = NSMenuItem(title: "刷新", action: #selector(refreshAll), keyEquivalent: "r")
        refresh.target = self
        menu.addItem(refresh)

        menu.addItem(rankModeItem())

        let profile = NSMenuItem(title: "打开 tokens.ci 主页", action: #selector(openProfile), keyEquivalent: "o")
        profile.target = self
        menu.addItem(profile)

        let login = NSMenuItem(title: "开机启动", action: #selector(toggleLoginItem), keyEquivalent: "")
        login.target = self
        login.state = LoginItem.isEnabled ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "退出 TokensBar", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    /// Submenu picking which rank the menu bar shows, with the live numbers
    /// inline so the choice is obvious.
    private func rankModeItem() -> NSMenuItem {
        let parent = NSMenuItem(title: "菜单栏显示排名", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for mode in [RankMode.allTime, .today] {
            let st = server?.standing(mode)
            let detail: String
            if let st { detail = st.rank > 0 ? "  #\(st.rank) / \(st.totalUsers)" : "  未上榜" }
            else { detail = "" }
            let it = NSMenuItem(title: mode.label + detail,
                                action: #selector(setRankMode(_:)), keyEquivalent: "")
            it.target = self
            it.representedObject = mode.rawValue
            it.state = mode == rankMode ? .on : .off
            sub.addItem(it)
        }
        sub.addItem(.separator())
        sub.addItem(disabledItem("累计榜 = 历史总量排名", font: rowFont, dim: true))
        sub.addItem(disabledItem("今日榜 = 只算当天提交量的排名", font: rowFont, dim: true))
        parent.submenu = sub
        return parent
    }

    @objc private func setRankMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let mode = RankMode(rawValue: raw) else { return }
        rankMode = mode
        UserDefaults.standard.set(raw, forKey: Controller.rankModeKey)
        render()
    }

    // MARK: Actions


    @objc private func refreshAll() {
        refreshLocal()
        refreshServer()
    }

    @objc private func submitNow() {
        guard !busy else { return }
        busy = true
        transient = "提交中…"
        render()
        workQueue.async { [weak self] in
            let result = CLI.run(["submit", "--no-spinner"], timeout: 300)
            DispatchQueue.main.async {
                guard let self else { return }
                self.busy = false
                let ok = result?.1 == 0
                self.transient = ok ? "已提交 ✓ \(fmtClock(Date()))" : "提交失败 ✗ \(fmtClock(Date()))"
                self.render()
                // Server-side aggregation lags a moment behind the POST.
                DispatchQueue.main.asyncAfter(deadline: .now() + 6) { self.refreshServer() }
                DispatchQueue.main.asyncAfter(deadline: .now() + 90) {
                    self.transient = nil
                    self.render()
                }
            }
        }
    }

    @objc private func openProfile() {
        let name = config.username
        let path = name.isEmpty ? "/leaderboard" : "/u/\(name)"
        guard let url = URL(string: config.apiBase + path) else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func toggleLoginItem() {
        LoginItem.set(!LoginItem.isEnabled)
        render()
    }

    @objc private func quit() { NSApp.terminate(nil) }
}

// MARK: - Entry point

/// Prints exactly what the menu would show, then exits. Useful for checking the
/// data path (CLI discovery, network, parsing) without the GUI.
func runDump() -> Never {
    let config = Config.load()
    print("username: \(config.username.isEmpty ? "(none)" : config.username)")
    print("tokens CLI: \(CLI.binary() ?? "NOT FOUND")")

    var local = LocalStats()
    let today = CLI.report(["--today"])
    let week = CLI.report(["--week"])
    if today == nil && week == nil {
        local.failed = true
    } else {
        if let today { local.todayTokens = today.tokens; local.todayCost = today.cost }
        if let week { local.weekTokens = week.tokens; local.weekCost = week.cost }
        local.updatedAt = Date()
    }

    var server: ServerStats?
    let sema = DispatchSemaphore(value: 0)
    let api = API(config: config) // held strongly: fetch captures self weakly
    api.fetch(on: .global()) { s in server = s; sema.signal() }
    if sema.wait(timeout: .now() + 45) == .timedOut { print("api: TIMEOUT") }

    let mode = UserDefaults.standard.string(forKey: "menuBarRank")
        .flatMap(RankMode.init(rawValue:)) ?? config.menuBarRank
    let p = Presenter(config: config, rankMode: mode, server: server, local: local,
                      serverFailed: server == nil, transient: nil)
    print("\nmenu bar:  ⚡ \(p.title)   (rank mode: \(mode.rawValue))\n")
    for line in p.lines {
        switch line {
        case .separator: print("  " + String(repeating: "─", count: 42))
        case .header(let t): print("  " + t)
        case .row(let l, let v, let tr): print("  " + rowText(l, v, tr))
        case .note(let t), .small(let t): print("  " + t)
        }
    }
    exit(server == nil || local.failed ? 1 : 0)
}

if CommandLine.arguments.contains("--dump") { runDump() }

// `--set-login on|off` toggles the LaunchAgent without opening the menu.
if let i = CommandLine.arguments.firstIndex(of: "--set-login") {
    let want = CommandLine.arguments.count > i + 1 ? CommandLine.arguments[i + 1] : "on"
    LoginItem.set(want != "off")
    print("login item: \(LoginItem.isEnabled ? "enabled" : "disabled") (\(LoginItem.plistPath))")
    exit(0)
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = Controller()
    func applicationDidFinishLaunching(_ notification: Notification) {
        controller.start()
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()

