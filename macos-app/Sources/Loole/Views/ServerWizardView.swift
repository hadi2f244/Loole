import SwiftUI

/// Step 3 of the wizard: package the server binary and give the user deploy commands.
struct ServerWizardView: View {
    var onComplete: (() -> Void)?
    var onBack: (() -> Void)?

    @EnvironmentObject var app: AppState
    @State private var detectedArch: String?
    @State private var serverIP: String = ""
    @State private var serverPassword: String = ""
    @State private var includeSSH = false
    @State private var zipURL: URL?
    @State private var isBuilding = false
    @State private var buildError: String?

    private let store = ConfigStore()

    var body: some View {
        VStack {
            Card {
                VStack(alignment: .leading, spacing: 24) {
                    stepHeader

                    if zipURL == nil {
                        archDetectionSection
                    } else {
                        deploySection
                    }
                }
            }
            .frame(maxWidth: 560)
            .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Header

    private var stepHeader: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Color.accentColor.opacity(0.15)).frame(width: 32, height: 32)
                Text("3").font(.system(size: 14, weight: .bold, design: .rounded)).foregroundStyle(Color.accentColor)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Deploy Loole Server").font(.system(size: 18, weight: .bold))
                Text("The server runs on your VPS and connects to your Drive folder.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Arch detection

    private var archDetectionSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("1. Confirm VPS CPU Architecture")
                .font(.system(size: 13, weight: .bold))

            Text("SSH into your server and run **`uname -m`**, then pick the result below:")
                .font(.system(size: 12)).foregroundStyle(.secondary)

            // Arch selection buttons
            HStack(spacing: 12) {
                archButton(arch: "amd64", label: "x86_64", subtitle: "Most common\n(Intel/AMD)")
                archButton(arch: "arm64", label: "aarch64", subtitle: "ARM64\n(Oracle/Ampere)")
            }

            if let err = buildError {
                Label(err, systemImage: "xmark.circle.fill")
                    .font(.system(size: 11)).foregroundStyle(.red)
            }

            HStack {
                if let back = onBack {
                    Button("← Go Back") { back() }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isBuilding {
                    ProgressView().controlSize(.small)
                    Text("Building bundle…").font(.system(size: 12)).foregroundStyle(.secondary)
                } else {
                    Button("Prepare Server Zip") {
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
            VStack(spacing: 6) {
                Text(label)
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                Text(subtitle)
                    .font(.system(size: 10))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(detectedArch == arch
                          ? Color.accentColor.opacity(0.12)
                          : Color.white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(detectedArch == arch
                                    ? Color.accentColor
                                    : Color.white.opacity(0.1), lineWidth: 1.5)
                    )
            )
        }
        .buttonStyle(.plain)
        .foregroundStyle(detectedArch == arch ? Color.accentColor : Color.primary)
    }

    // MARK: - Deploy section

    private var deploySection: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label("Server package is ready!", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.green)
                Spacer()
                Button("Show in Finder") {
                    if let url = zipURL { ServerPackager.revealInFinder(url) }
                }
                .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Color.accentColor)
            }

            Text("The zip file contains everything your server needs.")
                .font(.system(size: 11)).foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 12) {
                Toggle("Include SSH login in commands", isOn: $includeSSH)
                    .toggleStyle(.switch)
                    .font(.system(size: 12, weight: .medium))

                if includeSSH {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            Image(systemName: "network").font(.system(size: 12)).foregroundStyle(.secondary)
                                .frame(width: 14)
                            Text("Server IP:").font(.system(size: 12)).foregroundStyle(.secondary)
                                .frame(width: 70, alignment: .leading)
                            TextField("e.g. 85.34.12.99", text: $serverIP)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12, design: .monospaced))
                        }
                        
                        if !serverIP.isEmpty && !serverIPValid {
                            Text("Enter a valid IPv4 address")
                                .font(.system(size: 10))
                                .foregroundStyle(.red)
                                .padding(.leading, 100)
                        }
                        
                        HStack(spacing: 10) {
                            Image(systemName: "lock").font(.system(size: 12)).foregroundStyle(.secondary)
                                .frame(width: 14)
                            Text("Password:").font(.system(size: 12)).foregroundStyle(.secondary)
                                .frame(width: 70, alignment: .leading)
                            SecureField("Optional (for sshpass)", text: $serverPassword)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12, design: .monospaced))
                        }
                    }
                    .padding(.bottom, 4)
                }
            }
            .padding(12)
            .background(Color.white.opacity(0.04))
            .cornerRadius(8)

            if let url = zipURL {
                VStack(spacing: 12) {
                    ForEach(ServerPackager.deploymentCommands(zipURL: url, serverIP: serverIP, includeSSH: includeSSH, serverPassword: serverPassword), id: \.label) { step in
                        CodeBlock(label: step.label, code: step.code)
                    }
                }
            }

            Divider().opacity(0.15)

            HStack {
                Button("← Re-package") {
                    zipURL = nil
                    buildError = nil
                }
                .buttonStyle(.plain).foregroundStyle(.secondary)

                Spacer()

                Button("Finish Setup") {
                    onComplete?()
                }
                .buttonStyle(.borderedProminent)
                .tint(.accentColor)
            }
        }
    }

    // MARK: - Validation

    private var serverIPValid: Bool {
        let parts = serverIP.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }
        return parts.allSatisfy { guard let n = Int($0) else { return false }; return (0...255).contains(n) }
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
