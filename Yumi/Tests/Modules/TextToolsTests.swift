import AppKit
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

// MARK: - Summary, tone, reply, agenda

@Suite struct TextEventTests {
    @Test func onlyWellFormedFieldsAreKept() {
        #expect(TextEvent.checked(title: "Réunion avec Paul", date: "2026-10-15", time: "15:00")
                == TextEvent(title: "Réunion avec Paul", date: "2026-10-15", time: "15:00"))
        // An hour without a day means nothing: a reminder without date
        #expect(TextEvent.checked(title: "Appeler Paul", date: "jeudi", time: "15:00") == TextEvent(title: "Appeler Paul", date: nil, time: nil))
        #expect(TextEvent.checked(title: "Appeler", date: "2026-10-15", time: "25:00")?.time == nil)
        #expect(TextEvent.checked(title: "  ", date: "", time: "") == nil)
    }

    @Test func aDayAndAnHourMakeAnAppointmentAskedFirst() throws {
        let (plan, _) = TextEvent(title: "Réunion", date: "2026-10-15", time: "15:00").plan()
        let step = try #require(plan.steps.first)
        #expect(step.toolID == "add_event")
        #expect(step.requiresApproval)
        #expect(step.arguments["time"] == .string("15:00"))
        #expect(TextEvent(title: "Pain", date: nil, time: nil).plan().0.steps.first?.toolID == "add_reminder")
    }

    @Test(.enabled(if: TextAI.isAvailable, "Apple Intelligence is not on this Mac"))
    func theModelFindsAnAppointmentInAMessage() async throws {
        let now = ISO8601DateFormatter().date(from: "2026-10-12T09:00:00Z")!   // a Monday
        let event = try #require(await TextEvent.find(in: "Salut ! On se voit le 15 octobre 2026 à 15h pour la réunion budget ?", now: now))
        #expect(event.date == "2026-10-15")
        #expect(event.time == "15:00")
    }

    @Test(.enabled(if: TextAI.isAvailable, "Apple Intelligence is not on this Mac"))
    func theModelSummarizesAndAnswers() async throws {
        let message = "Bonjour, je voulais savoir si tu pouvais m'envoyer le rapport trimestriel avant vendredi, nous en avons besoin pour la réunion du conseil. Merci beaucoup et bonne journée."
        let article = String(repeating: "Le conseil municipal a voté hier soir le budget de la ville pour l'année prochaine, avec une hausse des dépenses pour les écoles, les transports en commun et l'entretien des parcs, tandis que les impôts locaux restent stables pour la troisième année consécutive. ", count: 4)
        #expect(try await TextAI.summarize(article).count < article.count)
        #expect(try await !TextAI.reply(to: message).isEmpty)
    }
}

@Suite struct FeatureTests {
    @Test func everyFeatureReadsInBothLanguagesAndCanBeTurnedOff() throws {
        let defaults = try #require(UserDefaults(suiteName: "features-\(UUID().uuidString)"))
        for feature in Feature.allCases {
            #expect(Feature.isOn(feature, defaults) == feature.defaultOn)
            defaults.set(false, forKey: feature.key)
            #expect(!Feature.isOn(feature, defaults))
            #expect(feature.title != feature.detail)
            AppLanguage.$forced.withValue("en") {
                #expect(!feature.title.isEmpty && !feature.detail.contains("%@"), "\(feature)")
            }
        }
        #expect(!Feature.voiceReplies.defaultOn)
        AppLanguage.$forced.withValue("en") {
            #expect(Feature.batteryMood.detail == "He's hungry below 15 %, happy when you plug the charger in.")
        }
        #expect(Feature.batteryMood.detail == "Il a faim sous 15 %, il est content quand tu branches le chargeur.")
    }
}

// MARK: - The text of an image

@Suite struct ImageTextTests {
    /// A PNG with these words drawn in black on white.
    private func picture(_ text: String) throws -> URL {
        let size = NSSize(width: 900, height: 160)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.white.setFill()
            rect.fill()
            (text as NSString).draw(at: NSPoint(x: 30, y: 60),
                                    withAttributes: [.font: NSFont.systemFont(ofSize: 42), .foregroundColor: NSColor.black])
            return true
        }
        let tiff = try #require(image.tiffRepresentation)
        let png = try #require(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ocr-\(UUID().uuidString).png")
        try png.write(to: url)
        return url
    }

    @Test func theTextOfAScreenshotIsRead() async throws {
        let text = try #require(await ImageText.read(try picture("Réunion budget jeudi")))
        #expect(text.contains("budget"))
        #expect(text.contains("jeudi"))
    }

    @Test func onlyImagesAreRead() async throws {
        let notes = FileManager.default.temporaryDirectory.appendingPathComponent("notes-\(UUID().uuidString).txt")
        try "texte".write(to: notes, atomically: true, encoding: .utf8)
        #expect(!ImageText.isImage(notes))
        #expect(await ImageText.read(notes) == nil)
        #expect(ImageText.isImage(URL(fileURLWithPath: "/tmp/capture.PNG")))
    }
}
