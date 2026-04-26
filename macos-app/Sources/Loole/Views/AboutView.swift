import SwiftUI
import AppKit

struct AboutView: View {
    private var versionText: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "Version \(v) · Build \(b)"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                // Header
                HStack(spacing: 16) {
                    Image("Loole", bundle: .module)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 72, height: 72)
                        .cornerRadius(16)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Loole")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                        Text(versionText)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(.tertiary)
                        Text("A SOCKS5 proxy that tunnels traffic through Google Drive.")
                            .foregroundStyle(.secondary)
                            .font(.system(size: 13))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                }

                // Two-column row: Credits + What's inside
                HStack(alignment: .top, spacing: 16) {
                    Card {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Credits")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Text("macOS client by g3ntrix")
                                .font(.system(size: 13, weight: .medium))
                            Link("Telegram: @g3ntrix",
                                 destination: URL(string: "https://t.me/g3ntrix")!)
                                .font(.system(size: 13, weight: .medium))
                            Link("Upstream: FlowDriver",
                                 destination: URL(string: "https://github.com/masterking32/MasterHttpRelayVPN")!)
                                .font(.system(size: 13, weight: .medium))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Card {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("What's inside")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                            BulletRow(icon: "shippingbox",
                                      text: "Bundled Go core (loole-client / loole-server). No external install required.")
                            BulletRow(icon: "folder.badge.gearshape",
                                      text: "Credentials stored under ~/Library/Application Support/Loole/.")
                            BulletRow(icon: "network",
                                      text: "Traffic tunnelled through a Google Drive folder shared between client and server.")
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                // Donations full-width
                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Donations")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                        DonationRow(label: "TON",          address: "UQCriHkMUa6h9oN059tyC23T13OsQhGGM3hUS2S4IYRBZgvx")
                        DonationRow(label: "USDT (BEP20)", address: "0x71F41696c60C4693305e67eE3Baa650a4E3dA796")
                        DonationRow(label: "TRX (TRON)",   address: "TFrCzU7bDey9WSh3fhqCBqhaiMzr8VhcUV")
                    }
                }

                Spacer(minLength: 12)
            }
            .padding(32)
        }
    }
}

private struct BulletRow: View {
    let icon: String
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(.accentColor)
                .frame(width: 18)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct DonationRow: View {
    let label: String
    let address: String
    @State private var copied = false

    var body: some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.system(size: 12, weight: .bold))
                .frame(width: 90, alignment: .leading)
            Text(verbatim: address)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(copied ? "Copied" : "Copy") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(address, forType: .string)
                copied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }
}
