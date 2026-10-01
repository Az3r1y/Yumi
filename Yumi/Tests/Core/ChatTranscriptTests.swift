import Testing
import Foundation

/// What an answer leaves in the history once it is complete.
@Suite struct ChatTranscriptTests {
    private func history(_ events: [ChatStreamEvent], refused: [String] = [], result: String) -> [String] {
        var transcript = ChatTranscript()
        var lines: [String] = []
        for event in events {
            if case .toolFinished(let id, _, _) = event, refused.contains(id) { transcript.refuse(toolUseID: id) }
            lines += transcript.apply(event)
        }
        return lines + transcript.finish(ChatTurnResult(text: result, isError: false, sessionID: nil, errors: []))
    }
    private let write = ChatToolUse(id: "w", name: "Write", detail: "/d/bonjour.txt", content: "salut")
    private let bash = ChatToolUse(id: "b", name: "Bash", detail: "swift test")

    @Test func aPlainAnswerIsOneLine() {
        #expect(history([.messageStarted, .textDelta("Bon"), .text("Bonjour toi")], result: "Bonjour toi") == ["Bonjour toi"])
    }

    @Test func textWrittenBeforeAnActionIsKeptInOrder() {
        let lines = history([
            .text("Je crée le fichier."),
            .toolStarted(write), .toolFinished(id: "w", failed: false, output: "ok"),
            .text("C'est fait."),
        ], result: "C'est fait.")
        #expect(lines == ["Je crée le fichier.", "Fichier créé : bonjour.txt", "C'est fait."])
    }

    @Test func severalStepsKeepEverythingInOrder() {
        let lines = history([
            .text("D'abord le fichier."),
            .toolStarted(write), .toolFinished(id: "w", failed: false, output: ""),
            .text("Maintenant les tests."),
            .toolStarted(bash), .toolFinished(id: "b", failed: true, output: "Exit code 1"),
            .text("Les tests échouent."),
        ], result: "Les tests échouent.")
        #expect(lines == ["D'abord le fichier.", "Fichier créé : bonjour.txt", "Maintenant les tests.",
                          "Commande en échec : swift test", "Les tests échouent."])
    }

    @Test func theTextGoesInAsSoonAsTheActionStarts() {
        var transcript = ChatTranscript()
        #expect(transcript.apply(.text("Je crée le fichier.")).isEmpty)
        #expect(transcript.apply(.toolStarted(write)) == ["Je crée le fichier."])
        #expect(transcript.apply(.toolFinished(id: "w", failed: false, output: "")) == ["Fichier créé : bonjour.txt"])
    }

    @Test func twoBlocksOfTextInARowAreBothKept() {
        #expect(history([.text("Un."), .text("Deux.")], result: "Deux.") == ["Un.", "Deux."])
    }

    @Test func theConclusionIsNotSaidTwice() {
        // The result repeats the last message, sometimes with what came just before it.
        #expect(history([.text("Voilà.")], result: "Voilà.") == ["Voilà."])
        #expect(history([.toolStarted(bash), .toolFinished(id: "b", failed: false, output: "")], result: "")
                == ["Commande lancée : swift test"])
    }

    @Test func aResultThatSaysMoreIsAdded() {
        #expect(history([.toolStarted(write), .toolFinished(id: "w", failed: false, output: "")], result: "Fichier prêt.")
                == ["Fichier créé : bonjour.txt", "Fichier prêt."])
    }

    @Test func aRefusedActionSaysSo() {
        let lines = history([.text("Je lance les tests."), .toolStarted(bash), .toolFinished(id: "b", failed: true, output: "refusé"),
                             .text("D'accord, j'arrête.")], refused: ["b"], result: "D'accord, j'arrête.")
        #expect(lines == ["Je lance les tests.", "Commande refusée : swift test", "D'accord, j'arrête."])
    }

    @Test func lookingLeavesNoLineButKeepsTheTextAround() {
        let read = ChatToolUse(id: "r", name: "Read", detail: "/d/a.txt")
        #expect(history([.text("Je regarde."), .toolStarted(read), .toolFinished(id: "r", failed: false, output: "x"), .text("Rien à signaler.")],
                        result: "Rien à signaler.") == ["Je regarde.", "Rien à signaler."])
    }

    @Test func anAnswerWithoutTextIsKnown() {
        var transcript = ChatTranscript()
        let last = transcript.finish(ChatTurnResult(text: "", isError: false, sessionID: nil, errors: []))
        #expect(last.isEmpty)
        #expect(!transcript.hasText)
    }

    @Test func theLiveTextStartsAgainOnceItIsInTheHistory() {
        var tracker = ChatLiveTracker()
        tracker.apply(.text("Je crée le fichier."))
        tracker.textCommitted()
        #expect(tracker.live.text == "")
    }
}
