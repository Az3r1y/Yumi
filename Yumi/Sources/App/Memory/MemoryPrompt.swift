import Foundation

/// What a conversation is told about the person, so Yumi takes it into account without being asked.
enum MemoryPrompt {
    /// How many entries of the thread a conversation receives: the latest ones.
    static let threadShare = 15

    /// The part of the system prompt that carries the first name and the memories, or an empty
    /// string when Yumi knows nothing yet. Each memory comes with its identifier, which the
    /// conversation quotes to forget one.
    static func knowledge(_ book: MemoryBook) -> String {
        var lines: [String] = []
        if let name = book.name {
            lines.append("La personne à qui tu parles s'appelle \(name).")
        } else {
            lines.append("Tu ne connais pas encore le prénom de la personne. Ne l'invente pas.")
        }
        let sections: [(String, [MemoryEntry])] = [
            ("Ce que tu sais d'elle", book.entries(of: .person)),
            ("Ses projets", book.entries(of: .project)),
            ("Le fil récent", Array(book.entries(of: .thread).sorted { $0.date < $1.date }.suffix(threadShare))),
        ]
        for (title, entries) in sections where !entries.isEmpty {
            lines.append("\(title) :")
            lines += entries.map { "[\($0.id)] \($0.text)" }
        }
        guard book.name != nil || !book.entries.isEmpty else { return lines.joined(separator: "\n") }
        lines.append("Tiens compte de tout cela naturellement, comme quelqu'un qui connaît la personne. Ne le récite pas, ne dis pas que tu t'en souviens sauf si on te le demande, et ne cite jamais les identifiants entre crochets.")
        return lines.joined(separator: "\n")
    }
}
