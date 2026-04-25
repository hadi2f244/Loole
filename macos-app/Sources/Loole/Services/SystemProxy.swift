import Foundation
import AppKit

/// Sets / clears the system-wide SOCKS5 proxy via networksetup.
/// Uses AppleScript with administrator privileges — asks once per enable/disable.
enum SystemProxy {
    enum Result { case ok, cancelled, failed(String) }

    static func enable(host: String, port: Int) async -> Result {
        let h = host == "0.0.0.0" ? "127.0.0.1" : host
        let shell = """
        networksetup -listallnetworkservices \
          | grep -v '^[*]' | tail -n +2 \
          | while IFS= read -r svc; do \
              networksetup -setsocksfirewallproxy "$svc" \(h) \(port) off 2>/dev/null; \
              networksetup -setsocksfirewallproxystate "$svc" on 2>/dev/null; \
            done
        """
        return await run(shell,
            prompt: "Loole needs permission to route your Mac's traffic through the proxy.")
    }

    static func disable() async -> Result {
        let shell = """
        networksetup -listallnetworkservices \
          | grep -v '^[*]' | tail -n +2 \
          | while IFS= read -r svc; do \
              networksetup -setsocksfirewallproxystate "$svc" off 2>/dev/null; \
            done
        """
        return await run(shell,
            prompt: "Loole needs permission to turn off the system proxy.")
    }

    static func disableSync() {
        let shell = """
        networksetup -listallnetworkservices \
          | grep -v '^[*]' | tail -n +2 \
          | while IFS= read -r svc; do \
              networksetup -setsocksfirewallproxystate "$svc" off 2>/dev/null; \
            done
        """
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

    private static func run(_ shell: String, prompt: String) async -> Result {
        let escaped = shell
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let promptEsc = prompt
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let src = "do shell script \"\(escaped)\" with administrator privileges with prompt \"\(promptEsc)\""

        return await Task.detached(priority: .userInitiated) {
            var errDict: NSDictionary?
            guard let script = NSAppleScript(source: src) else {
                return Result.failed("AppleScript init failed")
            }
            _ = script.executeAndReturnError(&errDict)
            if let e = errDict {
                let code = (e[NSAppleScript.errorNumber] as? Int) ?? 0
                if code == -128 { return Result.cancelled }
                return Result.failed((e[NSAppleScript.errorMessage] as? String) ?? "unknown")
            }
            return Result.ok
        }.value
    }
}
