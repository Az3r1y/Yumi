import AppKit
import SwiftUI

// What the open island says: one piece of information, a few words under Yumi, and the
// buttons that go with it (`STATES[...].content()` in the mock-up). Built from `AppState`.

struct IslandAction: Identifiable {
    let id: String
    let label: String
    let run: @MainActor () -> Void

    init(_ label: String, id: String? = nil, run: @escaping @MainActor () -> Void) {
        self.id = id ?? label
        self.label = label
        self.run = run
    }
}

/// `block(c)` of the mock-up: eyebrow, title, then one line of text or of code, then buttons.
struct IslandCard {
    var eyebrow: String
    var color: Color
    var title: String
    var sub: String?
    var code: String?
    var actions: [IslandAction] = []
    /// Index of the main button, the one in the colour of the card.
    var main: Int? = 0
    /// The few words under Yumi.
    var caption: String
}

@MainActor
enum IslandContent {

    // MARK: - Cards

    static func card(for screen: IslandScreen, state: AppState, model: IslandModel) -> IslandCard {
        switch screen {
        case .home:     return home(state, model)
        case .working:  return working(state, model)
        case .alert:    return alert(state)
        case .finished: return finished(state, model)
        case .error:    return error(state)
        case .module:   return module(state, model)
        case .talk, .drop:
            // These two have their own layout; only the caption is used.
            return IslandCard(eyebrow: "", color: IslandTheme.blue, title: "", caption: caption(for: screen, state: state))
        }
    }

    static func caption(for screen: IslandScreen, state: AppState) -> String {
        switch screen {
        case .talk: return state.stateOverride == .thinking ? "Il réfléchit" : "Il t'écoute"
        case .drop: return state.droppedFile != nil && state.view != .upload ? "Bien reçu" : "Donne !"
        default:    return ""
        }
    }

    private static func home(_ state: AppState, _ model: IslandModel) -> IslandCard {
        let caption = state.effectiveState == .ratelimit ? "Limite atteinte" : "Tout est calme"
        guard let m = model.featuredModule(in: state.modules) else {
            return IslandCard(eyebrow: "Maintenant", color: IslandTheme.blue,
                              title: "Rien à signaler",
                              sub: "Dépose un fichier ou parle-moi",
                              actions: [IslandAction("Parler") { IslandActions.go(.prompt) }],
                              caption: caption)
        }
        return IslandCard(eyebrow: "Maintenant", color: IslandTheme.blue,
                          title: m.title, sub: m.subtitle,
                          actions: [
                              IslandAction(m.primaryAction, id: "primary") { IslandActions.module(m.id, "primary") },
                              IslandAction("Plus tard", id: "later") { IslandActions.fold() },
                          ],
                          caption: caption)
    }

    private static func working(_ state: AppState, _ model: IslandModel) -> IslandCard {
        let task = state.focusTask
        var title: String
        var sub = elapsed(since: model.workStart)
        switch state.effectiveState {
        case .thinking:  title = "Claude réfléchit"
        case .searching: title = "Claude cherche"
        default:
            if let phrase = task?.steps.last.flatMap(sentence(forStep:)) {
                title = phrase
            } else {
                title = "Claude travaille"
            }
        }
        if task?.source == .n8n { title = task?.steps.first ?? "Un workflow tourne" }
        let files = model.filesTouched.count
        if files > 0 {
            let text = files == 1 ? "1 fichier modifié" : "\(files) fichiers modifiés"
            sub = sub.isEmpty ? text : "\(sub), \(text)"
        }
        if sub.isEmpty { sub = "Il vient de s'y mettre" }
        return IslandCard(eyebrow: eyebrow(task), color: IslandTheme.blue,
                          title: title, sub: sub,
                          actions: [
                              IslandAction("Voir") { IslandActions.openAgent(task) },
                              IslandAction("Plus tard") { IslandActions.fold() },
                          ],
                          caption: "Il bosse")
    }

    private static func alert(_ state: AppState) -> IslandCard {
        let task = state.focusTask
        if let approval = state.pendingApproval {
            let title = approval.tool == "Bash" ? "Claude veut lancer une commande" : "Claude veut utiliser \(approval.tool)"
            return IslandCard(eyebrow: eyebrow(task), color: IslandTheme.amber,
                              title: title, code: approval.command,
                              actions: [
                                  IslandAction("Refuser") { HookServer.shared.sendApprovalDecision("deny") },
                                  IslandAction("Toujours") { HookServer.shared.sendApprovalDecision("always") },
                                  IslandAction("Autoriser") { HookServer.shared.sendApprovalDecision("allow") },
                              ],
                              main: 2,
                              caption: "Il a besoin de toi")
        }
        // A question asked in the session: it can only be answered there
        return IslandCard(eyebrow: eyebrow(task), color: IslandTheme.amber,
                          title: task?.steps.last ?? "Claude attend ta réponse",
                          sub: "Réponds-lui dans la session",
                          actions: [
                              IslandAction("Voir") { IslandActions.openAgent(task) },
                              IslandAction("Plus tard") { IslandActions.fold() },
                          ],
                          caption: "Il a besoin de toi")
    }

