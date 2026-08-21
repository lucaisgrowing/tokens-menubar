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
    /// Initial UI language; the menu can override it.
    var language: Lang = .en

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
        if let v = o["language"] as? String, let l = Lang(rawValue: v) { cfg.language = l }
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

/// CJK glyphs occupy two cells in a monospaced run, so padding by character
/// count would misalign the Chinese labels against the English ones.
func displayWidth(_ s: String) -> Int {
    s.unicodeScalars.reduce(0) { total, u in
        switch u.value {
        case 0x1100...0x115F, 0x2E80...0xA4CF, 0xA960...0xA97F, 0xAC00...0xD7A3,
             0xF900...0xFAFF, 0xFE30...0xFE6F, 0xFF00...0xFF60, 0xFFE0...0xFFE6,
             0x1F300...0x1F9FF, 0x20000...0x3FFFD:
            return total + 2
        default:
            return total + 1
        }
    }
}

func padDisplay(_ s: String, _ width: Int) -> String {
    let w = displayWidth(s)
    return w >= width ? s : s + String(repeating: " ", count: width - w)
}

/// Truncates to a display width, for columns that must not run into each other.
func clipDisplay(_ s: String, _ width: Int) -> String {
    guard displayWidth(s) > width else { return s }
    var out = ""
    for ch in s {
        if displayWidth(out + String(ch)) > width - 1 { break }
        out.append(ch)
    }
    return out + "…"
}

