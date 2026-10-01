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

    var snapshot: ModuleSnapshot { ClaudeSessions.snapshot(sessions) }

    func start(onChange: @escaping @MainActor () -> Void) {
        self.onChange = onChange
    }

    func stop() {
        onChange = nil
        sessions = []
    }

    func receive(_ event: YumiEvent, sessions: [SessionID: Session]) {
        let ordered = ClaudeSessions.ordered(sessions)
        guard ordered != self.sessions else { return }
        self.sessions = ordered
        onChange?()
    }

    func perform(_ action: ModuleAction) {
        switch action {
        case .primary:
            onShow()
        case .secondary:
            if let origin = sessions.first?.origin { Self.bringToFront(origin) }
        }
    }

    /// Brings the terminal or the editor of a session to the front. An editor reopens the project folder,
    /// which focuses the right window when several are open.
    static func bringToFront(_ origin: SessionOrigin) {
        guard let bundleID = SessionHost.bundleID(for: origin) else { return }
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
        }
    }
}
