// TokensBar — macOS menu bar readout for tokens.ci usage.
//
// Menu bar line:  ⚡ <today tokens>  #<rank>
// Data sources:
//   - tokens.ci REST API  → rank, lifetime and today's totals (every device on
//     the account, as of the last submission), model split, neighbour gap
//   - local `tokens` CLI  → this week, and today on this machine, live
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
    /// Where the "Buy Me a Coffee" item points.
    var supportURL = "https://github.com/lucaisgrowing/tokens-menubar#support"
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
        if let v = o["supportURL"] as? String, !v.isEmpty { cfg.supportURL = v }
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

/// One layout for value rows, shared by the menu and `--dump`. The label column
/// always keeps at least one space, however long the label is.
func rowText(_ label: String, _ value: String, _ trailing: String?) -> String {
    let labelWidth = max(12, displayWidth(label) + 1)
    let head = padDisplay(label, labelWidth) + padDisplay(value, 11)
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
    var contribs: [ContribDay] = []
    var contribStart: Date?
    var contribEnd: Date?

    func standing(_ mode: RankMode) -> BoardStanding? {
        mode == .today ? today : allTime
    }

    /// Today as the server has it: every device on the account, as of the last
    /// submission. Keyed by the GMT day — the same day the daily board counts, so
    /// the Today row and the daily rank never disagree. Nil until the first
    /// submission of that day lands.
    var todayDay: ContribDay? {
        let key = dayFormatter.string(from: Date())
        return contribs.first { dayFormatter.string(from: $0.date) == key }
    }

    /// Today's per-model split, for the donut chart.
    var todayModels: [ModelSlice] {
        (todayDay?.models ?? []).map {
            ModelSlice(model: $0.name, tokens: $0.tokens, cost: $0.cost)
        }
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

/// Today's slices for the donut chart: the server's all-device split, so the
/// chart agrees with the Today row, falling back to this machine's scan before
/// the day's first submission.
func todayChartModels(_ local: LocalStats, _ server: ServerStats?) -> [ModelSlice] {
    let fromServer = server?.todayModels ?? []
    return fromServer.isEmpty ? local.todayModels : fromServer
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

    /// Runs the CLI and returns its output and exit code. stderr is captured on
    /// a separate queue so a chatty CLI cannot deadlock the pipe.
    ///
    /// Note the flag order the CLI wants: global options such as `--no-spinner`
    /// and `--json` are rejected after a subcommand, so they go before it —
    /// `tokens --no-spinner submit`, not `tokens submit --no-spinner`.
    static func run(_ args: [String], timeout: TimeInterval = 120)
        -> (out: Data, err: Data, status: Int32)? {
        guard let bin = binary() else { return nil }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: bin)
        p.arguments = args
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        p.standardInput = FileHandle.nullDevice
        do { try p.run() } catch { return nil }

        let errData = DispatchGroup()
        var captured = Data()
        errData.enter()
        DispatchQueue.global(qos: .utility).async {
            captured = (try? err.fileHandleForReading.readToEnd()) ?? Data()
            errData.leave()
        }
        let killer = DispatchWorkItem { if p.isRunning { p.terminate() } }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: killer)

        let data = (try? out.fileHandleForReading.readToEnd()) ?? Data()
        p.waitUntilExit()
        killer.cancel()
        errData.wait()
        return (data, captured, p.terminationStatus)
    }

    /// First meaningful line of a failed run, for surfacing in the menu.
    static func firstLine(_ data: Data) -> String? {
        String(data: data, encoding: .utf8)?
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
    }

    /// `tokens --json` totals: the site counts input+output+cacheRead+cacheWrite+reasoning.
    /// reasoning has no top-level total, so it is summed from the entries. The
    /// entries also carry the per-model split used by the chart.
    static func report(_ extraArgs: [String]) -> (tokens: Int, cost: Double, models: [ModelSlice])? {
        guard let r = run(["--json", "--no-spinner"] + extraArgs), r.status == 0,
              let o = try? JSONSerialization.jsonObject(with: r.out) as? [String: Any]
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
            let contribs: [ContribDay] = (o["contributions"] as? [[String: Any]] ?? [])
                .compactMap { entry in
                    guard let date = parseDay(entry["date"]) else { return nil }
                    let totals = entry["totals"] as? [String: Any]
                    let tokens = int(totals, "tokens")
                    // The API reports 0 for some days that do have tokens; a day
                    // with usage must never render as an empty cell.
                    let level = max(int(entry, "intensity"), tokens > 0 ? 1 : 0)
                    var clientMessages = 0
                    var modelTotals: [String: (tokens: Int, cost: Double)] = [:]
                    let clients = (entry["clients"] as? [[String: Any]] ?? []).compactMap {
                        c -> ContribSlice? in
                        guard let name = c["client"] as? String else { return nil }
                        clientMessages += int(c, "messages")
                        // Each client carries its own per-model map; the day's model
                        // split is those maps merged.
                        for (model, raw) in (c["models"] as? [String: Any] ?? [:]) {
                            guard let m = raw as? [String: Any] else { continue }
                            var e = modelTotals[model] ?? (0, 0)
                            e.tokens += int(m, "tokens")
                            e.cost += dbl(m, "cost")
                            modelTotals[model] = e
                        }
                        let b = c["tokens"] as? [String: Any]
                        return ContribSlice(
                            name: name,
                            tokens: int(b, "input") + int(b, "output") + int(b, "cacheRead")
                                + int(b, "cacheWrite") + int(b, "reasoning"),
                            cost: dbl(c, "cost"))
                    }
                    let models = modelTotals
                        .map { ContribSlice(name: $0.key, tokens: $0.value.tokens, cost: $0.value.cost) }
                        .sorted { $0.tokens > $1.tokens }
                    return ContribDay(date: date, tokens: tokens,
                                      cost: dbl(totals, "cost"),
                                      messages: max(int(totals, "messages"), clientMessages),
                                      level: level,
                                      clients: clients.sorted { $0.tokens > $1.tokens },
                                      models: models)
                }
            let range = o["chartRange"] as? [String: Any]

            var stats = ServerStats(
                rank: int(u, "rank"),
                totalTokens: int(s, "totalTokens"),
                totalCost: dbl(s, "totalCost"),
                activeDays: int(s, "activeDays"),
                updatedAt: parseDate(o["updatedAt"]) ?? parseDate(fresh?["lastUpdated"]),
                isStale: (fresh?["isStale"] as? Bool) ?? false,
                models: models,
                allTime: nil,
                today: nil,
                contribs: contribs,
                contribStart: parseDay(range?["start"]) ?? contribs.first?.date,
                contribEnd: parseDay(range?["end"]) ?? contribs.last?.date)

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

/// What a clickable dropdown row opens.
enum RowAction: Equatable {
    case chart(ChartScope)
    case contributions
}

enum Line {
    case header(String)
    /// A non-nil action makes the row clickable.
    case row(String, String, String?, RowAction?)
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

    /// The server's figure for today — all devices, as of the last submission.
    /// Preferred everywhere over the local scan so the numbers agree with the
    /// daily rank and with the site; the local scan is still shown alongside,
    /// because it is live.
    private var serverToday: ContribDay? { server?.todayDay }

    var title: String {
        var parts: [String] = []
        if let d = serverToday { parts.append(fmtTokens(d.tokens)) }
        else { parts.append(local.failed ? "—" : fmtTokens(local.todayTokens)) }
        if let st = server?.standing(rankMode) {
            parts.append(st.rank > 0 ? "\(rankMode.badge)\(st.rank)" : "\(rankMode.badge)—")
        } else if serverFailed {
            parts.append("#?")
        }
        return parts.joined(separator: "  ")
    }

    var tooltip: String {
        var bits: [String] = []
        if let d = serverToday { bits.append(t("tooltip.todayAll", fmtExact(d.tokens))) }
        bits.append(local.failed ? t("tooltip.localFailed")
                                 : t("tooltip.todayLocal", fmtExact(local.todayTokens)))
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
                            fmtMoney(s.totalCost), .chart(.lifetime)))
        } else if serverFailed {
            out.append(.note(t("state.serverFailed")))
        } else {
            out.append(.note(t("state.loading")))
        }

        // Today is the server's all-device figure, so this row, the daily rank
        // and the site all say the same thing. Before the day's first submission
        // there is no server figure yet and the local scan stands in.
        if let d = serverToday {
            out.append(.row(t("row.today"), fmtTokens(d.tokens), fmtMoney(d.cost), .chart(.today)))
        } else if !local.failed {
            out.append(.row(t("row.today"), fmtTokens(local.todayTokens),
                            fmtMoney(local.todayCost), .chart(.today)))
        }

        if local.failed {
            out.append(.note(t("state.localFailed")))
        } else {
            // The live counterpart: this machine only, including work not yet
            // submitted. Kept visible because the row above can only move when a
            // submission lands.
            if serverToday != nil {
                out.append(.note(t("row.todayLocal", fmtTokens(local.todayTokens),
                                   fmtMoney(local.todayCost))))
            }
            out.append(.row(t("row.week"), fmtTokens(local.weekTokens),
                            fmtMoney(local.weekCost), nil))
        }
        if let s = server, !s.contribs.isEmpty {
            let active = s.contribs.filter { $0.tokens > 0 }.count
            out.append(.row(t("heat.row"), "\(active)", nil, .contributions))
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
    /// How the current `transient` reads. A submit outcome earns the panel's
    /// banner; a background notice stays on the timestamp line.
    private var noticeKind: PanelNotice = .info
    /// Bumped every time a notice is set, so a pending clear only fires for the
    /// notice it was scheduled for — a submit landing during an update check's
    /// 20-second window used to have its banner wiped early.
    private var noticeToken = 0
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
            // Left-click opens the drawn panel; right-click keeps the plain menu,
            // which is the keyboard-shortcut and accessibility path.
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        menu.delegate = self
        DropdownPanel.shared.onAction = { [weak self] action in self?.handle(action) }
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
            // Today's split comes from the server too, so a server refresh moves it.
            ChartPopover.shared.update(
                scope: .today,
                data: todayChartModels(self.local, self.server).map(Self.datum))
            if let st = self.server, let from = st.contribStart, let to = st.contribEnd {
                ContribPopover.shared.update(days: st.contribs, start: from, end: to)
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
                ChartPopover.shared.update(
                    scope: .today,
                    data: todayChartModels(self.local, self.server).map(Self.datum))
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
                let message: String
                if let info {
                    message = info.isNewer
                        ? t("update.available", info.latest, info.current)
                        : t("update.upToDate", info.current)
                } else {
                    message = t("update.failed")
                }
                self.note(message, kind: .info)
                self.render()
                self.clearTransient(after: 20)
                return
            }
            self.render()
        }
    }

    /// Clears the notice, unless a newer one has already replaced it — two
    /// overlapping timers would otherwise let the older one wipe the newer text.
    private func clearTransient(after seconds: TimeInterval) {
        let token = noticeToken
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            guard let self, self.noticeToken == token else { return }
            self.transient = nil
            self.noticeKind = .info
            self.render()
        }
    }

    // MARK: Rendering

    private var presenter: Presenter {
        Presenter(config: config, rankMode: rankMode, server: server, local: local,
                  serverFailed: serverFailed, transient: transient)
    }

    /// The drawn panel reads the same inputs as the text menu, plus the state its
    /// actions page shows: the numbers alone cannot say whether an update is
    /// waiting or the login item is on.
    private var panelData: PanelData {
        var data = PanelData(config: config, rankMode: rankMode, server: server, local: local,
                             serverFailed: serverFailed, busy: busy, transient: transient)
        data.loginEnabled = LoginItem.isEnabled
        data.updateTitle = updateItemTitle()
        data.updateWaiting = update?.isNewer == true
        data.canSubmit = CLI.binary() != nil
        return data
    }

    private func render() {
        let p = presenter
        statusItem.button?.attributedTitle = NSAttributedString(
            string: " " + p.title, attributes: [.font: monoFont])
        statusItem.button?.toolTip = p.tooltip
        rebuildMenu()
        DropdownPanel.shared.update(panelData)
    }

    /// Left-click draws the panel; right-click (or control-click) pops the menu.
    @objc private func statusItemClicked() {
        let event = NSApp.currentEvent
        let wantsMenu = event?.type == .rightMouseUp
            || event?.modifierFlags.contains(.control) == true
        if wantsMenu { popMenu(); return }
        if DropdownPanel.shared.isShown || DropdownPanel.shared.justClosed {
            DropdownPanel.shared.close()
            return
        }
        // Opening the panel is an explicit request for current numbers.
        refreshLocal()
        if lastServerFetch.map({ Date().timeIntervalSince($0) >= 60 }) ?? true { refreshServer() }
        DropdownPanel.shared.show(panelData, from: statusItem.button)
    }

    /// The status item only owns the menu for as long as it is open, so a plain
    /// left-click still reaches `statusItemClicked`.
    private func popMenu() {
        DropdownPanel.shared.close()
        rebuildMenu()
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
    }

    func menuDidClose(_ menu: NSMenu) { statusItem.menu = nil }

    private func handle(_ action: PanelAction) {
        switch action {
        case .menuPage, .back:
            // The panel turns its own pages; the controller only hears the verbs.
            break
        case .profile:
            openProfile()
        case .textMenu:
            popMenu()
        case .history:
            guard let s = server, let from = s.contribStart, let to = s.contribEnd else { return }
            DropdownPanel.shared.close()
            ContribPopover.shared.show(days: s.contribs, start: from, end: to,
                                       from: statusItem.button)
        case .chart(let scope):
            let models = scope == .today ? todayChartModels(local, server) : (server?.models ?? [])
            guard !models.isEmpty else { return }
            DropdownPanel.shared.close()
            ChartPopover.shared.show(scope: scope, data: models.map(Self.datum),
                                     from: statusItem.button)
        case .submit:
            submitNow()
        case .refresh:
            refreshAll()
        case .setRank(let mode):
            use(rank: mode)
        case .setLanguage(let lang):
            use(language: lang)
        case .toggleLogin:
            toggleLoginItem()
        case .updates:
            updateItemClicked()
        case .support:
            openSupport()
        case .quit:
            quit()
        }
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
        case .row(let label, let value, let trailing, let action):
            let text = rowText(label, value, trailing)
            guard let action else { return disabledItem(text, font: rowFont, dim: false) }
            let it = NSMenuItem(title: text, action: #selector(openRow(_:)), keyEquivalent: "")
            it.attributedTitle = NSAttributedString(string: text, attributes: [.font: rowFont])
            switch action {
            case .chart(let scope): it.representedObject = scope == .today ? "today" : "lifetime"
            case .contributions: it.representedObject = "contributions"
            }
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

    /// The menu as text, for `--menu-dump`: nesting depth is the thing this menu is
    /// judged on, and it is invisible in a screenshot.
    func menuTree() -> [String] {
        rebuildMenu()
        return Controller.describe(menu, depth: 0)
    }

    private static func describe(_ m: NSMenu, depth: Int) -> [String] {
        m.items.flatMap { it -> [String] in
            // Indented rows stand in for the submenus this menu used to have, so
            // the dump has to show indentationLevel or it can't tell them apart.
            let indent = String(repeating: "    ", count: depth + it.indentationLevel)
            let key = it.keyEquivalent.isEmpty ? "" : "  ⌘" + it.keyEquivalent.uppercased()
            let body = it.isSeparatorItem
                ? "──────"
                : (it.state == .on ? "✓ " : "") + it.title + key
                    + (it.isEnabled || it.isSeparatorItem ? "" : "  ·")
            return [indent + body]
                + (it.submenu.map { Controller.describe($0, depth: depth + 1) } ?? [])
        }
    }

    /// One shape, one level deep. The numbers lead and the verbs follow, both at
    /// the top level: the model breakdowns hang off the Lifetime, Today and active
    /// day rows, and burying those in a submenu put the charts three clicks from
    /// the menu bar.
    private func rebuildMenu() {
        menu.removeAllItems()
        for line in presenter.lines {
            if let it = item(line) { menu.addItem(it) }
        }
        // The presenter's own trailing rule would otherwise double up with ours.
        if menu.items.last?.isSeparatorItem != true { menu.addItem(.separator()) }
        addActions()
    }

    /// Action rows carry an SF Symbol so the menu reads as a list of verbs
    /// rather than a wall of text.
    private func actionItem(_ title: String, symbol: String, action: Selector,
                            key: String = "") -> NSMenuItem {
        let it = NSMenuItem(title: title, action: action, keyEquivalent: key)
        it.target = self
        it.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        return it
    }

    private func addActions() {
        let submit = actionItem(busy ? t("action.submitting") : t("action.submit"),
                               symbol: "arrow.up.circle", action: #selector(submitNow), key: "s")
        submit.isEnabled = !busy && CLI.binary() != nil
        menu.addItem(submit)

        menu.addItem(actionItem(t("action.refresh"), symbol: "arrow.clockwise",
                                action: #selector(refreshAll), key: "r"))

        menu.addItem(.separator())
        addRankModeItems()
        addLanguageItems()

        menu.addItem(actionItem(t("action.openProfile"), symbol: "person.crop.circle",
                                action: #selector(openProfile), key: "o"))

        let updateWaiting = update?.isNewer == true
        let updates = actionItem(updateItemTitle(),
                                 symbol: updateWaiting ? "arrow.down.circle.fill" : "arrow.down.circle",
                                 action: #selector(updateItemClicked), key: "u")
        updates.isEnabled = !checkingUpdate
        menu.addItem(updates)

        menu.addItem(actionItem(t("action.support"), symbol: "cup.and.saucer.fill",
                                action: #selector(openSupport)))

        let login = actionItem(t("action.launchAtLogin"), symbol: "power",
                               action: #selector(toggleLoginItem))
        login.state = LoginItem.isEnabled ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())
        menu.addItem(actionItem(t("action.quit"), symbol: "xmark.circle",
                                action: #selector(quit), key: "q"))
    }

    private func updateItemTitle() -> String {
        if checkingUpdate { return t("update.checking") }
        if let u = update, u.isNewer { return t("update.openPage", u.latest) }
        return t("action.checkUpdates")
    }

    /// The two boards, as sibling rows under one caption rather than a submenu.
    /// A checkmark already says which is showing, so the choice does not need a
    /// level of its own; the live rank rides along so the labels mean something.
    private func addRankModeItems() {
        menu.addItem(captionItem(t("action.rankMode"), symbol: "list.number"))
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
            it.indentationLevel = 1
            menu.addItem(it)
        }
    }

    private func addLanguageItems() {
        menu.addItem(captionItem(t("action.language"), symbol: "globe"))
        for lang in Lang.allCases {
            let it = NSMenuItem(title: lang.displayName,
                                action: #selector(setLanguage(_:)), keyEquivalent: "")
            it.target = self
            it.representedObject = lang.rawValue
            it.state = lang == L10n.current ? .on : .off
            it.indentationLevel = 1
            menu.addItem(it)
        }
    }

    /// A dim, unclickable heading for the indented rows under it — what a submenu's
    /// parent item used to say, without the submenu.
    private func captionItem(_ title: String, symbol: String) -> NSMenuItem {
        let it = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        it.attributedTitle = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.secondaryLabelColor])
        it.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        it.isEnabled = false
        return it
    }

    @objc private func setLanguage(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let lang = Lang(rawValue: raw) else { return }
        use(language: lang)
    }

    @objc private func setRankMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let mode = RankMode(rawValue: raw) else { return }
        use(rank: mode)
    }

    /// The menu item and the panel's actions page both land here, so a setting
    /// cannot behave differently depending on which one flipped it.
    private func use(language lang: Lang) {
        guard lang != L10n.current else { return }
        L10n.current = lang
        UserDefaults.standard.set(lang.rawValue, forKey: Controller.languageKey)
        transient = nil
        render()
        ChartPopover.shared.refreshLanguage()
        ContribPopover.shared.refreshLanguage()
    }

    private func use(rank mode: RankMode) {
        guard mode != rankMode else { return }
        rankMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: Controller.rankModeKey)
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
        note(t("action.submitting"), kind: .info)
        render()
        workQueue.async { [weak self] in
            // Global flags must precede the subcommand; `submit --no-spinner`
            // is rejected by the CLI outright.
            let result = CLI.run(["--no-spinner", "submit"], timeout: 300)
            DispatchQueue.main.async {
                guard let self else { return }
                self.busy = false
                let ok = result?.status == 0
                if ok {
                    self.note(t("action.submitted", fmtClock(Date())), kind: .success)
                } else {
                    let reason = result.flatMap { CLI.firstLine($0.err) ?? CLI.firstLine($0.out) }
                    self.note(t("action.submitFailed", fmtClock(Date()))
                        + (reason.map { " — " + clipDisplay($0, 48) } ?? ""), kind: .failure)
                }
                self.render()
                // The outcome of a button press should not be something the user has
                // to go looking for: if the panel is shut, open it on the banner.
                // A failure stays up until dismissed; a success clears itself.
                if !DropdownPanel.shared.isShown {
                    DropdownPanel.shared.show(self.panelData, from: self.statusItem.button)
                }
                // Server-side aggregation lags a moment behind the POST.
                DispatchQueue.main.asyncAfter(deadline: .now() + 6) { self.refreshServer() }
                if ok { self.clearTransient(after: 12) }
            }
        }
    }

    /// Sets the transient notice and how it reads, invalidating any pending clear.
    private func note(_ message: String, kind: PanelNotice) {
        transient = message
        noticeKind = kind
        noticeToken += 1
    }

    /// Opens the release page when an update is waiting, otherwise checks.
    @objc private func updateItemClicked() {
        if let u = update, u.isNewer, let url = URL(string: u.url) {
            NSWorkspace.shared.open(url)
            return
        }
        checkForUpdates(announce: true)
    }

    @objc private func openRow(_ sender: NSMenuItem) {
        switch sender.representedObject as? String {
        case "contributions":
            guard let s = server, let from = s.contribStart, let to = s.contribEnd else { return }
            ContribPopover.shared.show(days: s.contribs, start: from, end: to,
                                       from: statusItem.button)
        case let which:
            let isToday = which == "today"
            let scope: ChartScope = isToday ? .today : .lifetime
            let models = isToday ? todayChartModels(local, server) : (server?.models ?? [])
            ChartPopover.shared.show(scope: scope, data: models.map(Self.datum),
                                     from: statusItem.button)
        }
    }

    @objc private func openProfile() {
        let name = config.username
        let path = name.isEmpty ? "/leaderboard" : "/u/\(name)"
        guard let url = URL(string: config.apiBase + path) else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func openSupport() {
        guard let url = URL(string: config.supportURL) else { return }
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
        case .row(let l, let v, let tr, let action):
            print("  " + rowText(l, v, tr) + (action == nil ? "" : "   ← clickable"))
        case .note(let s), .small(let s): print("  " + s)
        }
    }

    // The same slices the donut chart would draw.
    for (scope, models) in [(ChartScope.today, todayChartModels(local, server)),
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
    let models = scope == .today ? todayChartModels(local, server) : (server?.models ?? [])
    let data = models.map { ChartDatum(label: $0.model, tokens: $0.tokens, cost: $0.cost) }
    let dark = args.contains("dark")
    // `hover N` renders the highlight state for slice N; `reveal F` freezes the
    // draw-in animation at progress F.
    var hover: Int?
    if let i = args.firstIndex(of: "hover"), args.count > i + 1 { hover = Int(args[i + 1]) }
    var reveal: CGFloat = 1
    if let i = args.firstIndex(of: "reveal"), args.count > i + 1,
       let v = Double(args[i + 1]) { reveal = CGFloat(v) }

    guard let png = ChartPopover.shared.snapshot(scope: scope, data: data, metric: metric,
                                                 dark: dark, hover: hover, reveal: reveal) else {
        print("render failed")
        exit(1)
    }
    try? png.write(to: URL(fileURLWithPath: path))
    print("wrote \(path) (\(t(scope.titleKey)), \(t(metric.titleKey)), \(chartSlices(data, metric: metric).count) slices)")
    exit(0)
}

/// Renders the dropdown panel offscreen to a PNG, since the panel cannot be
/// screenshotted from a script. `dark` for dark mode, `menu` for the actions
/// page, `hover N` to force the readout for day N of the seven (0 = oldest).
func runPanelPNG(path: String) -> Never {
    let (config, local, server) = collect()
    applyLanguage(config)
    let args = CommandLine.arguments
    let mode = UserDefaults.standard.string(forKey: "menuBarRank")
        .flatMap(RankMode.init(rawValue:)) ?? config.menuBarRank
    var day: Int?
    if let i = args.firstIndex(of: "hover"), args.count > i + 1 { day = Int(args[i + 1]) }
    // `hit N` forces the hover state of clickable region N, which is what the
    // footer hint line reacts to.
    var hit: Int?
    if let i = args.firstIndex(of: "hit"), args.count > i + 1 { hit = Int(args[i + 1]) }
    let page: PanelPage = args.contains("menu") ? .menu : .main
    var data = PanelData(config: config, rankMode: mode, server: server, local: local,
                         serverFailed: server == nil, busy: false, transient: nil)
    // `notice success|failure|info <text>` forces the banner, which otherwise
    // only appears for a second or two after a real submit.
    if let i = args.firstIndex(of: "notice"), args.count > i + 2 {
        data.noticeKind = ["success": .success, "failure": .failure][args[i + 1]] ?? .info
        data.transient = args[i + 2]
    }
    // The actions page shows state the numbers do not carry.
    data.loginEnabled = LoginItem.isEnabled
    data.canSubmit = CLI.binary() != nil
    guard let png = DropdownPanel.shared.snapshot(data, dark: args.contains("dark"), page: page,
                                                  hoverDay: day, hoverHit: hit) else {
        print("render failed")
        exit(1)
    }
    try? png.write(to: URL(fileURLWithPath: path))
    print("wrote \(path) (today \(fmtTokens(data.todayTokens)), \(data.models.count) models,"
        + " rank mode \(mode.rawValue))")
    for line in DropdownPanel.shared.hitMap(data, page: page) { print("  " + line) }
    exit(0)
}

/// Opens the panel for real against a throwaway anchor, prints the live
/// geometry and captures the popover window — the only way to see what the
/// popover actually does to the view's width without clicking the status item.
/// Add `menu` to turn to the actions page while it is open, which is what the ⋯
/// button does.
func runPanelProbe(path: String?) -> Never {
    let (config, local, server) = collect()
    applyLanguage(config)
    let mode = UserDefaults.standard.string(forKey: "menuBarRank")
        .flatMap(RankMode.init(rawValue:)) ?? config.menuBarRank
    var data = PanelData(config: config, rankMode: mode, server: server, local: local,
                         serverFailed: server == nil, busy: false, transient: nil)
    data.loginEnabled = LoginItem.isEnabled
    data.canSubmit = CLI.binary() != nil
    let wantsMenu = CommandLine.arguments.contains("menu")
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let anchor = NSWindow(contentRect: NSRect(x: 500, y: 800, width: 40, height: 24),
                          styleMask: [.borderless], backing: .buffered, defer: false)
    anchor.isReleasedWhenClosed = false
    anchor.backgroundColor = .clear
    let host = NSView(frame: NSRect(x: 0, y: 0, width: 40, height: 24))
    anchor.contentView = host
    anchor.orderFront(nil)
    DropdownPanel.shared.show(data, from: host)
    // A refresh landing while the panel is open is what used to shove the content
    // 13 pt off-centre, so the probe always exercises it.
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
        DropdownPanel.shared.update(data)
        if wantsMenu { DropdownPanel.shared.turn(to: .menu) }
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
        print(DropdownPanel.shared.probe())
        if let path { print(DropdownPanel.shared.captureWindow(to: path)) }
        exit(0)
    }
    app.run()
    exit(0)
}

/// Prints the menu as a tree and exits.
func runMenuDump() -> Never {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let controller = Controller()
    controller.start()
    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
        for line in controller.menuTree() { print(line) }
        exit(0)
    }
    app.run()
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

/// Renders the contributions grid offscreen. `dark` for dark mode, `hover
/// YYYY-MM-DD` to force a day's readout.
func runContribPNG(path: String) -> Never {
    let (config, _, server) = collect()
    applyLanguage(config)
    guard let s = server, let from = s.contribStart, let to = s.contribEnd, !s.contribs.isEmpty else {
        print("no contributions data")
        exit(1)
    }
    let args = CommandLine.arguments
    var hover: Date?
    if let i = args.firstIndex(of: "hover"), args.count > i + 1 { hover = parseDay(args[i + 1]) }
    let mode: ContribMode = args.contains("cost") ? .cost
        : args.contains("clients") ? .clients : .models
    guard let png = ContribPopover.shared.snapshot(days: s.contribs, start: from, end: to,
                                                   dark: args.contains("dark"), hover: hover,
                                                   mode: mode)
    else {
        print("render failed")
        exit(1)
    }
    try? png.write(to: URL(fileURLWithPath: path))
    let active = s.contribs.filter { $0.tokens > 0 }.count
    print("wrote \(path) (\(s.contribs.count) days, \(active) active)")
    exit(0)
}

if CommandLine.arguments.contains("--dump") { runDump() }
if CommandLine.arguments.contains("--check-updates") { runUpdateCheck() }

/// Runs the same submit the menu item runs, through the same wrapper, so a
/// failure can be reproduced from a terminal. Add `--dry-run` to send nothing.
if CommandLine.arguments.contains("--submit") {
    let dry = CommandLine.arguments.contains("--dry-run")
    let args = ["--no-spinner", "submit"] + (dry ? ["--dry-run"] : [])
    print("running: tokens " + args.joined(separator: " "))
    guard let r = CLI.run(args, timeout: 300) else {
        print("tokens CLI not found in \(CLI.candidates.joined(separator: ", "))")
        exit(1)
    }
    print("exit: \(r.status)")
    if let line = CLI.firstLine(r.out) { print("stdout: \(line)") }
    if let line = CLI.firstLine(r.err) { print("stderr: \(line)") }
    exit(r.status == 0 ? 0 : 1)
}
if let i = CommandLine.arguments.firstIndex(of: "--chart-png"),
   CommandLine.arguments.count > i + 1 {
    runChartPNG(path: CommandLine.arguments[i + 1])
}
if let i = CommandLine.arguments.firstIndex(of: "--contrib-png"),
   CommandLine.arguments.count > i + 1 {
    runContribPNG(path: CommandLine.arguments[i + 1])
}
if let i = CommandLine.arguments.firstIndex(of: "--panel-png"),
   CommandLine.arguments.count > i + 1 {
    runPanelPNG(path: CommandLine.arguments[i + 1])
}
if let i = CommandLine.arguments.firstIndex(of: "--panel-probe") {
    runPanelProbe(path: CommandLine.arguments.count > i + 1 ? CommandLine.arguments[i + 1] : nil)
}
if CommandLine.arguments.contains("--menu-dump") { runMenuDump() }

// `--set-login on|off` toggles the LaunchAgent without opening the menu.
if let i = CommandLine.arguments.firstIndex(of: "--set-login") {
    let want = CommandLine.arguments.count > i + 1 ? CommandLine.arguments[i + 1] : "on"
    LoginItem.set(want != "off")
    print("login item: \(LoginItem.isEnabled ? "enabled" : "disabled") (\(LoginItem.plistPath))")
    exit(0)
}

// A LaunchAgent copy and a hand-launched copy are two separate launches as far
// as Launch Services is concerned, so macOS runs both and you end up with two
// icons in the menu bar polling the same API. Count our own bundle id and bow
// out if an older instance is already up. Running the bare binary out of the
// build directory has no bundle id, so this never gets in the way of a rebuild.
if let bundleID = Bundle.main.bundleIdentifier {
    let me = NSRunningApplication.current
    let started = me.launchDate ?? Date()
    let older = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        .first { $0.processIdentifier != me.processIdentifier
                 && ($0.launchDate ?? .distantPast) <= started }
    if let older {
        let msg = "TokensBar is already running (pid \(older.processIdentifier)); exiting.\n"
        FileHandle.standardError.write(Data(msg.utf8))
        exit(0)
    }
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

