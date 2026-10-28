import Foundation

@main struct AutomaticTests {
    static func main() throws {
        var n = 0
        func check(_ ok: @autoclosure () -> Bool, _ detail: String) { precondition(ok(), detail); n += 1 }
        let rate: [String: Any] = ["rateLimits": ["primary": ["usedPercent": 33.5, "windowDurationMins": 300, "resetsAt": 2000000000], "secondary": ["usedPercent": 110, "windowDurationMins": 10080]]]
        let windows = try codexRateWindows(rate)
        check(windows.count == 2, "two codex windows"); check(windows[0].remainingPercent == 66.5, "percentage remains fractional"); check(windows[1].remainingPercent == 0, "over-quota remains zero remaining"); check(windows[1].usedPercent == 110, "used over 100 not hidden")
        check(agentFinite(true) == nil, "boolean invalid"); check(agentFinite(-1) == nil, "negative invalid"); check(agentFinite(Double.infinity) == nil, "infinite invalid")
        do { _ = try codexRateWindows([:]); fatalError("missing must fail") } catch { n += 1 }
        let now = Date(timeIntervalSince1970: 1900000000)
        let input = Data("{\"rate_limits\":{\"five_hour\":{\"used_percentage\":25,\"resets_at\":2000000000},\"seven_day\":{\"used_percentage\":40,\"resets_at\":1800000000}},\"cost\":{\"total_cost_usd\":0.75},\"session_id\":\"private\",\"workspace\":{\"current_dir\":\"private\"}}".utf8)
        let safe = try ClaudeStatusBridge.sanitized(input, now: now)
        check(!String(decoding: safe, as: UTF8.self).contains("private"), "private content discarded")
        let snapshot = try ClaudeStatusBridge.parse(safe, now: now)
        check(snapshot.windows.count == 1, "expired window removed"); check(snapshot.sessionEstimatedUSD == 0.75, "session estimate separate"); check(snapshot.observedAt == now, "arrival timestamp")
        let unknown = try ClaudeStatusBridge.parse(ClaudeStatusBridge.sanitized(Data("{}".utf8), now: now), now: now)
        check(unknown.windows.isEmpty, "no percentage fabricated"); check(unknown.sessionEstimatedUSD == nil, "unknown not zero")
        let muse = try museCodeSnapshot(["usage": ["observedAtMs": 1900000000000, "window": ["usedPercent": 22, "windowDurationMins": 300, "resetsAtMs": 2000000000000], "weekly": ["usedPercent": 120, "resetsAtMs": 2000000000000]]])
        check(muse.observedAt == now, "Muse milliseconds preserved"); check(muse.windows[0].remainingPercent == 78, "Muse remainder"); check(muse.windows[1].remainingPercent == 0, "Muse over quota"); check(muse.windows[0].resetsAt == Date(timeIntervalSince1970: 2000000000), "Muse reset milliseconds")
        do { _ = try museCodeSnapshot([:]); fatalError("empty host unknown") } catch { n += 1 }
        let keys = (1...7).map(String.init)
        let previous = keys.map { UsageDayInput(key: $0, tokens: 100, models: ["a": 80, "b": 20]) }
        let today = UsageDayInput(key: "today", tokens: 150, models: ["a": 70, "b": 80])
        let comparison = usageComparison(today: today, previous: previous, expectedKeys: keys)
        check(comparison?.mean == 100, "seven day baseline"); check(comparison?.changePercent == 50, "difference not percentage of baseline"); check(comparison?.topModel == "b", "largest actual model delta"); check(comparison?.topModelDelta == 60, "absolute token contribution")
        check(usageComparison(today: today, previous: Array(previous.dropLast()), expectedKeys: keys) == nil, "missing day unknown not zero")
        check(usageComparison(today: nil, previous: previous, expectedKeys: keys) == nil, "no local mixing")
        var partial = previous; partial[0].models = [:]
        check(usageComparison(today: today, previous: partial, expectedKeys: keys)?.topModel == nil, "incomplete model data not attributed")
        let zero = keys.map { UsageDayInput(key: $0, tokens: 0, models: [:]) }
        check(usageComparison(today: today, previous: zero, expectedKeys: keys)?.changePercent == nil, "no divide by zero")
        check(validMenuItems(["rank", "bad", "cost", "rank", "tokens"]) == ["rank", "cost", "tokens"], "display preserves order removes invalid/duplicates")
        let rule = CostAlertRule(daily: 5, monthly: 50, interval: 3600)
        check(rule.eligible(value: 5, threshold: 5, observed: now, now: now, previous: nil), "threshold inclusive")
        check(!rule.eligible(value: nil, threshold: 5, observed: now, now: now, previous: nil), "unknown no alert")
        check(!rule.eligible(value: 9, threshold: 5, observed: nil, now: now, previous: nil), "failure no alert")
        check(!rule.eligible(value: 9, threshold: 5, observed: now.addingTimeInterval(-901), now: now, previous: nil), "stale no alert")
        check(!rule.eligible(value: 9, threshold: 5, observed: now, now: now, previous: now.addingTimeInterval(-3599)), "throttle")
        check(rule.eligible(value: 9, threshold: 5, observed: now, now: now, previous: now.addingTimeInterval(-3600)), "interval exact")
        check(!CostAlertRule(daily: 5, monthly: 50, interval: 0).eligible(value: 9, threshold: 5, observed: now, now: now, previous: nil), "off")
        print("PASS: \(n) automation, insight and preference checks")
    }
}
