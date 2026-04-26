import SwiftUI
import Combine

@main
struct LooleApp: App {
    @StateObject private var appState = AppState()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 800, idealWidth: 880, minHeight: 540, idealHeight: 820)
                .preferredColorScheme(.dark)
                .onAppear {
                    delegate.setup(appState)
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.automatic)
        .defaultSize(width: 880, height: 820)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    var appState: AppState?
    var statusItem: NSStatusItem?
    var popover = NSPopover()
    private var eventMonitor: Any?
    private var statusCancellable: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
    }

    func setup(_ state: AppState) {
        self.appState = state
        statusCancellable = state.$status
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateMenuBarIcon() }
        refreshPopover()
        updateMenuBarIcon()
    }

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.action = #selector(togglePopover)
            button.target = self
        }
        popover.behavior = .transient
        updateMenuBarIcon()
        refreshPopover()
    }

    private func refreshPopover() {
        guard let state = appState else { return }
        let view = MenuBarView(onOpenMain: { [weak self] in
            self?.closePopover()
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first?.makeKeyAndOrderFront(nil)
        })
        .environmentObject(state)

        if let hc = popover.contentViewController as? NSHostingController<AnyView> {
            hc.rootView = AnyView(view)
        } else {
            popover.contentViewController = NSHostingController(rootView: AnyView(view))
        }
    }

    func updateMenuBarIcon() {
        let running = appState?.status.isRunning ?? false
        guard let button = statusItem?.button else { return }

        let img = NSImage(systemSymbolName: "dot.radiowaves.left.and.right",
                          accessibilityDescription: "Loole")
        img?.isTemplate = true
        button.image = img
        // Tint blue when connected, default (adaptive gray) when idle.
        button.contentTintColor = running ? .systemBlue : nil
    }

    @objc func togglePopover() {
        if popover.isShown { closePopover() } else { showPopover() }
    }

    private func showPopover() {
        guard let button = statusItem?.button else { return }
        refreshPopover()
        popover.contentSize = NSSize(width: 240, height: 200)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            if self?.popover.isShown == true { self?.closePopover() }
        }
    }

    private func closePopover() {
        popover.performClose(nil)
        if let m = eventMonitor { NSEvent.removeMonitor(m); eventMonitor = nil }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let state = appState, state.status.isRunning {
            if state.settings.useSystemProxy { SystemProxy.disableSync() }
            Task { await state.stop() }
            Thread.sleep(forTimeInterval: 0.4)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
