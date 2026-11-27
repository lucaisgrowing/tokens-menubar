// Pure Foundation helpers shared by the app and the offline regression tests.
import Foundation

struct CLIReportParser {
    /// `submit --dry-run` is text, not JSON. Fail closed on missing/invalid totals;
    /// accepting an incomplete report as $0 would silently understate usage.
    static func parse(_ raw: String) -> (tokens: Int, cost: Double)? {
        let ansi = try! NSRegularExpression(pattern: "\\u001B\\[[0-?]*[ -/]*[@-~]")
        let text = ansi.stringByReplacingMatches(in: raw,
            range: NSRange(raw.startIndex..., in: raw), withTemplate: "")
        var tokens: Int?
        var cost: Double?
        for line in text.split(whereSeparator: \.isNewline)
            .map({ $0.trimmingCharacters(in: .whitespaces) }) {
            if line.hasPrefix("Total tokens:") {
                let value = line.dropFirst("Total tokens:".count)
                    .trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "")
                if !value.isEmpty && value.allSatisfy({ $0.isASCII && $0.isNumber }) {
                    tokens = Int(value)
                } else { return nil }
            } else if line.hasPrefix("Total cost:") {
                let value = line.dropFirst("Total cost:".count)
                    .trimmingCharacters(in: .whitespaces)
                guard value.hasPrefix("$") else { return nil }
                let amount = value.dropFirst().replacingOccurrences(of: ",", with: "")
                guard let parsed = Double(amount), parsed.isFinite, parsed >= 0 else { return nil }
                cost = parsed
            }
        }
        guard let tokens, let cost else { return nil }
        return (tokens, cost)
    }
}

func fmtShare(_ value: Int, total: Double) -> String {
    guard value > 0, total > 0 else { return "0%" }
    let percent = Double(value) / total * 100
    return percent < 1 ? "<1%" : String(format: "%.0f%%", min(100, percent))
}

func apiPollingInterval(_ value: TimeInterval) -> TimeInterval {
    value.isFinite ? max(60, value) : 300
}

/// Tokens are account- AND origin-scoped, and may only travel over HTTPS.
func readTokenAccount(apiBase: String, username: String) -> String? {
    guard !username.isEmpty, let url = URL(string: apiBase),
          url.scheme?.lowercased() == "https", let host = url.host?.lowercased(),
          url.user == nil, url.password == nil,
          url.query == nil, url.fragment == nil else { return nil }
    return "https://\(host):\(url.port ?? 443)|\(username)"
}

enum APIReadError: Error, Equatable {
    case invalidConfiguration, notFound, unauthorized, rateLimited, network, invalidResponse
    case http(Int)

    var message: String {
        switch self {
        case .invalidConfiguration: return t("api.configuration")
        case .notFound: return t("api.notFound")
        case .unauthorized: return t("api.unauthorized")
        case .rateLimited: return t("api.rateLimited")
        case .network: return t("api.network")
        case .invalidResponse: return t("api.invalidResponse")
        case .http(let status): return t("api.http", status)
        }
    }

    static func forStatus(_ status: Int) -> APIReadError? {
        switch status {
        case 200: return nil
        case 401, 403: return .unauthorized
        case 404: return .notFound
        case 429: return .rateLimited
        default: return .http(status)
        }
    }
}

/// Compares dot-separated numeric versions; missing components count as 0,
/// so 1.1 and 1.1.0 are equal and 1.10 beats 1.9.
func isNewerVersion(_ candidate: String, than current: String) -> Bool {
    func parts(_ s: String) -> [Int] {
        s.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
            .split(separator: ".")
            .map { Int($0.prefix(while: \.isNumber)) ?? 0 }
    }
    let a = parts(candidate), b = parts(current)
    for i in 0..<max(a.count, b.count) {
        let x = i < a.count ? a[i] : 0
        let y = i < b.count ? b[i] : 0
        if x != y { return x > y }
    }
    return false
}

/// 1-based leaderboard page containing `rank` for a given `pageSize`.
func leaderboardPage(forRank rank: Int, pageSize: Int = 100) -> Int {
    guard rank > 0, pageSize > 0 else { return 1 }
    return (rank - 1) / pageSize + 1
}

