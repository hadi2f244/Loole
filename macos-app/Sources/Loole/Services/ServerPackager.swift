import Foundation
import AppKit

/// Builds the server deployment zip that the user uploads to their Linux server.
enum ServerPackager {

    enum PackageError: LocalizedError {
        case unknownArch(String)
        case binaryNotFound(String)
        case packagingFailed(String)

        var errorDescription: String? {
            switch self {
            case .unknownArch(let a):     return "Unrecognized architecture: \(a)"
            case .binaryNotFound(let b):  return "Server binary '\(b)' not found in app bundle."
            case .packagingFailed(let m): return "Packaging failed: \(m)"
            }
        }
    }

    /// Parses `uname -a` output and returns "amd64" or "arm64".
    static func detectArch(from unameOutput: String) -> String? {
        let lower = unameOutput.lowercased()
        if lower.contains("x86_64") || lower.contains("amd64") { return "amd64" }
        if lower.contains("aarch64") || lower.contains("arm64") { return "arm64" }
        return nil
    }

    /// Creates loole-server.zip on the Desktop. Returns the zip URL.
    static func buildPackage(
        arch: String,
        settings: AppSettings,
        store: ConfigStore
    ) throws -> URL {
        let binaryName = "loole-server-linux-\(arch)"
        guard let binaryURL = Bundle.main.url(forResource: binaryName, withExtension: nil) else {
            throw PackageError.binaryNotFound(binaryName)
        }

        let fm = FileManager.default
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("loole-server-pkg-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmp) }

        // server binary → server
        let serverDest = tmp.appendingPathComponent("server")
        try fm.copyItem(at: binaryURL, to: serverDest)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: serverDest.path)

        // credentials.json
        if store.credentialsExist() {
            try fm.copyItem(at: store.credentialsURL, to: tmp.appendingPathComponent("credentials.json"))
        }

        // token file (must exist at same name the Go binary expects: credentials.json.token)
        if store.tokenExists() {
            try fm.copyItem(at: store.tokenURL, to: tmp.appendingPathComponent("credentials.json.token"))
        }

        // server_config.json
        let _ = try store.writeServerConfig(settings)
        try fm.copyItem(
            at: store.appSupportDir.appendingPathComponent("server_config.json"),
            to: tmp.appendingPathComponent("server_config.json")
        )

        // run.sh convenience script
        let runSh = """
        #!/bin/bash
        # Run the Loole server
        chmod +x ./server
        ./server -c server_config.json -gc credentials.json
        """
        try runSh.write(to: tmp.appendingPathComponent("run.sh"), atomically: true, encoding: .utf8)

        // Zip it
        let desktop = fm.urls(for: .desktopDirectory, in: .userDomainMask)[0]
        let zipURL = desktop.appendingPathComponent("loole-server.zip")
        if fm.fileExists(atPath: zipURL.path) { try fm.removeItem(at: zipURL) }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        task.arguments = ["-r", zipURL.path, "."]
        task.currentDirectoryURL = tmp
        let errPipe = Pipe()
        task.standardError = errPipe
        try task.run()
        task.waitUntilExit()

        if task.terminationStatus != 0 {
            let errMsg = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw PackageError.packagingFailed(errMsg)
        }

        return zipURL
    }

    static func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// Returns the deployment steps the user needs to run, each as a separate (label, command) pair.
    static func deploymentCommands(zipURL: URL, serverIP: String, includeSSH: Bool) -> [(label: String, code: String)] {
        let localPath = zipURL.path
        let target = serverIP.isEmpty ? "YOUR_SERVER_IP" : serverIP
        let user = "root"
        
        if !includeSSH {
            return [
                (
                    label: "1. Upload to Server",
                    code: "scp \"\(localPath)\" \(user)@\(target):/root/"
                ),
                (
                    label: "2. Install Unzip & Setup",
                    code: "apt-get update && apt-get install -y unzip && cd /root && unzip -o loole-server.zip && chmod +x server"
                ),
                (
                    label: "3. Run (Background)",
                    code: "cd /root && nohup ./server -c server_config.json -gc credentials.json > loole.log 2>&1 &"
                ),
                (
                    label: "4. Show Logs",
                    code: "tail -f /root/loole.log"
                ),
                (
                    label: "5. Terminate",
                    code: "pkill -f server"
                )
            ]
        }
        
        return [
            (
                label: "1. Upload to Server",
                code: "scp \"\(localPath)\" \(user)@\(target):/root/"
            ),
            (
                label: "2. Install Unzip & Setup",
                code: "ssh \(user)@\(target) 'apt-get update && apt-get install -y unzip && cd /root && unzip -o loole-server.zip && chmod +x server'"
            ),
            (
                label: "3. Run (Background)",
                code: "ssh \(user)@\(target) 'cd /root && nohup ./server -c server_config.json -gc credentials.json > loole.log 2>&1 &'"
            ),
            (
                label: "4. Show Logs",
                code: "ssh \(user)@\(target) 'tail -f /root/loole.log'"
            ),
            (
                label: "5. Terminate",
                code: "ssh \(user)@\(target) 'pkill -f server'"
            )
        ]
    }
}
