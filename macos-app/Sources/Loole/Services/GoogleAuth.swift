import Foundation
import Network
import AppKit

/// Handles Google OAuth 2.0 and Drive folder management entirely from Swift,
/// so the Go client subprocess never needs to do interactive auth.
final class GoogleAuth: ObservableObject {

    // MARK: - Types

    struct OAuthCredentials: Decodable {
        struct Installed: Decodable {
            let client_id: String
            let client_secret: String
            let auth_uri: String
            let token_uri: String
        }
        let installed: Installed
    }

    struct TokenCache: Codable {
        let refresh_token: String
    }

    enum AuthError: LocalizedError {
        case missingCredentials
        case noCodeInRedirect
        case exchangeFailed(String)
        case noRefreshToken
        case driveFailed(String)

        var errorDescription: String? {
            switch self {
            case .missingCredentials:   return "credentials.json is missing or invalid."
            case .noCodeInRedirect:     return "No authorization code received from Google."
            case .exchangeFailed(let m): return "Token exchange failed: \(m)"
            case .noRefreshToken:       return "Google did not return a refresh token. Try again."
            case .driveFailed(let m):   return "Drive API error: \(m)"
            }
        }
    }

    // MARK: - State

    @Published var phase: Phase = .idle

    enum Phase: Equatable {
        case idle
        case waitingForBrowser
        case exchanging
        case findingFolder
        case done(folderID: String)
        case failed(String)
    }

    private var listener: NWListener?
    private var authorizeTask: Task<Void, Never>?
    private(set) var accessToken: String = ""

    // MARK: - Main flow

    func startAuthorize(credentialsURL: URL) {
        authorizeTask?.cancel()
        authorizeTask = Task { await authorize(credentialsURL: credentialsURL) }
    }

    private func authorize(credentialsURL: URL) async {
        await MainActor.run { phase = .waitingForBrowser }

        do {
            let creds = try loadCredentials(at: credentialsURL)
            let port = UInt16.random(in: 49152...65000)
            let redirectURI = "http://127.0.0.1:\(port)"

            let authURL = buildAuthURL(creds: creds.installed, redirectURI: redirectURI)
            NSWorkspace.shared.open(authURL)

            let code = try await captureCode(port: port)

            await MainActor.run { phase = .exchanging }

            let (access, refresh) = try await exchangeCode(
                code: code, creds: creds.installed, redirectURI: redirectURI
            )
            accessToken = access

            // Save token in Loole's format: <credentials.json>.token = {"refresh_token":"..."}
            let cache = TokenCache(refresh_token: refresh)
            let tokenPath = credentialsURL.path + ".token"
            let data = try JSONEncoder().encode(cache)
            try data.write(to: URL(fileURLWithPath: tokenPath), options: .atomic)

            await MainActor.run { phase = .findingFolder }

            let folderID = try await findOrCreateFlowDataFolder(accessToken: access)
            await MainActor.run { phase = .done(folderID: folderID) }

        } catch is CancellationError {
            // User cancelled — phase already reset to .idle by reset()
        } catch {
            await MainActor.run { phase = .failed(error.localizedDescription) }
        }
    }

    func reset() {
        authorizeTask?.cancel()
        authorizeTask = nil
        listener?.cancel()
        listener = nil
        phase = .idle
        accessToken = ""
    }

    // MARK: - OAuth helpers

    private func loadCredentials(at url: URL) throws -> OAuthCredentials {
        let data = try Data(contentsOf: url)
        do {
            return try JSONDecoder().decode(OAuthCredentials.self, from: data)
        } catch {
            throw AuthError.missingCredentials
        }
    }

