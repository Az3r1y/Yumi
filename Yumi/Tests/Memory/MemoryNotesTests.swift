import Testing
import Foundation

/// What the conversation decides to remember, read from the block at the end of its answer.
@Suite struct MemoryNotesTests {
    private let answer = """
    C'est noté.

    <memoire>
    + toi | Tu préfères les réponses courtes
    + projet | Yumi : tu avances sur la mémoire
    + fil | Tu m'as montré le devis du client Dupont
    - a1b2
    </memoire>
    """

    @Test func theBlockIsTakenOutOfWhatThePersonReads() {
        let (visible, changes) = MemoryNotes.extract(from: answer)
        #expect(visible == "C'est noté.")
        #expect(changes == [.remember(.person, "Tu préfères les réponses courtes"),
                            .remember(.project, "Yumi : tu avances sur la mémoire"),
                            .remember(.thread, "Tu m'as montré le devis du client Dupont"),
                            .forget("a1b2")])
    }

    @Test func anAnswerWithoutBlockIsLeftAlone() {
        let (visible, changes) = MemoryNotes.extract(from: "Il fait 19°.")
        #expect(visible == "Il fait 19°.")
        #expect(changes.isEmpty)
    }

    @Test func malformedLinesAreIgnored() {
        let text = "ok\n<memoire>\n+ inconnu | x\n+ toi |\n+ toi sans barre\nbla bla\n- \n- deux mots\n- [c3]\n+ FIL | Tu voulais la météo\n</memoire>"
        #expect(MemoryNotes.extract(from: text).changes == [.forget("c3"), .remember(.thread, "Tu voulais la météo")])
    }

    @Test func anUnclosedBlockIsStillHidden() {
        let (visible, changes) = MemoryNotes.extract(from: "Voilà.\n<memoire>\n+ toi | Tu bois du thé")
        #expect(visible == "Voilà.")
        #expect(changes == [.remember(.person, "Tu bois du thé")])
    }

    @Test func nothingOfTheBlockShowsWhileItIsBeingWritten() {
        #expect(MemoryNotes.visible(whileWriting: "C'est noté.") == "C'est noté.")
        #expect(MemoryNotes.visible(whileWriting: "C'est noté.\n\n<") == "C'est noté.")
        #expect(MemoryNotes.visible(whileWriting: "C'est noté.\n\n<mem") == "C'est noté.")
        #expect(MemoryNotes.visible(whileWriting: "C'est noté.\n\n<memoire>\n+ toi | Tu") == "C'est noté.")
        #expect(MemoryNotes.visible(whileWriting: answer) == "C'est noté.")
        // A lone "<" in the middle of a sentence is ordinary text.
        #expect(MemoryNotes.visible(whileWriting: "si a < b alors") == "si a < b alors")
    }

    @Test func theLiveTextNeverShowsTheBlock() {
        var tracker = ChatLiveTracker()
        for piece in ["C'est ", "noté.", "\n\n<mem", "oire>\n+ toi | Tu bois", " du thé\n</memoire>"] {
            tracker.apply(.textDelta(piece))
            #expect(!tracker.live.text.contains("<"), "\(tracker.live.text)")
            #expect(!tracker.live.text.contains("thé"))
        }
        #expect(tracker.live.text == "C'est noté.")
    }

    // MARK: Applying

    @Test func decisionsReachTheBook() {
        var book = MemoryBook()
        book.remember("Tu détestes les réunions", kind: .person, id: "a1b2")
        MemoryNotes.apply(MemoryNotes.extract(from: answer).changes, to: &book)
        #expect(book.entries.map(\.text) == ["Tu préfères les réponses courtes", "Yumi : tu avances sur la mémoire",
                                            "Tu m'as montré le devis du client Dupont"])
        #expect(book.entries.map(\.kind) == [.person, .project, .thread])
    }

    @Test func theGuardHasTheLastWord() {
        // Whatever the conversation decided, a secret or a pasted document does not get in.
        var book = MemoryBook()
        MemoryNotes.apply([
            .remember(.person, "Ton mot de passe est hunter2"),
            .remember(.thread, "Ta carte : 4242 4242 4242 4242"),
            .remember(.project, "Clé API : sk-ant-api03-abcdefghijklmnop"),
            .remember(.thread, String(repeating: "contenu du fichier ", count: 30)),
            .remember(.person, "Tu préfères le thé"),
        ], to: &book)
        #expect(book.entries.map(\.text) == ["Tu préfères le thé"])
    }

    @Test func theSameDecisionTwiceCountsOnce() {
        var book = MemoryBook()
        MemoryNotes.apply([.remember(.person, "Tu bois du thé"), .remember(.person, "Tu bois du thé")], to: &book)
        #expect(book.entries.count == 1)
    }

    @Test func theClosingSummaryOnlyWritesToTheThread() {
        var book = MemoryBook()
        book.remember("Tu bois du thé", kind: .person, id: "p1")
        MemoryNotes.apply([.remember(.thread, "Tu as préparé le devis Dupont, il reste à l'envoyer"),
                           .remember(.person, "Tu es pressé"), .forget("p1")], to: &book, only: .thread)
        #expect(book.entries.map(\.text) == ["Tu bois du thé", "Tu as préparé le devis Dupont, il reste à l'envoyer"])
    }

    @Test func theInstructionsCarryTheRulesOfTheVoiceSheet() {
        let text = MemoryNotes.instructions
        for rule in ["mot de passe", "numéro de carte", "contenu d'un fichier", "autre personne", "oublier", "de toi-même"] {
            #expect(text.contains(rule), "\(rule)")
        }
        #expect(ChatPhrases.systemPrompt(characterName: "Yumi", folder: "/d", memory: MemoryBook()).contains(MemoryNotes.opening))
        #expect(MemoryNotes.summaryRequest.contains("+ fil |"))
    }
}

