import Foundation

// MARK: - What Yumi remembers
// See design/yumi/voix.md and Contracts/MemoryTypes.swift. The book is the memory itself, pure:
// a first name and short sentences. `MemoryStore` keeps it in a file and tells the app.

struct MemoryBook: Equatable, Sendable {
    /// How many memories are kept. Beyond it the oldest of the thread go first, then the oldest
    /// about projects. What is known about the person is never dropped.
    static let limit = 120
    /// A memory is a short sentence, not a document.
    static let maxLength = 200

    var name: String?
    private(set) var entries: [MemoryEntry] = []

    // MARK: Changing

    /// Remembers a sentence. Returns the entry kept, or nil when there is nothing to keep:
    /// an empty text, something Yumi must never remember, or a sentence already known.
    @discardableResult
    mutating func remember(_ text: String, kind: MemoryEntry.Kind, now: Date = Date(),
                           id: String = MemoryBook.newID()) -> MemoryEntry? {
        guard let clean = MemoryGuard.cleaned(text) else { return nil }
        if let known = entries.first(where: { $0.text.caseInsensitiveCompare(clean) == .orderedSame }) { return known }
        let entry = MemoryEntry(id: id, kind: kind, text: clean, date: Self.toTheSecond(now))
        entries.append(entry)
        trim()
        return entries.contains(entry) ? entry : nil
    }

    /// Corrects an entry. A correction that must not be remembered leaves the entry as it was.
    @discardableResult
    mutating func edit(id: String, text: String, now: Date = Date()) -> Bool {
        guard let index = entries.firstIndex(where: { $0.id == id }), let clean = MemoryGuard.cleaned(text) else { return false }
        entries[index].text = clean
        entries[index].date = Self.toTheSecond(now)
        return true
    }

