import SwiftUI

/// Step 3 of the wizard: package the server binary and give the user deploy commands.
struct ServerWizardView: View {
    var onComplete: (() -> Void)?

    @EnvironmentObject var app: AppState
    @State private var detectedArch: String?
    @State private var serverIP: String = ""
    @State private var zipURL: URL?
    @State private var isBuilding = false
    @State private var buildError: String?

    private let store = ConfigStore()

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 20) {
                stepHeader

                if zipURL == nil {
                    archDetectionSection
                } else {
                    deploySection
                }
            }
        }
    }

    // MARK: - Header

    private var stepHeader: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(Color.accentColor.opacity(0.2)).frame(width: 28, height: 28)
                Text("3").font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle(Color.accentColor)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Set up your server").font(.system(size: 16, weight: .semibold))
                Text("The server runs on your Linux VPS and connects to the same Drive folder.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Arch detection

    private var archDetectionSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("What type of CPU does your server have?")
                .font(.system(size: 13, weight: .semibold))

            Text("SSH into your server and run **`uname -m`** to check, then pick below:")
                .font(.system(size: 12)).foregroundStyle(.secondary)

            CodeBlock(label: "run on server", code: "uname -m")

            // Arch selection buttons
            HStack(spacing: 12) {
                archButton(
                    arch: "amd64",
                    label: "x86_64",
                    subtitle: "Intel / AMD\n(most common)"
                )
                archButton(
                    arch: "arm64",
                    label: "aarch64",
                    subtitle: "ARM64\nOracle Cloud / Ampere"
                )
            }

            if let arch = detectedArch {
                Label("Selected: **\(arch == "amd64" ? "x86_64 (Intel/AMD)" : "aarch64 (ARM64)")**",
                      systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.green)
            }

            Divider().opacity(0.2)

            // Optional server IP
            HStack(spacing: 10) {
                Image(systemName: "network").font(.system(size: 12)).foregroundStyle(.secondary)
                Text("Server IP:")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                TextField("e.g. 192.168.1.10  (optional — for command preview)", text: $serverIP)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11))
            }

            if let err = buildError {
                Label(err, systemImage: "xmark.circle.fill")
                    .font(.system(size: 11)).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                if isBuilding {
                    ProgressView().controlSize(.small)
                    Text("Packaging…").font(.system(size: 12)).foregroundStyle(.secondary)
                } else {
                    Button("Build Server Package") {
                        buildPackage()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.accentColor)
                    .disabled(detectedArch == nil)
                }
            }
        }
    }

    private func archButton(arch: String, label: String, subtitle: String) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) { detectedArch = arch }
        } label: {
            VStack(spacing: 4) {
                Text(label)
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                Text(subtitle)
                    .font(.system(size: 10))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(detectedArch == arch
                          ? Color.accentColor.opacity(0.18)
                          : Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(detectedArch == arch
                                    ? Color.accentColor
                                    : Color.white.opacity(0.12), lineWidth: 1.5)
                    )
            )
        }
        .buttonStyle(.plain)
        .foregroundStyle(detectedArch == arch ? Color.accentColor : Color.primary)
    }

    // MARK: - Deploy section

    private var deploySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Package ready!", systemImage: "checkmark.circle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.green)

            Text("**loole-server.zip** has been saved to your Desktop. It contains the server binary, your credentials, and config.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                if let url = zipURL { ServerPackager.revealInFinder(url) }
            } label: {
                Label("Show in Finder", systemImage: "folder")
                    .font(.system(size: 12, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.bordered)

            Divider().opacity(0.2)

            Text("Copy each command in order:")
                .font(.system(size: 12)).foregroundStyle(.secondary)

            if let url = zipURL {
                VStack(spacing: 10) {
                    ForEach(ServerPackager.deploymentCommands(zipURL: url, serverIP: serverIP), id: \.label) { step in
                        CodeBlock(label: step.label, code: step.code)
                    }
                }
            }

            Text("After the server starts, come back here and click **Done**.")
                .font(.system(size: 11)).foregroundStyle(.secondary)

            HStack {
                Button("← Re-package") {
                    zipURL = nil
                    buildError = nil
                }
                .buttonStyle(.plain).foregroundStyle(.secondary)

                Spacer()

                Button("Done — Go to Dashboard") {
                    onComplete?()
                }
                .buttonStyle(.borderedProminent)
                .tint(.accentColor)
            }
        }
    }

    // MARK: - Build

    private func buildPackage() {
        guard let arch = detectedArch else { return }
        isBuilding = true
        buildError = nil

        Task {
            do {
                let url = try ServerPackager.buildPackage(
                    arch: arch,
                    settings: app.settings,
                    store: store
                )
                await MainActor.run {
                    zipURL = url
                    isBuilding = false
                    ServerPackager.revealInFinder(url)
                }
            } catch {
                await MainActor.run {
                    buildError = error.localizedDescription
                    isBuilding = false
                }
            }
        }
    }
}
