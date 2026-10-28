import AppKit
import Darwin

final class AgentAutomatic {
    private let defaults: UserDefaults
    private var lastAttempt: Date?
    private(set) var codex: AgentAutomaticSnapshot?
    private(set) var codexError: String?
    private(set) var busy = false
    var changed: (() -> Void)?
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    var enabled: Bool { defaults.bool(forKey: "agent.codex.enabled") }
    func setEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: "agent.codex.enabled"); codex = nil; codexError = nil; lastAttempt = nil
        if enabled { refresh() }; changed?()
    }
    private var codexPath: String? {
        let home = NSHomeDirectory()
        return (ProcessInfo.processInfo.environment["PATH", default: ""].split(separator: ":").map { String($0) + "/codex" } + ["/opt/homebrew/bin/codex", "/usr/local/bin/codex", home + "/.local/bin/codex", home + "/.npm-global/bin/codex", home + "/.volta/bin/codex"])
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }
    func refresh() {
        guard enabled, !busy else { return }
        if let lastAttempt, Date().timeIntervalSince(lastAttempt) < 300 { return }
        lastAttempt = Date()
        guard let path = codexPath else { codexError = agentText("Codex CLI not found. Install/update the official CLI and sign in there first; no account is connected by this switch.", "未找到 Codex CLI。请先安装/更新官方 CLI 并在其中登录；此开关不会替你登录。"); changed?(); return }
        busy = true; changed?()
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let result = Self.readCodex(executable: path)
            DispatchQueue.main.async {
                guard let self else { return }; self.busy = false
                guard self.enabled else { return }
                switch result {
                case .success(let snapshot): self.codex = snapshot; self.codexError = nil
                case .failure: self.codexError = agentText("Codex could not return usage. Check its login, connection and CLI version. Last successful values, if any, remain dated; this is not zero use.", "Codex 未返回用量。请检查 CLI 登录、连接与版本；如有旧数据会保留时间，不会当作零用量。")
                }; self.changed?()
            }
        }
    }
    // Bounded local JSON-RPC. Never sends a model turn or reads credential files.
    static func readCodex(executable: String) -> Result<AgentAutomaticSnapshot, Error> {
        do {
            let results = try LocalUsageRPC.read(executable: executable, arguments: ["app-server"], methods: ["account/rateLimits/read", "account/usage/read"])
            var snapshot = AgentAutomaticSnapshot()
            if let result = results[0]["result"] as? [String: Any] { snapshot.windows = try codexRateWindows(result) }
            if let result = results[1]["result"] as? [String: Any], let summary = result["summary"] as? [String: Any] { snapshot.lifetimeTokens = agentFinite(summary["lifetimeTokens"]) }
            else { snapshot.usageError = "account/usage/read unavailable" }
            guard !snapshot.windows.isEmpty || snapshot.lifetimeTokens != nil else { throw AgentAutomaticError.unavailable }
            return .success(snapshot)
        } catch { return .failure(error) }
    }

}

// Installs a supported Claude Code statusLine only after a user's explicit confirmation.
// Existing custom status lines are preserved, not wrapped, executed or overwritten.
enum ClaudeBridgeInstall {
    static var settingsOverride: URL?
    static var settings: URL { settingsOverride ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json") }
    static var command: String? {
        guard let path = Bundle.main.executableURL?.path else { return nil }
        return "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "' --claude-statusline"
    }
    static func read() throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: settings.path) else { return [:] }
        let data = try Data(contentsOf: settings)
        guard data.count <= 1_048_576, let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw AgentAutomaticError.malformed }
        return object
    }
    static var installed: Bool {
        guard let object = try? read(), let line = object["statusLine"] as? [String: Any] else { return false }
        return line["command"] as? String == command
    }
    static func change(enable: Bool) throws {
        var object = try read()
        let original = object["statusLine"]
        if enable {
            guard original == nil || installed, let command else { throw AgentAutomaticError.unavailable }
            object["statusLine"] = ["type": "command", "command": command]
        } else {
            guard installed else { throw AgentAutomaticError.unavailable }
            object.removeValue(forKey: "statusLine")
        }
        try FileManager.default.createDirectory(at: settings.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: settings, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: settings.path)
        if !enable && settingsOverride == nil { try? FileManager.default.removeItem(at: ClaudeStatusBridge.file) }
    }
}