/// One layout for value rows, shared by the menu and `--dump`.
func rowText(_ label: String, _ value: String, _ trailing: String?) -> String {
    let head = padDisplay(label, 11) + padDisplay(value, 11)
    guard let trailing else { return head }
    return head + (head.hasSuffix(" ") ? "" : " ") + trailing
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
    let cost: Double
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

    var label: String { self == .today ? t("board.today") : t("board.allTime") }
    /// Menu bar prefix — marks a daily rank so it cannot be read as a lifetime one.
    var badge: String {
        if self == .allTime { return "#" }
        return L10n.current == .zh ? "今#" : "D#"
    }
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
    /// Per-model breakdown of today, for the donut chart.
    var todayModels: [ModelSlice] = []
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
    /// reasoning has no top-level total, so it is summed from the entries. The
    /// entries also carry the per-model split used by the chart.
    static func report(_ extraArgs: [String]) -> (tokens: Int, cost: Double, models: [ModelSlice])? {
        guard let (data, status) = run(extraArgs + ["--json", "--no-spinner"]), status == 0,
              let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        let entries = o["entries"] as? [[String: Any]] ?? []
        let reasoning = entries.reduce(0) { $0 + int($1, "reasoning") }
        let total = int(o, "totalInput") + int(o, "totalOutput")
            + int(o, "totalCacheRead") + int(o, "totalCacheWrite") + reasoning
        // Entries are grouped by client+model, so the same model can appear more
        // than once; the chart merges duplicate labels itself.
        let models = entries.map { e in
            ModelSlice(model: e["model"] as? String ?? "?",
                       tokens: int(e, "input") + int(e, "output") + int(e, "cacheRead")
                           + int(e, "cacheWrite") + int(e, "reasoning"),
                       cost: dbl(e, "cost"))
        }
        return (total, dbl(o, "totalCost"), models)
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
                           cost: dbl($0, "cost"))
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
    /// A non-nil scope makes the row clickable and opens that chart.
    case row(String, String, String?, ChartScope?)
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
        var bits = [local.failed ? t("tooltip.localFailed")
                                 : t("tooltip.today", fmtExact(local.todayTokens))]
        if let s = server {
            if let a = s.allTime, a.rank > 0 {
                bits.append(t("tooltip.rankAllTime", a.rank, a.totalUsers))
            }
            if let d = s.today {
                bits.append(d.rank > 0 ? t("tooltip.rankToday", d.rank, d.totalUsers)
                                       : t("tooltip.rankTodayNone"))
            }
        }
        return bits.joined(separator: "\n")
    }

    private func standingRow(_ mode: RankMode) -> Line? {
        guard let st = server?.standing(mode) else { return nil }
        let value = st.rank > 0 ? "#\(st.rank) / \(st.totalUsers)" : t("board.notRanked")
        return .row(mode.label, value, mode == rankMode ? t("marker.menuBar") : nil, nil)
    }

    private var gapLine: Line? {
        guard let st = server?.standing(rankMode) else { return nil }
        if st.rank == 0 { return .note(t("gap.unranked", rankMode.label)) }
        guard let above = st.above else {
            return st.rank == 1 ? .note(t("gap.first", rankMode.label)) : nil
        }
        let gap = max(0, above.tokens - st.tokens)
        return .note(t("gap.behind", rankMode.label, fmtTokens(gap), above.rank, above.username))
    }

    var lines: [Line] {
        var out: [Line] = []
        out.append(.header(config.username.isEmpty ? t("state.notLoggedIn") : "@" + config.username))
        out.append(.separator)

        if server != nil {
            if let l = standingRow(.allTime) { out.append(l) }
            if let l = standingRow(.today) { out.append(l) }
            out.append(.note(t("board.hint")))
            out.append(.separator)
        }

        if let s = server {
            out.append(.row(t("row.lifetime"), fmtTokens(s.totalTokens),
                            fmtMoney(s.totalCost), .lifetime))
        } else if serverFailed {
            out.append(.note(t("state.serverFailed")))
        } else {
            out.append(.note(t("state.loading")))
        }

        if local.failed {
            out.append(.note(t("state.localFailed")))
        } else {
            out.append(.row(t("row.today"), fmtTokens(local.todayTokens),
                            fmtMoney(local.todayCost), .today))
            out.append(.row(t("row.week"), fmtTokens(local.weekTokens),
                            fmtMoney(local.weekCost), nil))
        }
        out.append(.small(t("chart.hint")))

        if let l = gapLine {
            out.append(.separator)
            out.append(l)
        }

        if config.topModels > 0, let s = server, !s.models.isEmpty {
            out.append(.separator)
            let denom = Double(max(1, s.totalTokens))
            for m in s.models.sorted(by: { $0.tokens > $1.tokens }).prefix(config.topModels) {
                let n = clipDisplay(m.model, 22)
                let share = Double(m.tokens) / denom * 100
                out.append(.small("\(padDisplay(n, 24))\(String(format: "%5.1f%%", share))  \(fmtTokens(m.tokens))"))
            }
        }

        out.append(.separator)
        if let transient {
            out.append(.note(transient))
        } else {
            var bits: [String] = []
            if let d = local.updatedAt { bits.append(t("stamp.local", fmtClock(d))) }
            if let d = server?.updatedAt { bits.append(t("stamp.server", fmtClock(d))) }
            if server?.isStale == true { bits.append(t("stamp.stale")) }
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
    private var update: UpdateInfo?
    private var checkingUpdate = false
    private var lastServerFetch: Date?
    private var apiTimer: Timer?
    private var localTimer: Timer?
    private var updateTimer: Timer?
    private let workQueue = DispatchQueue(label: "ci.tokens.menubar.cli", qos: .utility)

    private let monoFont = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)
    private let rowFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)

    /// config.json sets the defaults; flipping them in the menu wins from then on.
    private static let rankModeKey = "menuBarRank"
    private static let languageKey = "language"

    override init() {
        super.init()
        let storedRank = UserDefaults.standard.string(forKey: Controller.rankModeKey)
        rankMode = storedRank.flatMap(RankMode.init(rawValue:)) ?? config.menuBarRank
        let storedLang = UserDefaults.standard.string(forKey: Controller.languageKey)
        L10n.current = storedLang.flatMap(Lang.init(rawValue:)) ?? config.language
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
        // Quiet daily check; the menu item does the same thing on demand.
        checkForUpdates(announce: false)
        updateTimer = Timer.scheduledTimer(withTimeInterval: 86_400, repeats: true) {
            [weak self] _ in self?.checkForUpdates(announce: false)
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
            if let models = self.server?.models {
                ChartPopover.shared.update(scope: .lifetime, data: models.map(Self.datum))
            }
        }
    }

    private static func datum(_ m: ModelSlice) -> ChartDatum {
        ChartDatum(label: m.model, tokens: m.tokens, cost: m.cost)
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
                    if let today {
                        self.local.todayTokens = today.tokens
                        self.local.todayCost = today.cost
                        self.local.todayModels = today.models
                    }
                    if let week { self.local.weekTokens = week.tokens; self.local.weekCost = week.cost }
                    self.local.updatedAt = Date()
                }
                self.render()
                ChartPopover.shared.update(scope: .today,
                                                   data: self.local.todayModels.map(Self.datum))
            }
        }
    }

    private func checkForUpdates(announce: Bool) {
        if announce {
            checkingUpdate = true
            transient = t("update.checking")
            render()
        }
        Updates.check { [weak self] info in
            guard let self else { return }
            self.checkingUpdate = false
            self.update = info
            if announce {
                if let info {
                    self.transient = info.isNewer
                        ? t("update.available", info.latest, info.current)
                        : t("update.upToDate", info.current)
                } else {
                    self.transient = t("update.failed")
                }
                self.clearTransient(after: 20)
            }
            self.render()
        }
    }

    private func clearTransient(after seconds: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            guard let self else { return }
            self.transient = nil
            self.render()
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
        case .row(let label, let value, let trailing, let scope):
            let text = rowText(label, value, trailing)
            guard let scope else { return disabledItem(text, font: rowFont, dim: false) }
            let it = NSMenuItem(title: text, action: #selector(openChart(_:)), keyEquivalent: "")
            it.attributedTitle = NSAttributedString(string: text, attributes: [.font: rowFont])
            it.representedObject = scope == .today ? "today" : "lifetime"
            it.target = self
            return it
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

        let submit = NSMenuItem(title: busy ? t("action.submitting") : t("action.submit"),
                                action: #selector(submitNow), keyEquivalent: "s")
        submit.target = self
        submit.isEnabled = !busy && CLI.binary() != nil
        menu.addItem(submit)

        let refresh = NSMenuItem(title: t("action.refresh"), action: #selector(refreshAll), keyEquivalent: "r")
        refresh.target = self
        menu.addItem(refresh)

        menu.addItem(rankModeItem())
        menu.addItem(languageItem())

        let profile = NSMenuItem(title: t("action.openProfile"), action: #selector(openProfile), keyEquivalent: "o")
        profile.target = self
        menu.addItem(profile)

        let updates = NSMenuItem(title: updateItemTitle(),
                                 action: #selector(updateItemClicked), keyEquivalent: "u")
        updates.target = self
        updates.isEnabled = !checkingUpdate
        menu.addItem(updates)

        let login = NSMenuItem(title: t("action.launchAtLogin"), action: #selector(toggleLoginItem), keyEquivalent: "")
        login.target = self
        login.state = LoginItem.isEnabled ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: t("action.quit"), action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    private func updateItemTitle() -> String {
        if checkingUpdate { return t("update.checking") }
        if let u = update, u.isNewer { return t("update.openPage", u.latest) }
        return t("action.checkUpdates")
    }

    /// Submenu picking which rank the menu bar shows, with the live numbers
    /// inline so the choice is obvious.
    private func rankModeItem() -> NSMenuItem {
        let parent = NSMenuItem(title: t("action.rankMode"), action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for mode in [RankMode.allTime, .today] {
            let st = server?.standing(mode)
            let detail: String
            if let st { detail = st.rank > 0 ? "  #\(st.rank) / \(st.totalUsers)" : "  " + t("board.notRanked") }
            else { detail = "" }
            let it = NSMenuItem(title: mode.label + detail,
                                action: #selector(setRankMode(_:)), keyEquivalent: "")
            it.target = self
            it.representedObject = mode.rawValue
            it.state = mode == rankMode ? .on : .off
            sub.addItem(it)
        }
        sub.addItem(.separator())
        sub.addItem(disabledItem(t("board.explainAllTime"), font: rowFont, dim: true))
        sub.addItem(disabledItem(t("board.explainToday"), font: rowFont, dim: true))
        parent.submenu = sub
        return parent
    }

    private func languageItem() -> NSMenuItem {
        let parent = NSMenuItem(title: t("action.language"), action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for lang in Lang.allCases {
            let it = NSMenuItem(title: lang.displayName,
                                action: #selector(setLanguage(_:)), keyEquivalent: "")
            it.target = self
            it.representedObject = lang.rawValue
            it.state = lang == L10n.current ? .on : .off
            sub.addItem(it)
        }
        parent.submenu = sub
        return parent
    }

    @objc private func setLanguage(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let lang = Lang(rawValue: raw), lang != L10n.current else { return }
        L10n.current = lang
        UserDefaults.standard.set(raw, forKey: Controller.languageKey)
        transient = nil
        render()
        ChartPopover.shared.refreshLanguage()
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
        transient = t("action.submitting")
        render()
        workQueue.async { [weak self] in
            let result = CLI.run(["submit", "--no-spinner"], timeout: 300)
            DispatchQueue.main.async {
                guard let self else { return }
                self.busy = false
                let ok = result?.1 == 0
                self.transient = ok ? t("action.submitted", fmtClock(Date()))
                                    : t("action.submitFailed", fmtClock(Date()))
                self.render()
                // Server-side aggregation lags a moment behind the POST.
                DispatchQueue.main.asyncAfter(deadline: .now() + 6) { self.refreshServer() }
                self.clearTransient(after: 90)
            }
        }
    }

    /// Opens the release page when an update is waiting, otherwise checks.
    @objc private func updateItemClicked() {
        if let u = update, u.isNewer, let url = URL(string: u.url) {
            NSWorkspace.shared.open(url)
            return
        }
        checkForUpdates(announce: true)
    }

    @objc private func openChart(_ sender: NSMenuItem) {
        let isToday = (sender.representedObject as? String) == "today"
        let scope: ChartScope = isToday ? .today : .lifetime
        let models = isToday ? local.todayModels : (server?.models ?? [])
        ChartPopover.shared.show(scope: scope, data: models.map(Self.datum),
                                 from: statusItem.button)
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

/// Loads config, the local CLI reports and the server stats, blocking until both
/// are in. Shared by the diagnostic flags below.
func collect() -> (config: Config, local: LocalStats, server: ServerStats?) {
    let config = Config.load()
    var local = LocalStats()
    let today = CLI.report(["--today"])
    let week = CLI.report(["--week"])
    if today == nil && week == nil {
        local.failed = true
    } else {
        if let today {
            local.todayTokens = today.tokens
            local.todayCost = today.cost
            local.todayModels = today.models
        }
        if let week { local.weekTokens = week.tokens; local.weekCost = week.cost }
        local.updatedAt = Date()
    }

    var server: ServerStats?
    let sema = DispatchSemaphore(value: 0)
    let api = API(config: config) // held strongly: fetch captures self weakly
    api.fetch(on: .global()) { s in server = s; sema.signal() }
    if sema.wait(timeout: .now() + 45) == .timedOut { print("api: TIMEOUT") }
    return (config, local, server)
}

func applyLanguage(_ config: Config) {
    if let i = CommandLine.arguments.firstIndex(of: "--lang"),
       CommandLine.arguments.count > i + 1,
       let lang = Lang(rawValue: CommandLine.arguments[i + 1]) {
        L10n.current = lang
    } else {
        L10n.current = UserDefaults.standard.string(forKey: "language")
            .flatMap(Lang.init(rawValue:)) ?? config.language
    }
}

/// Prints exactly what the menu would show, then exits. Useful for checking the
/// data path (CLI discovery, network, parsing) without the GUI.
/// `--lang en|zh` overrides the language for this run only.
func runDump() -> Never {
    let (config, local, server) = collect()
    applyLanguage(config)
    print("username: \(config.username.isEmpty ? "(none)" : config.username)")
    print("tokens CLI: \(CLI.binary() ?? "NOT FOUND")")
    print("language: \(L10n.current.rawValue)   version: \(Updates.currentVersion)")

    let mode = UserDefaults.standard.string(forKey: "menuBarRank")
        .flatMap(RankMode.init(rawValue:)) ?? config.menuBarRank
    let p = Presenter(config: config, rankMode: mode, server: server, local: local,
                      serverFailed: server == nil, transient: nil)
    print("\nmenu bar:  ⚡ \(p.title)   (rank mode: \(mode.rawValue))\n")
    for line in p.lines {
        switch line {
        case .separator: print("  " + String(repeating: "─", count: 42))
        case .header(let s): print("  " + s)
        case .row(let l, let v, let tr, let scope):
            print("  " + rowText(l, v, tr) + (scope == nil ? "" : "   ← clickable"))
        case .note(let s), .small(let s): print("  " + s)
        }
    }

    // The same slices the donut chart would draw.
    for (scope, models) in [(ChartScope.today, local.todayModels),
                            (ChartScope.lifetime, server?.models ?? [])] {
        print("\n\(t(scope.titleKey)):")
        for metric in [ChartMetric.tokens, .cost] {
            let slices = chartSlices(models.map { ChartDatum(label: $0.model, tokens: $0.tokens, cost: $0.cost) },
                                     metric: metric)
            let total = slices.reduce(0.0) { $0 + $1.value(metric) }
            print("  [\(t(metric.titleKey))] total \(metric == .tokens ? fmtTokens(Int(total)) : fmtMoney(total))")
            for s in slices {
                let share = total > 0 ? s.value(metric) / total * 100 : 0
                let value = metric == .tokens ? fmtTokens(s.tokens) : fmtMoney(s.cost)
                print("    \(padDisplay(clipDisplay(s.label, 23), 24))\(pad(value, 11))\(String(format: "%5.1f%%", share))")
            }
        }
    }
    exit(server == nil || local.failed ? 1 : 0)
}

/// Renders the chart popover offscreen to a PNG, so the layout can be reviewed
/// without opening the GUI. `--scope today|lifetime`, `--metric tokens|cost`.
func runChartPNG(path: String) -> Never {
    let (config, local, server) = collect()
    applyLanguage(config)
    let args = CommandLine.arguments
    let scope: ChartScope = args.contains("lifetime") ? .lifetime : .today
    let metric: ChartMetric = args.contains("cost") ? .cost : .tokens
    let models = scope == .today ? local.todayModels : (server?.models ?? [])
    let data = models.map { ChartDatum(label: $0.model, tokens: $0.tokens, cost: $0.cost) }

    guard let png = ChartPopover.shared.snapshot(scope: scope, data: data, metric: metric) else {
        print("render failed")
        exit(1)
    }
    try? png.write(to: URL(fileURLWithPath: path))
    print("wrote \(path) (\(t(scope.titleKey)), \(t(metric.titleKey)), \(chartSlices(data, metric: metric).count) slices)")
    exit(0)
}

/// Prints the update check result and exits.
func runUpdateCheck() -> Never {
    var result: UpdateInfo??
    let sema = DispatchSemaphore(value: 0)
    Updates.check(on: .global()) { result = $0; sema.signal() }
    _ = sema.wait(timeout: .now() + 30)
    guard let info = result ?? nil else {
        print("update check failed")
        exit(1)
    }
    print("current: v\(info.current)  latest: \(info.latest)  newer: \(info.isNewer)")
    print("url: \(info.url)")
    exit(0)
}

if CommandLine.arguments.contains("--dump") { runDump() }
if CommandLine.arguments.contains("--check-updates") { runUpdateCheck() }
if let i = CommandLine.arguments.firstIndex(of: "--chart-png"),
   CommandLine.arguments.count > i + 1 {
    runChartPNG(path: CommandLine.arguments[i + 1])
}

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

