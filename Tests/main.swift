import Foundation

var checks = 0
func expect(_ condition: @autoclosure () -> Bool, _ label: String) {
    checks += 1
    if !condition() { fatalError("FAIL: \(label)") }
}
let fixture = try String(contentsOfFile: "Tests/fixtures/dry-run.txt", encoding: .utf8)
let parsed = CLIReportParser.parse(fixture)
expect(parsed?.tokens == 6_941_007, "grouped token total")
expect(parsed?.cost == 6.55, "cost total")
expect(CLIReportParser.parse("Total tokens: 0\nTotal cost: $0.00")?.tokens == 0, "valid zero")
expect(CLIReportParser.parse("\u{001B}[32mTotal tokens: 1,234\u{001B}[0m\r\nTotal cost: $1,234.56")?.cost == 1234.56, "ANSI/CRLF/grouped cost")
for invalid in ["", "Total tokens: 4", "Total cost: $1", "Total tokens: -5\nTotal cost: $1", "Total tokens: x\nTotal cost: $1", "Total tokens: 4\nTotal cost: $nan", "Total tokens: 4\nTotal cost: $inf", "Total tokens: 4\nTotal cost: $-1", "Total tokens: 4\nTotal cost: 1"] {
    expect(CLIReportParser.parse(invalid) == nil, "reject incomplete/invalid report")
}
expect(fmtShare(0, total: 100) == "0%", "zero share")
expect(fmtShare(1, total: 1000) == "<1%", "tiny share")
expect(fmtShare(10, total: 1000) == "1%", "one percent")
expect(fmtShare(1000, total: 1000) == "100%", "whole share")
expect(apiPollingInterval(30) == 60, "API floor")
expect(apiPollingInterval(60) == 60, "60s allowed")
expect(apiPollingInterval(300) == 300, "default retained")
expect(apiPollingInterval(.nan) == 300, "non-finite rejected")
expect(readTokenAccount(apiBase: "https://tokens.ci", username: "a") == "https://tokens.ci:443|a", "token origin")
expect(readTokenAccount(apiBase: "http://tokens.ci", username: "a") == nil, "no token over HTTP")
expect(readTokenAccount(apiBase: "https://tokens.ci?token=x", username: "a") == nil, "no credential query")
expect(readTokenAccount(apiBase: "https://tokens.ci", username: "") == nil, "no empty account")
expect(readTokenAccount(apiBase: "https://tokens.ci", username: "a") != readTokenAccount(apiBase: "https://other.example", username: "a"), "origins isolated")
expect(readTokenAccount(apiBase: "https://tokens.ci", username: "a") != readTokenAccount(apiBase: "https://tokens.ci", username: "b"), "users isolated")
expect(APIReadError.forStatus(200) == nil, "HTTP success")
expect(APIReadError.forStatus(404) == .notFound, "404 ambiguous account/private")
expect(APIReadError.forStatus(401) == .unauthorized, "401 credentials")
expect(APIReadError.forStatus(403) == .unauthorized, "403 credentials")
expect(APIReadError.forStatus(429) == .rateLimited, "429 rate limit")
expect(APIReadError.forStatus(503) == .http(503), "server status retained")
for language in Lang.allCases {
    L10n.current = language
    for error in [APIReadError.network, .notFound, .unauthorized, .rateLimited, .invalidResponse, .http(503)] {
        expect(!error.message.hasPrefix("api."), "localized API feedback")
    }
}
// Month labels near a clipped opening month, across year and leap-day boundaries.
var monthCal = Calendar(identifier: .gregorian)
monthCal.timeZone = TimeZone(secondsFromGMT: 0)!
let monthParser = DateFormatter()
monthParser.calendar = monthCal
monthParser.timeZone = monthCal.timeZone
monthParser.locale = Locale(identifier: "en_US_POSIX")
monthParser.dateFormat = "yyyy-MM-dd"
for (first, expected) in [("2025-10-27", [10, 11, 12, 1]),
                          ("2023-12-25", [12, 1, 2, 3]),
                          ("2024-02-26", [2, 3, 4, 5]),
                          ("2026-06-01", [6, 7, 8])] {
    let candidates = heatmapMonthCandidates(firstMonday: monthParser.date(from: first)!, columns: 14, calendar: monthCal)
    expect(candidates.map { monthCal.component(.month, from: $0.date) } == expected, "month boundaries \(first)")
    let positions = candidates.map { Double($0.column * 13) }
    for width in [18.0, 25.0, 36.0] {
        let widths = Array(repeating: width, count: positions.count)
        let visible = heatmapVisibleMonthIndices(positions: positions, widths: widths, rightEdge: 182)
        expect(zip(visible, visible.dropFirst()).allSatisfy { positions[$0] + widths[$0] + 4 <= positions[$1] }, "no collision \(first) width \(width)")
        expect(visible.allSatisfy { positions[$0] + widths[$0] <= 182 }, "no clipping \(first)")
    }
}
expect(heatmapVisibleMonthIndices(positions: [0, 13, 65], widths: [25, 25, 25], rightEdge: 100) == [1, 2], "favor next month over short opening month")
expect(heatmapVisibleMonthIndices(positions: [0], widths: [25], rightEdge: 24).isEmpty, "skip clipped final label")
expect(heatmapVisibleMonthIndices(positions: [0], widths: [], rightEdge: 100).isEmpty, "mismatched labels rejected")
print("PASS: \(checks) pure-Swift regression checks")
