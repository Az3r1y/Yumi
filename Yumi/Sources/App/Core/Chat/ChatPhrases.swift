import Foundation

/// The French wording of the chat: what Yumi is told to be, what the history says about each
/// action, and the sentences shown when something goes wrong.
enum ChatPhrases {

    /// Added to Claude Code's own system prompt.
    /// - Parameter memory: what Yumi knows about the person; nil leaves that part out.
    static func systemPrompt(characterName: String, folder: String, memory: MemoryBook? = nil) -> String {
        let persona = """
        Tu es \(characterName), un compagnon qui vit dans l'encoche du Mac de l'utilisateur. \
        Tu réponds dans une toute petite fenêtre : sois bref, va droit au but, tutoie l'utilisateur et réponds dans sa langue. \
        Pas de mise en forme Markdown (ni titres, ni listes à puces, ni gras) : du texte simple, avec des retours à la ligne si besoin. \
        Tu peux agir : créer et modifier des fichiers, lancer des commandes, chercher sur le web. \
        Ton dossier de travail est \(folder) ; range-y ce que tu crées, sauf si l'utilisateur indique un autre endroit. \
        Chaque action qui demande une permission est proposée à l'utilisateur dans l'encoche : si elle est refusée, n'insiste pas et ne cherche pas à la contourner. \
        Quand tu as fini, dis en une phrase ce que tu as fait.
        """
        guard let memory else { return persona }
        return persona + "\n\n" + MemoryPrompt.knowledge(memory)
    }

    // MARK: Message

    /// The text sent to Claude Code: the user's words, preceded by what was attached.
    static func message(query: String, context: ChatContext?) -> String {
        switch context {
        case .window(let app, let title, let url):
            var lines = ["[Contexte joint : fenêtre de \(app)"]
            if !title.isEmpty { lines[0] += ", « \(title) »" }
            if let url, !url.isEmpty { lines[0] += ", \(url)" }
            lines[0] += "]"
            return lines[0] + "\n\n" + query
        case .file(let name, let path):
            if let path, !path.isEmpty {
                return "[Fichier joint : \(path)]\n\n\(query)"
            }
            return "[Fichier joint : \(name)]\n\n\(query)"
        case nil:
            return query
        }
    }

    // MARK: Actions

    /// The line the history gets when a tool has done something, or nil for tools that only look
    /// (reading a file, searching the folder), which are not worth a line.
    static func action(_ tool: ChatToolUse, outcome: ChatToolOutcome) -> String? {
        let file = (tool.detail as NSString).lastPathComponent
        let command = short(tool.detail)
        switch (tool.name, outcome) {
        case ("Write", .done):                     return "Fichier créé : \(file)"
        case ("Edit", .done), ("MultiEdit", .done), ("NotebookEdit", .done):
                                                   return "Fichier modifié : \(file)"
        case ("Bash", .done):                      return "Commande lancée : \(command)"
        case ("WebSearch", .done):                 return "Recherche web : \(command)"
        case ("WebFetch", .done):                  return "Page lue : \(URL(string: tool.detail)?.host ?? command)"
        case ("Bash", .failed):                    return "Commande en échec : \(command)"
        case ("Write", .failed), ("Edit", .failed), ("MultiEdit", .failed), ("NotebookEdit", .failed):
                                                   return "Fichier non écrit : \(file)"
        case ("Bash", .refused):                   return "Commande refusée : \(command)"
        case ("Write", .refused), ("Edit", .refused), ("MultiEdit", .refused), ("NotebookEdit", .refused):
                                                   return "Écriture refusée : \(file)"
        case (_, .refused):                        return "Action refusée : \(tool.name)"
        default:                                   return nil
        }
    }

    private static func short(_ text: String) -> String {
        let oneLine = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
        return oneLine.count > 60 ? String(oneLine.prefix(59)) + "…" : oneLine
    }

    // MARK: Errors

    static let notInstalled = "Claude Code est introuvable : installe-le avec « curl -fsSL https://claude.ai/install.sh | bash » dans le Terminal, puis lance « claude » une fois pour te connecter."
    static let notLoggedIn = "Claude Code n'est pas connecté : lance « claude » dans le Terminal, tape /login, puis réessaie."
    static let stopped = "Claude Code s'est arrêté avant de répondre. Réessaie."
    static let noAnswer = "Pas de réponse cette fois. Réessaie."
    static let refusedInNotch = "L'utilisateur a refusé cette action dans l'encoche. N'insiste pas."
    static let unansweredInNotch = "L'utilisateur n'a pas répondu à la demande de permission dans l'encoche. Arrête-toi là et dis-lui ce qui reste à faire."

    /// The sentence shown for a turn that ended in error.
    static func failure(_ result: ChatTurnResult) -> String {
        let text = ([result.text] + result.errors).joined(separator: " ")
        if isLoginProblem(text) { return notLoggedIn }
        let detail = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return detail.isEmpty ? stopped : "Claude Code a rencontré une erreur : \(short(detail))"
    }

    static func isLoginProblem(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.contains("not logged in") || lower.contains("/login") || lower.contains("invalid api key")
            || lower.contains("authentication_failed") || lower.contains("oauth token has expired")
    }

    /// True when a resume failed because the session no longer exists (the folder changed, or its history was removed).
    static func isUnknownSession(_ result: ChatTurnResult) -> Bool {
        result.isError && (result.errors + [result.text]).contains { $0.lowercased().contains("no conversation found") }
    }
}

/// What the user attached to the conversation. Mirrors `PromptContext`, without its dependencies.
enum ChatContext: Equatable, Sendable {
    case window(app: String, title: String, url: String?)
    case file(name: String, path: String?)
}

enum ChatToolOutcome: Equatable, Sendable {
    case done
    /// The tool ran and reported an error.
    case failed
    /// The user refused it in the notch.
    case refused
}
