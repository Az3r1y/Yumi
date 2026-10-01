import Testing
import Foundation

@Suite struct SessionHostTests {
    private let desktop = SessionOrigin(workingDirectory: "/dev/yumi", hostBundleID: "com.anthropic.claudefordesktop")
    private let terminal = SessionOrigin(workingDirectory: "/dev/yumi", hostBundleID: "com.apple.Terminal", hostName: "Apple_Terminal")
    private let code = SessionOrigin(workingDirectory: "/dev/yumi", hostBundleID: "com.microsoft.VSCode", hostName: "vscode")

    @Test func kinds() {
        #expect(SessionHost.kind(of: terminal) == .terminal)
        #expect(SessionHost.kind(of: SessionOrigin(hostName: "ghostty")) == .terminal)
        #expect(SessionHost.kind(of: SessionOrigin(hostBundleID: "com.unknown.term", hostName: "SomeTerm")) == .terminal)
        #expect(SessionHost.kind(of: code) == .editor)
        #expect(SessionHost.kind(of: desktop) == .other)
        #expect(SessionHost.kind(of: SessionOrigin(hostName: "tmux")) == nil)
        #expect(SessionHost.kind(of: nil) == nil)
    }

    @Test func theSecondButtonNamesWhatItOpens() {
        func second(_ origin: SessionOrigin) -> String? {
            var sessions = SessionReducer.apply(.sessionStarted(SessionID("s"), ClaudeHookTranslator.agent, title: "yumi"), to: [:])
            sessions = SessionReducer.apply(.sessionLocated(SessionID("s"), origin), to: sessions)
            return ClaudeSessions.snapshot(ClaudeSessions.ordered(sessions)).secondaryAction
        }
        #expect(second(terminal) == "Ouvrir le terminal")
        #expect(second(code) == "Ouvrir l'éditeur")
        #expect(second(desktop) == "Ouvrir la session")
        #expect(second(SessionOrigin(workingDirectory: "/dev/yumi")) == nil)
    }

    @Test func cursorIsAnEditorByItsRealIdentifier() {
        #expect(SessionHost.kind(of: SessionOrigin(hostBundleID: "com.todesktop.230313mzl4w4u92")) == .editor)
    }
}

@MainActor
@Suite struct ClaudeCodeVoirTests {
    @Test func voirShowsTheSessionsInTheIslandAndNothingElse() {
        var shown = 0
        let module = ClaudeCodeModule(onShow: { shown += 1 })
        module.start {}

        // No session: the island opens all the same.
        module.perform(.primary)
        #expect(shown == 1)

        // A session hosted by the Claude desktop app, working: still the island.
        let id = SessionID("a")
        var sessions = SessionReducer.apply(.sessionStarted(id, ClaudeHookTranslator.agent, title: "yumi"), to: [:])
        let origin = SessionOrigin(workingDirectory: "/dev/yumi", hostBundleID: "com.anthropic.claudefordesktop")
        sessions = SessionReducer.apply(.sessionLocated(id, origin), to: sessions)
        module.receive(.sessionLocated(id, origin), sessions: sessions)
        module.perform(.primary)
        #expect(shown == 2)

        // An approval pending: the island again, where it is answered.
        let request = PermissionRequest(tool: "Bash", command: "ls")
        sessions = SessionReducer.apply(.permissionRequested(id, request), to: sessions)
        module.receive(.permissionRequested(id, request), sessions: sessions)
        module.perform(.primary)
        #expect(shown == 3)
    }
}
