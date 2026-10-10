import AppKit

/// Antigravity, as a module: its sessions, seen through its hooks. Nothing to approve from the
/// notch: Antigravity asks in its own terminal.
@MainActor
final class AntigravityModule: YumiModule {
    let id = "antigravity"

    private var sessions: [Session] = []
    private var onChange: (@MainActor () -> Void)?
    /// Opens the settings where the hooks are shown before anything is written.
    private let onInstallHooks: @MainActor () -> Void

    init(onInstallHooks: @escaping @MainActor () -> Void = {}) {
        self.onInstallHooks = onInstallHooks
    }

    var snapshot: ModuleSnapshot {
        Self.snapshot(sessions, hooksMissing: AntigravityLLMProvider.find() != nil && !AntigravityHooks.isInstalled)
    }

    func start(onChange: @escaping @MainActor () -> Void) { self.onChange = onChange }

    func stop() {
        onChange = nil
        sessions = []
    }

    func receive(_ event: YumiEvent, sessions: [SessionID: Session]) {
        let ordered = Self.ordered(sessions)
        guard ordered != self.sessions else { return }
        self.sessions = ordered
        onChange?()
    }

    func perform(_ action: ModuleAction) {
        if sessions.isEmpty, !AntigravityHooks.isInstalled { return onInstallHooks() }
        ClaudeCodeModule.bringToFront(sessions.first?.origin)
    }

    static func ordered(_ sessions: [SessionID: Session]) -> [Session] {
        sessions.values
            .filter { $0.agent.id == AntigravityHookTranslator.agent.id }
            .sorted { $0.recency != $1.recency ? $0.recency > $1.recency : $0.id.value < $1.id.value }
    }

    static func phrase(_ session: Session) -> String {
        let project = ClaudeSessions.projectName(session)
        switch session.activity {
        case .working(let tool):
            let what = tool.summary.isEmpty ? tool.name : tool.summary
            return loc("Antigravity sur \(project) : \(what)")
        case .thinking, .requestingPermission, .asking:
            return loc("Antigravity réfléchit sur \(project).")
        case .idle:
            switch session.status {
            case .errored:   return loc("Ça a planté sur \(project). Tu veux voir où ?")
            case .completed: return loc("C'est passé sur \(project).")
            default:         return session.isTurnActive ? loc("Antigravity avance sur \(project).")
                                                         : loc("Antigravity attend ton message sur \(project).")
            }
        }
    }

    static func snapshot(_ sessions: [Session], hooksMissing: Bool) -> ModuleSnapshot {
        var snapshot = ModuleSnapshot(id: "antigravity", name: "Antigravity", colorHex: "#4C8DF6",
                                      status: loc("au repos"), title: loc("Rien ne tourne sur Antigravity."),
                                      subtitle: loc("Lance agy, je regarderai."),
                                      primaryAction: loc("Voir"), secondaryAction: nil)
        if let featured = sessions.first {
            snapshot.status = FrenchText.count(sessions.count, "session", "sessions")
            snapshot.title = phrase(featured)
            snapshot.subtitle = FrenchText.sentenceStart(FrenchText.spelledCount(sessions.count, loc("session ouverte"), loc("sessions ouvertes"), feminine: true)) + "."
            if let working = sessions.first(where: { $0.status == .running && $0.isTurnActive }) {
                snapshot.live = ModuleLive(text: phrase(working), priority: ClaudeSessions.workingPriority - 1)
            }
        } else if hooksMissing {
            snapshot.status = loc("à brancher")
            snapshot.title = loc("Je ne vois pas tes sessions Antigravity.")
            snapshot.subtitle = loc("Il me manque mes hooks. Je m'installe ?")
            snapshot.primaryAction = loc("Installer")
        }
        return snapshot.withSymbols("sparkles")
    }
}
