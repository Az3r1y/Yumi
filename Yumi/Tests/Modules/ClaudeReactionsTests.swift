import Foundation
import Testing

// Yumi reacts to the tests of a Claude Code session, and says what a long task did.

@Suite struct TestRunTests {
    @Test func testCommandsAreRecognised() {
        for command in ["swift test", "cd Yumi && xcodebuild -scheme Yumi test CODE_SIGNING_ALLOWED=NO", "npm test", "pnpm run test",
                        "yarn test --watch=false", "pytest -q", "python3 -m pytest tests/", "cargo test", "go test ./...",
                        "npx vitest run", "bundle exec rspec", "make test", "./node_modules/.bin/jest"] {
            #expect(TestRun.isTests(command), "\(command)")
        }
        for command in ["git status", "ls tests/", "cat test.txt", "echo latest", "npm install", "swift build", "grep -r contest ."] {
            #expect(!TestRun.isTests(command), "\(command)")
        }
    }

    @Test func passedOrFailedComesFromTheHook() {
        func payload(_ event: String, _ command: String, tool: String = "Bash") -> [String: Any] {
            ["hook_event_name": event, "tool_name": tool, "tool_input": ["command": command]]
        }
        #expect(TestRun.outcome(payload("PostToolUse", "swift test")) == true)
        #expect(TestRun.outcome(payload("PostToolUseFailure", "swift test")) == false)
        #expect(TestRun.outcome(payload("PreToolUse", "swift test")) == nil)
        #expect(TestRun.outcome(payload("PostToolUse", "git status")) == nil)
        #expect(TestRun.outcome(payload("PostToolUse", "swift test", tool: "Read")) == nil)
    }
}

@Suite struct SessionSummaryTests {
    @Test func theTurnKeepsClaudesWholeLastMessageMasked() throws {
        let transcript = "J'ai corrigé le bug du login. Ensuite j'ai ajouté trois tests. API_KEY=sk-123456"
        let note = try #require(SessionNote.from(["hook_event_name": "Stop", "session_id": "s", "transcript_path": "/t"],
                                                 lastMessage: { _ in transcript }))
        var journal = SessionJournal(started: Date())
        journal.apply(note.kind, now: Date())
        #expect(journal.lastMessage?.contains("trois tests") == true)
        #expect(journal.lastMessage?.contains("sk-123456") == false)
        #expect(journal.summary?.contains("J'ai corrigé le bug du login.") == true)
    }

    @Test func aSummaryIsSaidAsItIs() {
        let variants = InitiativePhrases.variants(for: .agentDone(project: "yumi", minutes: 12, summary: "a corrigé le bug du login."),
                                                 Surroundings(now: Date()))
        #expect(variants.map(\.text) == ["Sur yumi, Claude a corrigé le bug du login."])
    }

    @Test func aLongAnswerIsCutToOneShortSentence() {
        #expect(TextAI.shortSentence("a corrigé le bug. Puis il a ajouté des tests.") == "a corrigé le bug.")
        let long = Array(repeating: "mot", count: 30).joined(separator: " ")
        #expect(TextAI.shortSentence(long) == Array(repeating: "mot", count: 20).joined(separator: " ") + "…")
        #expect(TextAI.shortSentence("a mis à jour la version 1.2 du README") == "a mis à jour la version 1.2 du README")
    }

    @Test(.enabled(if: TextAI.isAvailable, "Apple Intelligence is not on this Mac"))
    func theModelSaysItInOneShortSentence() async throws {
        let line = try await TextAI.sessionLine("J'ai corrigé le bug qui empêchait la connexion avec Google, ajouté trois tests unitaires pour le cas d'un jeton expiré, et mis à jour le README.")
        #expect(line.split(separator: " ").count <= 20)
        #expect(!line.contains("\n"))
    }
}
