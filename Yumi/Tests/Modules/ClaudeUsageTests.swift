import Foundation
import Testing

// The day of Claude Code, read from transcripts written here the way Claude Code writes them.

private let midnight = ISO8601DateFormatter().date(from: "2026-10-09T00:00:00Z")!

private func line(_ object: [String: Any]) -> String {
    String(decoding: try! JSONSerialization.data(withJSONObject: object), as: UTF8.self)
}

private func message(_ type: String, _ time: String, session: String = "s1", id: String? = nil, usage: [String: Int]? = nil) -> String {
    var message: [String: Any] = ["role": type, "content": "…"]
    if let id { message["id"] = id }
    if let usage { message["usage"] = usage }
    return line(["type": type, "timestamp": "2026-10-\(time)Z", "sessionId": session, "message": message])
}

private func cost(_ total: Double) -> String { line(["type": "cost-state", "sessionId": "s1", "totalCostUSD": total]) }

private func transcript(_ lines: [String]) throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("usage-\(UUID().uuidString).jsonl")
    try (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
    return url
}

@Suite struct ClaudeUsageTests {
    @Test func aDayIsCountedFromMidnight() throws {
        let usage = ["output_tokens": 100, "input_tokens": 10, "cache_read_input_tokens": 1000, "cache_creation_input_tokens": 50]
        let file = try transcript([
            message("user", "08T22:00:00.000"),
            cost(1.0),                                                  // yesterday's part of the session
            message("user", "09T09:00:00.000"),
            message("assistant", "09T09:02:00.000", id: "m1", usage: usage),
            message("assistant", "09T09:02:01.000", id: "m1", usage: usage), // the same reply, another block
            message("assistant", "09T09:03:00.000", id: "m2", usage: ["output_tokens": 50]),
            message("user", "09T09:33:00.000"),                          // after a break
            message("assistant", "09T09:35:00.000", id: "m3", usage: ["output_tokens": 10]),
            cost(3.5),
            "not json",
        ])
        let other = try transcript([message("user", "09T10:00:00.000", session: "s2"),
                                    message("assistant", "09T10:01:00.000", session: "s2", id: "m4", usage: ["output_tokens": 5])])
        let day = ClaudeUsageReader.day(files: [file, other], since: midnight)
        #expect(day.sessions == 2)
        // 9:00 to 9:03, 9:33 to 9:35, 10:00 to 10:01: the half hour of silence is not counted
        #expect(day.activeSeconds == 6 * 60)
        #expect(day.outputTokens == 165)
        #expect(day.inputTokens == 1060)
        #expect(day.apiCostUSD == 2.5)
    }

    @Test func theStatusLineGivesTheCostOfTheLiveSession() throws {
        let file = try transcript([message("user", "08T23:00:00.000"), cost(1.0), message("user", "09T09:00:00.000")])
        let session = file.deletingPathExtension().lastPathComponent
        // Yesterday's dollar is not today's
        #expect(ClaudeUsageReader.day(files: [file], since: midnight, live: [session: 4.0]).apiCostUSD == 3.0)
        #expect(ClaudeUsageReader.day(files: [file], since: midnight).apiCostUSD == nil)
    }

    @Test func aDayWithoutClaudeSaysSo() {
        let day = ClaudeUsageReader.day(files: [], since: midnight)
        #expect(day == ClaudeUsageDay())
        let snapshot = ClaudeUsageReader.snapshot(day)
        #expect(snapshot.title == "Pas encore de Claude aujourd'hui")
        #expect(snapshot.rows.first?.label == "à brancher")
    }

    @Test func theAllowancesComeFirstAndTheCostInEuros() {
        let now = ISO8601DateFormatter().date(from: "2026-10-09T10:00:00Z")!
        var day = ClaudeUsageDay(sessions: 3, activeSeconds: 2 * 3600 + 5 * 60, outputTokens: 42_000, inputTokens: 1_200_000,
                                 apiCostUSD: 10, quotasConnected: true)
        day.fiveHour = .init(usedPercent: 42.4, resetsAt: now.addingTimeInterval(3 * 3600))
        day.sevenDay = .init(usedPercent: 18, resetsAt: now.addingTimeInterval(3 * 86_400))
        let snapshot = ClaudeUsageReader.snapshot(day, rate: 0.9, now: now)
        #expect(snapshot.title == "Quota 5 h : 42 %")
        #expect(snapshot.status == "42 %")
        #expect(snapshot.rows.map(\.id) == ["five", "week", "sessions", "time", "tokens", "api"])
        #expect(snapshot.rows[1].label == "18 %")
        #expect(snapshot.rows[5].label.contains("9,00") && snapshot.rows[5].label.contains("€"))
        #expect(!snapshot.subtitle.contains("$") && !snapshot.rows.contains { $0.label.contains("$") })
        #expect(snapshot.progress?.fraction == 0.424)
        #expect(snapshot.live == nil)
    }