    private func buildAuthURL(creds: OAuthCredentials.Installed, redirectURI: String) -> URL {
        var c = URLComponents(string: creds.auth_uri)!
        c.queryItems = [
            URLQueryItem(name: "client_id",     value: creds.client_id),
            URLQueryItem(name: "redirect_uri",  value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope",         value: "https://www.googleapis.com/auth/drive.file"),
            URLQueryItem(name: "access_type",   value: "offline"),
            URLQueryItem(name: "prompt",        value: "consent"),
        ]
        return c.url!
    }

    private func captureCode(port: UInt16) async throws -> String {
        let resumer = ContinuationResumer<String>()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { [weak self] cont in
                resumer.set(cont)

                let params = NWParameters.tcp
                guard let nwPort = NWEndpoint.Port(rawValue: port),
                      let listener = try? NWListener(using: params, on: nwPort) else {
                    resumer.fail(AuthError.noCodeInRedirect)
                    return
                }
                self?.listener = listener

                listener.newConnectionHandler = { conn in
                    conn.start(queue: .global())
                    conn.receive(minimumIncompleteLength: 1, maximumLength: 8192) { data, _, _, _ in
                        guard let data, let raw = String(data: data, encoding: .utf8),
                              let code = Self.parseCode(from: raw) else {
                            conn.cancel()
                            return
                        }
                        let ok = "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nConnection: close\r\n\r\n" +
                            "<html><body style='font-family:-apple-system,sans-serif;padding:40px;background:#1a1a1a;color:white;text-align:center;'>" +
                            "<h2>✅ Loole: Connected</h2>" +
                            "<p>Authorization captured. You can close this tab.</p></body></html>"
                        conn.send(content: ok.data(using: .utf8), completion: .idempotent)
                        listener.cancel()
                        resumer.succeed(code)
                    }
                }
                listener.start(queue: .global())
            }
        } onCancel: { [weak self] in
            self?.listener?.cancel()
            resumer.fail(CancellationError())
        }
    }

    private static func parseCode(from httpRequest: String) -> String? {
        guard let firstLine = httpRequest.components(separatedBy: "\r\n").first,
              let pathPart = firstLine.components(separatedBy: " ").dropFirst().first,
              let url = URL(string: "http://x" + pathPart) else { return nil }
        return URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "code" })?.value
    }

    private func exchangeCode(code: String, creds: OAuthCredentials.Installed, redirectURI: String) async throws -> (String, String) {
        var req = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = [
            "grant_type=authorization_code",
            "code=\(code)",
            "client_id=\(creds.client_id)",
            "client_secret=\(creds.client_secret)",
            "redirect_uri=\(redirectURI.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? redirectURI)"
        ].joined(separator: "&")
        req.httpBody = body.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw AuthError.exchangeFailed(String(data: data, encoding: .utf8) ?? "unknown")
        }

        struct TR: Decodable { let access_token: String; let refresh_token: String? }
        let tr = try JSONDecoder().decode(TR.self, from: data)
        guard let refresh = tr.refresh_token else { throw AuthError.noRefreshToken }
        return (tr.access_token, refresh)
    }

    // MARK: - Drive

    func findOrCreateFlowDataFolder(accessToken: String) async throws -> String {
        // Search for existing "Flow-Data" folder
        var comp = URLComponents(string: "https://www.googleapis.com/drive/v3/files")!
        comp.queryItems = [
            URLQueryItem(name: "q", value: "name = 'Flow-Data' and mimeType = 'application/vnd.google-apps.folder' and trashed = false"),
            URLQueryItem(name: "fields", value: "files(id,name)")
        ]
        var req = URLRequest(url: comp.url!)
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (searchData, _) = try await URLSession.shared.data(for: req)
        struct ListResp: Decodable { struct F: Decodable { let id: String }; let files: [F] }
        let list = try JSONDecoder().decode(ListResp.self, from: searchData)
        if let existing = list.files.first { return existing.id }

        // Create folder
        var createReq = URLRequest(url: URL(string: "https://www.googleapis.com/drive/v3/files")!)
        createReq.httpMethod = "POST"
        createReq.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        createReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
        createReq.httpBody = try JSONSerialization.data(withJSONObject: [
            "name": "Flow-Data",
            "mimeType": "application/vnd.google-apps.folder"
        ])

        let (createData, createResp) = try await URLSession.shared.data(for: createReq)
        guard let http = createResp as? HTTPURLResponse, http.statusCode == 200 else {
            throw AuthError.driveFailed(String(data: createData, encoding: .utf8) ?? "create failed")
        }
        struct FileResp: Decodable { let id: String }
        return try JSONDecoder().decode(FileResp.self, from: createData).id
    }
}

private final class ContinuationResumer<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var cont: CheckedContinuation<T, Error>?

    func set(_ cont: CheckedContinuation<T, Error>) {
        lock.lock(); defer { lock.unlock() }
        self.cont = cont
    }

    func succeed(_ value: T) {
        lock.lock(); let c = cont; cont = nil; lock.unlock()
        c?.resume(returning: value)
    }

    func fail(_ error: Error) {
        lock.lock(); let c = cont; cont = nil; lock.unlock()
        c?.resume(throwing: error)
    }
}