    private static func finished(_ state: AppState, _ model: IslandModel) -> IslandCard {
        let task = state.focusTask
        let files = model.filesTouched.count
        var sub = task?.steps.last ?? "La session est terminée"
        if files > 0, let start = model.workStart {
            let minutes = max(1, Int(((model.workEnd ?? .now).timeIntervalSince(start) / 60).rounded()))
            let filesText = files == 1 ? "1 fichier modifié" : "\(files) fichiers modifiés"
            sub = "\(filesText) en \(minutes) \(minutes == 1 ? "minute" : "minutes")"
        }
        return IslandCard(eyebrow: eyebrow(task), color: IslandTheme.green,
                          title: "C'est fini", sub: sub,
                          actions: [
                              IslandAction("Voir") { IslandActions.openAgent(task); IslandActions.fold() },
                              IslandAction("OK") { IslandActions.fold() },
                          ],
                          caption: "Bien joué")
    }

    private static func error(_ state: AppState) -> IslandCard {
        let task = state.focusTask
        var card = IslandCard(eyebrow: eyebrow(task), color: IslandTheme.red,
                              title: "Claude s'est arrêté sur une erreur",
                              actions: [
                                  IslandAction("Voir") { IslandActions.openAgent(task) },
                                  IslandAction("OK") { IslandActions.fold() },
                              ],
                              caption: "Aïe")
        if let last = task?.steps.last {
            card.code = last
        } else {
            card.sub = "Ouvre la session pour voir ce qui bloque"
        }
        return card
    }

    private static func module(_ state: AppState, _ model: IslandModel) -> IslandCard {
        guard let m = model.selectedModule(in: state.modules) else {
            return IslandCard(eyebrow: "Modules", color: IslandTheme.blue,
                              title: "Aucun module", sub: "Choisis-en dans les réglages",
                              actions: [IslandAction("Gérer") { IslandActions.manageModules() }],
                              caption: "Tout est calme")
        }
        var actions = [IslandAction(m.primaryAction, id: "primary") { IslandActions.module(m.id, "primary") }]
        if let second = m.secondaryAction {
            actions.append(IslandAction(second, id: "secondary") { IslandActions.module(m.id, "secondary") })
        }
        return IslandCard(eyebrow: m.name, color: Color(hex: m.colorHex),
                          title: m.title, sub: m.subtitle,
                          actions: actions,
                          caption: m.status)
    }

    // MARK: - Words

    private static func eyebrow(_ task: AgentTask?) -> String {
        guard let task else { return "Claude Code" }
        let source = task.source == .n8n ? "n8n" : "Claude Code"
        // "VS Code" is the name of the task while no session has given its project
        return task.name.isEmpty || task.name == "VS Code" || task.name == source ? source : "\(source) · \(task.name)"
    }

    /// "Modifie · IslandRootView.swift" → "Claude modifie IslandRootView.swift".
    /// The labels are the ones of HookServer.frenchStep.
    private static func sentence(forStep step: String) -> String? {
        let verbs: [String: String] = [
            "Exécute": "exécute", "Lit": "lit", "Écrit": "écrit", "Modifie": "modifie",
            "Cherche": "cherche", "Recherche": "cherche", "Recherche web": "cherche sur le web",
            "Récupère": "récupère", "Liste": "liste", "Tâches": "met à jour ses tâches",
            "Agent": "lance un agent", "Notebook": "modifie un notebook",
        ]
        let parts = step.components(separatedBy: " · ")
        guard let verb = verbs[parts[0]] else { return nil }
        let detail = parts.dropFirst().joined(separator: " · ")
        return detail.isEmpty ? "Claude \(verb)" : "Claude \(verb) \(detail)"
    }

    private static func elapsed(since start: Date?) -> String {
        guard let start else { return "" }
        let minutes = Int(Date.now.timeIntervalSince(start) / 60)
        if minutes < 1 { return "Depuis moins d'une minute" }
        if minutes < 60 { return "Depuis \(minutes) min" }
        return "Depuis \(minutes / 60) h \(String(format: "%02d", minutes % 60))"
    }

    // MARK: - The compact island: one dot, one mark

    /// "Yumi reste discret et affiche le prochain repère."
    static func compactMark(state: AppState, model: IslandModel) -> (color: Color, text: String)? {
        switch IslandScreen.resolve(view: .overview, state: state.effectiveState, approvalPending: state.pendingApproval != nil) {
        case .alert:    return (IslandTheme.amber, "à toi")
        case .error:    return (IslandTheme.red, "erreur")
        case .finished: return (IslandTheme.green, "fini")
        case .working:
            let minutes = model.workStart.map { Int(Date.now.timeIntervalSince($0) / 60) } ?? 0
            return (IslandTheme.blue, "\(max(1, minutes)) min")
        default:
            guard let m = model.featuredModule(in: state.modules) else { return nil }
            return (Color(hex: m.colorHex), m.status)
        }
    }
}

