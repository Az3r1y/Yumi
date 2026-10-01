import Foundation

/// Reads the Claude Code sessions out of the store: which one to show first, and how to say what it does.
enum ClaudeSessions {
    /// Claude Code sessions, the one to show first. A session waiting for the user comes
    /// before the others; then the most recently active.
    static func ordered(_ sessions: [SessionID: Session]) -> [Session] {
        sessions.values
            .filter { $0.agent.id == ClaudeHookTranslator.agent.id }
            .sorted { a, b in
                let waitingA = a.status == .waitingForUser, waitingB = b.status == .waitingForUser
                if waitingA != waitingB { return waitingA }
                if a.recency != b.recency { return a.recency > b.recency }
                return a.id.value < b.id.value
            }
    }

    /// The folder the session works in gives it its name; it can change during the session.
    static func projectName(_ session: Session) -> String {
        guard let directory = session.origin?.workingDirectory, !directory.isEmpty else { return session.title }
        return ClaudeHookTranslator.projectName(forDirectory: directory)
    }

    /// What the session is doing, as the end of "projet : …".
    static func phrase(_ session: Session) -> String {
        switch session.activity {
        case .requestingPermission: return "demande ton accord"
        case .asking:               return "te pose une question"
        case .working(let tool):    return ClaudeToolPhrase.sentence(tool)
        case .thinking:             return "réfléchit"
        case .idle:
            switch session.status {
            case .rateLimited:    return "limite d'usage atteinte"
            case .errored:        return "s'est arrêté sur une erreur"
            case .completed:      return "a terminé"
            case .waitingForUser: return "attend ta réponse"
            case .running:        return session.isTurnActive ? "travaille" : "attend ton message"
            }
        }
    }

    static func snapshot(_ sessions: [Session]) -> ModuleSnapshot {
        var snapshot = ModuleSnapshot(id: "claude-code", name: "Claude Code", colorHex: "#FFB547",
                                      status: "au repos", title: "Aucune session ouverte",
                                      subtitle: "Lance Claude Code dans un terminal",
                                      primaryAction: "Voir", secondaryAction: nil)
        guard let featured = sessions.first else { return snapshot }

        let waiting = sessions.filter { $0.status == .waitingForUser }.count
        snapshot.status = FrenchText.count(sessions.count, "session", "sessions")
        snapshot.title = "\(projectName(featured)) : \(phrase(featured))"
        snapshot.subtitle = FrenchText.count(sessions.count, "session ouverte", "sessions ouvertes")
        if waiting == 1 { snapshot.subtitle += ", 1 attend ta réponse" }
        if waiting > 1 { snapshot.subtitle += ", \(waiting) attendent ta réponse" }
        switch SessionHost.kind(of: featured.origin) {
        case .editor:   snapshot.secondaryAction = "Ouvrir l'éditeur"
        case .terminal: snapshot.secondaryAction = "Ouvrir le terminal"
        case .other:    snapshot.secondaryAction = "Ouvrir la session"
        case nil:       break
        }
        snapshot.needsAttention = waiting > 0
        snapshot.live = live(sessions)
        return snapshot
    }

    /// The folded island only hears about Claude Code when a session is waiting for the user.
    /// `sessions` is ordered: a waiting session, if any, is the first one.
    static func live(_ sessions: [Session]) -> ModuleLive? {
        guard let session = sessions.first, session.status == .waitingForUser else { return nil }
        let name = projectName(session)
        let text: String
        if case .requestingPermission = session.activity {
            text = "\(name) demande ton accord"
        } else {
            text = "\(name) te pose une question"
        }
        return ModuleLive(text: text, priority: ModuleLivePriority.attention,
                          controls: [ModuleControl(id: ModuleAction.primary.rawValue, symbol: "eye.fill", label: "Voir")])
    }
}

/// The application a session runs in: a terminal, or an editor with an integrated terminal.
enum SessionHost {
    /// `TERM_PROGRAM` values of the hosts that do not always pass their bundle identifier along.
    private static let knownPrograms: [String: String] = [
        "apple_terminal": "com.apple.Terminal",
        "iterm.app":      "com.googlecode.iterm2",
        "vscode":         "com.microsoft.VSCode",
        "ghostty":        "com.mitchellh.ghostty",
        "wezterm":        "com.github.wez.wezterm",
        "warpterminal":   "dev.warp.Warp-Stable",
        "kitty":          "net.kovidgoyal.kitty",
        "alacritty":      "org.alacritty",
        "zed":            "dev.zed.Zed",
        "hyper":          "co.zeit.hyper",
        "tabby":          "org.tabby",
    ]

    /// Bundle identifiers that open a folder as a project rather than as a shell.
    private static let editorMarkers = ["vscode", "vscodium", "cursor", "windsurf", "dev.zed", "jetbrains", "xcode"]

    /// Code editors Yumi can open a project in, in order of preference.
    static let knownEditors = ["com.microsoft.VSCode", "com.microsoft.VSCodeInsiders", "com.vscodium.codium",
                               "com.todesktop.230313mzl4w4u92", "com.exafunction.windsurf", "dev.zed.Zed"]

    enum Kind: Equatable, Sendable {
        /// A terminal emulator: bringing it forward shows the session.
        case terminal
        /// An editor with an integrated terminal: reopening the folder focuses the right window.
        case editor
        /// Another application that hosts sessions (the Claude desktop app, for instance).
        case other
    }

    static func bundleID(for origin: SessionOrigin?) -> String? {
        guard let origin else { return nil }
        if !origin.hostBundleID.isEmpty { return origin.hostBundleID }
        return knownPrograms[origin.hostName.lowercased()]
    }

    static func isEditor(_ origin: SessionOrigin?) -> Bool {
        guard let id = bundleID(for: origin)?.lowercased() else { return false }
        return editorMarkers.contains { id.contains($0) }
    }

    /// What kind of application hosts the session, or nil when it is unknown.
    static func kind(of origin: SessionOrigin?) -> Kind? {
        guard let origin, let id = bundleID(for: origin) else { return nil }
        if isEditor(origin) { return .editor }
        // Only terminals set TERM_PROGRAM; the known ones are also recognised by their identifier.
        if !origin.hostName.isEmpty || knownPrograms.values.contains(id) { return .terminal }
        return .other
    }

    /// The editor to show a session's project in: the one the session runs in, else the one the
    /// user chose, else a known editor that is open, else a known editor that is installed.
    static func editor(for origin: SessionOrigin?, preferred: String?, running: Set<String>,
                       isInstalled: (String) -> Bool) -> String? {
        if isEditor(origin), let host = bundleID(for: origin) { return host }
        if let preferred, !preferred.isEmpty, isInstalled(preferred) { return preferred }
        return knownEditors.first(where: running.contains) ?? knownEditors.first(where: isInstalled)
    }
}
