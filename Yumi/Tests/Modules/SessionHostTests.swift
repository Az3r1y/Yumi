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
    @Test func withoutASessionOrWithAnApprovalPendingVoirOpensTheIsland() {
        var shown = 0
        let module = ClaudeCodeModule(onShow: { shown += 1 })
        module.start {}
        module.perform(.primary)
        #expect(shown == 1)

        // A session whose host is unknown: nowhere to go but the island.
        let id = SessionID("a")
        var sessions = SessionReducer.apply(.sessionStarted(id, ClaudeHookTranslator.agent, title: "yumi"), to: [:])
        module.receive(.sessionStarted(id, ClaudeHookTranslator.agent, title: "yumi"), sessions: sessions)
        module.perform(.primary)
        #expect(shown == 2)

        // An approval pending, even with a known host: it is answered in the island.
        let origin = SessionOrigin(workingDirectory: "/dev/yumi", hostBundleID: "com.example.not-installed")
        let request = PermissionRequest(tool: "Bash", command: "ls")
        sessions = SessionReducer.apply(.sessionLocated(id, origin), to: sessions)
        sessions = SessionReducer.apply(.permissionRequested(id, request), to: sessions)
        module.receive(.permissionRequested(id, request), sessions: sessions)
        module.perform(.primary)
        #expect(shown == 3)
    }

    @Test func anApplicationThatIsNotInstalledCannotBeBroughtForward() {
        #expect(!ClaudeCodeModule.bringToFront(SessionOrigin(hostBundleID: "com.example.not-installed")))
        #expect(!ClaudeCodeModule.bringToFront(nil))
    }
}
