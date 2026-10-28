import Foundation

struct UsageDayInput {
    var key: String
    var tokens: Int
    var models: [String: Int]
}
struct UsageComparison {
    let mean: Double
    let changePercent: Double?
    let topModel: String?
    let topModelDelta: Double?
}
// No gap filling here: an absent day is not evidence of zero submitted usage.
func usageComparison(today: UsageDayInput?, previous: [UsageDayInput], expectedKeys: [String]) -> UsageComparison? {
    guard let today, today.tokens >= 0, expectedKeys.count == 7,
          Set(expectedKeys).count == 7 else { return nil }
    let unique = Dictionary(previous.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
    let days = expectedKeys.compactMap { unique[$0] }
    guard days.count == 7, days.allSatisfy({ $0.tokens >= 0 }) else { return nil }
    let mean = days.reduce(0.0) { $0 + Double($1.tokens) } / 7
    let change = mean > 0 ? (Double(today.tokens) / mean - 1) * 100 : nil
    let completeModels = ([today] + days).allSatisfy { day in
        day.models.values.allSatisfy { $0 >= 0 } && day.models.values.reduce(0.0) { $0 + Double($1) } == Double(day.tokens)
    }
    var model: String?, delta: Double?
    if completeModels {
        let names = Set(([today] + days).flatMap { $0.models.keys })
        let changes = names.map { name in (name, Double(today.models[name, default: 0]) - days.reduce(0.0) { $0 + Double($1.models[name, default: 0]) } / 7) }
        if let biggest = changes.filter({ $0.1 != 0 }).sorted(by: { abs($0.1) == abs($1.1) ? $0.0 < $1.0 : abs($0.1) > abs($1.1) }).first { model = biggest.0; delta = biggest.1 }
    }
    return UsageComparison(mean: mean, changePercent: change, topModel: model, topModelDelta: delta)
}
func validMenuItems(_ items: [String]) -> [String] {
    var seen = Set<String>()
    return items.filter { ["tokens", "cost", "rank"].contains($0) && seen.insert($0).inserted }
}
struct CostAlertRule {
    var daily: Double
    var monthly: Double
    var interval: TimeInterval // 0 disables notifications; colour is independent.
    func eligible(value: Double?, threshold: Double, observed: Date?, now: Date, previous: Date?) -> Bool {
        guard interval > 0, threshold.isFinite, threshold > 0, let value, value.isFinite, value >= threshold,
              let observed, now.timeIntervalSince(observed) >= -60, now.timeIntervalSince(observed) <= 900 else { return false }
        return previous.map { now.timeIntervalSince($0) >= interval } ?? true
    }
}
