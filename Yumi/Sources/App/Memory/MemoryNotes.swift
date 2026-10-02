import Foundation

// MARK: - How Yumi learns
// The conversation itself decides what is worth remembering: it knows what was said, what was
// shown and what was asked, which no list of keywords can tell. It writes its decisions in a
// small block at the end of its answer, that the person never sees; the app reads the block,
// passes every line through `MemoryGuard`, and updates the memory.

/// One decision of the conversation about the memory.
enum MemoryChange: Equatable, Hashable, Sendable {
    case remember(MemoryEntry.Kind, String)
    /// Forget the entry with this identifier.
    case forget(String)
}

enum MemoryNotes {
    static let opening = "<memoire>"
    static let closing = "</memoire>"

    /// What the conversation is told about remembering (design/yumi/voix.md).
    static let instructions = """
    Tu as une mémoire, et c'est toi qui décides ce qui mérite d'y entrer. Pour la modifier, termine ta réponse par un bloc que la personne ne verra pas, une ligne par souvenir :
    \(opening)
    + toi | une phrase courte sur la personne : sa façon de travailler, ce qu'elle aime ou non
    + projet | le nom d'un projet et ce sur quoi elle avance
    + fil | ce qu'elle t'a demandé ou montré, ce qui reste en suspens
    - identifiant d'un souvenir à oublier
    \(closing)
    Retiens ce qu'elle te demande de retenir, et de toi-même toute information durable qui passe dans la conversation. Quand elle te montre un fichier ou une fenêtre, retiens dans le fil de quoi il s'agissait (« Tu m'as montré le devis du client Dupont »), jamais son contenu. Quand elle dit d'oublier quelque chose, retire le souvenir concerné avec son identifiant entre crochets. Écris chaque souvenir en français, en t'adressant à elle (« Tu préfères… »), en une phrase.
    Ne retiens jamais : un mot de passe, une clé, un code, un numéro de carte ou de compte ; le contenu d'un fichier ou d'une fenêtre ; une information sur une autre personne, au-delà de son prénom. Dans le doute, ne retiens pas.
    La plupart des réponses n'ont rien à retenir : dans ce cas n'écris pas de bloc. Ne parle jamais de ce bloc, et ne dis pas que tu as noté quelque chose sauf si on te l'a demandé.
    """

    /// Asked at the end of a conversation, to keep a trace of it in the thread.
    static let summaryRequest = """
    La conversation se termine. Sans utiliser d'outil, résume-la pour ta mémoire en une à trois lignes « + fil | … » dans un bloc \(opening) … \(closing) : ce que la personne voulait, ce qui a été fait, ce qui reste en suspens. Mêmes interdits que d'habitude. Si rien ne mérite d'être retenu, réponds seulement « rien ». N'écris rien d'autre que le bloc.
    """

    private static let kinds: [String: MemoryEntry.Kind] = ["toi": .person, "projet": .project, "fil": .thread]

    /// Separates what the person reads from what goes to the memory.
    static func extract(from text: String) -> (visible: String, changes: [MemoryChange]) {
        var visible = text
        var changes: [MemoryChange] = []
        while let open = visible.range(of: opening) {
            let close = visible.range(of: closing, range: open.upperBound..<visible.endIndex)
            let body = visible[open.upperBound..<(close?.lowerBound ?? visible.endIndex)]
            changes += body.split(whereSeparator: \.isNewline).compactMap { change(fromLine: String($0)) }
            visible.removeSubrange(open.lowerBound..<(close?.upperBound ?? visible.endIndex))
        }
        return (visible.trimmingCharacters(in: .whitespacesAndNewlines), changes)
    }

    /// What can be shown of a text still being written: everything before the block, and nothing
    /// of a block that is only beginning ("<mem" at the very end).
    static func visible(whileWriting text: String) -> String {
        var shown = text
        if let open = shown.range(of: opening) {
            shown = String(shown[..<open.lowerBound])
        } else {
            for length in stride(from: min(opening.count - 1, shown.count), to: 0, by: -1) where shown.hasSuffix(opening.prefix(length)) {
                shown = String(shown.dropLast(length))
                break
            }
        }
        return shown.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func change(fromLine raw: String) -> MemoryChange? {
        let line = raw.trimmingCharacters(in: .whitespaces)
        if line.hasPrefix("+") {
            let parts = line.dropFirst().split(separator: "|", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2, let kind = kinds[parts[0].lowercased()], !parts[1].isEmpty else { return nil }
            return .remember(kind, parts[1])
        }
        if line.hasPrefix("-") {
            let id = line.dropFirst().trimmingCharacters(in: CharacterSet(charactersIn: " []"))
            return id.isEmpty || id.contains(" ") ? nil : .forget(id)
        }
        return nil
    }

    /// Applies the decisions to the book. The book's guard has the last word on each sentence.
    /// - Parameter only: when set, only memories of this kind are accepted (the closing summary writes to the thread only).
    static func apply(_ changes: [MemoryChange], to book: inout MemoryBook, only: MemoryEntry.Kind? = nil, now: Date = Date()) {
        var seen = Set<MemoryChange>()
        for change in changes where seen.insert(change).inserted {
            switch change {
            case .remember(let kind, let text):
                if let only, kind != only { continue }
                book.remember(text, kind: kind, now: now)
            case .forget(let id):
                if only == nil { book.forget(id: id) }
            }
        }
    }
}
