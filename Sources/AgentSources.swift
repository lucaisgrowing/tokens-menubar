import Foundation
import CoreFoundation

struct OpenRouterKeyUsage: Equatable {
    let lifetimeUSD: Double
    let dailyUSD: Double?
    let weeklyUSD: Double?
    let monthlyUSD: Double?
    let keyLimitUSD: Double?
    let keyRemainingUSD: Double?
    let limitReset: String?
    let includeBYOK: Bool?
    let observedAt: Date
    // Key caps are not account balances. A null cap is unknown/unlimited, not zero.
    static func parse(_ data: Data, observedAt: Date = Date()) throws -> OpenRouterKeyUsage {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let object = root["data"] as? [String: Any] else { throw AgentUsageError.invalidNumber }
        func number(_ key: String, allowNegative: Bool = false) throws -> Double? {
            guard let value = object[key], !(value is NSNull) else { return nil }
            guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
                  number.doubleValue.isFinite, allowNegative || number.doubleValue >= 0 else {
                throw AgentUsageError.invalidNumber
            }
            return number.doubleValue
        }
        guard let lifetime = try number("usage") else { throw AgentUsageError.noValue }
        return try OpenRouterKeyUsage(lifetimeUSD: lifetime, dailyUSD: number("usage_daily"),
            weeklyUSD: number("usage_weekly"), monthlyUSD: number("usage_monthly"),
            keyLimitUSD: number("limit"), keyRemainingUSD: number("limit_remaining", allowNegative: true),
            limitReset: object["limit_reset"] as? String,
            includeBYOK: object["include_byok_in_limit"] as? Bool, observedAt: observedAt)
    }
}


struct AgentClientDay {
    let date: Date
    let client: String
    let tokens: Int
    let estimatedUSD: Double
}
struct AgentClientTotal {
    let client: String
    let tokens: Int
    let estimatedUSD: Double
    let days: Int
}
func agentSubmittedTotals(_ days: [AgentClientDay], start: Date, end: Date) -> [AgentClientTotal] {
    var grouped: [String: (tokens: Int, cost: Double, days: Set<Date>)] = [:]
    for day in days where day.date >= start && day.date < end {
        guard day.tokens >= 0, day.estimatedUSD.isFinite, day.estimatedUSD >= 0 else { continue }
        var entry = grouped[day.client] ?? (0, 0, [])
        let (total, overflow) = entry.tokens.addingReportingOverflow(day.tokens)
        guard !overflow, (entry.cost + day.estimatedUSD).isFinite else { continue }
        entry.tokens = total; entry.cost += day.estimatedUSD; entry.days.insert(day.date)
        grouped[day.client] = entry
    }
    return grouped.map { AgentClientTotal(client: $0.key, tokens: $0.value.tokens,
        estimatedUSD: $0.value.cost, days: $0.value.days.count) }
        .sorted { $0.tokens == $1.tokens ? $0.client < $1.client : $0.tokens > $1.tokens }
}
