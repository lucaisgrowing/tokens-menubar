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
print("PASS: \(checks) pure-Swift regression checks")
