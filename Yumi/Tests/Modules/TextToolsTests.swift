import Foundation
import Testing

// Correcting and translating on the Mac, and the shortcut that starts it.

@Suite struct TextToolsTests {
    @Test func keptFixesAreAppliedFromTheEndAndTheOthersLeft() {
        let text = "Je suis tres content, vous etes la."
        let fixes = [TextFix(location: 8, length: 4, original: "tres", replacement: "très"),
                     TextFix(location: 27, length: 4, original: "etes", replacement: "êtes")]
        #expect(TextCorrector.apply(fixes, to: text) == "Je suis très content, vous êtes la.")
        #expect(TextCorrector.apply([fixes[1]], to: text) == "Je suis tres content, vous êtes la.")
        // A text changed since: a fix that no longer matches is not applied
        #expect(TextCorrector.apply(fixes, to: "Je suis TRES content") == "Je suis TRES content")
    }

    @Test @MainActor func macOSFixesAccentsInTheTextsOwnLanguage() {
        let fixes = TextCorrector.fixes(for: "Bonjour, je voulais savoir si vous etes disponible demain pour une reunion.")
        #expect(fixes.map(\.replacement).contains("êtes"))
        #expect(fixes.map(\.replacement).contains("réunion"))
        #expect(TextCorrector.fixes(for: "").isEmpty)
    }

    @Test func frenchGoesToEnglishAndTheRestToFrench() {
        #expect(TextCorrector.language(of: "Bonjour, comment vas-tu aujourd'hui ?") == "fr")
        #expect(TextLanguage.target(for: "fr") == .en)
        #expect(TextLanguage.target(for: "de") == .fr)
        #expect(TextLanguage.target(for: nil) == .fr)
    }

    @Test func aTextIsNotTranslatedIntoItsOwnLanguage() async {
        await #expect(throws: TextTranslator.Failure.sameLanguage) {
            try await TextTranslator.translate("Bonjour", from: "fr", to: .fr)
        }
        await #expect(throws: TextTranslator.Failure.unsupported) {
            try await TextTranslator.translate("???", from: nil, to: .en)
        }
    }

    @Test func eachShortcutKeepsItsOwnKeys() throws {
        let defaults = try #require(UserDefaults(suiteName: "shortcuts-\(UUID().uuidString)"))
        #expect(QuickTaskShortcut.stored(defaults, QuickTaskShortcut.textTool) == QuickTaskShortcut.textTool.standard)
        #expect(QuickTaskShortcut.stored(defaults) == QuickTaskShortcut.standard)
        QuickTaskShortcut(flags: 1 << 20, keyCode: 3).store(defaults, QuickTaskShortcut.textTool)
        #expect(QuickTaskShortcut.stored(defaults, QuickTaskShortcut.textTool)?.keyCode == 3)
        #expect(QuickTaskShortcut.stored(defaults) == QuickTaskShortcut.standard)
        defaults.set(false, forKey: QuickTaskShortcut.textTool.enabled)
        #expect(QuickTaskShortcut.stored(defaults, QuickTaskShortcut.textTool) == nil)
    }
}

// MARK: - Apple Intelligence

@Suite struct TextAITests {
    @Test func theChangedWordsAreMarked() {
        let words = TextDiff.words(from: "Je suis aller au marché, il fesait beau.", to: "Je suis allé au marché, il faisait beau.")
        #expect(words.map(\.text).joined() == "Je suis allé au marché, il faisait beau.")
        #expect(words.filter(\.changed).map { $0.text.trimmingCharacters(in: .whitespaces) } == ["allé", "faisait"])
        #expect(TextDiff.words(from: "Rien", to: "Rien").allSatisfy { !$0.changed })
    }

    @Test func anAnswerThatIsNotTheTextIsRefused() throws {
        #expect(try TextAI.usable("« Bonjour à tous. »", for: "Bonjour a tous.") == "Bonjour à tous.")
        #expect(throws: TextAI.Failure.unusable) { try TextAI.usable("", for: "Bonjour") }
        // A comment or a summary instead of the text
        #expect(throws: TextAI.Failure.unusable) {
            try TextAI.usable("Voici le texte corrigé avec toutes les explications de chaque faute, une par une, et pourquoi.", for: "Bonjour")
        }
    }

    @Test(.enabled(if: TextAI.isAvailable, "Apple Intelligence is not on this Mac"))
    func theModelOfTheMacCorrectsGrammar() async throws {
        let corrected = try await TextAI.correct("Les enfant était contant.")
        #expect(corrected.contains("enfants"))
        #expect(corrected.contains("étaient"))
    }
}
