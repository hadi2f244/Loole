import SwiftUI

struct LogsView: View {
    @EnvironmentObject var app: AppState
    @State private var autoScroll = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            toolbar
            Divider().opacity(0.2)
            logList
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var toolbar: some View {
        HStack {
            Text("Logs")
                .font(.system(size: 14, weight: .semibold))
            Spacer()
            Toggle("Auto-scroll", isOn: $autoScroll)
                .toggleStyle(.checkbox)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Button {
                app.clearLogs()
            } label: {
                Label("Clear", systemImage: "trash")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var logList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(app.logs) { line in
                        logRow(line)
                            .id(line.id)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .onChange(of: app.logs.count) { _ in
                if autoScroll, let last = app.logs.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }

    private func logRow(_ line: LogLine) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(line.timestamp.formatted(date: .omitted, time: .standard))
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.secondary.opacity(0.6))
                .frame(width: 68, alignment: .leading)

            Text(line.text.trimmingCharacters(in: .newlines))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(lineColor(line))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 1)
    }

    private func lineColor(_ line: LogLine) -> Color {
        switch line.stream {
        case .system: return Color.accentColor.opacity(0.8)
        case .stderr: return Color.orange
        case .stdout: return Color.white.opacity(0.75)
        }
    }
}
