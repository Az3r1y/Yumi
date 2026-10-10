import Foundation
import Testing
@testable import Yumi

struct AntigravityHookTranslatorTests {
    private func payload(_ event: String, _ extra: [String: Any] = [:]) -> [String: Any] {
        ["source": "antigravity", "hook_event_name": event, "conversationId": "c1",
         "workspacePaths": ["/Users/me/Projets/site"], "term_program": "ghostty"].merging(extra) { $1 }
    }

    @Test func aToolCallBecomesAToolOfTheSessionInItsProject() {
        let events = AntigravityHookTranslator.events(
            for: payload("PreToolUse", ["toolCall": ["name": "view_file", "args": ["toolSummary": "Read a.txt"]]]), ownFolder: "/yumi")
        let id = SessionID("agy-c1")
        #expect(Array(events.prefix(2)) == [.sessionStarted(id, AntigravityHookTranslator.agent, title: "site"),
                                            .sessionLocated(id, SessionOrigin(workingDirectory: "/Users/me/Projets/site", hostBundleID: "", hostName: "ghostty"))])
        guard case .toolStarted(id, let tool) = events.last else { Issue.record("no tool"); return }
        #expect(tool.name == "view_file" && tool.summary == "Read a.txt")
    }

    @Test func onlyTheFirstCallOfAnAnswerStartsATurn() {
        #expect(AntigravityHookTranslator.events(for: payload("PreInvocation", ["invocationNum": 0]), ownFolder: "/yumi").last
                == .promptSubmitted(SessionID("agy-c1"), text: ""))
        #expect(AntigravityHookTranslator.events(for: payload("PreInvocation", ["invocationNum": 2]), ownFolder: "/yumi").count == 2)
    }

    @Test func aStopEndsTheTaskOrSaysItFailed() {
        let id = SessionID("agy-c1")
        #expect(AntigravityHookTranslator.events(for: payload("Stop"), ownFolder: "/yumi").last == .taskCompleted(id))
        #expect(AntigravityHookTranslator.events(for: payload("Stop", ["error": "quota"]), ownFolder: "/yumi").last
                == .sessionErrored(id, YumiError(message: "quota")))
    }

    @Test func yumisOwnSessionsAndUnknownPayloadsAreIgnored() {
        #expect(AntigravityHookTranslator.events(for: payload("Stop", ["workspacePaths": ["/yumi/research"]]), ownFolder: "/yumi").isEmpty)
        #expect(!AntigravityHookTranslator.events(for: payload("Stop", ["workspacePaths": ["/yumi-other"]]), ownFolder: "/yumi").isEmpty)
        #expect(AntigravityHookTranslator.events(for: payload("Stop", ["conversationId": ""]), ownFolder: "/yumi").isEmpty)
        #expect(AntigravityHookTranslator.events(for: payload("Other"), ownFolder: "/yumi").isEmpty)
    }
}

struct AntigravityHooksTests {
    let script = "/S/yumi-hook"

    @Test func installKeepsTheOtherHooksAndIsRecognised() throws {
        let before = Data(#"{"mine":{"Stop":[{"command":"echo hi"}]}}"#.utf8)
        let after = try AntigravityHooks.install(before, script: script)
        let hooks = try #require(JSONSerialization.jsonObject(with: after) as? [String: Any])
        #expect(hooks["mine"] != nil)
        #expect(AntigravityHooks.isInstalled(after, script: script))
        // Someone else's hook beside Yumi's: Antigravity can no longer be Yumi's engine
        #expect(!AntigravityHooks.isOwn(hooks, script: script))
        let removed = try AntigravityHooks.remove(after)
        #expect(!AntigravityHooks.isInstalled(removed, script: script))
        #expect((try JSONSerialization.jsonObject(with: removed) as? [String: Any])?["mine"] != nil)
    }

    @Test func yumisHooksAloneKeepAntigravityUsableAsTheEngine() throws {
        let data = try AntigravityHooks.install(nil, script: script)
        let hooks = try #require(try JSONSerialization.jsonObject(with: data))
        #expect(AntigravityHooks.isOwn(hooks, script: script))
        #expect(!AntigravityHooks.isOwn(hooks, script: "/other/yumi-hook"))
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try data.write(to: folder.appendingPathComponent("hooks.json"))
        #expect(AntigravityLLMProvider.isolationProblem(in: folder.path, isOwnHooks: { AntigravityHooks.isOwn($0, script: script) },
                                                        adminSettings: "/nonexistent") == nil)
    }

    @Test func theCommandNamesItsSourceAndEvent() {
        #expect(AntigravityHooks.command("Stop", script: script) == #"YUMI_HOOK_SOURCE=antigravity YUMI_HOOK_EVENT=Stop /bin/sh "/S/yumi-hook""#)
    }

    @Test func aFileThatIsNotJSONIsLeftAlone() {
        #expect(throws: HookSettings.Problem.notJSON) { try AntigravityHooks.install(Data("{nope".utf8), script: script) }
    }
}