    @Test func closeToTheLimitTheFoldedIslandSaysIt() {
        var day = ClaudeUsageDay(sessions: 1)
        day.fiveHour = .init(usedPercent: 91, resetsAt: nil)
        let snapshot = ClaudeUsageReader.snapshot(day)
        #expect(snapshot.live?.text == "Quota 5 h : 91 %")
        #expect(snapshot.rows.first?.state == .failure)
    }

    @Test func itReadsInEnglish() {
        AppLanguage.$forced.withValue("en") {
            let snapshot = ClaudeUsageReader.snapshot(ClaudeUsageDay(sessions: 3, activeSeconds: 600, outputTokens: 1, inputTokens: 1))
            #expect(snapshot.name == "Claude usage")
            #expect(snapshot.title == "10 min with Claude today")
            #expect(snapshot.subtitle == "3 sessions")
        }
    }

    @Test func tokensReadShort() {
        #expect(ClaudeUsageReader.tokens(850) == "850")
        #expect(ClaudeUsageReader.tokens(12_400) == "12 k")
    }
}

// MARK: - The status line relay

@Suite struct StatusLineRelayTests {
    private let command = "/bin/sh \"/Users/someone/Library/Application Support/Yumi/yumi-statusline.sh\""

    @Test func itStandsInFrontOfTheStatusLineAndPutsItBack() throws {
        let original = #"{"model": "opus", "statusLine": {"type": "command", "command": "bash ~/ponytail.sh", "padding": 1}}"#
        let installed = try StatusLineRelay.install(Data(original.utf8), command: command)
        let settings = try #require(JSONSerialization.jsonObject(with: installed.data) as? [String: Any])
        let line = try #require(settings["statusLine"] as? [String: Any])
        #expect(line["command"] as? String == command)
        #expect(line["padding"] as? Int == 1)
        #expect(settings["model"] as? String == "opus")
        #expect(installed.previous?["command"] as? String == "bash ~/ponytail.sh")
        #expect(StatusLineRelay.isInstalled(installed.data, command: command))

        // Installed again: what it stands in front of is not itself
        #expect(try StatusLineRelay.install(installed.data, command: command).previous == nil)

        let removed = try StatusLineRelay.remove(installed.data, command: command, previous: installed.previous)
        let back = try #require(JSONSerialization.jsonObject(with: removed) as? [String: Any])
        #expect((back["statusLine"] as? [String: Any])?["command"] as? String == "bash ~/ponytail.sh")
        #expect(back["model"] as? String == "opus")
    }

    @Test func aStatusLineChangedSinceIsLeftAlone() throws {
        let theirs = #"{"statusLine": {"type": "command", "command": "other"}}"#
        let removed = try StatusLineRelay.remove(Data(theirs.utf8), command: command, previous: ["command": "old"])
        let settings = try #require(JSONSerialization.jsonObject(with: removed) as? [String: Any])
        #expect((settings["statusLine"] as? [String: Any])?["command"] as? String == "other")
    }

    @Test func settingsItCannotReadAreNeverReplaced() {
        #expect(throws: HookSettings.Problem.notJSON) { try StatusLineRelay.install(Data("{oops".utf8), command: command) }
    }

    @Test func theScriptKeepsACopyAndHandsOn() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("relay-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try StatusLineRelay.script.write(to: StatusLineRelay.scriptURL(in: folder), atomically: true, encoding: .utf8)
        // The status line that was there: it prints what it was given
        try "cat".write(to: folder.appendingPathComponent(StatusLineRelay.nextName), atomically: true, encoding: .utf8)
        let input = #"{"session_id":"abc-123","cost":{"total_cost_usd":1.25},"rate_limits":{"five_hour":{"used_percentage":42,"resets_at":1791463800},"seven_day":{"used_percentage":18.5,"resets_at":1791900000}}}"#

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [StatusLineRelay.scriptURL(in: folder).path]
        let stdin = Pipe(), stdout = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        try process.run()
        stdin.fileHandleForWriting.write(Data(input.utf8))
        try stdin.fileHandleForWriting.close()
        process.waitUntilExit()

        #expect(String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self) == input)
        let report = StatusLineRelay.report(in: folder, since: .distantPast)
        #expect(report.fiveHour == .init(usedPercent: 42, resetsAt: Date(timeIntervalSince1970: 1791463800)))
        #expect(report.sevenDay?.usedPercent == 18.5)
        #expect(report.sessionCosts == ["abc-123": 1.25])
        // Nothing left behind but the copy
        let left = try FileManager.default.contentsOfDirectory(atPath: folder.appendingPathComponent(StatusLineRelay.reportsFolder).path)
        #expect(left == ["abc-123.json"])
    }
}

