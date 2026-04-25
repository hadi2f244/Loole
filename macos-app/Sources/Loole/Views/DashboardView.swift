import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var app: AppState
    @State private var isToggling = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header with Logo
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(LinearGradient(colors: [.accentColor, .blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 48, height: 48)
                        Image(systemName: "dot.radiowaves.left.and.right")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.white)
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Loole")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                        Text("Secure Data Flow")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.bottom, 8)

                connectionCard
                proxyCard
                statsCard
            }
            .padding(32)
        }
    }

    // MARK: - Connection card

    private var connectionCard: some View {
        Card {
            VStack(spacing: 24) {
                // Status indicator
                HStack(spacing: 12) {
                    StatusDot(
                        color: statusColor,
                        animated: app.status.isRunning
                    )
                    VStack(alignment: .leading, spacing: 2) {
                        Text(app.status.label)
                            .font(.system(size: 16, weight: .bold))
                        if let started = app.startedAt, app.status.isRunning {
                            Text("Active for " + started.formatted(date: .omitted, time: .shortened))
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                }

                // Connect Button (Redesigned & Properly Sized)
                Button {
                    guard !isToggling else { return }
                    isToggling = true
                    Task {
                        if app.status.isRunning { await app.stop() }
                        else { await app.start() }
                        isToggling = false
                    }
                } label: {
                    HStack(spacing: 10) {
                        if app.status.isTransitioning || isToggling {
                            ProgressView().controlSize(.small).colorScheme(.dark)
                        } else {
                            Image(systemName: app.status.isRunning ? "power" : "power")
                                .font(.system(size: 18, weight: .bold))
                        }
                        Text(app.status.isRunning ? "STOP VPN" : "START VPN")
                            .font(.system(size: 13, weight: .heavy))
                    }
                    .frame(width: 180)
                    .padding(.vertical, 14)
                    .background(
                        Capsule()
                            .fill(app.status.isRunning ? 
                                 LinearGradient(colors: [.red, .orange], startPoint: .topLeading, endPoint: .bottomTrailing) :
                                 LinearGradient(colors: [.accentColor, .blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                    )
                    .foregroundColor(.white)
                    .shadow(color: (app.status.isRunning ? Color.red : Color.accentColor).opacity(0.3), radius: 10, x: 0, y: 4)
                }
                .buttonStyle(.plain)
                .disabled(app.status.isTransitioning || isToggling)
                .scaleEffect(isToggling ? 0.96 : 1.0)
                .animation(.spring(), value: isToggling)

                // SOCKS5 address info
                if app.status.isRunning {
                    HStack {
                        Image(systemName: "lock.shield.fill").font(.system(size: 11)).foregroundStyle(.green)
                        Text("Encrypted Tunnel: **\(app.settings.listenAddr)**")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Spacer()
                        CopyButton(text: app.settings.listenAddr)
                    }
                    .padding(.top, 4)
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
