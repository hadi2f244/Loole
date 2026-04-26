import Foundation

final class ConfigStore {
    private let fm = FileManager.default

    var appSupportDir: URL {
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Loole", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    var credentialsURL: URL { appSupportDir.appendingPathComponent("credentials.json") }
    var tokenURL: URL { appSupportDir.appendingPathComponent("credentials.json.token") }
    private var settingsURL: URL { appSupportDir.appendingPathComponent("settings.json") }
    private var clientConfigURL: URL { appSupportDir.appendingPathComponent("client_config.json") }
    private var serverConfigURL: URL { appSupportDir.appendingPathComponent("server_config.json") }

    // MARK: - Settings

    func loadSettings() -> AppSettings? {
        guard let data = try? Data(contentsOf: settingsURL) else { return nil }
        return try? JSONDecoder().decode(AppSettings.self, from: data)
    }

    func saveSettings(_ s: AppSettings) {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(s) {
            try? data.write(to: settingsURL, options: .atomic)
        }
    }

    // MARK: - Core configs

    func writeClientConfig(_ settings: AppSettings) throws -> URL {
        let data = try JSONSerialization.data(
            withJSONObject: settings.makeClientConfig(),
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: clientConfigURL, options: .atomic)
        return clientConfigURL
    }

    func writeServerConfig(_ settings: AppSettings) throws -> URL {
        let data = try JSONSerialization.data(
            withJSONObject: settings.makeServerConfig(),
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: serverConfigURL, options: .atomic)
        return serverConfigURL
    }

    // MARK: - Credentials management

    /// Copies a credentials file from an external path into App Support.
    func importCredentials(from sourceURL: URL) throws {
        if fm.fileExists(atPath: credentialsURL.path) {
            try fm.removeItem(at: credentialsURL)
        }
        try fm.copyItem(at: sourceURL, to: credentialsURL)
    }

    func deleteCredentials() throws {
        if fm.fileExists(atPath: credentialsURL.path) {
            try fm.removeItem(at: credentialsURL)
        }
        if fm.fileExists(atPath: tokenURL.path) {
            try fm.removeItem(at: tokenURL)
        }
    }

    func credentialsExist() -> Bool {
        fm.fileExists(atPath: credentialsURL.path)
    }

    func tokenExists() -> Bool {
        fm.fileExists(atPath: tokenURL.path)
    }
}
