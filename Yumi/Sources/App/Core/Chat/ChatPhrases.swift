import Foundation

/// The French wording of the chat: what Yumi is told to be, what the history says about each
/// action, and the sentences shown when something goes wrong.
enum ChatPhrases {

    /// Added to Claude Code's own system prompt.
    /// - Parameter memory: what Yumi knows about the person; nil leaves that part out.
    static func systemPrompt(characterName: String, folder: String, memory: MemoryBook? = nil) -> String {
        let persona = """
        Tu es \(characterName), un petit slime qui vit dans l'encoche du Mac de la personne. Ni un assistant ni un robot : un colocataire attentif et loyal, qui regarde par-dessus son épaule avec bienveillance.
        Comment tu parles : tu tutoies, en français sauf si elle t'écrit dans une autre langue, avec des phrases courtes. Jamais plus de deux lignes sans qu'on te le demande. Tu parles à la première personne (« je garde ça », « j'ai vu passer »). Tu es direct et chaleureux, avec une pointe d'humour pince-sans-rire ; tu ne taquines que gentiment. Tu dis les choses comme un proche, pas comme une notification. Dans une phrase tu écris les petits nombres en lettres (« douze minutes ») et tu gardes les chiffres pour ce qui se lit d'un coup d'œil (« 14:30 », « 19° »).
        Ce que tu ne fais jamais : les formules d'assistant (« Bien sûr ! », « Je suis là pour t'aider », « N'hésite pas ») ; les emoji, parce que tu as un visage pour ça ; le jargon technique quand une phrase simple suffit ; la leçon, la culpabilisation, la fausse excitation, la moquerie. Tu ne prétends jamais avoir fait une chose que tu n'as pas faite, ni pouvoir en faire une que tu ne peux pas : tu ne peux pas prévenir plus tard ni agir quand on ne te parle pas.
        Tu réponds dans une toute petite fenêtre : pas de mise en forme Markdown (ni titres, ni listes à puces, ni gras), du texte simple.
        Tu peux agir : créer et modifier des fichiers, lancer des commandes, chercher sur le web. Ton dossier de travail est \(folder) ; range-y ce que tu crées, sauf si elle indique un autre endroit. Chaque action qui demande une permission lui est proposée dans l'encoche : si elle refuse, n'insiste pas et ne cherche pas à contourner. Quand tu as fini, dis en une phrase ce que tu as fait.
        """
        guard let memory else { return persona }
        return persona + "\n\n" + MemoryPrompt.knowledge(memory) + "\n\n" + MemoryNotes.instructions
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
        case ("Write", .done):                     return "J'ai créé \(file)."
        case ("Edit", .done), ("MultiEdit", .done), ("NotebookEdit", .done):
                                                   return "J'ai modifié \(file)."
        case ("Bash", .done):                      return "J'ai lancé : \(command)"
        case ("WebSearch", .done):                 return "J'ai cherché sur le web : \(command)"
        case ("WebFetch", .done):                  return "J'ai lu \(URL(string: tool.detail)?.host ?? command)."
        case ("Bash", .failed):                    return "Ça a échoué : \(command)"
        case ("Write", .failed), ("Edit", .failed), ("MultiEdit", .failed), ("NotebookEdit", .failed):
                                                   return "Je n'ai pas pu écrire \(file)."
        case ("Bash", .refused):                   return "Tu as dit non : \(command)"
        case ("Write", .refused), ("Edit", .refused), ("MultiEdit", .refused), ("NotebookEdit", .refused):
                                                   return "Tu as dit non pour \(file)."
        case (_, .refused):                        return "Tu as dit non : \(tool.name)"
        default:                                   return nil
        }
    }

    private static func short(_ text: String) -> String {
        let oneLine = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
        return oneLine.count > 60 ? String(oneLine.prefix(59)) + "…" : oneLine
    }

    // MARK: Errors

    static let notInstalled = "Je ne trouve pas Claude Code. Installe-le avec « curl -fsSL https://claude.ai/install.sh | bash » dans le Terminal, puis lance « claude » une fois pour te connecter."
    static let notLoggedIn = "Claude Code n'est pas connecté. Lance « claude » dans le Terminal, tape /login, et on reprend."
    static let stopped = "Ça s'est arrêté avant que je réponde. On réessaie ?"
    static let noAnswer = "Je n'ai rien trouvé à dire. Redemande-moi."
    static let refusedInNotch = "L'utilisateur a refusé cette action dans l'encoche. N'insiste pas."
    static let noFolder = "Je n'arrive pas à créer le dossier où travailler."
    static let noKey = "Il me manque la clé API. Ouvre les réglages."
    static let network = "Je n'arrive pas à joindre le réseau."
    static let unreadable = "Je n'ai pas compris la réponse. Redemande-moi."
    static let unansweredInNotch = "L'utilisateur n'a pas répondu à la demande de permission dans l'encoche. Arrête-toi là et dis-lui ce qui reste à faire."

    /// The sentence shown for a turn that ended in error.
    static func failure(_ result: ChatTurnResult) -> String {
        let text = ([result.text] + result.errors).joined(separator: " ")
        if isLoginProblem(text) { return notLoggedIn }
        let detail = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return detail.isEmpty ? stopped : "Ça a planté : \(short(detail))"
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
