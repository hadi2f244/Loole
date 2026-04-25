import Foundation

struct AppSettings: Codable, Equatable {
    var credentialsFilename: String = "credentials.json"
    var folderID: String = ""
    var listenAddr: String = "127.0.0.1:1080"
    var refreshRateMs: Int = 200
    var flushRateMs: Int = 300
    var useSystemProxy: Bool = false
    var setupComplete: Bool = false
    var serverSetupComplete: Bool = false

    static let `default` = AppSettings()

    func makeClientConfig() -> [String: Any] {
        [
            "listen_addr": listenAddr,
            "storage_type": "google",
            "google_folder_id": folderID,
            "refresh_rate_ms": refreshRateMs,
            "flush_rate_ms": flushRateMs,
            "transport": [
                "TargetIP": "216.239.38.120:443",
                "SNI": "google.com",
                "HostHeader": "www.googleapis.com",
                "InsecureSkipVerify": false
            ]
        ]
    }

    func makeServerConfig() -> [String: Any] {
        [
            "storage_type": "google",
            "google_folder_id": folderID,
            "refresh_rate_ms": refreshRateMs,
            "flush_rate_ms": flushRateMs
        ]
    }

    var socksPort: Int {
        if let portStr = listenAddr.split(separator: ":").last,
           let port = Int(portStr) { return port }
        return 1080
    }

    var socksHost: String {
        let parts = listenAddr.split(separator: ":")
        if parts.count >= 1 { return String(parts[0]) }
        return "127.0.0.1"
    }
}
