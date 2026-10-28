import AppKit

// Disposable CI only: actual native controls, no credentials, production requests or notifications.
func runUsagePreferencesDiagnostics(directory: String, dark: Bool) throws {
    NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    let config = Config(username: "DEMO")
    let now = Date()
    let sample = PreferencesSnapshot(config: config,
        comparison: UsageComparison(mean: 100000, changePercent: 50, topModel: "DEMO model", topModelDelta: 35000), todayTokens: 150000,
        serverError: agentText("DEMO · Network unavailable. Previous values retained.", "演示状态 · 网络不可用，保留旧数值。"),
        serverAttempt: now, serverFetched: now.addingTimeInterval(-1200), submitted: now.addingTimeInterval(-90000),
        localSuccess: now.addingTimeInterval(-1800), localAttempt: now, localFailed: true, cliPath: nil, hasServer: true, loading: false)
    let view = UsagePreferencesWindow.shared
    for tab in 0...3 {
        view.show(sample, tab: tab)
        guard let window = NSApp.windows.first(where: { $0.title == "TokensBar" }), let content = window.contentView else { throw AgentAutomaticError.unavailable }
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        content.layoutSubtreeIfNeeded()
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(content.bounds.width * 2), pixelsHigh: Int(content.bounds.height * 2), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { throw AgentAutomaticError.unavailable }
        rep.size = content.bounds.size; content.cacheDisplay(in: content.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { throw AgentAutomaticError.unavailable }
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        try png.write(to: URL(fileURLWithPath: directory).appendingPathComponent("preferences-\(tab)-\(L10n.current.rawValue)-\(dark ? "dark" : "light").png"))
    }
    print("PASS: four native preference panes rendered at 2×; DEMO fixtures, no notification attempts")
}

func runNativeAutomaticChecks() throws {
    let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temp) }
    let executable = temp.appendingPathComponent("fixture")
    let script = """
    #!/bin/sh
    while IFS= read -r line; do
      case "$line" in
        *'"initialize"'*) printf '%s\\n' '{"id":1,"result":{}}' ;;
        *'"account/rateLimits/read"'*) printf '%s\\n' '{"id":2,"result":{"rateLimits":{"primary":{"usedPercent":25,"windowDurationMins":300,"resetsAt":2000000000}}}}' ;;
        *'"account/usage/read"'*) printf '%s\\n' '{"id":3,"result":{"summary":{"lifetimeTokens":1234}}}' ;;
        *'"usage/read"'*) printf '%s\\n' '{"id":2,"result":{"usage":{"observedAtMs":1900000000000,"window":{"usedPercent":12,"windowDurationMins":300,"resetsAtMs":2000000000000},"weekly":{"usedPercent":40,"resetsAtMs":2000000000000}}}}' ;;
      esac
    done
    """
    try script.write(to: executable, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
    let started = Date()
    switch AgentAutomatic.readCodex(executable: executable.path) {
    case .success(let s): precondition(s.lifetimeTokens == 1234 && s.windows.first?.usedPercent == 25)
    case .failure(let e): throw e
    }
    precondition(Date().timeIntervalSince(started) < 5, "small stdio frames must not wait for EOF")
    let reply = try LocalUsageRPC.read(executable: executable.path, arguments: [], methods: ["usage/read"], timeout: 2)
    let muse = try museCodeSnapshot(reply[0]["result"] as! [String: Any]); precondition(muse.windows.count == 2)
    try "#!/bin/sh\nwhile IFS= read -r line; do :; done\n".write(to: executable, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
    do { _ = try LocalUsageRPC.read(executable: executable.path, arguments: [], methods: ["usage/read"], timeout: 0.4); fatalError("timeout must fail") } catch AgentAutomaticError.timeout { }
    ClaudeBridgeInstall.settingsOverride = temp.appendingPathComponent("claude/settings.json")
    defer { ClaudeBridgeInstall.settingsOverride = nil }
    try FileManager.default.createDirectory(at: ClaudeBridgeInstall.settings.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("{\"unrelated\":42}".utf8).write(to: ClaudeBridgeInstall.settings)
    try ClaudeBridgeInstall.change(enable: true); precondition(ClaudeBridgeInstall.installed); let preservedAfterEnable = try ClaudeBridgeInstall.read(); precondition(preservedAfterEnable["unrelated"] as? Int == 42)
    try ClaudeBridgeInstall.change(enable: false); precondition(!ClaudeBridgeInstall.installed); let preservedAfterRemove = try ClaudeBridgeInstall.read(); precondition(preservedAfterRemove["unrelated"] as? Int == 42)
    try Data("{\"statusLine\":{\"command\":\"private-custom-command\"},\"unrelated\":42}".utf8).write(to: ClaudeBridgeInstall.settings)
    let original = try Data(contentsOf: ClaudeBridgeInstall.settings)
    do { try ClaudeBridgeInstall.change(enable: true); fatalError("custom line not overwritten") } catch { }
    let unchanged = try Data(contentsOf: ClaudeBridgeInstall.settings); precondition(unchanged == original)
    print("PASS: 9 native CLI framing/timeout and reversible Claude config checks; fixture-only")
}
