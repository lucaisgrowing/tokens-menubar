import Foundation

// Provider catalog is research, not proof of an account connection. Unknowns stay nil.
struct AgentProvider: Codable, Equatable {
    let id: String
    let name: String
    let category: String // personal, coding, api, custom
    let unit: String
    let documentation: String
    let noteEN: String
    let noteZH: String
    let upstreamClient: Bool
    var note: String { L10n.current == .zh ? noteZH : noteEN }
}

enum AgentOrigin: String, Codable { case manual, imported, tokensCI }

struct AgentUsageRecord: Codable, Equatable, Identifiable {
    var id: String = UUID().uuidString
    var providerID: String
    var account: String = ""
    var metric: String = ""
    var unit: String = "credits"
    var used: Double?
    var allowance: Double?
    // Some dashboards expose only remaining. Never infer it from tokens or price.
    var remainingReported: Double?
    var tokens: Double?
    var cost: Double?
    var currency: String = "USD"
    var periodStart: Date
    var periodEnd: Date
    var resetAt: Date?
    var observedAt: Date = Date()
    var sharedPool: String = ""
    var origin: AgentOrigin = .manual
    var note: String = ""

    var remaining: Double? {
        if let value = remainingReported { return value }
        guard let allowance, let used else { return nil }
        return max(0, allowance - used)
    }
    var overage: Double? {
        guard let allowance, let used else { return nil }
        return max(0, used - allowance)
    }
    func isStale(at now: Date) -> Bool {
        // No fake reset: expired records remain visible, with old values labelled.
        now >= periodEnd || resetAt.map { now >= $0 } == true
            || now.timeIntervalSince(observedAt) > 86400
    }
    func validate(allowAutomatic: Bool = false) throws {
        guard !id.isEmpty, id.count <= 200, !providerID.isEmpty, providerID.count <= 200,
              !unit.trimmingCharacters(in: .whitespaces).isEmpty, unit.count <= 80,
              account.count <= 160, metric.count <= 160, note.count <= 1000,
              sharedPool.count <= 160 else { throw AgentUsageError.invalidText }
        guard periodStart < periodEnd, observedAt.timeIntervalSince1970.isFinite,
              periodStart.timeIntervalSince1970.isFinite, periodEnd.timeIntervalSince1970.isFinite,
              resetAt?.timeIntervalSince1970.isFinite != false else { throw AgentUsageError.invalidPeriod }
        let values = [used, allowance, remainingReported, tokens, cost].compactMap { $0 }
        guard !values.isEmpty else { throw AgentUsageError.noValue }
        guard values.allSatisfy({ $0.isFinite && $0 >= 0 }) else { throw AgentUsageError.invalidNumber }
        if let tokens, tokens.rounded() != tokens { throw AgentUsageError.invalidTokens }
        if let cost { // Currency is never silently converted or defaulted on import.
            guard cost >= 0, currency.count == 3,
                  currency.unicodeScalars.allSatisfy({ (65...90).contains($0.value) }) else {
                throw AgentUsageError.invalidCurrency
            }
        }
        if let allowance, let remainingReported, remainingReported > allowance {
            throw AgentUsageError.inconsistentAllowance
        }
        if let used, let allowance, let remainingReported,
           abs(max(0, allowance - used) - remainingReported) > max(0.000001, allowance * 0.000001) {
            throw AgentUsageError.inconsistentAllowance
        }
        guard allowAutomatic || origin != .tokensCI else { throw AgentUsageError.automaticImport }
    }
}

