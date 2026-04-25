import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var app: AppState
    @State private var isToggling = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                connectionCard
                proxyCard
                statsCard
            }
            .padding(24)
        }
    }

    // MARK: - Connection card

    private var connectionCard: some View {
        Card {
            VStack(spacing: 20) {
                // Status indicator
                HStack(spacing: 12) {
                    StatusDot(
                        color: statusColor,
                        animated: app.status.isRunning
                    )
                    VStack(alignment: .leading, spacing: 2) {
                        Text(app.status.label)
                            .font(.system(size: 14, weight: .semibold))
                        if let started = app.startedAt, app.status.isRunning {
                            Text("Since " + started.formatted(date: .omitted, time: .shortened))
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if case .error = app.status {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }

                // Big connect button
                Button {
                    guard !isToggling else { return }
                    isToggling = true
                    Task {
                        if app.status.isRunning {
                            await app.stop()
                        } else {
                            await app.start()
                        }
                        isToggling = false
                    }
                } label: {
                    HStack(spacing: 8) {
                        if app.status.isTransitioning || isToggling {
                            ProgressView().controlSize(.small)
                                .colorScheme(.dark)
                        } else {
                            Image(systemName: app.status.isRunning ? "stop.fill" : "play.fill")
                        }
                        Text(app.status.isRunning ? "Disconnect" : "Connect")
                            .font(.system(size: 14, weight: .bold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .tint(app.status.isRunning ? Color.red.opacity(0.8) : Color.accentColor)
                .disabled(app.status.isTransitioning || isToggling)

                // SOCKS5 address info
                if app.status.isRunning {
                    HStack {
                        Image(systemName: "network").font(.system(size: 11)).foregroundStyle(.secondary)
                        Text("SOCKS5 proxy: **\(app.settings.listenAddr)**")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Spacer()
                        CopyButton(text: app.settings.listenAddr)
                    }
                }
            }
        }
    }

    // MARK: - Proxy card

    private var proxyCard: some View {
        Card {
            HStack(spacing: 12) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 18))
                    .foregroundStyle(app.settings.useSystemProxy ? Color.accentColor : Color.secondary)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Route all Mac traffic")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Sets system-wide SOCKS5 proxy so every app uses the tunnel.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { app.settings.useSystemProxy },
                    set: { on in Task { await app.setSystemProxy(on) } }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
            }
        }
    }

    // MARK: - Stats card

    private var statsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("Configuration")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                statRow(label: "Listen address", value: app.settings.listenAddr)
                statRow(label: "Poll rate", value: "\(app.settings.refreshRateMs) ms")
                statRow(label: "Flush rate", value: "\(app.settings.flushRateMs) ms")
                statRow(label: "Drive folder", value: app.settings.folderID.isEmpty ? "—" : String(app.settings.folderID.prefix(20)) + "…")
            }
        }
    }

    private func statRow(label: String, value: String) -> some View {
        HStack {
            Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.system(size: 11, design: .monospaced)).foregroundStyle(.primary)
        }
    }

    private var statusColor: Color {
        switch app.status {
        case .running:  return .green
        case .starting, .stopping: return .yellow
        case .error:    return .orange
        case .stopped:  return Color.white.opacity(0.25)
        }
    }
}
