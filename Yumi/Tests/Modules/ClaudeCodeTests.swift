import Testing
import Foundation

// Modules/ is compiled straight into this bundle (see project.yml).

@Suite struct ClaudeHookTranslatorTests {

    private func payload(_ name: String, session: String = "abc", _ extra: [String: Any] = [:]) -> [String: Any] {
        var payload: [String: Any] = ["hook_event_name": name, "session_id": session, "cwd": "/Users/me/dev/yumi",
                                      "term_program": "ghostty", "bundle_id": "com.mitchellh.ghostty"]
        payload.merge(extra) { _, new in new }
        return payload
    }

    private let id = SessionID("abc")

    @Test func everyHookIntroducesItsSession() {
        let events = ClaudeHookTranslator.events(for: payload("PreToolUse", ["tool_name": "Read", "tool_input": ["file_path": "/a/b/main.swift"]]))
        #expect(events.count == 3)
        #expect(events[0] == .sessionStarted(id, ClaudeHookTranslator.agent, title: "yumi"))
        #expect(events[1] == .sessionLocated(id, SessionOrigin(workingDirectory: "/Users/me/dev/yumi",
                                                                hostBundleID: "com.mitchellh.ghostty", hostName: "ghostty")))
        if case .toolStarted(_, let tool) = events[2] {
            #expect(tool.name == "Read")
            #expect(tool.summary == "main.swift")
        } else {
            Issue.record("Expected toolStarted")
        }
    }

    @Test func aTerminalThatIsNotVSCodeIsNotIgnored() {
        let events = ClaudeHookTranslator.events(for: payload("SessionStart", ["term_program": "Apple_Terminal", "bundle_id": "com.apple.Terminal"]))
        #expect(events.first == .sessionStarted(id, ClaudeHookTranslator.agent, title: "yumi"))
    }

    @Test func sessionEndOnlyEndsTheSession() {
        #expect(ClaudeHookTranslator.events(for: payload("SessionEnd")) == [.sessionEnded(id)])
    }

    @Test func promptIsCarried() {
        let events = ClaudeHookTranslator.events(for: payload("UserPromptSubmit", ["prompt": "écris les tests"]))
        #expect(events.last == .promptSubmitted(id, text: "écris les tests"))
    }

    @Test func permissionRequestKeepsItsIdentifierAndCommand() {
        let events = ClaudeHookTranslator.events(
            for: payload("PermissionRequest", ["tool_name": "Bash", "tool_input": ["command": "rm -rf build"]]),
            requestID: "req-1")
        #expect(events.last == .permissionRequested(id, PermissionRequest(id: "req-1", tool: "Bash", command: "rm -rf build")))
    }

    @Test func permissionRequestWithoutCommandShowsTheTool() {
        let events = ClaudeHookTranslator.events(
            for: payload("PermissionRequest", ["tool_name": "Edit", "tool_input": ["file_path": "/a/b.swift"]]),
            requestID: "req-2")
        #expect(events.last == .permissionRequested(id, PermissionRequest(id: "req-2", tool: "Edit", command: "Edit")))
    }

    @Test func notifications() {
        #expect(ClaudeHookTranslator.events(for: payload("Notification", ["message": "You hit the rate limit"])).last == .rateLimited(id))
        if case .questionRequested(_, let question) = ClaudeHookTranslator.events(for: payload("Notification", ["message": "Which file?"])).last {
            #expect(question.text == "Which file?")
        } else {
            Issue.record("Expected questionRequested")
        }
        // Any other notification only introduces the session.
        #expect(ClaudeHookTranslator.events(for: payload("Notification", ["message": "Claude is waiting"])).count == 2)
    }

    @Test func stopNotesTheMessageThenCompletes() {
        let events = ClaudeHookTranslator.events(for: payload("Stop", ["message": "Done."]))
        #expect(Array(events.suffix(2)) == [.activityNoted(id, "Done."), .taskCompleted(id)])
    }

    @Test func failuresAndSubagents() {
        #expect(ClaudeHookTranslator.events(for: payload("StopFailure", ["message": "boom"])).last == .sessionErrored(id, YumiError(message: "boom")))
        #expect(ClaudeHookTranslator.events(for: payload("SubagentStart")).last == .activityNoted(id, "+ subagent"))
        #expect(ClaudeHookTranslator.events(for: payload("PostToolUseFailure", ["tool_name": "Bash"])).last == .activityNoted(id, "⚠ failed"))
    }

    @Test func unknownHooksAndMissingFields() {
        #expect(ClaudeHookTranslator.events(for: payload("SomethingNew")).isEmpty)
        let events = ClaudeHookTranslator.events(for: ["hook_event_name": "SessionStart"])
        #expect(events.first == .sessionStarted(SessionID("unknown"), ClaudeHookTranslator.agent, title: "Session"))
    }

    @Test func protocolVersion() {
        #expect(ClaudeHookTranslator.protocolVersion(of: [:]) == 1)
        #expect(ClaudeHookTranslator.protocolVersion(of: ["hook_protocol": 2]) == 2)
    }

    @Test func toolWording() {
        #expect(ClaudeToolPhrase.step(ToolInfo(name: "Edit", summary: "main.swift")) == "Modifie · main.swift")
        #expect(ClaudeToolPhrase.step(ToolInfo(name: "TodoWrite")) == "Tâches")
        #expect(ClaudeToolPhrase.step(ToolInfo(name: "mcp__x", summary: "")) == "mcp__x")
        #expect(ClaudeToolPhrase.sentence(ToolInfo(name: "Write", summary: "Tests.swift")) == "écrit Tests.swift")
    }
}