@Suite struct MemoryCorrectionsTests {
    @Test func aFirstNameGivenInTheChatGoesToTheName() {
        var book = MemoryBook()
        let changes = MemoryNotes.extract(from: "Enchanté.\n<memoire>\nprénom | Esteban\n+ toi | Tu bois du thé\n</memoire>").changes
        #expect(changes == [.name("Esteban"), .remember(.person, "Tu bois du thé")])
        MemoryNotes.apply(changes, to: &book)
        #expect(book.name == "Esteban")
        #expect(book.entries.map(\.text) == ["Tu bois du thé"])
        // With or without the plus sign, and it can be corrected.
        MemoryNotes.apply(MemoryNotes.extract(from: "<memoire>\n+ Prénom | Estéban\n</memoire>").changes, to: &book)
        #expect(book.name == "Estéban")
        #expect(MemoryNotes.instructions.contains("prénom |"))
    }

    @Test func aNameThatIsNotANameIsRefused() {
        var book = MemoryBook()
        MemoryNotes.apply([.name("mot de passe : hunter2"), .name(String(repeating: "a", count: 60))], to: &book)
        #expect(book.name == nil)
        // The closing summary never renames anyone.
        MemoryNotes.apply([.name("Léa")], to: &book, only: .thread)
        #expect(book.name == nil)
    }

    @Test func theClosingSummaryReachesTheThreadEvenWithALooseLabel() {
        // A real answer of the conversation to the closing request: the label is not "fil".
        let answer = "<memoire>\n+ devis site vitrine | Tu prépares un devis pour un site vitrine, budget de 2000 euros\n+ fil | Il reste à l'envoyer vendredi\n</memoire>"
        #expect(MemoryNotes.extract(from: answer).changes == [.remember(.thread, "Il reste à l'envoyer vendredi")])
        var book = MemoryBook()
        MemoryNotes.apply(MemoryNotes.extract(from: answer, unknownKindAs: .thread).changes, to: &book, only: .thread)
        #expect(book.entries(of: .thread).map(\.text) == ["Tu prépares un devis pour un site vitrine, budget de 2000 euros", "Il reste à l'envoyer vendredi"])
        #expect(MemoryNotes.extract(from: "rien", unknownKindAs: .thread).changes.isEmpty)
        #expect(MemoryNotes.summaryRequest.contains("+ fil |") && MemoryNotes.summaryRequest.contains("au moins une ligne"))
    }

    @Test func noLongDashInAnswersNorInMemories() {
        #expect(VoiceRules.withoutLongDashes("Devis à envoyer vendredi — structure définie") == "Devis à envoyer vendredi, structure définie")
        #expect(VoiceRules.withoutLongDashes("2019–2024") == "2019-2024")
        #expect(MemoryNotes.extract(from: "C'est fait — tout est là.").visible == "C'est fait, tout est là.")
        #expect(MemoryNotes.visible(whileWriting: "Je regarde — un instant") == "Je regarde, un instant")
        var book = MemoryBook()
        book.remember("Tu veux finir vendredi — sans faute", kind: .thread)
        #expect(book.entries.first?.text == "Tu veux finir vendredi, sans faute")
        var tracker = ChatLiveTracker()
        tracker.apply(.textDelta("Voilà — c'est prêt"))
        #expect(!tracker.live.text.contains("—"))
    }
}
