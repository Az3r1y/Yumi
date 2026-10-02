import Testing
import Foundation

@Suite struct MemoryPromptTests {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func withoutAnythingYumiIsToldNotToInventAName() {
        let text = MemoryPrompt.knowledge(MemoryBook())
        #expect(text == "Tu ne connais pas encore le prénom de la personne. Ne l'invente pas.")
    }

    @Test func theNameAndTheMemoriesAreGivenWithTheirIdentifiers() {
        var book = MemoryBook()
        book.setName("Esteban")
        book.remember("Tu préfères les réponses courtes", kind: .person, now: t0, id: "a1")
        book.remember("Yumi : une app pour la notch", kind: .project, now: t0, id: "b2")
        book.remember("Tu voulais revoir la météo", kind: .thread, now: t0, id: "c3")
        let text = MemoryPrompt.knowledge(book)
        #expect(text.contains("s'appelle Esteban."))
        #expect(text.contains("Ce que tu sais d'elle :\n[a1] Tu préfères les réponses courtes"))
        #expect(text.contains("Ses projets :\n[b2] Yumi : une app pour la notch"))
        #expect(text.contains("Le fil récent :\n[c3] Tu voulais revoir la météo"))
        #expect(text.contains("Ne le récite pas"))
    }

    @Test func onlyTheLatestOfTheThreadIsGiven() {
        var book = MemoryBook()
        for index in 0..<40 { book.remember("Fil \(index)", kind: .thread, now: t0.addingTimeInterval(Double(index)), id: "f\(index)") }
        let text = MemoryPrompt.knowledge(book)
        #expect(!text.contains("[f24]"))
        #expect(text.contains("[f25] Fil 25") && text.contains("[f39] Fil 39"))
    }

    @Test func everyConversationReceivesIt() {
        var book = MemoryBook()
        book.setName("Léa")
        let prompt = ChatPhrases.systemPrompt(characterName: "Yumi", folder: "/Users/lea/Downloads", memory: book)
        #expect(prompt.contains("s'appelle Léa."))
        #expect(prompt.contains("/Users/lea/Downloads"))
        #expect(!ChatPhrases.systemPrompt(characterName: "Yumi", folder: "/d").contains("prénom"))
    }
}