/// Finds a matching entry on a leaderboard page while preserving the neighbour
/// directly above it even when the entry sits at index 0 of page 2+ (e.g. #101).
func findLeaderboardEntry<T>(in items: [T], previousLast: T?,
                             where match: (T) -> Bool) -> (item: T, above: T?, below: T?)? {
    guard let i = items.firstIndex(where: match) else { return nil }
    let above = i > 0 ? items[i - 1] : previousLast
    let below = i + 1 < items.count ? items[i + 1] : nil
    return (items[i], above, below)
}

/// Computes current and longest UTC active-day streaks from `yyyy-MM-dd` keys.
/// If today has no submission yet, an active yesterday still keeps the current
/// streak alive so it does not drop to 0 right after 00:00 UTC.
func computeStreaks(activeDayKeys: Set<String>, todayKey: String) -> (current: Int, longest: Int) {
    guard !activeDayKeys.isEmpty else { return (0, 0) }
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
    let fmt = DateFormatter()
    fmt.calendar = cal
    fmt.timeZone = cal.timeZone
    fmt.locale = Locale(identifier: "en_US_POSIX")
    fmt.dateFormat = "yyyy-MM-dd"

    let dates = activeDayKeys.compactMap { fmt.date(from: $0) }.sorted()
    guard !dates.isEmpty else { return (0, 0) }

    var longest = 1
    var run = 1
    for i in 1..<dates.count {
        let prev = dates[i - 1]
        if let nextDay = cal.date(byAdding: .day, value: 1, to: prev),
           cal.isDate(nextDay, inSameDayAs: dates[i]) {
            run += 1
            if run > longest { longest = run }
        } else if !cal.isDate(prev, inSameDayAs: dates[i]) {
            run = 1
        }
    }

    var current = 0
    if let today = fmt.date(from: todayKey) {
        var cursor: Date?
        if activeDayKeys.contains(todayKey) {
            cursor = today
        } else if let yesterday = cal.date(byAdding: .day, value: -1, to: today),
                  activeDayKeys.contains(fmt.string(from: yesterday)) {
            cursor = yesterday
        }
        while let day = cursor, activeDayKeys.contains(fmt.string(from: day)) {
            current += 1
            cursor = cal.date(byAdding: .day, value: -1, to: day)
        }
    }
    return (current, longest)
}

/// Prompt cache hit ratio: cacheRead / (input + cacheRead + cacheWrite).
func cacheHitRate(input: Int, cacheRead: Int, cacheWrite: Int) -> Double? {
    let promptTotal = max(0, input) + max(0, cacheRead) + max(0, cacheWrite)
    guard promptTotal > 0, cacheRead > 0 else { return nil }
    return min(1.0, Double(cacheRead) / Double(promptTotal))
}

struct CLIVersionParser {
    /// Extracts semantic version from `tokens --version` output like `tokens 27.4.1`.
    static func parse(_ raw: String) -> String? {
        for line in raw.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            for token in trimmed.split(whereSeparator: \.isWhitespace) {
                let cleaned = token.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
                let parts = cleaned.split(separator: ".")
                if parts.count >= 2,
                   parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy({ $0.isASCII && $0.isNumber }) }) {
                    return cleaned
                }
            }
        }
        return nil
    }
}

struct CLIServiceStatusParser {
    /// Parses `tokens status` output to check whether `tokens serve` is running.
    static func isServeRunning(_ raw: String) -> Bool {
        let lower = raw.lowercased()
        return lower.contains("tokens serve running") || lower.contains("service: running")
    }
}

struct SHA256SumsParser {
    /// Parses a `SHA256SUMS.txt` file and returns the expected lowercase hex digest for `filename`.
    static func expectedHash(for filename: String, in text: String) -> String? {
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            let parts = line.split(maxSplits: 1, whereSeparator: \.isWhitespace)
            guard parts.count == 2 else { continue }
            let hash = String(parts[0]).lowercased()
            var name = String(parts[1]).trimmingCharacters(in: .whitespaces)
            if name.hasPrefix("*") { name.removeFirst() }
            if name.hasPrefix("./") { name.removeFirst(2) }
            guard name == filename, hash.count == 64,
                  hash.allSatisfy({ ("0"..."9").contains($0) || ("a"..."f").contains($0) })
            else { continue }
            return hash
        }
        return nil
    }
}