// MARK: - What the buttons do

@MainActor
enum IslandActions {
    private static var state: AppState { .shared }

    /// A tap that changes nothing by itself: the little "tap" of the mock-up.
    static func tap() {
        SoundEngine.shared.play("blip")
    }

    /// Shows another view of the open island.
    static func go(_ view: IslandView) {
        leaveChatError(next: view)
        IslandModel.shared.drawerOpen = false
        #if !APPSTORE
        if view == .prompt, state.promptContext == nil {
            state.promptContext = WindowContextCapture.captureActive(from: state.lastExternalApp)
        }
        #endif
        if view == .upload {
            // A fresh drop zone: the previous file has been dealt with
            state.droppedFile = nil
        }
        state.view = view
        state.lastActivity = .now
        tap()
    }

    static func showModule(_ id: String) {
        leaveChatError(next: .module)
        IslandModel.shared.selectedModuleID = id
        IslandModel.shared.drawerOpen = false
        state.view = .module
        state.lastActivity = .now
        tap()
    }

    /// A module button was pressed: the core does the work (Contracts/ModuleTypes.swift).
    static func module(_ id: String, _ action: String) {
        NotificationCenter.default.post(name: .moduleAction, object: nil,
                                        userInfo: ["module": id, "action": action])
        tap()
        IslandModel.shared.pose(.pop)
    }

    static func toggleDrawer() {
        let model = IslandModel.shared
        model.drawerOpen.toggle()
        SoundEngine.shared.play(model.drawerOpen ? "open" : "close")
    }

    static func manageModules() {
        IslandModel.shared.drawerOpen = false
        NotificationCenter.default.post(name: .openFullSettings, object: nil)
        tap()
    }

    static func fold() {
        NotificationCenter.default.post(name: .islandCollapse, object: nil)
    }

    /// The chat service leaves `stateOverride = .error` behind after a failure; nothing
    /// else clears it.
    static func leaveChatError(next: IslandView?) {
        if state.view == .note, next != .note, state.stateOverride == .error {
            state.stateOverride = nil
        }
    }

    /// Brings the agent's own window forward: the project in VS Code, or n8n.
    static func openAgent(_ task: AgentTask?) {
        if task?.source == .n8n {
            if let text = KeychainStore.shared.get("n8n-url"), let url = URL(string: text) {
                NSWorkspace.shared.open(url)
            }
            return
        }
        let ids = ["com.microsoft.VSCode", "com.microsoft.VSCodeInsiders", "com.vscodium.codium"]
        let appURL = ids.compactMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }.first
        if let cwd = task?.sessionCwd, !cwd.isEmpty, let appURL {
            NSWorkspace.shared.open([URL(fileURLWithPath: cwd)], withApplicationAt: appURL,
                                    configuration: .init(), completionHandler: nil)
            return
        }
        if let running = ids.compactMap({ id in
            NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == id }
        }).first {
            running.activate()
            return
        }
        if let appURL {
            NSWorkspace.shared.openApplication(at: appURL, configuration: .init(), completionHandler: nil)
        }
    }

    // MARK: Talk

    static func send(_ text: String) {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        state.chatHistory.append(ChatMessage(role: .user, content: query))
        state.noteMessage = nil
        state.stateOverride = .thinking
        state.view = .prompt
        state.lastActivity = .now
        SoundEngine.shared.play("send")
        let appState = state
        Task { await ClaudeService.shared.chat(query: query, context: appState.promptContext, state: appState) }
    }

    // MARK: Drop

    /// "Résumer": the file he was given, or failing that the window the user was in.
    static func summarize() {
        if let file = state.droppedFile {
            send("Résume-moi \(file.name) en trois points")
            return
        }
        #if !APPSTORE
        if let context = WindowContextCapture.captureActive(from: state.lastExternalApp) {
            newConversation()
            state.promptContext = context
            send("Résume-moi cette fenêtre en trois points")
            return
        }
        #endif
        go(.prompt)
    }

    /// "Envoyer": a new mail with the file attached; the user writes and sends it.
    static func sendByMail() {
        guard let file = state.droppedFile, let service = NSSharingService(named: .composeEmail) else {
            tap()
            return
        }
        service.subject = file.name
        service.perform(withItems: [file.url])
        SoundEngine.shared.play("send")
        IslandModel.shared.pose(.pop)
        fold()
    }

    /// "Ranger": the file stays in Yumi's inbox (FileDropHandler copied it there).
    static func putAway() {
        guard state.droppedFile != nil else {
            tap()
            return
        }
        SoundEngine.shared.play("approve")
        IslandModel.shared.pose(.pop)
        state.droppedFile = nil
        fold()
    }

    /// A new file or window is a new subject: the conversation starts again with it.
    static func newConversation() {
        ClaudeService.shared.clearConversation()
        state.chatHistory = []
        state.noteMessage = nil
    }
}
