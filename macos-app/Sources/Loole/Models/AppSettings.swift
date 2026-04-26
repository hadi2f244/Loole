import Foundation

struct AppSettings: Equatable {
    var credentialsFilename: String = "credentials.json"
    var folderID: String = ""
    var listenHost: String = "127.0.0.1"   // "127.0.0.1" (Local) or "0.0.0.0" (LAN)
    var listenPort: Int = 1080
    var refreshRateMs: Int = 200
    var flushRateMs: Int = 300
    var useSystemProxy: Bool = false
    var setupComplete: Bool = false
    var serverSetupComplete: Bool = false

    static let `default` = AppSettings()

    var listenAddr: String { "\(listenHost):\(listenPort)" }

    var isLAN: Bool {
        get { listenHost == "0.0.0.0" }
        set { listenHost = newValue ? "0.0.0.0" : "127.0.0.1" }
    }

    var socksPort: Int { listenPort }
    var socksHost: String { listenHost }

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
}

extension AppSettings: Codable {
    enum CodingKeys: String, CodingKey {
        case credentialsFilename, folderID
        case listenHost, listenPort
        case refreshRateMs, flushRateMs
        case useSystemProxy, setupComplete, serverSetupComplete
        case listenAddr   // legacy — only read during migration
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        credentialsFilename = (try? c.decode(String.self, forKey: .credentialsFilename)) ?? "credentials.json"
        folderID            = (try? c.decode(String.self, forKey: .folderID)) ?? ""
        refreshRateMs       = (try? c.decode(Int.self,    forKey: .refreshRateMs)) ?? 200
        flushRateMs         = (try? c.decode(Int.self,    forKey: .flushRateMs))   ?? 300
        useSystemProxy      = (try? c.decode(Bool.self,   forKey: .useSystemProxy)) ?? false
        setupComplete       = (try? c.decode(Bool.self,   forKey: .setupComplete))  ?? false
        serverSetupComplete = (try? c.decode(Bool.self,   forKey: .serverSetupComplete)) ?? false

        // Prefer new split fields; fall back to old listenAddr string.
        if let host = try? c.decode(String.self, forKey: .listenHost) {
            listenHost = host
            listenPort = (try? c.decode(Int.self, forKey: .listenPort)) ?? 1080
        } else if let addr = try? c.decode(String.self, forKey: .listenAddr) {
            let parts = addr.split(separator: ":").map(String.init)
            listenHost = parts.first ?? "127.0.0.1"
            listenPort = parts.last.flatMap(Int.init) ?? 1080
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(credentialsFilename, forKey: .credentialsFilename)
        try c.encode(folderID,            forKey: .folderID)
        try c.encode(listenHost,          forKey: .listenHost)
        try c.encode(listenPort,          forKey: .listenPort)
        try c.encode(refreshRateMs,       forKey: .refreshRateMs)
        try c.encode(flushRateMs,         forKey: .flushRateMs)
        try c.encode(useSystemProxy,      forKey: .useSystemProxy)
        try c.encode(setupComplete,       forKey: .setupComplete)
        try c.encode(serverSetupComplete, forKey: .serverSetupComplete)
    }
}