@Suite struct ClaudeSessionsTests {

    /// Replays hook payloads through the translator and the reducer, the way the app does.
    private func replay(_ hooks: [[String: Any]]) -> [SessionID: Session] {
        var sessions: [SessionID: Session] = [:]
        for (index, hook) in hooks.enumerated() {
            for event in ClaudeHookTranslator.events(for: hook, requestID: "req-\(index)") {
                sessions = SessionReducer.apply(event, to: sessions)
            }
        }
        return sessions
    }

    private func hook(_ name: String, _ session: String, cwd: String, _ extra: [String: Any] = [:]) -> [String: Any] {
        var payload: [String: Any] = ["hook_event_name": name, "session_id": session, "cwd": cwd,
                                      "term_program": "iTerm.app", "bundle_id": "com.googlecode.iterm2"]
        payload.merge(extra) { _, new in new }
        return payload
    }

    @Test func noSession() {
        let snapshot = ClaudeSessions.snapshot([])
        #expect(snapshot.id == "claude-code")
        #expect(snapshot.status == "au repos")
        #expect(snapshot.secondaryAction == nil)
        #expect(!snapshot.needsAttention)
    }

    @Test func twoSessionsStayApartAndTheLastActiveComesFirst() {
        let sessions = replay([
            hook("UserPromptSubmit", "a", cwd: "/dev/yumi", ["prompt": "go"]),
            hook("UserPromptSubmit", "b", cwd: "/dev/site", ["prompt": "go"]),
            hook("PreToolUse", "a", cwd: "/dev/yumi", ["tool_name": "Write", "tool_input": ["file_path": "/dev/yumi/Tests.swift"]]),
        ])
        let ordered = ClaudeSessions.ordered(sessions)
        #expect(ordered.map(\.id.value) == ["a", "b"])
        #expect(sessions[SessionID("b")]?.activity == .thinking)

        let snapshot = ClaudeSessions.snapshot(ordered)
        #expect(snapshot.status == "2 sessions")
        #expect(snapshot.title == "yumi : écrit Tests.swift")
        #expect(snapshot.subtitle == "2 sessions ouvertes")
        #expect(snapshot.secondaryAction == "Ouvrir le terminal")
        #expect(!snapshot.needsAttention)
    }

    @Test func aSessionWaitingForTheUserComesFirst() {
        let sessions = replay([
            hook("PermissionRequest", "a", cwd: "/dev/yumi", ["tool_name": "Bash", "tool_input": ["command": "swift test"]]),
            hook("PreToolUse", "b", cwd: "/dev/site", ["tool_name": "Read", "tool_input": ["file_path": "/dev/site/index.html"]]),
        ])
        let snapshot = ClaudeSessions.snapshot(ClaudeSessions.ordered(sessions))
        #expect(snapshot.title == "yumi : demande ton accord")
        #expect(snapshot.subtitle == "2 sessions ouvertes, 1 attend ta réponse")
        #expect(snapshot.needsAttention)
    }

    @Test func endedSessionsDisappear() {
        let sessions = replay([
            hook("SessionStart", "a", cwd: "/dev/yumi"),
            hook("SessionStart", "b", cwd: "/dev/site"),
            hook("SessionEnd", "a", cwd: "/dev/yumi"),
        ])
        let snapshot = ClaudeSessions.snapshot(ClaudeSessions.ordered(sessions))
        #expect(snapshot.status == "1 session")
        #expect(snapshot.title == "site : attend ton message")
        #expect(snapshot.subtitle == "1 session ouverte")
    }

    @Test func theProjectNameFollowsTheWorkingDirectory() {
        let sessions = replay([
            hook("SessionStart", "a", cwd: "/dev/yumi"),
            hook("PostToolUse", "a", cwd: "/dev/yumi/Yumi", ["tool_name": "Bash"]),
        ])
        #expect(ClaudeSessions.projectName(sessions[SessionID("a")]!) == "Yumi")
    }

    @Test func sessionsOfOtherAgentsAreLeftOut() {
        let other = Agent(id: AgentID("cursor"), name: "Cursor", kind: .coding)
        let sessions = SessionReducer.apply(.sessionStarted(SessionID("x"), other, title: "x"), to: [:])
        #expect(ClaudeSessions.ordered(sessions).isEmpty)
    }

    @Test func hosts() {
        #expect(SessionHost.bundleID(for: SessionOrigin(hostBundleID: "dev.warp.Warp-Stable", hostName: "WarpTerminal")) == "dev.warp.Warp-Stable")
        #expect(SessionHost.bundleID(for: SessionOrigin(hostName: "Apple_Terminal")) == "com.apple.Terminal")
        #expect(SessionHost.bundleID(for: SessionOrigin(hostName: "tmux")) == nil)
        #expect(SessionHost.bundleID(for: nil) == nil)
        #expect(SessionHost.isEditor(SessionOrigin(hostBundleID: "com.microsoft.VSCode")))
        #expect(!SessionHost.isEditor(SessionOrigin(hostBundleID: "com.apple.Terminal")))
    }
}
