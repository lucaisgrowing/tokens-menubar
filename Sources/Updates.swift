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
    /// Optional SHA256SUMS.txt asset published alongside the zip.
    let checksumAsset: URL?
    let isNewer: Bool
}

struct CLIUpdateInfo {
    let latest: String
    let current: String
    let url: String
    let isNewer: Bool
}

enum Updates {
    static var repo = "lucaisgrowing/tokens-menubar"
    static var cliRepo = "missuo/tokens"

    private static let session: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 20
        cfg.timeoutIntervalForResource = 30
        return URLSession(configuration: cfg)
    }()

    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    static func isNewer(_ candidate: String, than current: String) -> Bool {
        isNewerVersion(candidate, than: current)
    }

    static func check(on queue: DispatchQueue = .main, _ done: @escaping (UpdateInfo?) -> Void) {
        guard let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest") else {
            return queue.async { done(nil) }
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 20
        req.setValue("TokensBar/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        session.dataTask(with: req) { data, resp, _ in
            guard let data, (resp as? HTTPURLResponse)?.statusCode == 200,
                  let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = o["tag_name"] as? String
            else { return queue.async { done(nil) } }
            let page = o["html_url"] as? String ?? "https://github.com/\(repo)/releases/latest"
            let assets = o["assets"] as? [[String: Any]] ?? []
            // The zip the release workflow attaches, by exact name: a release can
            // carry other files, and the installer must not download one of those.
            let asset = assets
                .first { $0["name"] as? String == "TokensBar.app.zip" }
                .flatMap { $0["browser_download_url"] as? String }
                .flatMap(URL.init(string:))
            let checksumAsset = assets
                .first { $0["name"] as? String == "SHA256SUMS.txt" }
                .flatMap { $0["browser_download_url"] as? String }
                .flatMap(URL.init(string:))
            let current = currentVersion
            let info = UpdateInfo(latest: tag, current: current, url: page, asset: asset,
                                  checksumAsset: checksumAsset,
                                  isNewer: isNewer(tag, than: current))
            queue.async { done(info) }
        }.resume()
    }

    /// Checks whether the upstream `tokens` CLI has a newer release than the
    /// locally installed binary.
    static func checkCLI(current: String, on queue: DispatchQueue = .main,
                         _ done: @escaping (CLIUpdateInfo?) -> Void) {
        guard !current.isEmpty,
              let url = URL(string: "https://api.github.com/repos/\(cliRepo)/releases/latest")
        else { return queue.async { done(nil) } }
        var req = URLRequest(url: url)
        req.timeoutInterval = 20
        req.setValue("TokensBar/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        session.dataTask(with: req) { data, resp, _ in
            guard let data, (resp as? HTTPURLResponse)?.statusCode == 200,
                  let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = o["tag_name"] as? String
            else { return queue.async { done(nil) } }
            let page = o["html_url"] as? String ?? "https://github.com/\(cliRepo)/releases/latest"
            let info = CLIUpdateInfo(latest: tag, current: current, url: page,
                                     isNewer: isNewer(tag, than: current))
            queue.async { done(info) }
        }.resume()
    }
}