    @discardableResult
    mutating func forget(id: String) -> Bool {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return false }
        entries.remove(at: index)
        return true
    }

    /// Erases everything, first name included.
    mutating func clear() {
        name = nil
        entries = []
    }

    /// Sets the first name. An empty one removes it.
    mutating func setName(_ newName: String) {
        let clean = newName.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        name = clean.isEmpty ? nil : String(clean.prefix(40))
    }

    private mutating func trim() {
        for kind in [MemoryEntry.Kind.thread, .project] {
            while entries.count > Self.limit,
                  let oldest = entries.filter({ $0.kind == kind }).min(by: { $0.date < $1.date }),
                  let index = entries.firstIndex(of: oldest) {
                entries.remove(at: index)
            }
        }
    }

    /// Dates are kept to the second, which is what the file holds.
    private static func toTheSecond(_ date: Date) -> Date {
        Date(timeIntervalSince1970: date.timeIntervalSince1970.rounded(.down))
    }

    static func newID() -> String {
        String(UUID().uuidString.lowercased().prefix(8))
    }

    // MARK: Reading

    func entries(of kind: MemoryEntry.Kind) -> [MemoryEntry] {
        entries.filter { $0.kind == kind }
    }

    // MARK: File
    // A Markdown file a person can read and edit: a first name, then one list per kind. Each line
    // ends with its date and identifier in a comment, which Markdown readers do not show.

    private static let titles: [(MemoryEntry.Kind, String)] = [(.person, "Toi"), (.project, "Tes projets"), (.thread, "Le fil")]

    var markdown: String {
        var lines = ["# Ce que Yumi retient", "",
                     "Tu peux lire, corriger ou supprimer des lignes. Rien ici ne quitte ton Mac, sauf ce que le chat envoie pour te répondre.", "",
                     "Prénom : \(name ?? "")", ""]
        let stamp = ISO8601DateFormatter()
        for (kind, title) in Self.titles {
            lines.append("## \(title)")
            lines.append("")
            for entry in entries(of: kind) {
                lines.append("- \(entry.text) <!-- \(stamp.string(from: entry.date)) \(entry.id) -->")
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    init() {}

    /// Reads the file back. Lines added by hand, without the comment, get a date and an identifier.
    /// Everything read goes through the same guard as what Yumi learns.
    init(markdown: String, now: Date = Date()) {
        let stamp = ISO8601DateFormatter()
        var kind: MemoryEntry.Kind?
        for raw in markdown.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("Prénom :") {
                setName(String(line.dropFirst("Prénom :".count)))
            } else if line.hasPrefix("## ") {
                let title = line.dropFirst(3).trimmingCharacters(in: .whitespaces)
                kind = Self.titles.first { $0.1.caseInsensitiveCompare(title) == .orderedSame }?.0
            } else if line.hasPrefix("- "), let kind {
                var text = String(line.dropFirst(2))
                var date = now
                var id = Self.newID()
                if let open = text.range(of: "<!--", options: .backwards), let close = text.range(of: "-->", options: .backwards),
                   open.upperBound <= close.lowerBound {
                    let parts = text[open.upperBound..<close.lowerBound].split(separator: " ")
                    if let first = parts.first, let parsed = stamp.date(from: String(first)) { date = parsed }
                    if parts.count >= 2, let last = parts.last { id = String(last) }
                    text = String(text[..<open.lowerBound])
                }
                if entries.contains(where: { $0.id == id }) { id = Self.newID() }
                guard let clean = MemoryGuard.cleaned(text) else { continue }
                entries.append(MemoryEntry(id: id, kind: kind, text: clean, date: date))
            }
        }
        trim()
    }
}

// MARK: - What Yumi never remembers

/// The last check before anything is written (design/yumi/voix.md, « Ce qu'il ne retient jamais »).
/// The conversation itself sorts what is worth remembering; this guard only makes sure that a
/// secret or a pasted document can never reach the file, whatever the conversation decided.
enum MemoryGuard {
    /// The sentence ready to be kept (one line, trimmed), or nil when it must not be remembered.
    static func cleaned(_ text: String) -> String? {
        let oneLine = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !oneLine.isEmpty, oneLine.count <= MemoryBook.maxLength, !looksSecret(oneLine) else { return nil }
        return oneLine
    }

    /// True for a password, a key, a code, a card or account number.
    static func looksSecret(_ text: String) -> Bool {
        let lower = text.lowercased()

        // Named secrets followed by a value: "mot de passe : hunter2", "code 4821", "token=abc".
        let names = ["mot de passe", "mdp", "password", "passphrase", "code pin", "pin", "code secret", "code de la carte",
                     "code d'accès", "code wifi", "digicode", "cvv", "cvc", "cryptogramme", "iban", "rib", "bic",
                     "numéro de carte", "numero de carte", "numéro de compte", "numero de compte", "numéro de sécu",
                     "numero de secu", "clé api", "cle api", "api key", "apikey", "token", "jeton", "secret", "identifiant et"]
        for name in names where containsWord(name, in: lower) {
            let after = lower.components(separatedBy: name).dropFirst().joined(separator: name)
            // The name alone is harmless ("tu changes ton mot de passe tous les mois"); a value after it is not.
            if after.range(of: #"^[^.!?]{0,30}?(:|=|est|is|c'est)\s*\S"#, options: .regularExpression) != nil { return true }
            if after.range(of: #"\d{3,}"#, options: .regularExpression) != nil { return true }
        }
        if containsWord("code", in: lower), lower.range(of: #"code(\s+\d{4,}|[^.!?\d]{0,25}?(:|=|est|c'est)\s*\w*\d{3,})"#, options: .regularExpression) != nil { return true }

        // Keys by their shape.
        let shapes = [#"\bsk-[A-Za-z0-9_\-]{8,}"#, #"\bgh[pousr]_[A-Za-z0-9]{20,}"#, #"\bAKIA[0-9A-Z]{12,}"#, #"\bxox[abprs]-[A-Za-z0-9\-]{10,}"#,
                      #"-----BEGIN [A-Z ]*PRIVATE KEY-----"#, #"\beyJ[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{10,}"#,
                      #"\b[A-Z]{2}\d{2}(?: ?[A-Z0-9]{4}){3,7}(?: ?[A-Z0-9]{1,3})?\b"#]
        for shape in shapes where text.range(of: shape, options: .regularExpression) != nil { return true }

        // A long run of mixed letters and digits is a key or a token, not a sentence.
        for word in text.split(whereSeparator: { $0.isWhitespace || "«»\"'()".contains($0) }) where word.count >= 20 {
            let letters = word.contains(where: \.isLetter), digits = word.contains(where: \.isNumber)
            if letters && digits && !word.contains("/") && !word.contains(".") { return true }
        }

        // Card numbers: 13 to 19 digits, possibly grouped, that pass the Luhn check.
        if let regex = try? NSRegularExpression(pattern: #"(?<!\d)(?:\d[ \-]?){12,18}\d(?!\d)"#) {
            let range = NSRange(text.startIndex..., in: text)
            for match in regex.matches(in: text, range: range) {
                if let found = Range(match.range, in: text), luhn(text[found].filter(\.isNumber)) { return true }
            }
        }
        return false
    }

    private static func containsWord(_ word: String, in text: String) -> Bool {
        text.range(of: "(?<![\\p{L}\\d])\(NSRegularExpression.escapedPattern(for: word))(?![\\p{L}\\d])", options: .regularExpression) != nil
    }

    private static func luhn(_ digits: String) -> Bool {
        var sum = 0
        for (index, character) in digits.reversed().enumerated() {
            guard var value = character.wholeNumberValue else { return false }
            if index % 2 == 1 { value *= 2; if value > 9 { value -= 9 } }
            sum += value
        }
        return digits.count >= 13 && sum % 10 == 0
    }
}
