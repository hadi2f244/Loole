import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var app: AppState

    @State private var draft = AppSettings.default
    @State private var portString = "1080"
    @State private var pollString = "200"
    @State private var flushString = "300"
    @State private var lanIP: String? = nil
    @State private var saved = false

    private var isRunning: Bool { app.status.isRunning }
    private var hasChanges: Bool { draft != app.settings }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {

                // MARK: Network
                section("Network") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("SOCKS5 Listen Mode")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)

                        HStack(spacing: 0) {
                            modeButton(label: "Local", selected: draft.listenHost == "127.0.0.1") {
                                draft.listenHost = "127.0.0.1"
                            }
                            modeButton(label: "LAN", selected: draft.listenHost == "0.0.0.0") {
                                draft.listenHost = "0.0.0.0"
                                if lanIP == nil { lanIP = AppState.getLANIPAddress() }
                            }
                        }
                        .background(Color.white.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1))

                        if draft.listenHost == "0.0.0.0" {
                            HStack(spacing: 6) {
                                Image(systemName: "wifi")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color.accentColor)
                                Text("Your LAN IP:")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                Text(lanIP ?? "N/A")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.white)
                            }
                            Text("Other devices on your network can use this address as their SOCKS5 proxy.")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Only this Mac can use the proxy.")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Divider().opacity(0.15).padding(.vertical, 4)

                    settingRow(label: "SOCKS5 Port") {
                        TextField("1080", text: $portString)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 90)
                            .font(.system(size: 12, design: .monospaced))
                            .onChange(of: portString) { v in
                                if let n = Int(v), (1...65535).contains(n) { draft.listenPort = n }
                            }
                    }
                }

                // MARK: Timing
                section("Timing") {
                    settingRow(label: "Poll Rate") {
                        HStack(spacing: 6) {
                            TextField("200", text: $pollString)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 80)
                                .font(.system(size: 12, design: .monospaced))
                                .onChange(of: pollString) { v in
                                    if let n = Int(v), n > 0 { draft.refreshRateMs = n }
                                }
                            Text("ms").font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                    }

                    settingRow(label: "Flush Rate") {
                        HStack(spacing: 6) {
                            TextField("300", text: $flushString)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 80)
                                .font(.system(size: 12, design: .monospaced))
                                .onChange(of: flushString) { v in
                                    if let n = Int(v), n > 0 { draft.flushRateMs = n }
                                }
                            Text("ms").font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                    }

                    Text("Lower poll/flush rates reduce latency but increase Drive API calls. Defaults (200/300 ms) work well for most setups.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                }

                // MARK: Save
                HStack {
                    if isRunning {
                        Label("Stop the tunnel before changing settings.", systemImage: "lock")
                            .font(.system(size: 11))
                            .foregroundStyle(.orange)
                    }
                    Spacer()
                    Button(saved ? "Saved" : "Save") { saveDraft() }
                        .buttonStyle(.borderedProminent)
                        .tint(saved ? .green : .accentColor)
                        .disabled(isRunning || !hasChanges)
                }
                .padding(.top, 4)

                Spacer(minLength: 20)
            }
            .padding(32)
        }
        .onAppear { loadDraft() }
    }

    // MARK: - Helpers

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
            Card {
                VStack(alignment: .leading, spacing: 14) {
                    content()
                }
            }
        }
    }

    private func settingRow<Control: View>(label: String, @ViewBuilder control: () -> Control) -> some View {
        HStack {
            Text(label).font(.system(size: 12)).foregroundStyle(.secondary)
            Spacer()
            control()
        }
    }

    private func modeButton(label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12, weight: selected ? .semibold : .regular))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(selected ? Color.accentColor.opacity(0.2) : Color.clear)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(selected ? Color.accentColor : .secondary)
    }

    private func loadDraft() {
        draft       = app.settings
        portString  = "\(app.settings.listenPort)"
        pollString  = "\(app.settings.refreshRateMs)"
        flushString = "\(app.settings.flushRateMs)"
        lanIP       = AppState.getLANIPAddress()
    }

    private func saveDraft() {
        app.settings = draft
        app.saveSettings()
        withAnimation { saved = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            withAnimation { saved = false }
        }
    }
}
