// Installs an update in place, so a new version does not mean a trip to the
// browser, a download, an unzip, a drag into /Applications and an xattr command.
//
// The download and the checks happen in-process; the swap itself is handed to a
// short shell script that outlives us, because a running app cannot reliably
// replace its own bundle while its pages are still mapped.

import AppKit
import Foundation

enum Installer {
    enum Failure: LocalizedError {
        /// The bundle's directory is not writable — /Applications is root:admin,
        /// so a standard account cannot swap the app there.
        case readOnly(String)
        case download
        case unpack
        /// Local filesystem or spawn trouble on our side, not the download's.
        case setup
        /// The zip did not contain a bundle where one was expected.
        case contents
        /// What arrived is not the version the check advertised.
        case version(String)

        var errorDescription: String? {
            switch self {
            case .readOnly(let path): return t("install.readOnly", path)
            case .download: return t("install.download")
            case .unpack: return t("install.unpack")
            case .setup: return t("install.setup")
            case .contents: return t("install.contents")
            case .version(let got): return t("install.version", got)
            }
        }
    }

    static var target: URL { Bundle.main.bundleURL }

    static var canReplace: Bool {
        FileManager.default.isWritableFile(atPath: target.deletingLastPathComponent().path)
    }

    /// Downloads, unpacks and verifies the release, then leaves a detached script
    /// waiting on this process to exit before it swaps the bundle and relaunches.
    /// On success the caller must terminate — nothing else will trigger the swap.
    static func install(asset: URL, expecting version: String,
                        done: @escaping (Failure?) -> Void) {
        let fm = FileManager.default
        func finish(_ f: Failure?) { DispatchQueue.main.async { done(f) } }
        guard canReplace else {
            return finish(.readOnly(target.deletingLastPathComponent().path))
        }
        var req = URLRequest(url: asset)
        req.timeoutInterval = 120
        req.setValue("TokensBar", forHTTPHeaderField: "User-Agent")
        // A download task, not `data`: the zip goes straight to disk instead of
        // through memory, and URLSession follows GitHub's redirect to its CDN.
        URLSession(configuration: .ephemeral).downloadTask(with: req) { tmp, resp, _ in
            guard let tmp, (resp as? HTTPURLResponse)?.statusCode == 200 else {
                return finish(.download)
            }
            // A replacement directory sits on the same volume as the target, so
            // moving the new bundle into place is a rename and not a slow copy
            // that could be interrupted half-written.
            guard let work = try? fm.url(for: .itemReplacementDirectory, in: .userDomainMask,
                                         appropriateFor: target, create: true)
            else { return finish(.setup) }
            let zip = work.appendingPathComponent("TokensBar.app.zip")
            guard (try? fm.moveItem(at: tmp, to: zip)) != nil else { return finish(.setup) }

            // ditto, to match the `ditto -c -k --keepParent` the release is packed
            // with: it round-trips bundle metadata that unzip does not.
            guard run("/usr/bin/ditto", ["-x", "-k", zip.path, work.path]) == 0 else {
                return finish(.unpack)
            }

            let new = work.appendingPathComponent("TokensBar.app")
            guard fm.fileExists(atPath: new.appendingPathComponent("Contents/MacOS/TokensBar").path),
                  let plist = NSDictionary(contentsOf: new.appendingPathComponent("Contents/Info.plist"))
            else { return finish(.contents) }
            // The download has to be the version the check advertised. Without this
            // the app would happily install whatever arrived under that URL.
            let got = plist["CFBundleShortVersionString"] as? String ?? "?"
            guard got == version.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
            else { return finish(.version(got)) }

            guard let script = writeSwapScript(new: new, work: work) else { return finish(.setup) }
            let helper = Process()
            helper.executableURL = URL(fileURLWithPath: "/bin/sh")
            helper.arguments = [script.path]
            guard (try? helper.run()) != nil else { return finish(.setup) }
            finish(nil)
        }.resume()
    }

    /// The swap, as a script that outlives us: wait for the process to go, rename
    /// the new bundle in, roll the old one back if that fails, then relaunch.
    ///
    /// It lives outside the work directory it deletes — a shell reads its script
    /// incrementally, so a script that removes itself mid-run is asking for it.
    private static func writeSwapScript(new: URL, work: URL) -> URL? {
        let pid = ProcessInfo.processInfo.processIdentifier
        let script = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("tokensbar-swap-\(pid).sh")
        let body = """
        #!/bin/sh
        set -u
        pid=\(pid)
        target=\(shq(target.path))
        new=\(shq(new.path))
        work=\(shq(work.path))

        # Wait for the old app to exit; its bundle cannot be replaced from under
        # it. Cap the wait at 30s rather than hanging around forever.
        i=0
        while kill -0 "$pid" 2>/dev/null && [ $i -lt 300 ]; do
          sleep 0.1
          i=$((i + 1))
        done

        rm -rf "$target.old"
        mv "$target" "$target.old" || exit 1
        if ! mv "$new" "$target"; then
          # Put the old one back rather than leaving the user with no app at all.
          mv "$target.old" "$target"
          exit 1
        fi
        rm -rf "$target.old"
        # URLSession does not set the quarantine flag the way a browser does, but
        # clearing it costs nothing and is the step people trip over by hand.
        xattr -dr com.apple.quarantine "$target" 2>/dev/null
        open "$target"
        rm -rf "$work"
        """
        guard (try? body.write(to: script, atomically: true, encoding: .utf8)) != nil else {
            return nil
        }
        return script
    }

    /// Single-quoted for the shell, with embedded quotes closed and reopened —
    /// these paths come from the filesystem, not from us.
    private static func shq(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func run(_ tool: String, _ args: [String]) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return -1 }
        p.waitUntilExit()
        return p.terminationStatus
    }
}
