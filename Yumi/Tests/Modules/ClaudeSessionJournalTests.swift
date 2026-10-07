import Testing
import Foundation

// What each Claude Code session is working on, from simulated hooks.

private func hook(_ name: String, session: String = "s1", _ extra: [String: Any] = [:]) -> [String: Any] {
    var payload: [String: Any] = ["hook_event_name": name, "session_id": session, "cwd": "/Users/me/dev/yumi"]
    payload.merge(extra) { _, new in new }
    return payload
}

private func note(_ payload: [String: Any], last: String? = nil) -> SessionNote.Kind? {
    SessionNote.from(payload, lastMessage: { _ in last })?.kind
}

private var todos: [String: Any] { ["todos": [
    ["content": "Lire le code", "activeForm": "Lit le code", "status": "completed"],
    ["content": "Écrire le test", "activeForm": "Écrit le test", "status": "in_progress"],
    ["content": "Lancer les tests", "status": "pending"],
]] }

@Suite struct ClaudeSessionJournalTests {
    private let start = Date(timeIntervalSince1970: 1_000_000)

    private func journal(_ payloads: [[String: Any]], last: String? = nil) -> SessionJournal {
        var journal = SessionJournal(started: start)
        for (index, payload) in payloads.enumerated() {
            if let kind = note(payload, last: last) { journal.apply(kind, now: start.addingTimeInterval(Double(index))) }
        }
        return journal
    }

    @Test func theRequestIsKeptOnOneLine() {
        let long = "Corrige le repli de l'île\nquand on clique dehors, et ajoute un test qui le vérifie bien, avec plusieurs cas, et explique-moi"
        let j = journal([hook("UserPromptSubmit", ["prompt": long])])
        #expect(j.request?.hasPrefix("Corrige le repli de l'île quand on clique dehors") == true)
        #expect(j.request?.hasSuffix("…") == true)
        #expect((j.request?.count ?? 0) <= 91)
    }

    @Test func theTodoListGivesTheTaskAndTheProgress() {
        let j = journal([hook("UserPromptSubmit", ["prompt": "Ajoute le test"]), hook("PreToolUse", ["tool_name": "TodoWrite", "tool_input": todos])])
        #expect(j.progress == "1/3")
        #expect(j.currentTask == "Écrit le test")
    }

    @Test func eachToolSaysWhatItDoesOnWhat() {
        let edit = ToolStep(tool: "Edit", input: ["file_path": "/a/b/IslandModel.swift"])
        #expect(edit.sentence == "Modifie IslandModel.swift")
        #expect(ToolStep(tool: "Bash", input: ["command": "swift test"]).sentence == "Lance swift test")
        #expect(ToolStep(tool: "Read", input: ["file_path": "/x/README.md"]).sentence == "Lit README.md")
        #expect(ToolStep(tool: "Grep", input: ["pattern": "TODO"]).sentence == "Cherche TODO")
        #expect(ToolStep(tool: "Write", input: ["file_path": "/x/new.swift"]).sentence == "Écrit new.swift")
    }

    @Test func theActionInProgressThenTheHistory() {
        var j = journal([hook("PreToolUse", ["tool_name": "Edit", "tool_input": ["file_path": "/a/Model.swift"]])])
        #expect(j.current?.sentence == "Modifie Model.swift")
        if let kind = note(hook("PostToolUse", ["tool_name": "Edit", "tool_input": ["file_path": "/a/Model.swift"]])) { j.apply(kind, now: start) }
        #expect(j.current == nil)
        #expect(j.history.map(\.sentence) == ["Modifie Model.swift"])
        #expect(j.filesTouched == ["/a/Model.swift"])
        for n in 0..<10 {
            if let kind = note(hook("PostToolUse", ["tool_name": "Bash", "tool_input": ["command": "echo \(n)"]])) { j.apply(kind, now: start) }
        }
        #expect(j.history.count == SessionJournal.historyLength)
        #expect(j.history.last?.sentence == "Lance echo 9")
        #expect(j.commands == 10)
    }

    @Test func theEndOfATurnSaysWhatWasDone() {
        let edit: [String: Any] = ["tool_name": "Edit", "tool_input": ["file_path": "/a/One.swift"]]
        let edit2: [String: Any] = ["tool_name": "Write", "tool_input": ["file_path": "/a/Two.swift"]]
        let bash: [String: Any] = ["tool_name": "Bash", "tool_input": ["command": "swift test"]]
        let done: [String: Any] = ["todos": [["content": "a", "status": "completed"], ["content": "b", "status": "completed"]]]
        let j = journal([hook("UserPromptSubmit", ["prompt": "Fais-le"]), hook("PostToolUse", edit), hook("PostToolUse", edit2),
                         hook("PostToolUse", bash), hook("PostToolUse", ["tool_name": "TodoWrite", "tool_input": done]),
                         hook("Stop", ["transcript_path": "/tmp/t.jsonl"])],
                        last: "J'ai ajouté le test et tout passe. Le reste est inchangé.")
        #expect(j.summary == "Deux fichiers modifiés, une commande, 2/2 tâches. J'ai ajouté le test et tout passe.")
    }

