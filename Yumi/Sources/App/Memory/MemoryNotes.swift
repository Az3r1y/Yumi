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
    /// The person gave their first name.
    case name(String)
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
    prénom | son prénom, quand elle te le donne ou le corrige
    \(closing)
    Retiens ce qu'elle te demande de retenir, et de toi-même toute information durable qui passe dans la conversation. Quand elle te montre un fichier ou une fenêtre, retiens dans le fil de quoi il s'agissait (« Tu m'as montré le devis du client Dupont »), jamais son contenu. Quand elle dit d'oublier quelque chose, retire le souvenir concerné avec son identifiant entre crochets. Quand elle te dit comment elle s'appelle, range-le avec la ligne « prénom », pas dans un souvenir. Écris chaque souvenir en français, en t'adressant à elle (« Tu préfères… »), en une phrase, sans tiret long.
    Ne retiens jamais : un mot de passe, une clé, un code, un numéro de carte ou de compte ; le contenu d'un fichier ou d'une fenêtre ; une information sur une autre personne, au-delà de son prénom. Dans le doute, ne retiens pas.
    La plupart des réponses n'ont rien à retenir : dans ce cas n'écris pas de bloc. Ne parle jamais de ce bloc, et ne dis pas que tu as noté quelque chose sauf si on te l'a demandé.
    """

    /// Asked at the end of a conversation, to keep a trace of it in the thread.
    static let summaryRequest = """
    La conversation se termine. Sans utiliser d'outil, écris pour ta mémoire ce qu'il faut en garder, en une à trois lignes, dans ce format exact et rien d'autre :
    \(opening)
    + fil | une phrase adressée à la personne (« Tu voulais… ») : ce qu'elle voulait, ce qui a été fait, ce qui reste en suspens
    \(closing)
    Chaque ligne commence par « + fil | ». Écris toujours au moins une ligne dès qu'elle a demandé ou dit quelque chose de précis ; réponds seulement « rien » si la conversation ne contenait que des salutations. Ne répète pas ce que ta mémoire contient déjà : complète-le. Mêmes interdits que d'habitude, et pas de tiret long.
    """

    private static let kinds: [String: MemoryEntry.Kind] = ["toi": .person, "projet": .project, "fil": .thread]

    /// Separates what the person reads from what goes to the memory.
    /// - Parameter unknownKindAs: the kind given to a "+" line whose kind is not one of the three.
    ///   The closing summary only writes to the thread, whatever word the line starts with.
    static func extract(from text: String, unknownKindAs fallback: MemoryEntry.Kind? = nil) -> (visible: String, changes: [MemoryChange]) {
        var visible = text
        var changes: [MemoryChange] = []
        while let open = visible.range(of: opening) {
            let close = visible.range(of: closing, range: open.upperBound..<visible.endIndex)
            let body = visible[open.upperBound..<(close?.lowerBound ?? visible.endIndex)]
            changes += body.split(whereSeparator: \.isNewline).compactMap { change(fromLine: String($0), unknownKindAs: fallback) }
            visible.removeSubrange(open.lowerBound..<(close?.upperBound ?? visible.endIndex))
        }
        return (VoiceRules.withoutLongDashes(visible).trimmingCharacters(in: .whitespacesAndNewlines), changes)
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
        return VoiceRules.withoutLongDashes(shown).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func change(fromLine raw: String, unknownKindAs fallback: MemoryEntry.Kind?) -> MemoryChange? {
        let line = raw.trimmingCharacters(in: .whitespaces)
        let fields = line.drop { $0 == "+" }.split(separator: "|", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
        if fields.count == 2, ["prénom", "prenom"].contains(fields[0].lowercased()), !fields[1].isEmpty {
            return .name(fields[1])
        }
        if line.hasPrefix("+") {
            guard fields.count == 2, let kind = kinds[fields[0].lowercased()] ?? fallback, !fields[1].isEmpty else { return nil }
            return .remember(kind, fields[1])
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
            case .name(let name):
                // A first name is one or a few words, never a sentence.
                if only == nil, name.count <= 40, !MemoryGuard.looksSecret(name) { book.setName(name) }
            }
        }
    }
}

/// Rules of the voice sheet that the app enforces by itself, whatever the conversation writes.
enum VoiceRules {
    /// Yumi never writes a long dash: one used as a pause becomes a comma, any other a hyphen.
    static func withoutLongDashes(_ text: String) -> String {
        guard text.contains("—") || text.contains("–") else { return text }
        var result = text
        for dash in ["—", "–"] {
            result = result.replacingOccurrences(of: " \(dash) ", with: ", ")
            result = result.replacingOccurrences(of: dash, with: "-")
        }
        return result
    }
}
