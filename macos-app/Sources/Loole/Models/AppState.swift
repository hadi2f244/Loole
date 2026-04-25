import Foundation
import Combine

@MainActor
final class AppState: ObservableObject {

    // MARK: - Connection status

    enum Status: Equatable {
        case stopped
        case starting
        case running
        case stopping
        case error(String)

        var isRunning: Bool { if case .running = self { return true }; return false }
        var isTransitioning: Bool {
            switch self { case .starting, .stopping: return true; default: return false }
        }
        var label: String {
            switch self {
            case .stopped:        return "Not connected"
            case .starting:       return "Connecting…"
            case .running:        return "Connected"
            case .stopping:       return "Disconnecting…"
            case .error(let msg): return "Error: \(msg)"
            }
        }
    }

    // MARK: - Wizard step

    enum WizardStep: Int, Comparable {
        case credentials = 0
        case authorize   = 1
        case serverSetup = 2

        static func < (lhs: WizardStep, rhs: WizardStep) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    // MARK: - Published

    @Published var settings: AppSettings
    @Published var status: Status = .stopped
    @Published var logs: [LogLine] = []
    @Published var startedAt: Date?
    @Published var wizardStep: WizardStep = .credentials
    @Published var isWizardComplete: Bool = false

    private let store = ConfigStore()
    private let core  = CoreManager()

    init() {
        let loaded = ConfigStore().loadSettings() ?? .default
        self.settings = loaded
        self.isWizardComplete = loaded.setupComplete

        core.onLog = { [weak self] line in
            Task { @MainActor in self?.appendLog(line) }
        }
        core.onStatus = { [weak self] s in
            Task { @MainActor in self?.status = s }
        }
    }

    // MARK: - Start / Stop

    func start() async {
        guard !settings.folderID.isEmpty else {
            status = .error("Complete the setup wizard first.")
            return
        }
        store.saveSettings(settings)
        status = .starting
        startedAt = Date()
        do {
            try await core.start(settings: settings, credentialsURL: store.credentialsURL)
            if settings.useSystemProxy {
                await applySystemProxy(true)
            }
        } catch {
            status = .error(error.localizedDescription)
            startedAt = nil
            await core.stop()
        }
    }

    func stop() async {
        status = .stopping
        if settings.useSystemProxy {
            await applySystemProxy(false)
        }
        await core.stop()
        startedAt = nil
    }

    // MARK: - System proxy

    func setSystemProxy(_ on: Bool) async {
        settings.useSystemProxy = on
        store.saveSettings(settings)
        guard status.isRunning else { return }
        await applySystemProxy(on)
    }

    private func applySystemProxy(_ on: Bool) async {
        let result: SystemProxy.Result
        if on {
            let host = settings.socksHost == "0.0.0.0" ? "127.0.0.1" : settings.socksHost
            result = await SystemProxy.enable(host: host, port: settings.socksPort)
        } else {
            result = await SystemProxy.disable()
        }
        if case .failed(let msg) = result {
            appendLog(LogLine(stream: .system, text: "⚠ System proxy: \(msg)\n"))
        }
    }

    // MARK: - Settings

    func saveSettings() { store.saveSettings(settings) }

    func completeWizard() {
        settings.setupComplete = true
        store.saveSettings(settings)
        isWizardComplete = true
    }

    // MARK: - Logs

    func appendLog(_ line: LogLine) {
        if logs.count > 3000 { logs.removeFirst(500) }
        logs.append(line)
    }

    func clearLogs() { logs.removeAll() }
}

struct LogLine: Identifiable, Equatable {
    let id = UUID()
    let timestamp = Date()
    let stream: Stream
    let text: String
    enum Stream { case stdout, stderr, system }
}
