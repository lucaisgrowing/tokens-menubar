// Update check against GitHub Releases. Read-only, unauthenticated.

import Foundation

struct UpdateInfo {
    let latest: String
    let current: String
    /// The release page, for the cases the installer has to hand over to a browser.
    let url: String
    /// The packaged app in that release, when it has one. A release published
    /// without its zip still reports a version; it just cannot be installed.
    let asset: URL?
    let isNewer: Bool
}

enum Updates {
    static var repo = "lucaisgrowing/tokens-menubar"

    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    /// Compares dot-separated numeric versions; missing components count as 0,
    /// so 1.1 and 1.1.0 are equal and 1.10 beats 1.9.
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        func parts(_ s: String) -> [Int] {
            s.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
                .split(separator: ".")
                .map { Int($0.prefix(while: \.isNumber)) ?? 0 }
        }
        let a = parts(candidate), b = parts(current)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    static func check(on queue: DispatchQueue = .main, _ done: @escaping (UpdateInfo?) -> Void) {
        guard let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest") else {
            return queue.async { done(nil) }
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 20
        req.setValue("TokensBar", forHTTPHeaderField: "User-Agent")
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        URLSession(configuration: .ephemeral).dataTask(with: req) { data, resp, _ in
            guard let data, (resp as? HTTPURLResponse)?.statusCode == 200,
                  let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = o["tag_name"] as? String
            else { return queue.async { done(nil) } }
            let page = o["html_url"] as? String ?? "https://github.com/\(repo)/releases/latest"
            // The zip the release workflow attaches, by exact name: a release can
            // carry other files, and the installer must not download one of those.
            let asset = (o["assets"] as? [[String: Any]] ?? [])
                .first { $0["name"] as? String == "TokensBar.app.zip" }
                .flatMap { $0["browser_download_url"] as? String }
                .flatMap(URL.init(string:))
            let current = currentVersion
            let info = UpdateInfo(latest: tag, current: current, url: page, asset: asset,
                                  isNewer: isNewer(tag, than: current))
            queue.async { done(info) }
        }.resume()
    }
}