enum AgentUsageError: Error, LocalizedError {
    case invalidText, invalidNumber, invalidTokens, invalidCurrency, invalidPeriod, noValue
    case inconsistentAllowance, automaticImport, unsupportedVersion, duplicateID, tooLarge
    var errorDescription: String? {
        let zh = L10n.current == .zh
        switch self {
        case .invalidText: return zh ? "名称、单位或备注无效或过长。" : "A name, unit or note is empty or too long."
        case .invalidNumber: return zh ? "数值必须是非负有限数；空白表示未知。" : "Use finite, non-negative numbers; leave unknown values blank."
        case .invalidTokens: return zh ? "Token 数必须是整数。" : "Token counts must be whole numbers."
        case .invalidCurrency: return zh ? "费用需要三位大写货币代码，例如 USD。" : "Cost needs a three-letter uppercase currency, such as USD."
        case .invalidPeriod: return zh ? "统计结束时间必须晚于开始时间；重置时间需为有效时间。" : "The period end must follow its start; use a valid reset time."
        case .noValue: return zh ? "至少填写一项用量、额度、剩余量、token 或费用。" : "Enter at least one usage, allowance, remaining, token or cost value."
        case .inconsistentAllowance: return zh ? "额度、用量和剩余量不一致，请核对同一口径。" : "Allowance, usage and remaining disagree. Check that they describe the same pool."
        case .automaticImport: return zh ? "不能导入冒充自动同步的记录。" : "Imported records cannot claim to be an automatic connection."
        case .unsupportedVersion: return zh ? "不支持此文件版本。" : "Unsupported file version."
        case .duplicateID: return zh ? "文件包含重复记录 ID，未导入任何记录。" : "Duplicate record IDs; nothing was imported."
        case .tooLarge: return zh ? "文件过大或记录超过 5000 条。" : "The file is too large or contains more than 5,000 records."
        }
    }
}

struct AgentUsageFile: Codable {
    var version = 1
    var records: [AgentUsageRecord]
}

final class AgentUsageStore {
    let url: URL
    private(set) var records: [AgentUsageRecord] = []
    private(set) var loadError: Error?
    init(url: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/tokens-menubar/agent-usage.json")) {
        self.url = url
        if FileManager.default.fileExists(atPath: url.path) {
            do { records = try Self.decode(Data(contentsOf: url), importing: false) }
            catch { loadError = error } // Preserve malformed original; never silently overwrite it.
        }
    }
    static func decoder() -> JSONDecoder { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }
    static func encoder() -> JSONEncoder {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]; return e
    }
    static func decode(_ data: Data, importing: Bool) throws -> [AgentUsageRecord] {
        guard data.count <= 5_000_000 else { throw AgentUsageError.tooLarge }
        let file = try decoder().decode(AgentUsageFile.self, from: data)
        guard file.version == 1 else { throw AgentUsageError.unsupportedVersion }
        guard file.records.count <= 5000 else { throw AgentUsageError.tooLarge }
        guard Set(file.records.map { $0.id }).count == file.records.count else { throw AgentUsageError.duplicateID }
        return try file.records.map { input in
            try input.validate()
            var record = input
            if importing { record.origin = .imported }
            return record
        }
    }
    private func persist(_ next: [AgentUsageRecord]) throws {
        if let loadError { throw loadError }
        guard next.count <= 5000 else { throw AgentUsageError.tooLarge }
        let fm = FileManager.default
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                               attributes: [.posixPermissions: 0o700])
        let data = try Self.encoder().encode(AgentUsageFile(records: next))
        try data.write(to: url, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        records = next
    }
    func save(_ record: AgentUsageRecord) throws {
        try record.validate()
        var next = records
        if let i = next.firstIndex(where: { $0.id == record.id }) { next[i] = record }
        else { next.append(record) }
        try persist(next)
    }
    func remove(id: String) throws { try persist(records.filter { $0.id != id }) }
    func importData(_ data: Data) throws {
        let incoming = try Self.decode(data, importing: true)
        var next = records
        // Stable IDs update the same snapshot, never double-count repeated imports.
        for record in incoming {
            if let i = next.firstIndex(where: { $0.id == record.id }) { next[i] = record }
            else { next.append(record) }
        }
        try persist(next)
    }
    func exportData() throws -> Data { try Self.encoder().encode(AgentUsageFile(records: records)) }
}

// This view never sums manual, API, local or all-device data across providers.
// Shared-pool identifiers are visible labels, not permission to combine metrics.
func agentNumber(_ value: Double?) -> String {
    guard let value else { return "—" }
    let formatter = NumberFormatter(); formatter.numberStyle = .decimal
    formatter.maximumFractionDigits = 4
    return formatter.string(from: NSNumber(value: value)) ?? "—"
}
