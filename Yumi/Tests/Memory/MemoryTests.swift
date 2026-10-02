import Testing
import Foundation

@Suite struct MemoryBookTests {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func remembersShortSentencesOnce() {
        var book = MemoryBook()
        let kept = book.remember("  Tu préfères\nles réponses courtes ", kind: .person, now: t0)
        #expect(kept?.text == "Tu préfères les réponses courtes")
        let again = book.remember("tu préfères les réponses courtes", kind: .thread, now: t0)
        #expect(again?.id == kept?.id)
        #expect(book.entries.count == 1)
        let empty = book.remember("   ", kind: .person)
        #expect(empty == nil)
    }

    @Test func editForgetAndClear() {
        var book = MemoryBook()
        book.setName("  Esteban ")
        let entry = book.remember("Tu travailles sur Yumi", kind: .project, now: t0, id: "p1")!
        let edited = book.edit(id: "p1", text: "Tu travailles sur Yumi, une app pour la notch", now: t0.addingTimeInterval(60))
        #expect(edited)
        #expect(book.entries.first?.text == "Tu travailles sur Yumi, une app pour la notch")
        #expect(book.entries.first?.date == t0.addingTimeInterval(60))
        #expect(book.entries.first?.id == entry.id)
        let unknown = book.edit(id: "nope", text: "x")
        let secret = book.edit(id: "p1", text: "mot de passe : hunter2")
        #expect(!unknown && !secret)
        #expect(book.entries.first?.text.contains("notch") == true)

        let gone = book.forget(id: "p1")
        let twice = book.forget(id: "p1")
        #expect(gone && !twice)
        book.remember("x y z", kind: .thread)
        book.clear()
        #expect(book.entries.isEmpty)
        #expect(book.name == nil)
    }

    @Test func theNameCanBeSetAndRemoved() {
        var book = MemoryBook()
        book.setName("Léa")
        #expect(book.name == "Léa")
        book.setName("   ")
        #expect(book.name == nil)
    }

    @Test func beyondTheLimitTheOldestOfTheThreadGoFirstAndThePersonNever() {
        var book = MemoryBook()
        for index in 0..<20 { book.remember("Sur toi \(index)", kind: .person, now: t0.addingTimeInterval(Double(index))) }
        for index in 0..<10 { book.remember("Projet \(index)", kind: .project, now: t0.addingTimeInterval(Double(index))) }
        for index in 0..<(MemoryBook.limit) { book.remember("Fil \(index)", kind: .thread, now: t0.addingTimeInterval(100 + Double(index))) }
        #expect(book.entries.count == MemoryBook.limit)
        #expect(book.entries(of: .person).count == 20)
        #expect(book.entries(of: .project).count == 10)
        // The oldest thread entries are the ones that went.
        #expect(book.entries(of: .thread).first?.text == "Fil 30")
        #expect(book.entries(of: .thread).last?.text == "Fil \(MemoryBook.limit - 1)")
    }

    @Test func whenTheThreadIsEmptyProjectsGoButNeverThePerson() {
        var book = MemoryBook()
        for index in 0..<MemoryBook.limit { book.remember("Sur toi \(index)", kind: .person, now: t0) }
        book.remember("Projet ancien", kind: .project, now: t0)
        #expect(book.entries(of: .project).isEmpty)
        let more = book.remember("Encore sur toi", kind: .person, now: t0)
        #expect(more != nil)
        #expect(book.entries(of: .person).count == MemoryBook.limit + 1)
    }

    @Test func theFileIsReadableAndComesBackTheSame() {
        var book = MemoryBook()
        book.setName("Esteban")
        book.remember("Tu préfères les réponses courtes", kind: .person, now: t0, id: "a1")
        book.remember("Yumi : une app pour la notch", kind: .project, now: t0, id: "b2")
        book.remember("Tu voulais revoir la météo", kind: .thread, now: t0, id: "c3")
        let text = book.markdown
        #expect(text.contains("Prénom : Esteban"))
        #expect(text.contains("## Toi\n\n- Tu préfères les réponses courtes <!-- "))
        #expect(text.contains("## Le fil"))
        #expect(MemoryBook(markdown: text) == book)
    }

    @Test func linesWrittenByHandAreRead() {
        let text = """
        # Ce que Yumi retient
        Prénom : Léa

        ## Toi
        - Tu bois du thé
        - mot de passe : hunter2

        ## Rubrique inconnue
        - ignoré

        ## Le fil
        - Avec un identifiant <!-- 2026-10-02T12:00:00Z zz9 -->
        """
        let book = MemoryBook(markdown: text, now: t0)
        #expect(book.name == "Léa")
        #expect(book.entries.map(\.text) == ["Tu bois du thé", "Avec un identifiant"])
        #expect(book.entries.first?.date == t0)
        #expect(book.entries.last?.id == "zz9")
        #expect(MemoryBook(markdown: "").entries.isEmpty)
    }
}

