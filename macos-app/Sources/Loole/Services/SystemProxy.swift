import Foundation
import AppKit

/// Sets / clears the system-wide SOCKS5 proxy via networksetup.
/// Uses ProxyHelper to avoid constant password prompts.
enum SystemProxy {
    enum Result { case ok, cancelled, failed(String) }

    static func enable(host: String, port: Int) async -> Result {
        let h = host == "0.0.0.0" ? "127.0.0.1" : host

        if ProxyHelper.isInstalled() {
            let rc = ProxyHelper.run(["enable", h, String(port)])
            return rc == 0 ? .ok : .failed("helper enable failed: \(rc)")
        }

        // Install helper on first run
        do {
            try ProxyHelper.install()
            let rc = ProxyHelper.run(["enable", h, String(port)])
            return rc == 0 ? .ok : .failed("helper enable failed: \(rc)")
        } catch ProxyHelper.HelperError.promptCancelled {
            return .cancelled
        } catch {
            // Fallback
            let shell = "networksetup -listallnetworkservices | grep -v '^[*]' | tail -n +2 | while IFS= read -r svc; do networksetup -setsocksfirewallproxy \"$svc\" \(h) \(port) off 2>/dev/null; networksetup -setsocksfirewallproxystate \"$svc\" on 2>/dev/null; done"
            return await runOneShot(shell, prompt: "Loole needs permission to set the system proxy.")
        }
    }

    static func disable() async -> Result {
        if ProxyHelper.isInstalled() {
            let rc = ProxyHelper.run(["disable"])
            return rc == 0 ? .ok : .failed("helper disable failed: \(rc)")
        }

        let shell = "networksetup -listallnetworkservices | grep -v '^[*]' | tail -n +2 | while IFS= read -r svc; do networksetup -setsocksfirewallproxystate \"$svc\" off 2>/dev/null; done"
        return await runOneShot(shell, prompt: "Loole needs permission to turn off the system proxy.")
    }

    static func disableSync() {
        if ProxyHelper.isInstalled() {
            ProxyHelper.run(["disable"])
            return
        }
        let shell = "networksetup -listallnetworkservices | grep -v '^[*]' | tail -n +2 | while IFS= read -r svc; do networksetup -setsocksfirewallproxystate \"$svc\" off 2>/dev/null; done"
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", shell]
        p.standardOutput = Pipe(); p.standardError = Pipe()
        try? p.run(); p.waitUntilExit()
    }

    static func isEnabled() -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/scutil")
        p.arguments = ["--proxy"]
        let pipe = Pipe()
        p.standardOutput = pipe; p.standardError = Pipe()
        do { try p.run(); p.waitUntilExit() } catch { return false }
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return out.contains("SOCKSEnable : 1")
    }

    private static func runOneShot(_ shell: String, prompt: String) async -> Result {
        let escaped = shell.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let promptEsc = prompt.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let src = "do shell script \"\(escaped)\" with administrator privileges with prompt \"\(promptEsc)\""

        return await Task.detached(priority: .userInitiated) {
            var errDict: NSDictionary?
            guard let script = NSAppleScript(source: src) else { return .failed("init failed") }
            _ = script.executeAndReturnError(&errDict)
            if let e = errDict {
                let code = (e[NSAppleScript.errorNumber] as? Int) ?? 0
                if code == -128 { return .cancelled }
                return .failed((e[NSAppleScript.errorMessage] as? String) ?? "unknown")
            }
            return .ok
        }.value
    }
}
