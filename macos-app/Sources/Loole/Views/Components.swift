import SwiftUI

// MARK: - Card

struct Card<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        content
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(.white.opacity(0.1), lineWidth: 1)
                    )
            )
    }
}

// MARK: - StatusDot

struct StatusDot: View {
    let color: Color
    var animated: Bool = false
    @State private var pulsing = false

    var body: some View {
        ZStack {
            if animated {
                Circle().fill(color.opacity(0.25))
                    .frame(width: 20, height: 20)
                    .scaleEffect(pulsing ? 1.6 : 1.0)
                    .opacity(pulsing ? 0 : 0.6)
                    .animation(.easeOut(duration: 1.2).repeatForever(autoreverses: false), value: pulsing)
            }
            Circle().fill(color).frame(width: 10, height: 10)
        }
        .onAppear { if animated { pulsing = true } }
    }
}

// MARK: - CopyButton

struct CopyButton: View {
    let text: String
    @State private var copied = false

    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            withAnimation { copied = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                withAnimation { copied = false }
            }
        } label: {
            Label(copied ? "Copied!" : "Copy",
                  systemImage: copied ? "checkmark" : "doc.on.doc")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(copied ? Color.green : Color.accentColor)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - CodeBlock

struct CodeBlock: View {
    let label: String
    let code: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(label)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
                CopyButton(text: code)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(.white.opacity(0.04))

            Divider().opacity(0.2)

            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.black.opacity(0.4)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(.white.opacity(0.08), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - Step indicator

struct StepIndicator: View {
    let current: Int
    let total: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<total, id: \.self) { i in
                Capsule()
                    .fill(i <= current ? Color.accentColor : Color.white.opacity(0.12))
                    .frame(height: 4)
                    .animation(.easeInOut(duration: 0.25), value: current)
            }
        }
    }
}

// MARK: - Background

struct AppBackground: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color(.sRGB, red: 0.05, green: 0.06, blue: 0.11, opacity: 1),
                Color(.sRGB, red: 0.08, green: 0.10, blue: 0.16, opacity: 1)
            ],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}

// MARK: - WindowAccessor (transparent titlebar)

struct WindowAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async {
            if let w = v.window {
                w.titlebarAppearsTransparent = true
                w.titleVisibility = .hidden
                w.isMovableByWindowBackground = true
                w.styleMask.insert(.fullSizeContentView)
            }
        }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

// MARK: - PrimaryButton

struct PrimaryButton: View {
    let title: String
    let icon: String
    var disabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 13, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
        }
        .buttonStyle(.borderedProminent)
        .tint(.accentColor)
        .disabled(disabled)
    }
}
