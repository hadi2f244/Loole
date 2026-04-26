import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var app: AppState
    var onOpenMain: (() -> Void)?
    @State private var isToggling = false

    var body: some View {
        VStack(spacing: 0) {

            // ── Header: identity + status ──────────────────────────
            HStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 36, height: 36)
                    .cornerRadius(8)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Loole")
                        .font(.system(size: 13, weight: .bold))
                    HStack(spacing: 5) {
                        StatusDot(color: statusColor, animated: app.status.isRunning)
                        Text(app.status.label)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 12)

            Divider()

            // ── Primary action: Connect / Disconnect ───────────────
            Button {
                guard !isToggling else { return }
                isToggling = true
                Task {
                    if app.status.isRunning { await app.stop() }
                    else { await app.start() }
                    isToggling = false
                }
            } label: {
                HStack(spacing: 0) {
                    if isToggling || app.status.isTransitioning {
                        ProgressView()
                            .controlSize(.small)
                            .frame(maxWidth: .infinity)
                    } else {
                        HStack(spacing: 7) {
                            Image(systemName: app.status.isRunning ? "stop.circle.fill" : "play.circle.fill")
                                .font(.system(size: 14, weight: .medium))
                            Text(app.status.isRunning ? "Disconnect" : "Connect")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .foregroundStyle(app.status.isRunning ? Color.red : Color.accentColor)
                .frame(height: 40)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(app.status.isRunning
                              ? Color.red.opacity(0.12)
                              : Color.accentColor.opacity(0.12))
                )
            }
            .buttonStyle(.plain)
            .disabled(isToggling || app.status.isTransitioning)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()

            // ── Secondary: System Proxy toggle ─────────────────────
            HStack(spacing: 10) {
                Image(systemName: "network")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                Text("System Proxy")
                    .font(.system(size: 12))
                Spacer()
                Toggle("", isOn: Binding(
                    get: { app.settings.useSystemProxy },
                    set: { on in Task { await app.setSystemProxy(on) } }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.mini)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)

            Divider()

            // ── Footer: app-level actions ──────────────────────────
            HStack(spacing: 0) {
                footerRow(label: "Open App", icon: "macwindow") {
                    onOpenMain?()
                }
                Divider().frame(height: 20)
                footerRow(label: "Quit", icon: "power", tint: .red) {
                    NSApplication.shared.terminate(nil)
                }
            }
            .padding(.bottom, 2)
        }
        .frame(width: 260)
        .preferredColorScheme(.dark)
    }

    private func footerRow(label: String, icon: String, tint: Color = .primary, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Spacer()
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundStyle(tint == .primary ? .secondary : tint)
                    .frame(width: 16)
                Text(label)
                    .font(.system(size: 12))
                    .foregroundStyle(tint)
                Spacer()
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var statusColor: Color {
        switch app.status {
        case .running:             return .green
        case .starting, .stopping: return .yellow
        case .error:               return .orange
        case .stopped:             return Color.white.opacity(0.3)
        }
    }
}