// A poll-based reader cannot hang on a small JSON line or an inherited open pipe.
// Responses are capped; unsolicited server requests are refused. All methods are fixed at call sites.
enum LocalUsageRPC {
    static func read(executable: String, arguments: [String], methods: [String], timeout: TimeInterval = 20, jsonrpc2: Bool = false) throws -> [[String: Any]] {
        let process = Process(), input = Pipe(), output = Pipe()
        process.executableURL = URL(fileURLWithPath: executable); process.arguments = arguments
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        process.standardInput = input; process.standardOutput = output; process.standardError = FileHandle.nullDevice
        try process.run()
        defer { try? input.fileHandleForWriting.close(); if process.isRunning { process.terminate() }; try? output.fileHandleForReading.close() }
        func send(_ o: [String: Any]) throws { var envelope = o; if jsonrpc2 { envelope["jsonrpc"] = "2.0" }; var data = try JSONSerialization.data(withJSONObject: envelope, options: [.withoutEscapingSlashes, .sortedKeys]); data.append(10); try input.fileHandleForWriting.write(contentsOf: data) }
        try send(["id": 1, "method": "initialize", "params": ["clientInfo": ["name": "tokensbar", "title": "TokensBar", "version": "1.12.0"]]])
        var buffer = Data(), responses: [Int: [String: Any]] = [:], total = 0
        let deadline = Date().addingTimeInterval(timeout), fd = output.fileHandleForReading.fileDescriptor
        while Date() < deadline {
            var descriptor = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let ready = Darwin.poll(&descriptor, 1, 200)
            if ready < 0 { if errno == EINTR { continue }; throw AgentAutomaticError.unavailable }
            if ready == 0 { continue }
            if descriptor.revents & Int16(POLLIN | POLLHUP) == 0 { throw AgentAutomaticError.unavailable }
            var bytes = [UInt8](repeating: 0, count: 16384)
            let count = Darwin.read(fd, &bytes, bytes.count)
            guard count > 0 else { throw AgentAutomaticError.unavailable }
            total += count; guard total <= 4_194_304 else { throw AgentAutomaticError.tooLarge }
            buffer.append(contentsOf: bytes.prefix(count))
            while let end = buffer.firstIndex(of: 10) {
                let line = buffer[..<end]; buffer.removeSubrange(...end)
                guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
                if object["method"] != nil, let id = object["id"] { try send(["id": id, "error": ["code": -32601, "message": "Read-only client"]]); continue }
                guard let id = object["id"] as? Int else { continue }
                if id == 1 {
                    guard object["result"] != nil else { throw AgentAutomaticError.unavailable }
                    try send(["method": "initialized"])
                    for (index, method) in methods.enumerated() { try send(["id": index + 2, "method": method]) }
                } else if id >= 2, id < methods.count + 2 { responses[id] = object }
                if responses.count == methods.count { return (0..<methods.count).map { responses[$0 + 2]! } }
            }
        }
        throw AgentAutomaticError.timeout
    }
}

final class MuseCodeAutomatic {
    private let defaults = UserDefaults.standard
    private var attempted: Date?
    private(set) var snapshot: AgentAutomaticSnapshot?
    private(set) var error: String?
    private(set) var busy = false
    var changed: (() -> Void)?
    var enabled: Bool { defaults.bool(forKey: "agent.museCode.enabled") }
    func setEnabled(_ value: Bool) { defaults.set(value, forKey: "agent.museCode.enabled"); attempted = nil; snapshot = nil; error = nil; if value { refresh() }; changed?() }
    func refresh() {
        guard enabled, !busy, attempted.map({ Date().timeIntervalSince($0) >= 300 }) ?? true else { return }
        attempted = Date()
        let home = NSHomeDirectory()
        let paths = ProcessInfo.processInfo.environment["PATH", default: ""].split(separator: ":").map { String($0) + "/muse" } + ["/opt/homebrew/bin/muse", "/usr/local/bin/muse", home + "/.local/bin/muse"]
        guard let path = paths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else { error = agentText("Muse Code CLI not found. This is not the Muse personal agent.", "未找到 Muse Code CLI；此接口不是 Muse 个人 Agent。"); changed?(); return }
        busy = true; changed?()
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let result: Result<AgentAutomaticSnapshot, Error> = Result {
                let reply = try LocalUsageRPC.read(executable: path, arguments: ["serve"], methods: ["usage/read"], jsonrpc2: true)
                guard let value = reply.first?["result"] as? [String: Any] else { throw AgentAutomaticError.unavailable }
                return try museCodeSnapshot(value)
            }
            DispatchQueue.main.async {
                guard let self else { return }; self.busy = false; guard self.enabled else { return }
                switch result { case .success(let value): self.snapshot = value; self.error = nil
                case .failure: self.error = agentText("No usage observation returned by this Muse Code host. Check CLI version and login; a new host may have no cached observation. TokensBar does not mint keys or start model calls.", "Muse Code 主机未返回额度记录。请检查 CLI 版本与登录；新主机可能没有缓存观测。TokensBar 不铸造密钥、不启动模型调用。") }; self.changed?()
            }
        }
    }
}
