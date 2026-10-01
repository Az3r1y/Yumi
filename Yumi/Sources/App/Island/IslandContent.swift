import AppKit
import SwiftUI

// The words of the open island and what its buttons do. Built from `AppState`.

/// What the island says about the agent (Claude Code): who, what, since when.
@MainActor
enum IslandAgent {

    /// "Claude Code · yumi"
    static func name(_ task: AgentTask?) -> String {
        guard let task else { return "Claude Code" }
        let source = task.source == .n8n ? "n8n" : "Claude Code"
        // "VS Code" is the name of the task while no session has given its project
        return task.name.isEmpty || task.name == "VS Code" || task.name == source ? source : "\(source) · \(task.name)"
    }

    /// "Écrit les tests": the current step as a sentence without its subject.
    static func doing(_ state: AppState) -> String {
        switch state.effectiveState {
        case .thinking:  return "Réfléchit"
        case .searching: return "Cherche"
        default:
            if state.focusTask?.source == .n8n { return state.focusTask?.steps.first ?? "Un workflow tourne" }
            return state.focusTask?.steps.last.flatMap(sentence(forStep:)) ?? "Travaille"
        }
    }

    /// "Modifie · IslandRootView.swift" → "Modifie IslandRootView.swift".
    /// The labels are the ones of HookServer.frenchStep.
    private static func sentence(forStep step: String) -> String? {
        let verbs: [String: String] = [
            "Exécute": "Exécute", "Lit": "Lit", "Écrit": "Écrit", "Modifie": "Modifie",
            "Cherche": "Cherche", "Recherche": "Cherche", "Recherche web": "Cherche sur le web",
            "Récupère": "Récupère", "Liste": "Liste", "Tâches": "Met à jour ses tâches",
            "Agent": "Lance un agent", "Notebook": "Modifie un notebook",
        ]
        let parts = step.components(separatedBy: " · ")
        guard let verb = verbs[parts[0]] else { return nil }
        let detail = parts.dropFirst().joined(separator: " · ")
        return detail.isEmpty ? verb : "\(verb) \(detail)"
    }

    static func files(_ model: IslandModel) -> String? {
        let count = model.filesTouched.count
        if count == 0 { return nil }
        return count == 1 ? "1 fichier modifié" : "\(count) fichiers modifiés"
    }

    /// "12 min": how long he has been at it.
    static func elapsed(_ model: IslandModel, until end: Date = .now) -> String? {
        guard let start = model.workStart else { return nil }
        let minutes = Int(end.timeIntervalSince(start) / 60)
        if minutes < 1 { return "< 1 min" }
        if minutes < 60 { return "\(minutes) min" }
        return "\(minutes / 60) h \(String(format: "%02d", minutes % 60))"
    }

    static func finishedLine(_ state: AppState, _ model: IslandModel) -> String {
        if let files = files(model), let time = elapsed(model, until: model.workEnd ?? .now) {
            return "\(files) en \(time)"
        }
        return state.focusTask?.steps.last ?? "La session est terminée"
    }
}

/// How a module looks in the island (Contracts/ModuleTypes.swift).
extension ModuleSnapshot {
    var color: Color { Color(hex: colorHex) }

    /// Its SF Symbol; a module that gives none gets one from what it is.
    var glyph: String {
        guard symbol == "circle.fill" else { return symbol }
        switch id {
        case "claude-code":       return "terminal"
        case "agenda":            return "calendar"
        case "notes":             return "note.text"
        case "focus":             return "timer"
        case "music", "musique":  return "music.note"
        case "weather", "meteo":  return "sun.max"
        default:                  return symbol
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

    /// A button of the folded island: the same action as in the detail view, and the
    /// island stays folded.
    static func liveControl(_ id: String, _ action: String) {
        NotificationCenter.default.post(name: .moduleAction, object: nil,
                                        userInfo: ["module": id, "action": action])
        tap()
        state.lastActivity = .now
    }

    /// A click on Yumi: he bounces, and the chat opens.
    static func pokeYumi(talking: Bool) {
        SoundEngine.shared.play("pop")
        IslandModel.shared.pose(.boing)
        if !talking { go(.prompt) }
    }

    static func manageModules() {
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

    /// Brings the agent's own window forward: the application its session runs in, or n8n.
    static func openAgent(_ task: AgentTask?) {
        if task?.source == .n8n {
            if let text = KeychainStore.shared.get("n8n-url"), let url = URL(string: text) {
                NSWorkspace.shared.open(url)
            }
            return
        }
        // Where the conversation is: the terminal, the editor or the Claude app the session runs in.
        ClaudeTaskMirror.openSession()
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
