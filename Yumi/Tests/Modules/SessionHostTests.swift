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

    @Test func aSessionInAnEditorIsShownInThatEditor() {
        let cursor = SessionOrigin(hostBundleID: "com.todesktop.230313mzl4w4u92.cursor")
        #expect(SessionHost.editor(for: cursor, preferred: "dev.zed.Zed", running: ["com.microsoft.VSCode"], isInstalled: { _ in true })
                == "com.todesktop.230313mzl4w4u92.cursor")
    }

    @Test func aSessionOutsideAnEditorIsShownInTheUsersEditor() {
        let installed: Set<String> = ["com.microsoft.VSCode", "dev.zed.Zed"]
        // The Claude desktop app hosts the session: the project opens in the code editor, not in Claude.
        #expect(SessionHost.editor(for: desktop, preferred: nil, running: [], isInstalled: installed.contains) == "com.microsoft.VSCode")
        // An editor already open wins over one that is only installed.
        #expect(SessionHost.editor(for: desktop, preferred: nil, running: ["dev.zed.Zed"], isInstalled: installed.contains) == "dev.zed.Zed")
        // The user's choice wins over both, if it is installed.
        #expect(SessionHost.editor(for: terminal, preferred: "dev.zed.Zed", running: ["com.microsoft.VSCode"], isInstalled: installed.contains) == "dev.zed.Zed")
        #expect(SessionHost.editor(for: terminal, preferred: "com.gone.editor", running: [], isInstalled: installed.contains) == "com.microsoft.VSCode")
        #expect(SessionHost.editor(for: desktop, preferred: nil, running: [], isInstalled: { _ in false }) == nil)
    }
}
