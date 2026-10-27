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
