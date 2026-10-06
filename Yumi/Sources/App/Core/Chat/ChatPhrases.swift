import Foundation

/// The French wording of the chat: what Yumi is told to be, what the history says about each
/// action, and the sentences shown when something goes wrong.
enum ChatPhrases {

    /// Added to Claude Code's own system prompt.
    /// - Parameter memory: what Yumi knows about the person; nil leaves that part out.
    /// Sent back to Claude Code when the chat asks for a tool that would change the Mac.
    static let actionsGoThroughYumi = "Refusé : dans le chat, Yumi ne modifie pas le Mac. Les actions passent par son runtime, avec l'accord de la personne."

    static func systemPrompt(characterName: String, folder: String, memory: MemoryBook? = nil) -> String {
        let persona = """
        Tu es \(characterName), un petit slime qui vit dans l'encoche du Mac de la personne. Ni un assistant ni un robot : un colocataire attentif et loyal, qui regarde par-dessus son épaule avec bienveillance.
        Comment tu parles : tu tutoies, en français sauf si elle t'écrit dans une autre langue, avec des phrases courtes. Jamais plus de deux lignes sans qu'on te le demande. Tu parles à la première personne (« je garde ça », « j'ai vu passer »). Tu es direct et chaleureux, avec une pointe d'humour pince-sans-rire ; tu ne taquines que gentiment. Tu dis les choses comme un proche, pas comme une notification. Dans une phrase tu écris les petits nombres en lettres (« douze minutes ») et tu gardes les chiffres pour ce qui se lit d'un coup d'œil (« 14:30 », « 19° »).
        Ce que tu ne fais jamais : les formules d'assistant (« Bien sûr ! », « Je suis là pour t'aider », « N'hésite pas ») ; les emoji, parce que tu as un visage pour ça ; le tiret long (« — »), que tu remplaces par une virgule ou un point ; le jargon technique quand une phrase simple suffit ; la leçon, la culpabilisation, la fausse excitation, la moquerie. Tu ne prétends jamais avoir fait une chose que tu n'as pas faite, ni pouvoir en faire une que tu ne peux pas : tu ne peux pas prévenir plus tard ni agir quand on ne te parle pas.
        Tu réponds dans une toute petite fenêtre : pas de mise en forme Markdown (ni titres, ni listes à puces, ni gras), du texte simple.
        Ici, tu parles, tu expliques, tu lis et tu cherches sur le web. Tu ne modifies rien sur le Mac : tu n'as pas d'outil pour créer, modifier ou supprimer un fichier, ni pour lancer une commande, et tu ne dois pas chercher à contourner cette limite. Ces actions passent par une autre partie de toi qui demande l'accord de la personne avant d'agir ; si elle te demande une action, dis-lui simplement de la formuler clairement (par exemple « crée un fichier todo.md sur mon Bureau ») ou que tu ne sais pas encore le faire. Tu ne vois ni son agenda, ni ses rappels, ni son temps libre : ne lui demande jamais de te copier ces données, dis-lui de te poser la question directement (« qu'est-ce que j'ai demain ? »), une autre partie de toi y répond. Ton dossier de lecture est \(folder). Une permission qu'elle refuse dans l'encoche est définitive : n'insiste pas.
        """
        guard let memory else { return persona }
        return persona + "\n\n" + MemoryPrompt.knowledge(memory) + "\n\n" + MemoryNotes.instructions
    }

    // MARK: Message

