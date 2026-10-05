import Foundation
import Testing

// yumi/premier-lancement: what a fresh Mac can throw at Yumi on the first day.

@Suite struct HookSettingsTests {
    private let events: [(String, Int)] = [("SessionStart", 10), ("PermissionRequest", 120)]
    private let command = "\"/Users/moi/Library/Application Support/Yumi/yumi-hook\""

    private func merge(_ text: String?) throws -> [String: Any] {
        let data = text.map { Data($0.utf8) }
        let merged = try HookSettings.merge(data, command: command, events: events,
                                            isOwn: { $0 == command }, isLegacy: { $0.contains("coucou") })
        return try #require(JSONSerialization.jsonObject(with: merged.data) as? [String: Any])
    }

    @Test func aMissingOrBlankFileGetsOnlyTheHooks() throws {
        for text in [nil, "", "  \n"] {
            let settings = try merge(text)
            #expect(Set(settings.keys) == ["hooks"])
            #expect((settings["hooks"] as? [String: Any])?.count == 2)
        }
    }

    @Test func aBrokenFileIsRefusedNeverReplaced() {
        #expect(throws: HookSettings.Problem.notJSON) { try merge(#"{"model": "opus", "permissions": {"#) }
        #expect(throws: HookSettings.Problem.notJSON) { try merge("\u{FEFF}{oops}") }
        #expect(throws: HookSettings.Problem.notAnObject) { try merge(#"["a", "b"]"#) }
        #expect(throws: HookSettings.Problem.unexpectedHooks("hooks")) { try merge(#"{"hooks": "none"}"#) }
        #expect(throws: HookSettings.Problem.unexpectedHooks("hooks.Stop")) { try merge(#"{"hooks": {"Stop": {"a": 1}}}"#) }
        #expect(HookSettings.Problem.notJSON.errorDescription?.contains("je n'y ai pas touché") == true)
    }

