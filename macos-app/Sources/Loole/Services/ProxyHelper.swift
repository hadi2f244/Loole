import Foundation
import AppKit

/// One-time admin install that drops a tiny wrapper + scoped NOPASSWD sudoers
/// rule for `/usr/local/bin/loole-proxy`. After install, the app can enable
/// or disable the system SOCKS proxy without showing the admin prompt.
enum ProxyHelper {
    static let sudoersPath = "/etc/sudoers.d/loole-proxy"
    static let helperPath  = "/usr/local/bin/loole-proxy"
    static let helperVersion = "1.0.0"

    enum HelperError: LocalizedError {
        case promptCancelled
        case installFailed(String)

        var errorDescription: String? {
            switch self {
            case .promptCancelled: return "Admin permission was cancelled."
            case .installFailed(let msg): return "System-proxy helper install failed: \(msg)"
            }
        }
    }

    /// True when the wrapper exists and passwordless sudo works against it.
    static func isInstalled() -> Bool {
        let fm = FileManager.default
        guard fm.isExecutableFile(atPath: helperPath),
              fm.fileExists(atPath: sudoersPath)
        else { return false }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        p.arguments = ["-n", helperPath, "--self-check"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError  = out
        do {
            try p.run()
            p.waitUntilExit()
            guard p.terminationStatus == 0 else { return false }
            let text = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return text == helperVersion
        } catch {
            return false
        }
    }

    /// Run the helper passwordless. Returns exit status (0 = success).
    @discardableResult
    static func run(_ args: [String]) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        p.arguments = ["-n", helperPath] + args
        p.standardOutput = Pipe()
        p.standardError  = Pipe()
        do { try p.run(); p.waitUntilExit() } catch { return -1 }
        return p.terminationStatus
    }

    static func install() throws {
        let user = NSUserName()
        let helperScript = #"""
        #!/bin/bash
        # loole-proxy: scoped wrapper for system SOCKS proxy toggles.
        set -euo pipefail
        if [ "${1:-}" = "--self-check" ]; then echo "__VERSION__"; exit 0; fi
        ACTION="${1:-}"
        HOST="${2:-}"
        PORT="${3:-}"
        case "$ACTION" in
          enable)
            if [ -z "$HOST" ] || [ -z "$PORT" ]; then
              echo "usage: $0 enable <host> <port>" >&2; exit 1
            fi
            /usr/sbin/networksetup -listallnetworkservices \
              | /usr/bin/grep -v '^[*]' | /usr/bin/tail -n +2 \
              | while IFS= read -r svc; do
                  /usr/sbin/networksetup -setsocksfirewallproxy "$svc" "$HOST" "$PORT" off 2>/dev/null || true
                  /usr/sbin/networksetup -setsocksfirewallproxystate "$svc" on 2>/dev/null || true
                done
            ;;
          disable)
            /usr/sbin/networksetup -listallnetworkservices \
              | /usr/bin/grep -v '^[*]' | /usr/bin/tail -n +2 \
              | while IFS= read -r svc; do
                  /usr/sbin/networksetup -setsocksfirewallproxystate "$svc" off 2>/dev/null || true
                done
            ;;
          *)
            echo "usage: $0 enable <host> <port> | disable" >&2; exit 1
            ;;
        esac
        """#.replacingOccurrences(of: "__VERSION__", with: helperVersion)

        let helperB64 = Data(helperScript.utf8).base64EncodedString()
        let sudoersContent = "\(user) ALL=(ALL) NOPASSWD: \(helperPath)\n"
        let sudoersB64 = Data(sudoersContent.utf8).base64EncodedString()

        let shell = """
        set -e
        mkdir -p /usr/local/bin
        echo '\(helperB64)' | /usr/bin/base64 -D > '\(helperPath)'
        chown root:wheel '\(helperPath)'
        chmod 755 '\(helperPath)'
        echo '\(sudoersB64)' | /usr/bin/base64 -D > '\(sudoersPath)'
        chown root:wheel '\(sudoersPath)'
        chmod 440 '\(sudoersPath)'
        /usr/sbin/visudo -cf '\(sudoersPath)' >/dev/null
        """

        let source = "do shell script \"\(escape(shell))\" with administrator privileges with prompt \"Loole needs one-time permission to install a small system proxy helper. After this, you won't be asked for a password to toggle the proxy.\""

        var errDict: NSDictionary?
        guard let script = NSAppleScript(source: source) else {
            throw HelperError.installFailed("NSAppleScript init failed")
        }
        _ = script.executeAndReturnError(&errDict)
        if let e = errDict {
            let code = (e[NSAppleScript.errorNumber] as? Int) ?? 0
            if code == -128 { throw HelperError.promptCancelled }
            let msg = (e[NSAppleScript.errorMessage] as? String) ?? "unknown"
            throw HelperError.installFailed(msg)
        }
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }
}
