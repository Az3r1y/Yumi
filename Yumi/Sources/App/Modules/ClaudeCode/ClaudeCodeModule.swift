import AppKit

/// Claude Code, as a module: every session of every terminal, the one that needs you first.
@MainActor
final class ClaudeCodeModule: YumiModule {
    let id = "claude-code"

    private var sessions: [Session] = []
    private var onChange: (@MainActor () -> Void)?
    /// Shows the sessions in the island (the pending approval if there is one).
    private let onShow: @MainActor () -> Void

    init(onShow: @escaping @MainActor () -> Void) {
        self.onShow = onShow
    }

    /// What the chat is doing, while it answers through Claude Code; nil when it is idle.
    private var chat: ChatAnnouncement?

    var snapshot: ModuleSnapshot {
        var snapshot = ClaudeSessions.snapshot(sessions)
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
    }

    func stop() {
        onChange = nil
        sessions = []
        chat = nil
    }

    func receive(_ event: YumiEvent, sessions: [SessionID: Session]) {
        let ordered = ClaudeSessions.ordered(sessions)
        guard ordered != self.sessions else { return }
        self.sessions = ordered
        onChange?()
    }

    func perform(_ action: ModuleAction) {
        guard let session = sessions.first else {
            if action == .primary { onShow() }
            return
        }
        switch action {
        case .primary:
            // A pending approval is answered in the island. Otherwise "Voir" shows the work itself:
            // the project, in the code editor.
            let approvalPending = sessions.contains {
                if case .requestingPermission = $0.activity { return true }
                return false
            }
            if approvalPending {
                onShow()
            } else if !showProject(of: session), !Self.bringToFront(session.origin) {
                onShow()
            }
        case .secondary:
            Self.bringToFront(session.origin)
        }
    }

    /// UserDefaults key of the bundle identifier of the editor the user wants projects opened in.
    static let editorKey = "codeEditor"

    /// Opens the folder of the session in a code editor. Returns false when there is no folder or no editor.
    private func showProject(of session: Session) -> Bool {
        let workspace = NSWorkspace.shared
        guard let directory = session.origin?.workingDirectory, !directory.isEmpty,
              let editor = SessionHost.editor(
                for: session.origin,
                preferred: UserDefaults.standard.string(forKey: Self.editorKey),
                running: Set(workspace.runningApplications.compactMap(\.bundleIdentifier)),
                isInstalled: { workspace.urlForApplication(withBundleIdentifier: $0) != nil }),
              let application = workspace.urlForApplication(withBundleIdentifier: editor) else { return false }
        workspace.open([URL(fileURLWithPath: directory)], withApplicationAt: application,
                       configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
        return true
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
