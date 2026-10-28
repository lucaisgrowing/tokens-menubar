import Foundation

@main struct AgentUsageTests {
    static var count = 0
    static func check(_ condition: @autoclosure () -> Bool, _ title: String) {
        count += 1; if !condition() { fatalError("FAIL: \(title)") }
    }
    static func rejects(_ title: String, _ body: () throws -> Void) {
        count += 1
        do { try body(); fatalError("FAIL: expected rejection: \(title)") } catch {}
    }
    static func main() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let end = start.addingTimeInterval(604800)
        var r = AgentUsageRecord(providerID: "muse", periodStart: start, periodEnd: end)
        r.used = 20; r.allowance = 100; r.unit = "Muse tokens"; r.observedAt = start
        try r.validate(); check(r.remaining == 80, "same unit remaining")
        check(r.overage == 0, "no overage")
        check(!r.isStale(at: start), "fresh snapshot")
        check(r.isStale(at: start.addingTimeInterval(86401)), "stale after day")
        check(r.isStale(at: end), "expired period")
        r.resetAt = start.addingTimeInterval(3600)
        check(r.isStale(at: start.addingTimeInterval(3600)), "reset marks stale without clearing values")
        check(r.used == 20, "reset never fabricates zero")
        r.resetAt = nil; r.used = 120
        try r.validate(); check(r.remaining == 0, "overage clamps remaining")
        check(r.overage == 20, "overage retains consumption")
        r.used = nil; r.allowance = nil; r.remainingReported = 33
        try r.validate(); check(r.remaining == 33, "remaining-only snapshot")
        check(r.overage == nil, "unknown allowance remains unknown")
        r.remainingReported = nil
        rejects("empty snapshot") { try r.validate() }
        r.used = -1; rejects("negative") { try r.validate() }
        r.used = .nan; rejects("NaN") { try r.validate() }
        r.used = .infinity; rejects("infinite") { try r.validate() }
        r.used = 0; try r.validate()
        check(r.remaining == nil, "zero use never implies allowance")
        r.tokens = 1.5; rejects("fractional tokens") { try r.validate() }
        r.tokens = 12; try r.validate()
        r.cost = 0; r.currency = "usd"; rejects("currency format") { try r.validate() }
        r.currency = "USD"; try r.validate()
        r.periodEnd = start; rejects("zero period") { try r.validate() }; r.periodEnd = end
        r.allowance = 100; r.remainingReported = 101
        rejects("remaining exceeds allowance") { try r.validate() }
        r.remainingReported = 50
        rejects("inconsistent metric") { try r.validate() }
        r.remainingReported = 100; try r.validate()
        r.origin = .tokensCI; rejects("false automatic provenance") { try r.validate() }
        r.origin = .manual; r.id = "stable-test-snapshot"
        let encoded = try AgentUsageStore.encoder().encode(AgentUsageFile(records: [r]))
        let decoded = try AgentUsageStore.decode(encoded, importing: false)
        check(decoded == [r], "lossless ISO8601 round trip")
        let imported = try AgentUsageStore.decode(encoded, importing: true)
        check(imported[0].origin == .imported, "import forced provenance")
        rejects("duplicate IDs") { _ = try AgentUsageStore.decode(AgentUsageStore.encoder().encode(AgentUsageFile(records: [r,r])), importing: true) }
        var unsupported = AgentUsageFile(records: [r]); unsupported.version = 99
        rejects("unknown schema version") { _ = try AgentUsageStore.decode(AgentUsageStore.encoder().encode(unsupported), importing: true) }
        rejects("oversized JSON") { _ = try AgentUsageStore.decode(Data(repeating: 0, count: 5_000_001), importing: true) }
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temp) }
        let url = temp.appendingPathComponent("records.json")
        let store = AgentUsageStore(url: url)
        try store.save(r); check(store.records.count == 1, "save")
        try store.importData(encoded); try store.importData(encoded)
        check(store.records.count == 1, "reimport updates rather than duplicates")
        check(store.records[0].origin == .imported, "store import provenance")
        let permissions = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
        check(permissions?.intValue == 0o600, "private file permissions")
        let reloaded = AgentUsageStore(url: url)
        check(reloaded.records == store.records && reloaded.loadError == nil, "reload")
        let before = try Data(contentsOf: url)
        var bad = r; bad.origin = .tokensCI
        rejects("import cannot inject automated data") { try store.importData(AgentUsageStore.encoder().encode(AgentUsageFile(records: [bad]))) }
        let afterFailedImport = try Data(contentsOf: url)
        check(afterFailedImport == before, "failed import atomicity")
        try store.remove(id: r.id); check(store.records.isEmpty, "delete")
        let corrupt = Data("invalid-json".utf8); try corrupt.write(to: url)
        let broken = AgentUsageStore(url: url)
        check(broken.loadError != nil, "corruption detected")
        rejects("corrupt store never overwritten") { try broken.save(r) }
        let preservedOriginal = try Data(contentsOf: url)
        check(preservedOriginal == corrupt, "preserves corrupt original")
        let validAPI = Data("""
        {"data":{"usage":12.25,"usage_daily":1.25,"usage_weekly":3.5,"usage_monthly":12.25,"limit":20,"limit_remaining":7.75,"limit_reset":"monthly","include_byok_in_limit":true}}
        """.utf8)
        let api = try OpenRouterKeyUsage.parse(validAPI, observedAt: start)
        check(api.lifetimeUSD == 12.25 && api.keyRemainingUSD == 7.75, "OpenRouter documented values")
        check(api.dailyUSD == 1.25 && api.includeBYOK == true && api.observedAt == start, "OpenRouter metadata")
        let unlimited = try OpenRouterKeyUsage.parse(Data("{\"data\":{\"usage\":0,\"limit\":null,\"limit_remaining\":null}}".utf8))
        check(unlimited.keyLimitUSD == nil && unlimited.keyRemainingUSD == nil, "null cap never becomes zero")
        let negativeRemaining = try OpenRouterKeyUsage.parse(Data("{\"data\":{\"usage\":1,\"limit_remaining\":-1}}".utf8))
        check(negativeRemaining.keyRemainingUSD == -1, "negative key remaining retained")
        rejects("API bool as amount") { _ = try OpenRouterKeyUsage.parse(Data("{\"data\":{\"usage\":true}}".utf8)) }
        rejects("API negative spend") { _ = try OpenRouterKeyUsage.parse(Data("{\"data\":{\"usage\":-1}}".utf8)) }
        rejects("API missing lifetime usage") { _ = try OpenRouterKeyUsage.parse(Data("{\"data\":{\"limit\":2}}".utf8)) }
        let days = [AgentClientDay(date: start, client: "A", tokens: 3, estimatedUSD: 0.1),
                    AgentClientDay(date: start.addingTimeInterval(86400), client: "A", tokens: 7, estimatedUSD: 0.2),
                    AgentClientDay(date: start, client: "B", tokens: 20, estimatedUSD: 0.5),
                    AgentClientDay(date: end, client: "A", tokens: 999, estimatedUSD: 1),
                    AgentClientDay(date: start, client: "bad", tokens: -1, estimatedUSD: 0),
                    AgentClientDay(date: start, client: "bad", tokens: 1, estimatedUSD: .nan)]
        let totals = agentSubmittedTotals(days, start: start, end: end)
        check(totals.count == 2 && totals[0].client == "B", "client sort and malformed-day exclusion")
        check(totals[1].tokens == 10 && totals[1].days == 2, "client days and exclusive end")
        check(abs(totals[1].estimatedUSD - 0.3) < 0.00001, "estimated cost stays source USD")
        let overflow = agentSubmittedTotals([AgentClientDay(date: start, client: "A", tokens: .max, estimatedUSD: 0), AgentClientDay(date: start, client: "A", tokens: 1, estimatedUSD: 0)], start: start, end: end)
        check(overflow[0].tokens == .max, "integer overflow guarded")
        check(Set(AgentCatalog.all.map(\.id)).count == AgentCatalog.all.count, "unique catalog IDs")
        check(AgentCatalog.all.count >= 50, "broad representative catalog")
        for id in ["muse", "grok-bot", "cue", "wabi", "openrouter"] {
            check(AgentCatalog.all.contains { $0.id == id }, "requested provider \(id)")
        }
        check(AgentCatalog.all.allSatisfy { $0.documentation.hasPrefix("https://") && !$0.noteEN.isEmpty && !$0.noteZH.isEmpty }, "every provider has source and caveat")
        print("PASS: \(count) agent usage regression checks; \(AgentCatalog.all.count) catalog entries")
    }
}
