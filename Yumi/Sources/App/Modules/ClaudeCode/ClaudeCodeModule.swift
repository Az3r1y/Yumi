import AppKit

/// Claude Code, as a module: every session of every terminal, the one that needs you first.
@MainActor
final class ClaudeCodeModule: YumiModule {
    let id = "claude-code"

    private var sessions: [Session] = []
    /// The list of the activity view: every session, a finished one for a moment more.
    private var board = SessionBoard()
    /// Wakes the module when a finished session leaves the list.
    private var departure: Task<Void, Never>?
    private var rowObserver: NSObjectProtocol?
    private var onChange: (@MainActor () -> Void)?
    /// Shows the sessions in the island (the pending approval if there is one).
    private let onShow: @MainActor () -> Void

    /// True when Claude Code is on the Mac but Yumi's hooks are not in its settings: Yumi sees
    /// no session. Read when the module starts and after each install.
    private let hooksMissing: @MainActor () -> Bool
    /// Opens the settings on the hooks, where the change is shown before anything is written.
    private let onInstallHooks: @MainActor () -> Void
    private var missing = false

    init(onShow: @escaping @MainActor () -> Void, hooksMissing: @escaping @MainActor () -> Bool = { false },
         onInstallHooks: @escaping @MainActor () -> Void = {}) {
        self.onShow = onShow
        self.hooksMissing = hooksMissing
        self.onInstallHooks = onInstallHooks
    }

    /// What the chat is doing, while it answers through Claude Code; nil when it is idle.
    private var chat: ChatAnnouncement?

    var snapshot: ModuleSnapshot {
        var snapshot = ClaudeSessions.snapshot(sessions, hooksMissing: missing)
        snapshot.rows = board.rows()
        // A session waiting for the user stays ahead of the chat's own activity.
        if snapshot.live == nil, let chat {
            snapshot.live = ModuleLive(text: chat.text,
                                       priority: chat.needsUser ? ModuleLivePriority.attention : ModuleLivePriority.activity)
        }
        return snapshot
    }

    /// Tells the folded island what the chat is doing. Pass nil when the answer is complete.
    func announceChat(_ announcement: ChatAnnouncement?) {
        guard announcement != chat else { return }
        chat = announcement
        onChange?()
    }

    func start(onChange: @escaping @MainActor () -> Void) {
        self.onChange = onChange
        missing = hooksMissing()
        rowObserver = NotificationCenter.default.addObserver(forName: .moduleRowAction, object: nil, queue: .main) { [weak self] note in
            guard note.userInfo?["module"] as? String == "claude-code", let row = note.userInfo?["row"] as? String else { return }
            MainActor.assumeIsolated { self?.open(row) }
        }
    }

    func stop() {
        onChange = nil
        sessions = []
        board = SessionBoard()
        chat = nil
        departure?.cancel()
        departure = nil
        if let rowObserver { NotificationCenter.default.removeObserver(rowObserver) }
        rowObserver = nil
    }

    func receive(_ event: YumiEvent, sessions: [SessionID: Session]) {
        let ordered = ClaudeSessions.ordered(sessions)
        guard ordered != self.sessions else { return }
        self.sessions = ordered
        board.update(ordered)
        scheduleDeparture()
        onChange?()
    }

    /// A finished session leaves the list on its own, without waiting for another event.
    private func scheduleDeparture() {
        departure?.cancel()
        guard let next = board.nextDeparture() else { return departure = nil }
        departure = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(1, next.timeIntervalSinceNow)), tolerance: .seconds(5))
            guard !Task.isCancelled, let self else { return }
            self.board.update(self.sessions)
            self.scheduleDeparture()
            self.onChange?()
        }
    }

    /// A line of the list was clicked: the application its session runs in comes forward.
    private func open(_ row: String) {
        Self.bringToFront(board.session(row)?.origin)
    }

    func perform(_ action: ModuleAction) {
        switch action {
        case .primary where missing && sessions.isEmpty:
            onInstallHooks()
            missing = hooksMissing()
        case .primary:
            // A pending approval is answered in the island. Otherwise "Voir" goes where the
            // conversation is: the application the session runs in, whichever it is.
            let approvalPending = sessions.contains {
                if case .requestingPermission = $0.activity { return true }
                return false
            }
            if approvalPending || !Self.bringToFront(sessions.first?.origin) { onShow() }
        case .secondary:
            Self.bringToFront(sessions.first?.origin)
        }
    }

    /// Brings the application a session runs in to the front. An editor reopens the project folder,
    /// which focuses the right window when several are open. Returns false when the host is unknown.
    @discardableResult
    static func bringToFront(_ origin: SessionOrigin?) -> Bool {
        guard let origin, let bundleID = SessionHost.bundleID(for: origin) else { return false }
        let workspace = NSWorkspace.shared
        if SessionHost.isEditor(origin), !origin.workingDirectory.isEmpty,
           let application = workspace.urlForApplication(withBundleIdentifier: bundleID) {
            workspace.open([URL(fileURLWithPath: origin.workingDirectory)], withApplicationAt: application,
                           configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
        } else if let running = workspace.runningApplications.first(where: { $0.bundleIdentifier == bundleID }) {
            running.activate()
        } else if let application = workspace.urlForApplication(withBundleIdentifier: bundleID) {
            workspace.openApplication(at: application, configuration: NSWorkspace.OpenConfiguration(),
                                      completionHandler: nil)
        } else {
            return false
        }
        return true
    }
}

/// One line about the chat's answer in progress, for the folded island.
struct ChatAnnouncement: Equatable, Sendable {
    /// "Écrit bonjour.txt", "Lance swift test", "Yumi répond".
    var text: String
    /// True while the chat waits for a permission.
    var needsUser = false

    init?(_ live: ChatLive?) {
        guard let live else { return nil }
        text = ChatLiveTracker.headline(live)
        needsUser = live.activity?.kind == .waiting
    }
}
