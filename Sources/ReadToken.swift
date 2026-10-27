// Optional tokens.ci read token: never stored in config.json or URLs.
import Foundation
import Security

struct ReadTokenStore {
    private static let service = "ci.tokens.menubar.read-token"

    private static func query(_ config: Config) -> [String: Any]? {
        guard let account = readTokenAccount(apiBase: config.apiBase, username: config.username)
        else { return nil }
        return [kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service, kSecAttrAccount as String: account]
    }

    static func load(_ config: Config) -> String? {
        guard var q = query(config) else { return nil }
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        // Background refresh must never trigger a Keychain prompt.
        q[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func save(_ token: String?, config: Config) -> OSStatus {
        guard let q = query(config) else { return errSecParam }
        guard let token, !token.isEmpty else {
            let status = SecItemDelete(q as CFDictionary)
            return status == errSecItemNotFound ? errSecSuccess : status
        }
        let attrs: [String: Any] = [kSecValueData as String: Data(token.utf8)]
        let result = SecItemUpdate(q as CFDictionary, attrs as CFDictionary)
        if result != errSecItemNotFound { return result }
        var add = q
        add[kSecValueData as String] = Data(token.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(add as CFDictionary, nil)
    }
}

/// Refuse redirects for token-bearing profile requests, rather than risk forwarding
/// a private token to a different host (including an HTTPS -> HTTP downgrade).
final class ReadRedirectPolicy: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        if task.originalRequest?.value(forHTTPHeaderField: "Authorization") != nil {
            completionHandler(nil)
        } else { completionHandler(request) }
    }
}