/// What must never reach the file (design/yumi/voix.md).
@Suite struct MemoryGuardTests {
    @Test func secretsAreRefused() {
        let secrets = [
            "Ton mot de passe est hunter2",
            "mot de passe wifi : Maison-2024",
            "Le code de la carte est 4821",
            "Ton code PIN c'est 0000",
            "Le digicode : 45B12",
            "Clé API : sk-ant-api03-abcdefghijklmnop",
            "sk-proj-AbCdEf123456789012345",
            "ghp_abcdefghijklmnopqrstuvwxyz0123456789",
            "Ta carte : 4242 4242 4242 4242",
            "4242424242424242",
            "IBAN FR76 3000 6000 0112 3456 7890 189",
            "Ton RIB : 30006 00001 12345678901 89",
            "token = eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0",
            "Le jeton est a8f3k2m9x7q1w5e4r6t8y0u2",
            "-----BEGIN RSA PRIVATE KEY-----",
            "Le code du coffre est 928374",
            "cvv 123",
        ]
        for secret in secrets {
            #expect(MemoryGuard.looksSecret(secret), "\(secret)")
            #expect(MemoryGuard.cleaned(secret) == nil, "\(secret)")
        }
    }

    @Test func ordinarySentencesAreKept() {
        let fine = [
            "Tu préfères les réponses courtes",
            "Tu travailles sur Yumi, une app macOS pour la notch",
            "Tu changes ton mot de passe tous les mois",
            "Tu écris du code Swift depuis 2019",
            "Ton point produit est le jeudi à 14:30",
            "Tu as 26 tests au vert sur la branche yumi/coeur",
            "Tu m'as montré le fichier Budget-2026.pdf",
            "Tu regardais la page github.com/estebanbaigts/Yumi",
            "Tu veux finir la version 1.0 avant le 15 novembre",
            "Ton associée s'appelle Léa",
            "Tu aimes le code propre et les secrets bien gardés",
        ]
        for sentence in fine {
            #expect(!MemoryGuard.looksSecret(sentence), "\(sentence)")
            #expect(MemoryGuard.cleaned(sentence) == sentence, "\(sentence)")
        }
    }

    @Test func aPastedDocumentIsNotAMemory() {
        #expect(MemoryGuard.cleaned(String(repeating: "contenu ", count: 40)) == nil)
        #expect(MemoryGuard.cleaned("") == nil)
    }

    @Test func nothingForbiddenEntersTheBookByAnyDoor() {
        var book = MemoryBook()
        let learnt = book.remember("Ton mot de passe est hunter2", kind: .person)
        #expect(learnt == nil)
        #expect(MemoryBook(markdown: "## Toi\n- Clé API : sk-ant-api03-abcdefghijklmnop\n").entries.isEmpty)
        #expect(book.entries.isEmpty)
    }
}

@MainActor
@Suite struct MemoryStoreTests {
    private func makeURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("yumi-memory-\(UUID().uuidString)/memoire.md")
    }

    @Test func savesEveryChangeAndReadsItBack() throws {
        let url = makeURL()
        var published: [MemoryBook] = []
        let store = MemoryStore(fileURL: url) { published.append($0) }
        store.start()
        #expect(published == [MemoryBook()])
        #expect(!FileManager.default.fileExists(atPath: url.path))

        store.change { $0.setName("Esteban"); $0.remember("Tu bois du café", kind: .person) }
        #expect(published.count == 2)
        let onDisk = try String(contentsOf: url, encoding: .utf8)
        #expect(onDisk.contains("Prénom : Esteban") && onDisk.contains("- Tu bois du café"))
        let permissions = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
        #expect(permissions == 0o600)

        // Nothing changed: nothing written, nothing reported.
        store.change { $0.setName("Esteban") }
        #expect(published.count == 2)
        store.stop()

        var reloaded: MemoryBook?
        let second = MemoryStore(fileURL: url) { reloaded = $0 }
        second.start()
        #expect(reloaded == store.book)
        second.stop()
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    @Test func answersTheIsland() {
        let url = makeURL()
        var last = MemoryBook()
        let store = MemoryStore(fileURL: url) { last = $0 }
        store.start()
        let center = NotificationCenter.default

        center.post(name: .memorySetName, object: nil, userInfo: ["name": "Léa"])
        #expect(last.name == "Léa")

        store.change { $0.remember("Tu bois du thé", kind: .person, id: "t1"); $0.remember("Tu voulais la météo", kind: .thread, id: "t2") }
        center.post(name: .memoryEdit, object: nil, userInfo: ["id": "t1", "text": "Tu bois du thé vert"])
        #expect(last.entries.first?.text == "Tu bois du thé vert")
        center.post(name: .memoryDelete, object: nil, userInfo: ["id": "t2"])
        #expect(last.entries.map(\.id) == ["t1"])
        center.post(name: .memoryEdit, object: nil, userInfo: ["id": "t1"])
        #expect(last.entries.first?.text == "Tu bois du thé vert")

        center.post(name: .memoryClear, object: nil)
        #expect(last == MemoryBook())
        #expect((try? String(contentsOf: url, encoding: .utf8))?.contains("thé") == false)

        store.stop()
        center.post(name: .memorySetName, object: nil, userInfo: ["name": "Personne"])
        #expect(last.name == nil)
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }
}