    @Test func everythingElseIsKeptAndOwnHooksAreNotDoubled() throws {
        let original = #"""
        {"model": "opus", "permissions": {"allow": ["Bash(git *)"]},
         "hooks": {"Stop": [{"hooks": [{"type": "command", "command": "say done"}]}],
                   "SessionStart": [{"hooks": [{"type": "command", "command": "\"/Users/moi/Library/Application Support/Yumi/yumi-hook\""}]},
                                    {"hooks": [{"type": "command", "command": "/x/coucou-hook"}]}]}}
        """#
        let settings = try merge(original)
        #expect(settings["model"] as? String == "opus")
        #expect((settings["permissions"] as? [String: Any])?["allow"] as? [String] == ["Bash(git *)"])
        let hooks = try #require(settings["hooks"] as? [String: Any])
        let stop = try #require(hooks["Stop"] as? [[String: Any]])
        #expect(((stop.first?["hooks"] as? [[String: Any]])?.first?["command"] as? String) == "say done")
        let start = try #require(hooks["SessionStart"] as? [[String: Any]])
        let commands = start.flatMap { ($0["hooks"] as? [[String: Any]] ?? []).compactMap { $0["command"] as? String } }
        #expect(commands == [command])
    }

    @Test func aBackupNeverReplacesAnEarlierOne() {
        let settings = URL(fileURLWithPath: "/Users/moi/.claude/settings.json")
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let taken: Set<String> = ["/Users/moi/.claude/settings.json.bak-20260921-1653", "/Users/moi/.claude/settings.json.bak-20260921-1653-2"]
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let first = HookSettings.backupURL(for: settings, now: now) { _ in false }
        #expect(first.lastPathComponent.hasPrefix("settings.json.bak-"))
        let next = HookSettings.backupURL(for: settings, now: now) { taken.contains($0.path) || $0 == first }
        #expect(next != first)
        #expect(next.path.hasPrefix(first.path))
    }
}

@Suite struct HookLauncherTests {
    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("yumi-launcher-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Runs the launcher as Claude Code would: payload on stdin.
    private func run(_ script: String, in folder: URL) throws -> (status: Int32, output: String) {
        let launcher = folder.appendingPathComponent("yumi-hook")
        try script.write(to: launcher, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: launcher.path)
        let process = Process()
        process.executableURL = launcher
        let input = Pipe(), output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        try process.run()
        input.fileHandleForWriting.write(Data(#"{"hook_event_name": "Stop"}"#.utf8))
        try input.fileHandleForWriting.close()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self))
    }

    @Test func withoutPythonItExitsCleanlyAndSaysNothing() throws {
        let here = try folder()
        defer { try? FileManager.default.removeItem(at: here) }
        let script = HookLauncher.script(pythons: [here.path + "/none"], systemPython: here.path + "/none", toolsCheck: "/usr/bin/false")
        let result = try run(script, in: here)
        #expect(result.status == 0)
        #expect(result.output.isEmpty)
    }

    @Test func theSystemPythonIsUsedOnlyWithTheDeveloperTools() throws {
        let here = try folder()
        defer { try? FileManager.default.removeItem(at: here) }
        let fake = here.appendingPathComponent("python3")
        try "#!/bin/sh\necho \"relay:$1\"\n".write(to: fake, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fake.path)
        let withoutTools = HookLauncher.script(pythons: [], systemPython: fake.path, toolsCheck: "/usr/bin/false")
        #expect(try run(withoutTools, in: here).output.isEmpty)
        let withTools = HookLauncher.script(pythons: [], systemPython: fake.path, toolsCheck: "/usr/bin/true")
        #expect(try run(withTools, in: here).output == "relay:\(here.path)/\(HookLauncher.relayName)\n")
        let standalone = HookLauncher.script(pythons: [fake.path], systemPython: here.path + "/none", toolsCheck: "/usr/bin/false")
        #expect(try run(standalone, in: here).output.hasPrefix("relay:"))
    }

    @Test func theAppSaysItBeforeClaudeCodeIsAffected() {
        #expect(!HookLauncher.pythonAvailable(isExecutable: { $0 == "/usr/bin/python3" }, developerToolsInstalled: { false }))
        #expect(HookLauncher.pythonAvailable(isExecutable: { $0 == "/usr/bin/python3" }, developerToolsInstalled: { true }))
        #expect(HookLauncher.pythonAvailable(isExecutable: { $0 == "/opt/homebrew/bin/python3" }, developerToolsInstalled: { false }))
        #expect(HookLauncher.missingPython.contains("xcode-select --install"))
        #expect(!HookLauncher.script.contains("python3 \"$relay\"; fi\nexec"))
    }
}

@Suite struct PlannerFirstDayTests {
    private let request = LLMRequest(system: "rules", messages: [LLMMessage(role: .user, content: "plan")],
                                     expectsJSON: true, maxOutputTokens: 100)

    private func claudeCode(_ answer: String, delay: Duration = .zero, timeout: Duration = .seconds(5)) -> ClaudeCodeLLMProvider {
        ClaudeCodeLLMProvider(binary: { "/opt/homebrew/bin/claude" },
                              folder: FileManager.default.temporaryDirectory.appendingPathComponent("yumi-planner-first").path,
                              runner: { _, _, _, _ in
                                  try await Task.sleep(for: delay)
                                  return Data(answer.utf8)
                              }, timeout: timeout)
    }

    @Test func notLoggedInLetsTheAPIKeyPlan() async throws {
        let notLoggedIn = #"{"type": "result", "is_error": true, "subtype": "success", "result": "Not logged in · Please run /login"}"#
        await #expect(throws: LLMProviderError.unavailable) { try await claudeCode(notLoggedIn).complete(request) }
        let api = AnthropicLLMProvider(model: "m", apiKey: { "sk" }, transport: { urlRequest in
            (Data(#"{"content": [{"type": "text", "text": "from api"}]}"#.utf8),
             HTTPURLResponse(url: urlRequest.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        let both = FallbackLLMProvider(providers: [claudeCode(notLoggedIn), api])
        #expect(try await both.complete(request).text == "from api")
    }

    @Test func aPlannerThatHangsIsStopped() async {
        let slow = claudeCode(#"{"result": "late"}"#, delay: .seconds(30), timeout: .milliseconds(100))
        let started = Date()
        await #expect(throws: LLMProviderError.failed("Claude Code did not answer in time")) { try await slow.complete(request) }
        #expect(Date().timeIntervalSince(started) < 5)
    }
}

@MainActor
@Suite struct MemoryFirstDayTests {
    @Test func anUnreadableMemoryIsPutAsideNotOverwritten() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("yumi-memory-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("memoire.md")
        let garbage = Data([0xFF, 0xFE, 0x00, 0xC3, 0x28])
        try garbage.write(to: url)
        let store = MemoryStore(fileURL: url) { _ in }
        store.start()
        store.change { $0.setName("Léa") }
        store.stop()
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        let aside = try #require(names.first { $0.hasPrefix("memoire.illisible-") })
        #expect(try Data(contentsOf: folder.appendingPathComponent(aside)) == garbage)
        #expect(try String(contentsOf: url, encoding: .utf8).contains("Léa"))
    }
}
