import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Apple Intelligence's on-device model (macOS 26), for correcting grammar as well as spelling,
/// and for translating. It runs on the Mac: nothing leaves it, nothing is billed. When it is not
/// there (an older macOS, Apple Intelligence turned off), `TextCorrector` and `TextTranslator`
/// do the work instead.
enum TextAI {
    enum Failure: Error, Equatable {
        case unavailable
        /// The answer looked like something else than the text: a comment, a summary, nothing.
        case unusable
        case failed(String)
    }

    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *), case .available = SystemLanguageModel.default.availability { return true }
        #endif
        return false
    }

    static func correct(_ text: String) async throws(Failure) -> String {
        try await answer(text, instructions: """
            Tu corriges l'orthographe, la grammaire et la ponctuation du texte donné, dans sa propre langue. \
            Tu ne changes ni le sens, ni le ton, ni les noms propres, et tu gardes les retours à la ligne. \
            Si le texte est déjà correct, tu le rends tel quel. \
            Réponds uniquement avec le texte corrigé, sans guillemets ni commentaire.
            """)
    }

    static func translate(_ text: String, to language: TextLanguage) async throws(Failure) -> String {
        try await answer(text, instructions: """
            Translate the given text into natural \(language.englishName). Keep the meaning, the tone, the names \
            and the line breaks. Answer with the translation only, without quotes or comments.
            """)
    }

    /// A few lines for a long text, in its own language.
    static func summarize(_ text: String) async throws(Failure) -> String {
        try await answer(text, instructions: """
            Tu résumes le texte donné en quelques lignes, dans sa propre langue, sans rien inventer. \
            Réponds uniquement avec le résumé.
            """, freeLength: true)
    }

    enum Tone: String, CaseIterable, Identifiable, Sendable {
        case formal, shorter, friendly
        var id: String { rawValue }
        var name: String {
            switch self {
            case .formal: loc("Plus formel")
            case .shorter: loc("Plus court")
            case .friendly: loc("Plus amical")
            }
        }
        fileprivate var instruction: String {
            switch self {
            case .formal: "plus formel et professionnel"
            case .shorter: "plus court et plus direct, en gardant l'essentiel"
            case .friendly: "plus chaleureux et amical"
            }
        }
    }

    static func rewrite(_ text: String, tone: Tone) async throws(Failure) -> String {
        try await answer(text, instructions: """
            Tu réécris le texte donné, dans sa propre langue, sur un ton \(tone.instruction). \
            Tu gardes le sens et les informations. Réponds uniquement avec le texte réécrit, sans commentaire.
            """, freeLength: tone == .shorter)
    }

    /// A draft answer to a message, in its language, for the person to read and change.
    static func reply(to text: String) async throws(Failure) -> String {
        try await answer(text, instructions: """
            Le texte donné est un message reçu. Tu rédiges une réponse courte et polie, dans la langue du message, \
            à la première personne, sans inventer de faits ni d'engagements précis. \
            Réponds uniquement avec la réponse, sans objet ni commentaire.
            """, freeLength: true)
    }

    /// For an answer whose length has nothing to do with the text's (a summary, a reply): only
    /// an empty one is refused.
    private static func answer(_ text: String, instructions: String, freeLength: Bool) async throws(Failure) -> String {
        guard freeLength else { return try await answer(text, instructions: instructions) }
        #if canImport(FoundationModels)
        guard #available(macOS 26.0, *), isAvailable else { throw .unavailable }
        let reply: String
        do {
            reply = try await LanguageModelSession(instructions: instructions).respond(to: text).content
        } catch {
            throw .failed(error.localizedDescription)
        }
        guard let answer = reply.nonEmptyTrimmed else { throw .unusable }
        return answer
        #else
        throw .unavailable
        #endif
    }

    private static func answer(_ text: String, instructions: String) async throws(Failure) -> String {
        #if canImport(FoundationModels)
        guard #available(macOS 26.0, *), isAvailable else { throw .unavailable }
        let reply: String
        do {
            reply = try await LanguageModelSession(instructions: instructions).respond(to: text).content
        } catch {
            throw .failed(error.localizedDescription)
        }
        return try usable(reply, for: text)
        #else
        throw .unavailable
        #endif
    }

    /// The model's answer, without the quotes it sometimes adds, when it can be the text
    /// corrected or translated: not empty, and of a comparable length.
    static func usable(_ reply: String, for text: String) throws(Failure) -> String {
        var answer = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        for (open, close) in [("\"", "\""), ("«", "»"), ("“", "”")]
        where answer.hasPrefix(open) && answer.hasSuffix(close) && !text.hasPrefix(open) && answer.count > 2 {
            answer = String(answer.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
        }
        let ratio = Double(answer.count) / Double(max(1, text.count))
        guard !answer.isEmpty, ratio > 0.4, ratio < 2.5 else { throw .unusable }
        return answer
    }
}

extension TextLanguage {
    /// The name the model is told, in English.
    var englishName: String {
        switch self {
        case .fr: "French"
        case .en: "English"
        case .es: "Spanish"
        case .de: "German"
        case .it: "Italian"
        case .pt: "Portuguese"
        }
    }
}

/// The words of a corrected text, each marked when it is not in the original: what the island
/// highlights before the person replaces anything.
enum TextDiff {
    struct Word: Equatable {
        let text: String
        let changed: Bool
    }

    static func words(from original: String, to corrected: String) -> [Word] {
        let before = tokens(original), after = tokens(corrected)
        let inserted = Set(after.difference(from: before).insertions.compactMap { change -> Int? in
            if case .insert(let offset, _, _) = change { return offset }
            return nil
        })
        return after.enumerated().map { Word(text: $0.element, changed: inserted.contains($0.offset)) }
    }

    /// Words with the spaces that follow them, so that joining them gives the text back.
    static func tokens(_ text: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var inSpace = false
        for character in text {
            if character.isWhitespace {
                inSpace = true
            } else if inSpace {
                tokens.append(current)
                current = ""
                inSpace = false
            }
            current.append(character)
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }
}
