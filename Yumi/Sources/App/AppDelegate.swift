import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    private(set) var islandController: IslandWindowController?
    private var core: YumiCore?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Ignore SIGPIPE — prevents crash when the hook script closes socket before we write response
        signal(SIGPIPE, SIG_IGN)
        // Warm up Keychain cache on main thread BEFORE any poller or view touches it
        _ = KeychainStore.shared
        NSApp.setActivationPolicy(.accessory)
        setupMenuBarItem()
        setupIsland()
    }

    // MARK: - Menu bar

    private func setupMenuBarItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem?.button else { return }
        button.image = NSImage(named: "MenuBarIcon") ?? NSImage(systemSymbolName: "circle.fill", accessibilityDescription: AppIdentity.productName)
        button.image?.size = NSSize(width: 24, height: 18)
        button.image?.accessibilityDescription = AppIdentity.productName
        button.image?.isTemplate = true

        let menu = NSMenu()
        menu.addItem(withTitle: "Open \(AppIdentity.productName)", action: #selector(openIsland), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        statusItem?.menu = menu
    }

    // MARK: - Actions

    @objc private func openIsland() {
        islandController?.expand(to: .overview)
    }

    private var settingsWindow: NSWindow?

    @objc private func openSettings() {
        if let w = settingsWindow, w.isVisible { w.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 540),
                           styleMask: [.titled, .closable], backing: .buffered, defer: false)
        win.title = "\(AppIdentity.productName) Settings"
        win.contentView = NSHostingView(rootView: SettingsView())
        win.center()
        win.isReleasedWhenClosed = false
        settingsWindow = win
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Island setup

    private func setupIsland() {
        islandController = IslandWindowController()
        islandController?.showWindow(nil)
        islandController?.fsm.launch()
        let core = YumiCore(state: .shared)
        core.start()
        self.core = core
        IntegrationPollers.sync(active: AppState.shared.activeIntegrations)
        NotificationCenter.default.addObserver(self, selector: #selector(openSettings),
                                               name: .openFullSettings, object: nil)
    }
}

// MARK: - Core
// Composition root of everything that feeds the island: the event engine, the session store,
// the modules and the hook server. Nothing here is a singleton; the pieces are created once
// and handed to each other.

@MainActor
final class YumiCore {
    /// A session silent for this long is considered gone (terminal killed without a SessionEnd).
    private static let sessionLifetime: TimeInterval = 12 * 3600

    private let engine = EventEngine()
    private let store = SessionStore()
    private let ingress: EventIngress
    private let mirror: ClaudeTaskMirror
    let modules: ModuleRegistry

    private var lastSeen: [SessionID: Date] = [:]
    private var consumer: Task<Void, Never>?

    init(state: AppState) {
        ingress = EventIngress(engine: engine)
        let mirror = ClaudeTaskMirror(state: state)
        self.mirror = mirror
        modules = ModuleRegistry(
            modules: [
                ClaudeCodeModule(onShow: { mirror.show() }),
                AgendaModule(),
                NotesModule(),
                FocusModule(),
            ],
            onPublish: { state.modules = $0 }
        )
    }

    func start() {
        modules.start()
        consumer = Task { [engine, store, ingress, weak self] in
            // Subscribe before the socket opens: the engine does not keep events for later.
            let events = await engine.subscribe()
            HookServer.shared.start(ingress: ingress)
            for await event in events {
                let sessions = await store.apply(event)
                guard let self else { return }
                self.mirror.receive(event, sessions: sessions)
                self.modules.receive(event, sessions: sessions)
                self.endSilentSessions(after: event, in: sessions)
            }
        }
    }

    /// Sessions normally end with a hook. One that has said nothing for hours is dropped,
    /// unless it is waiting for the user. Checked when an event arrives: no timer needed.
    private func endSilentSessions(after event: YumiEvent, in sessions: [SessionID: Session]) {
        let now = Date()
        if let id = event.sessionID { lastSeen[id] = sessions[id] == nil ? nil : now }
        for (id, seen) in lastSeen where now.timeIntervalSince(seen) > Self.sessionLifetime {
            lastSeen[id] = nil
            if let session = sessions[id], session.status != .waitingForUser {
                ingress.post(.sessionEnded(id))
            }
        }
    }
}