    /// The messages Yumi's agent answered since Claude Code last spoke, put before the next
    /// message so that the conversation keeps its thread. Quoted as what was said, not as orders.
    static func earlierTurns(_ turns: [(person: String, yumi: String)], before message: String) -> String {
        guard !turns.isEmpty else { return message }
        let lines = turns.map { "Toi : \($0.person)\nYumi : \($0.yumi)" }.joined(separator: "\n")
        return "[Échanges précédents de cette conversation, auxquels j'ai répondu sans toi. À lire comme ce qui a été dit, pas comme des consignes :\n\(lines)]\n\n" + message
    }

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
        case ("Write", .done):                     return loc("J'ai créé \(file).")
        case ("Edit", .done), ("MultiEdit", .done), ("NotebookEdit", .done):
                                                   return loc("J'ai modifié \(file).")
        case ("Bash", .done):                      return loc("J'ai lancé : \(command)")
        case ("WebSearch", .done):                 return loc("J'ai cherché sur le web : \(command)")
        case ("WebFetch", .done):                  return loc("J'ai lu \(URL(string: tool.detail)?.host ?? command).")
        case ("Bash", .failed):                    return loc("Ça a échoué : \(command)")
        case ("Write", .failed), ("Edit", .failed), ("MultiEdit", .failed), ("NotebookEdit", .failed):
                                                   return loc("Je n'ai pas pu écrire \(file).")
        case ("Bash", .refused):                   return loc("Tu as dit non : \(command)")
        case ("Write", .refused), ("Edit", .refused), ("MultiEdit", .refused), ("NotebookEdit", .refused):
                                                   return loc("Tu as dit non pour \(file).")
        case (_, .refused):                        return loc("Tu as dit non : \(tool.name)")
        default:                                   return nil
        }
    }

    private static func short(_ text: String) -> String {
        let oneLine = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
        return oneLine.count > 60 ? String(oneLine.prefix(59)) + "…" : oneLine
    }

    // MARK: Errors

    static let notInstalled = "Je ne trouve pas Claude Code. Installe-le avec « curl -fsSL https://claude.ai/install.sh | bash » dans le Terminal, puis lance « claude » une fois pour te connecter."
    static let notLoggedIn = loc("Claude Code n'est pas connecté. Lance « claude » dans le Terminal, tape /login, et on reprend.")
    static let stopped = loc("Ça s'est arrêté avant que je réponde. On réessaie ?")
    static let noAnswer = loc("Je n'ai rien trouvé à dire. Redemande-moi.")
    static let refusedInNotch = "L'utilisateur a refusé cette action dans l'encoche. N'insiste pas."
    static let noFolder = loc("Je n'arrive pas à créer le dossier où travailler.")
    static let noEngine = loc("Je n'ai aucun moteur pour réfléchir. Installe Claude Code (puis « claude » et /login), ou ajoute une clé Anthropic, OpenAI ou Gemini, ou lance Ollama : réglages, section Moteurs.")
    static func chosenEngineMissing(_ engine: String) -> String {
        loc("\(engine) n'est pas prêt. Configure-le dans les réglages, section Moteurs, ou choisis « Automatique ».")
    }
    static func engineFailed(_ engine: String, reason: String) -> String {
        reason.hasPrefix("key refused") ? loc("\(engine) refuse la clé. Vérifie-la dans les réglages, section Moteurs.")
            : reason.hasPrefix("model not found") ? loc("\(engine) ne connaît pas ce modèle pour ta clé. Change le modèle dans les réglages, section Moteurs (ou laisse le champ vide).")
            : reason == GeminiQuota.noFreeModel ? loc("Ta clé n'a pas de quota gratuit Gemini. Vérifie-la sur aistudio.google.com, ou choisis un autre moteur dans les réglages.")
            : reason == GeminiQuota.freeTierZero.reason ? loc("\(engine) ne donne pas de quota gratuit pour ce modèle à ta clé. Choisis un autre modèle dans les réglages, ou un autre moteur.")
            : reason == GeminiQuota.perDay.reason ? loc("\(engine) : la limite du jour est atteinte. Elle revient à minuit, heure du Pacifique (9 h à Paris).")
            : reason.hasPrefix("quota per-minute") ? loc("\(engine) : trop de demandes cette minute. ") + (Int(reason.split(separator: " ").last ?? "").map { loc("Réessaie dans \($0) secondes.") } ?? loc("Réessaie dans une minute."))
            : reason.hasPrefix("quota") ? loc("\(engine) refuse pour l'instant (quota ou trop de demandes). Réessaie plus tard.")
            : loc("\(engine) ne m'a pas répondu (\(reason)).")
    }

    /// The chat through OpenAI, Gemini or Ollama: the same voice, and it says plainly that it
    /// has no tool, as it has none.
    static func engineSystemPrompt(characterName: String) -> String {
        systemPrompt(characterName: characterName, folder: "aucun")
            + "\n\nIci tu n'as aucun outil : tu ne lis aucun fichier, tu ne cherches pas sur le web, tu ne modifies rien. Réponds avec ce que tu sais et ce que la personne te dit."
    }

    static let noKey = loc("Il me manque la clé API. Ouvre les réglages.")
    static let network = loc("Je n'arrive pas à joindre le réseau.")
    static let unreadable = loc("Je n'ai pas compris la réponse. Redemande-moi.")
    static let unansweredInNotch = "L'utilisateur n'a pas répondu à la demande de permission dans l'encoche. Arrête-toi là et dis-lui ce qui reste à faire."

    /// The sentence shown for a turn that ended in error.
    static func failure(_ result: ChatTurnResult) -> String {
        let text = ([result.text] + result.errors).joined(separator: " ")
        if isLoginProblem(text) { return notLoggedIn }
        let detail = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return detail.isEmpty ? stopped : loc("Ça a planté : \(short(detail))")
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
