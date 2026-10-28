import AppKit
import Security

// Only the documented per-key read endpoint is called. No model requests, web scraping,
// telemetry, credential export or tokens.ci upload. Keys are opt-in and local to Keychain.
final class AgentOpenRouter: NSObject, URLSessionTaskDelegate {
    private let service = "cc.luca.tokensbar.agent.openrouter"
    private let account = "usage-key"
    private var task: URLSessionDataTask?
    private var session: URLSession?
    private(set) var snapshot: OpenRouterKeyUsage?
    private(set) var lastError: String?
    private(set) var busy = false
    private var lastAttempt: Date?
    private var generation = 0
    var changed: (() -> Void)?
    private var query: [String: Any] { [kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service, kSecAttrAccount as String: account] }
    var connected: Bool { readKey() != nil }
    private func readKey() -> String? {
        var q = query; q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    func connect(key: String) throws {
        let clean = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.count >= 20, clean.count <= 1024,
              clean.unicodeScalars.allSatisfy({ $0.value >= 33 && $0.value <= 126 }) else {
            throw NSError(domain: "AgentOpenRouter", code: 1, userInfo: [NSLocalizedDescriptionKey:
                agentText("The key format is invalid.", "密钥格式无效。")])
        }
        var q = query
        q[kSecValueData as String] = Data(clean.utf8)
        q[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(q as CFDictionary, nil)
        let result = status == errSecDuplicateItem
            ? SecItemUpdate(query as CFDictionary, [kSecValueData as String: Data(clean.utf8)] as CFDictionary)
            : status
        guard result == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(result)) }
        generation += 1; task?.cancel(); task = nil
        session?.invalidateAndCancel(); session = nil; busy = false
        snapshot = nil; lastAttempt = nil; lastError = nil
        refresh(force: true)
    }
    func disconnect() throws {
        let result = SecItemDelete(query as CFDictionary)
        guard result == errSecSuccess || result == errSecItemNotFound else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(result))
        }
        generation += 1; task?.cancel(); task = nil; session?.invalidateAndCancel(); session = nil
        snapshot = nil; lastError = nil; lastAttempt = nil; busy = false; changed?()
    }
    func refresh(force: Bool = false) {
        guard !busy, let key = readKey() else { return }
        // Five-minute backoff even for explicit refresh after a failed request.
        if !force, let lastAttempt, Date().timeIntervalSince(lastAttempt) < 300 { return }
        lastAttempt = Date(); busy = true; generation += 1
        let requestGeneration = generation
        changed?()
        var request = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/key")!)
        request.httpMethod = "GET"; request.timeoutInterval = 20
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil; config.urlCache = nil
        config.httpShouldSetCookies = false
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        self.session = session
        task = session.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self, self.task != nil, self.generation == requestGeneration else { return }
                self.busy = false; self.task = nil; self.session?.finishTasksAndInvalidate(); self.session = nil
                do {
                    guard error == nil, let http = response as? HTTPURLResponse, http.statusCode == 200,
                          let data, data.count <= 100_000 else {
                        // Never show provider response bodies or keys in error messages.
                        throw NSError(domain: "AgentOpenRouter", code: 2)
                    }
                    self.snapshot = try OpenRouterKeyUsage.parse(data); self.lastError = nil
                } catch { self.lastError = agentText("Refresh failed; retained values may be old. Check the key and network.", "刷新失败，保留值可能已过期。请检查密钥与网络。") }
                self.changed?()
            }
        }
        task?.resume()
    }
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil) // Never forward a bearer key to a redirect destination.
    }
}
