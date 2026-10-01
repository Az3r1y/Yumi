import AppKit
import SwiftUI
import Combine

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
        #if DEBUG
        sendDevelopmentChatPrompts()
        #endif
        NotificationCenter.default.addObserver(self, selector: #selector(openSettings),
                                               name: .openFullSettings, object: nil)
    }
}

#if DEBUG
// MARK: - Development: chat without the island
// `YUMI_CHAT_PROMPT` sends its text to the chat a moment after launch ("||" separates several
// messages, sent one after the other) and prints the conversation as it grows. It exercises the
// real path, permission requests in the island included, without typing in the notch.
// `YUMI_CHAT_ANSWERS` ("allow,deny,always") scripts the answers to the permission requests of that
// run, in order: each one presses what the island's buttons press, a second after the request
// appears. Without it the requests wait for a real click. Neither exists in a Release build.

extension AppDelegate {
    private func sendDevelopmentChatPrompts() {
        guard let text = ProcessInfo.processInfo.environment["YUMI_CHAT_PROMPT"], !text.isEmpty else { return }
        let prompts = text.components(separatedBy: "||").map { $0.trimmingCharacters(in: .whitespaces) }
        let state = AppState.shared
        Task { @MainActor in
            var answers = (ProcessInfo.processInfo.environment["YUMI_CHAT_ANSWERS"] ?? "")
                .split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            var printed = 0
            @MainActor func printNew() {
                for message in state.chatHistory.dropFirst(printed) {
                    print("[chat] \(message.role == .user ? "moi" : "yumi") : \(message.content)")
                }
                printed = state.chatHistory.count
                fflush(stdout)
            }
            try? await Task.sleep(for: .seconds(2))
            for prompt in prompts {
                state.chatHistory.append(ChatMessage(role: .user, content: prompt))
                state.noteMessage = nil
                state.stateOverride = .thinking
                let watcher = Task { @MainActor in
                    var last = ""
                    var answered: String?
                    var lastLive: ChatLive?
                    var liveUpdates = 0
                    while !Task.isCancelled {
                        printNew()
                        if let request = state.pendingApproval, ChatSessionRegistry.shared.contains(request.sessionId),
                           answered != request.command, !answers.isEmpty {
                            answered = request.command
                            let answer = answers.removeFirst()
                            Task { @MainActor in
                                try? await Task.sleep(for: .seconds(1))
                                // Still the same request on screen: never answer another one.
                                guard state.pendingApproval?.command == request.command,
                                      state.pendingApproval?.sessionId == request.sessionId else { return }
                                print("[chat] réponse scriptée : \(answer)")
                                HookServer.shared.sendApprovalDecision(answer)
                            }
                        } else if state.pendingApproval == nil {
                            answered = nil
                        }
                        let now = "\(state.effectiveState)\(state.pendingApproval.map { " · demande : \($0.tool) \($0.command)" } ?? "")"
                        if now != last { print("[chat] état : \(now)"); fflush(stdout); last = now }
                        if state.chatLive != lastLive {
                            lastLive = state.chatLive
                            liveUpdates += 1
                            if let live = lastLive {
                                let activity = live.activity.map { "\($0.kind.rawValue) « \($0.label) »\($0.detail.map { " [\($0.replacingOccurrences(of: "\n", with: " ⏎ "))]" } ?? "")" } ?? "aucune"
                                let done = live.done.map { "\($0.label)\($0.succeeded ? "" : " (non)")" }.joined(separator: ", ")
                                print("[live \(liveUpdates)] texte : \(live.text.count) car. · action : \(activity) · faites : [\(done)]")
                            } else {
                                print("[live \(liveUpdates)] nil")
                            }
                            fflush(stdout)
                        }
                        try? await Task.sleep(for: .milliseconds(50))
                    }
                }
                await ClaudeService.shared.chat(query: prompt, context: state.promptContext, state: state)
                watcher.cancel()
                printNew()
                if let note = state.noteMessage { print("[chat] erreur : \(note)") }
                print("[chat] après la réponse, chatLive : \(state.chatLive == nil ? "nil" : "encore renseigné")")
            }
            print("[chat] fin")
            fflush(stdout)
        }
    }
}
#endif

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

    private var chatObserver: AnyCancellable?
    private var lastSeen: [SessionID: Date] = [:]
    private var consumer: Task<Void, Never>?

    init(state: AppState) {
        ingress = EventIngress(engine: engine)
        let mirror = ClaudeTaskMirror(state: state)
        self.mirror = mirror
        let claudeCode = ClaudeCodeModule(onShow: { mirror.show() })
        // The chat answers through Claude Code: its module tells the folded island what it is doing.
        // The text of the answer changes many times a second, the announcement only with the action.
        chatObserver = state.$chatLive
            .map(ChatAnnouncement.init)
            .removeDuplicates()
            .sink { [weak claudeCode] in claudeCode?.announceChat($0) }
        modules = ModuleRegistry(
            modules: [
                claudeCode,
                AgendaModule(),
                NotesModule(),
                FocusModule(),
                MusicModule(),
                WeatherModule(),
            ],
            onPublish: { snapshots in
                state.modules = snapshots
                Self.trace(snapshots)
            }
        )
    }

    /// Debug builds only: with `YUMI_TRACE_MODULES` set, prints the snapshots each time they change.
    private static func trace(_ snapshots: [ModuleSnapshot]) {
        #if DEBUG
        guard ProcessInfo.processInfo.environment["YUMI_TRACE_MODULES"] != nil else { return }
        for snapshot in snapshots {
            let actions = [snapshot.primaryAction, snapshot.secondaryAction].compactMap { $0 }.joined(separator: " | ")
            print("[\(snapshot.name)] \(snapshot.status) · \(snapshot.title) · \(snapshot.subtitle) · \(actions)\(snapshot.needsAttention ? " · !" : "")\(snapshot.live.map { " · en direct (\($0.priority)) : \($0.text)" } ?? "")")
        }
        print("")
        fflush(stdout)
        #endif
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