    @Test func aNewRequestStartsAFreshTurn() {
        var j = journal([hook("PostToolUse", ["tool_name": "Bash", "tool_input": ["command": "ls"]]), hook("Stop")])
        #expect(j.summary != nil)
        if let kind = note(hook("UserPromptSubmit", ["prompt": "Et maintenant ?"])) { j.apply(kind, now: start) }
        #expect(j.summary == nil && j.commands == 0 && j.request == "Et maintenant ?")
    }

    @Test func secretsAreMasked() {
        #expect(SecretMask.mask("OPENAI_API_KEY=sk-abc123 npm start") == "OPENAI_API_KEY=••• npm start")
        #expect(SecretMask.mask("curl -H 'Authorization: Bearer abc.def' https://x") == "curl -H 'Authorization: Bearer •••' https://x")
        #expect(SecretMask.mask("gh auth login --token ghp_abcdefghijklmnopqrstuvwxyz12") == "gh auth login --token •••")
        #expect(SecretMask.mask("git clone https://me:hunter2@github.com/me/x") == "git clone https://me:•••@github.com/me/x")
        #expect(SecretMask.mask("echo sk-ant-api03-abcdefghijklmnopqrstuv") == "echo •••")
        #expect(SecretMask.mask("swift test --filter Island") == "swift test --filter Island")
        let step = ToolStep(tool: "Bash", input: ["command": "export GITHUB_TOKEN=ghp_secret && deploy"])
        #expect(!step.target.contains("ghp_secret"))
    }

    @Test func theLastMessageIsReadFromTheTranscript() {
        let transcript = """
        {"type":"user","message":{"role":"user","content":"Salut"}}
        {"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Premier."}]}}
        {"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Bash"},{"type":"text","text":"C'est fait, les tests passent."}]}}
        """
        #expect(SessionText.lastAssistantText(transcript: transcript) == "C'est fait, les tests passent.")
    }

    @Test func severalSessionsKeepTheirOwnJournal() {
        let journals = ClaudeSessionJournalsTestDouble()
        journals.apply(hook("UserPromptSubmit", session: "a", ["prompt": "Un"]))
        journals.apply(hook("UserPromptSubmit", session: "b", ["prompt": "Deux"]))
        journals.apply(hook("PreToolUse", session: "b", ["tool_name": "Bash", "tool_input": ["command": "make"]]))
        #expect(journals.items["a"]?.request == "Un" && journals.items["a"]?.current == nil)
        #expect(journals.items["b"]?.current?.sentence == "Lance make")
    }
}

/// The same bookkeeping as ClaudeSessionJournals, without the shared instance.
private final class ClaudeSessionJournalsTestDouble {
    var items: [String: SessionJournal] = [:]
    func apply(_ payload: [String: Any]) {
        guard let note = SessionNote.from(payload) else { return }
        var journal = items[note.session] ?? SessionJournal(started: .now)
        journal.apply(note.kind, now: .now)
        items[note.session] = journal
    }
}

@Suite struct ClaudeSessionsShowTheWorkTests {
    private func session(_ id: String, working: Bool) -> Session {
        var session = Session(id: SessionID(id), agent: ClaudeHookTranslator.agent, title: "yumi")
        session.origin = SessionOrigin(workingDirectory: "/dev/yumi")
        session.isTurnActive = working
        session.activity = working ? .thinking : .idle
        return session
    }

    @Test func theFoldedIslandSaysWhatTheSessionIsOn() {
        var journal = SessionJournal(started: .now)
        if let kind = SessionNote.from(["hook_event_name": "PreToolUse", "session_id": "s", "tool_name": "Edit",
                                        "tool_input": ["file_path": "/x/IslandModel.swift"]])?.kind {
            journal.apply(kind, now: .now)
        }
        let live = ClaudeSessions.live([session("s", working: true)], journals: ["s": journal])
        #expect(live?.text == "yumi · Modifie IslandModel.swift")
        #expect(live?.priority == ClaudeSessions.workingPriority)
        #expect(ClaudeSessions.live([session("s", working: true)]) == nil)
    }

    @Test func aRowShowsTheActionTheProgressAndUnfolds() {
        var journal = SessionJournal(started: .now)
        if let kind = SessionNote.from(["hook_event_name": "PreToolUse", "session_id": "s", "tool_name": "TodoWrite", "tool_input": todos])?.kind {
            journal.apply(kind, now: .now)
        }
        var row = ModuleRow(id: "s", title: "yumi", detail: "Réfléchit.", state: .busy, label: "travaille")
        row = SessionBoard.enriched(row, journal, now: .now)
        #expect(row.detail == "Écrit le test")
        #expect(row.progress == "1/3")
        #expect(row.details.contains("Tâche 1/3 : Écrit le test"))
    }
}
