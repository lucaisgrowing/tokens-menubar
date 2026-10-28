import Foundation
import CoreFoundation

struct AgentRateWindow: Equatable {
    let label: String
    let usedPercent: Double
    let resetsAt: Date?
    var remainingPercent: Double { max(0, 100 - usedPercent) }
}
struct AgentAutomaticSnapshot {
    var windows: [AgentRateWindow] = []
    var lifetimeTokens: Double?
    var sessionEstimatedUSD: Double?
    var observedAt = Date()
    var usageError: String?
}
enum AgentAutomaticError: Error { case malformed, tooLarge, timeout, unavailable }
func agentFinite(_ value: Any?) -> Double? {
    guard let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(),
          n.doubleValue.isFinite, n.doubleValue >= 0 else { return nil }
    return n.doubleValue
}
func codexRateWindows(_ result: [String: Any]) throws -> [AgentRateWindow] {
    var pools: [(String, [String: Any])] = []
    if let map = result["rateLimitsByLimitId"] as? [String: [String: Any]], !map.isEmpty {
        pools = map.keys.sorted().map { ($0, map[$0]!) }
    } else if let rate = result["rateLimits"] as? [String: Any] { pools = [(rate["limitName"] as? String ?? "Codex", rate)] }
    else { throw AgentAutomaticError.malformed }
    var windows: [AgentRateWindow] = []
    for (pool, rate) in pools {
        for name in ["primary", "secondary"] {
            guard let window = rate[name] as? [String: Any] else { continue }
            guard let used = agentFinite(window["usedPercent"]) else { throw AgentAutomaticError.malformed }
            let minutes = agentFinite(window["windowDurationMins"])
            let duration = minutes.map { $0 >= 1440 ? String(format: "%.0fd", $0 / 1440) : String(format: "%.0fh", $0 / 60) } ?? name
            windows.append(AgentRateWindow(label: pool + " · " + duration, usedPercent: used,
                resetsAt: agentFinite(window["resetsAt"]).map { Date(timeIntervalSince1970: $0) }))
        }
    }
    return windows
}
struct ClaudeStatusBridge {
    static var directory: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/TokensBar") }
    static var file: URL { directory.appendingPathComponent("claude-status.json") }
    // Only aggregates survive. Prompts, paths, session IDs, accounts and tokens never enter this file.
    static func sanitized(_ input: Data, now: Date = Date()) throws -> Data {
        guard input.count <= 1_048_576,
              let root = try JSONSerialization.jsonObject(with: input) as? [String: Any] else { throw AgentAutomaticError.malformed }
        let rates = root["rate_limits"] as? [String: Any] ?? [:]
        var out: [String: Any] = ["observedAt": now.timeIntervalSince1970]
        var safe: [String: Any] = [:]
        for key in ["five_hour", "seven_day"] {
            guard let window = rates[key] as? [String: Any], let used = agentFinite(window["used_percentage"]) else { continue }
            var values: [String: Any] = ["used_percentage": used]
            if let reset = agentFinite(window["resets_at"]) { values["resets_at"] = reset }
            safe[key] = values
        }
        out["rate_limits"] = safe
        if let cost = root["cost"] as? [String: Any], let value = agentFinite(cost["total_cost_usd"]) { out["sessionEstimatedUSD"] = value }
        return try JSONSerialization.data(withJSONObject: out, options: [.sortedKeys])
    }
    static func parse(_ data: Data, now: Date = Date()) throws -> AgentAutomaticSnapshot {
        guard data.count <= 16384, let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let observed = agentFinite(root["observedAt"]) else { throw AgentAutomaticError.malformed }
        var snapshot = AgentAutomaticSnapshot(); snapshot.observedAt = Date(timeIntervalSince1970: observed)
        let rates = root["rate_limits"] as? [String: [String: Any]] ?? [:]
        for key in ["five_hour", "seven_day"] {
            guard let window = rates[key], let used = agentFinite(window["used_percentage"]) else { continue }
            let reset = agentFinite(window["resets_at"]).map { Date(timeIntervalSince1970: $0) }
            // Past windows disappear; absence never means a new unused quota.
            if let reset, reset <= now { continue }
            snapshot.windows.append(AgentRateWindow(label: key == "five_hour" ? "5h" : "7d", usedPercent: used, resetsAt: reset))
        }
        snapshot.sessionEstimatedUSD = agentFinite(root["sessionEstimatedUSD"])
        return snapshot
    }
    static func receive() {
        do {
            let input = try FileHandle.standardInput.read(upToCount: 1_048_577) ?? Data()
            let safe = try sanitized(input)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try safe.write(to: file, options: [.atomic])
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
            let snapshot = try parse(safe)
            let parts = snapshot.windows.map { "\($0.label) \(Int($0.usedPercent))%" }
            print(parts.isEmpty ? "TokensBar" : "TokensBar · " + parts.joined(separator: " · "))
        } catch { print("TokensBar · usage unavailable") }
    }
}

// MSP 1.4 usage/read, stable read-only cached observation. Not usage/refresh (experimental key mint).
func museCodeSnapshot(_ result: [String: Any]) throws -> AgentAutomaticSnapshot {
    guard let usage = result["usage"] as? [String: Any], let observed = agentFinite(usage["observedAtMs"]) else { throw AgentAutomaticError.unavailable }
    var snapshot = AgentAutomaticSnapshot(); snapshot.observedAt = Date(timeIntervalSince1970: observed / 1000)
    for key in ["window", "weekly"] {
        guard let row = usage[key] as? [String: Any], let used = agentFinite(row["usedPercent"]), let reset = agentFinite(row["resetsAtMs"]) else { throw AgentAutomaticError.malformed }
        let label = key == "weekly" ? "7d" : agentFinite(row["windowDurationMins"]).map { String(format: "%.1fh", $0 / 60) } ?? "window"
        snapshot.windows.append(AgentRateWindow(label: label, usedPercent: used, resetsAt: Date(timeIntervalSince1970: reset / 1000)))
    }
    return snapshot
}
