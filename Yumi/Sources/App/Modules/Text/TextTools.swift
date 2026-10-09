import AppKit
import NaturalLanguage
import Translation

// MARK: - Correcting and translating, on this Mac
// macOS's own spelling checker and Apple's on-device translation: nothing leaves the Mac and
// nothing is billed. The spelling checker fixes typos and accents; it does not see grammar.

/// One fix the spelling checker proposes. The person can leave it out before replacing.
struct TextFix: Identifiable, Equatable, Sendable {
    var id: Int { location }
    /// UTF-16 offset and length in the original text.
    let location: Int
    let length: Int
    let original: String
    let replacement: String
}

enum TextCorrector {
    /// The language the text is written in ("fr", "en"), when it can be told.
    static func language(of text: String) -> String? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        return recognizer.dominantLanguage?.rawValue
    }

    /// The fixes for this text, in its own language, first one first.
    @MainActor
    static func fixes(for text: String) -> [TextFix] {
        guard !text.isEmpty else { return [] }
        let checker = NSSpellChecker.shared
        let language = language(of: text).flatMap { candidate in
            checker.availableLanguages.first { $0 == candidate || $0.hasPrefix(candidate + "_") }
        }
        // Words checked against the dictionary of the text's language, not of the Mac's
        let previous = checker.automaticallyIdentifiesLanguages
        checker.automaticallyIdentifiesLanguages = language == nil
        if let language { _ = checker.setLanguage(language) }
        let tag = NSSpellChecker.uniqueSpellDocumentTag()
        defer {
            checker.closeSpellDocument(withTag: tag)
            checker.automaticallyIdentifiesLanguages = previous
        }
        let nsText = text as NSString
        let results = checker.check(text, range: NSRange(location: 0, length: nsText.length),
                                    types: NSTextCheckingResult.CheckingType.spelling.rawValue,
                                    options: nil, inSpellDocumentWithTag: tag, orthography: nil, wordCount: nil)
        return results.compactMap { result in
            guard result.resultType == .spelling else { return nil }
            let word = nsText.substring(with: result.range)
            let replacement = checker.correction(forWordRange: result.range, in: text, language: language ?? checker.language(),
                                                 inSpellDocumentWithTag: tag)
                ?? checker.guesses(forWordRange: result.range, in: text, language: language, inSpellDocumentWithTag: tag)?.first
            guard let replacement, replacement != word else { return nil }
            return TextFix(location: result.range.location, length: result.range.length, original: word, replacement: replacement)
        }
    }

    /// The text with the fixes kept, applied from the end so the offsets stay right.
    static func apply(_ fixes: [TextFix], to text: String) -> String {
        let result = NSMutableString(string: text)
        for fix in fixes.sorted(by: { $0.location > $1.location })
        where fix.location + fix.length <= result.length && result.substring(with: NSRange(location: fix.location, length: fix.length)) == fix.original {
            result.replaceCharacters(in: NSRange(location: fix.location, length: fix.length), with: fix.replacement)
        }
        return result as String
    }
}

/// The languages offered for a translation, in the order of the menu.
enum TextLanguage: String, CaseIterable, Identifiable, Sendable {
    case fr, en, es, de, it, pt

    var id: String { rawValue }

    var name: String {
        switch self {
        case .fr: loc("Français")
        case .en: loc("Anglais")
        case .es: loc("Espagnol")
        case .de: loc("Allemand")
        case .it: loc("Italien")
        case .pt: loc("Portugais")
        }
    }

    /// French goes to English, every other language to French.
    static func target(for source: String?) -> TextLanguage { source == "fr" ? .en : .fr }
}

enum TextTranslator {
    enum Failure: Error, Equatable {
        case sameLanguage
        /// The languages have to be downloaded first, in System Settings.
        case notInstalled
        case unsupported
        case needsNewerMac
        case failed(String)

        var reason: String {
            switch self {
            case .sameLanguage: loc("Le texte est déjà dans cette langue.")
            case .notInstalled: loc("Ces langues ne sont pas encore sur ton Mac : ajoute-les dans Réglages Système › Général › Langue et région › Langues de traduction.")
            case .unsupported: loc("Apple ne sait pas traduire entre ces deux langues.")
            case .needsNewerMac: loc("La traduction sur le Mac demande macOS 26.")
            case .failed(let why): loc("La traduction a échoué : \(why)")
            }
        }
    }

    static func translate(_ text: String, from source: String?, to target: TextLanguage) async throws(Failure) -> String {
        guard let source else { throw .unsupported }
        guard source != target.rawValue else { throw .sameLanguage }
        guard #available(macOS 26.0, *) else { throw .needsNewerMac }
        let from = Locale.Language(identifier: source), to = Locale.Language(identifier: target.rawValue)
        switch await LanguageAvailability().status(from: from, to: to) {
        case .installed: break
        case .supported: throw .notInstalled
        default: throw .unsupported
        }
        do {
            return try await TranslationSession(installedSource: from, target: to).translate(text).targetText
        } catch {
            throw .failed(error.localizedDescription)
        }
    }
}

// MARK: - The selection of the app in front

/// The text selected in the app in front, read and replaced through Accessibility.
struct TextSelection {
    let element: AXUIElement
    let text: String
    let appName: String

    /// What is selected in the focused field of the app in front, nil when nothing is (or the
    /// app does not tell: some apps keep their text out of Accessibility).
    @MainActor
    static func current() -> TextSelection? {
        guard AXIsProcessTrusted(), let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return nil }
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
        let element = focused as! AXUIElement
        var selected: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selected) == .success,
              let text = (selected as? String)?.nonEmptyTrimmed else { return nil }
        return TextSelection(element: element, text: text, appName: app.localizedName ?? "")
    }

    /// Puts `text` in place of the selection. False when the app refused.
    func replace(with text: String) -> Bool {
        AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFString) == .success
    }
}