// MARK: - Asking Anthropic

@Suite struct ClaudeQuotaAPITests {
    @Test func theUsualAnswerIsReadInPercent() throws {
        let answer = #"{"five_hour": {"utilization": 42.0, "resets_at": "2026-10-09T14:50:00.123+00:00"}, "seven_day": {"utilization": 18, "resets_at": "2026-10-12T09:00:00Z"}, "seven_day_opus": null}"#
        let read = try #require(ClaudeQuotaAPI.allowances(from: Data(answer.utf8)))
        #expect(read.fiveHour?.usedPercent == 42)
        let resets = try #require(read.fiveHour?.resetsAt)
        #expect(abs(resets.timeIntervalSince(ISO8601DateFormatter().date(from: "2026-10-09T14:50:00Z")!) - 0.123) < 0.001)
        #expect(read.sevenDay?.usedPercent == 18)
    }

    @Test func theListOfLimitsIsReadToo() throws {
        let answer = #"{"limits": [{"kind": "spend", "group": "monthly", "percent": 54}, {"kind": "rate", "group": "five_hour", "percent": 7, "resets_at": "2026-10-09T14:50:00Z"}]}"#
        let read = try #require(ClaudeQuotaAPI.allowances(from: Data(answer.utf8)))
        #expect(read.fiveHour?.usedPercent == 7)
        #expect(read.sevenDay == nil)
    }

    @Test func anAnswerWithoutAllowancesGivesNothing() {
        #expect(ClaudeQuotaAPI.allowances(from: Data(#"{"error": "nope"}"#.utf8)) == nil)
        #expect(ClaudeQuotaAPI.allowances(from: Data("<html>".utf8)) == nil)
    }

    @Test func anExpiredTokenIsNotUsedNorRenewed() {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        func stored(expires: Double) -> Data {
            Data(#"{"claudeAiOauth": {"accessToken": "sk-ant-oat01-x", "refreshToken": "r", "expiresAt": \#(expires)}}"#.utf8)
        }
        #expect(ClaudeQuotaAPI.token(from: stored(expires: (now.timeIntervalSince1970 + 600) * 1000), now: now) == "sk-ant-oat01-x")
        #expect(ClaudeQuotaAPI.token(from: stored(expires: (now.timeIntervalSince1970 - 1) * 1000), now: now) == nil)
        #expect(ClaudeQuotaAPI.token(from: Data("{}".utf8), now: now) == nil)
    }
}

// MARK: - Background sessions, the euro

@Suite struct ClaudeUsageOriginTests {
    @Test func programsCountInTokensNotInTime() throws {
        func entry(_ type: String, _ time: String, _ entrypoint: String, id: String? = nil) -> String {
            var object: [String: Any] = ["type": type, "timestamp": "2026-10-09T\(time)Z", "sessionId": entrypoint, "entrypoint": entrypoint]
            if let id { object["message"] = ["id": id, "usage": ["output_tokens": 10]] }
            return String(decoding: try! JSONSerialization.data(withJSONObject: object), as: UTF8.self)
        }
        let mine = try transcript([entry("user", "09:00:00.000", "claude-desktop"), entry("assistant", "09:02:00.000", "claude-desktop", id: "a")])
        let review = try transcript([entry("user", "09:00:00.000", "sdk-py"), entry("assistant", "09:04:00.000", "sdk-py", id: "b")])
        let day = ClaudeUsageReader.day(files: [mine, review], since: midnight)
        #expect(day.sessions == 1)
        #expect(day.backgroundSessions == 1)
        #expect(day.activeSeconds == 120)
        #expect(day.outputTokens == 20)
        let row = ClaudeUsageReader.snapshot(day).rows.first { $0.id == "background" }
        #expect(row?.label == "1 session")
    }

    @Test func theBanksRateIsTurnedIntoEurosForADollar() throws {
        let file = #"<gesmes:Envelope><Cube><Cube time='2026-10-09'><Cube currency='USD' rate='1.25'/><Cube currency='JPY' rate='160.1'/></Cube></Cube></gesmes:Envelope>"#
        #expect(EuroRate.euros(perDollarIn: Data(file.utf8)) == 0.8)
        #expect(EuroRate.euros(perDollarIn: Data("<html>maintenance</html>".utf8)) == nil)
        #expect(EuroRate.euros(perDollarIn: Data("currency='USD' rate='0'".utf8)) == nil)
    }

    @Test func theBankIsAskedOnceADay() async throws {
        let defaults = try #require(UserDefaults(suiteName: "euro-\(UUID().uuidString)"))
        defaults.set(Date(), forKey: EuroRate.askedKey)
        #expect(await EuroRate.refresh(defaults) == false)
        #expect(EuroRate.current(defaults) == ClaudeUsageReader.defaultRate)
    }
}
