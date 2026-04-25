import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var app: AppState
    var onOpenMain: (() -> Void)?
    @State private var isToggling = false

    var body: some View {
        VStack(spacing: 0) {
            // Status header
            HStack(spacing: 10) {
                StatusDot(color: statusColor, animated: app.status.isRunning)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Loole")
                        .font(.system(size: 13, weight: .semibold))
                    Text(app.status.label)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    onOpenMain?()
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            Divider().opacity(0.3)

            // Connect toggle
            Button {
                guard !isToggling else { return }
                isToggling = true
                Task {
                    if app.status.isRunning { await app.stop() }
                    else { await app.start() }
                    isToggling = false
                }
            } label: {
                HStack(spacing: 8) {
                    if isToggling || app.status.isTransitioning {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: app.status.isRunning ? "stop.circle" : "play.circle")
                            .font(.system(size: 15))
                    }
                    Text(app.status.isRunning ? "Disconnect" : "Connect")
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(app.status.isRunning ? Color.red : Color.accentColor)
            .disabled(isToggling || app.status.isTransitioning)

            // System proxy toggle
            HStack {
                Label("System proxy", systemImage: "arrow.triangle.2.circlepath")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
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
            .padding(.vertical, 6)

            Divider().opacity(0.3)

            Button("Quit Loole") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .frame(width: 240)
        .background(.ultraThinMaterial)
        .preferredColorScheme(.dark)
    }

    private var statusColor: Color {
        switch app.status {
        case .running:  return .green
        case .starting, .stopping: return .yellow
        case .error:    return .orange
        case .stopped:  return Color.white.opacity(0.3)
        }
    }
}
