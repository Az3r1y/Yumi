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
        #expect(day.costUSD == 2.5)
    }

    @Test func noCostWrittenSinceMidnightIsNotGuessed() throws {
        let file = try transcript([cost(4), message("user", "09T09:00:00.000"), message("user", "09T09:01:00.000")])
        #expect(ClaudeUsageReader.day(files: [file], since: midnight).costUSD == nil)
    }

    @Test func aDayWithoutClaudeSaysSo() {
        let day = ClaudeUsageReader.day(files: [], since: midnight)
        #expect(day == ClaudeUsageDay())
        #expect(ClaudeUsageReader.snapshot(day).title == "Pas encore de Claude aujourd'hui")
    }

    @Test func theIslandShowsTimeTokensAndCost() {
        let snapshot = ClaudeUsageReader.snapshot(ClaudeUsageDay(sessions: 3, activeSeconds: 2 * 3600 + 5 * 60, outputTokens: 42_000,
                                                                 inputTokens: 1_200_000, costUSD: 4.2))
        #expect(snapshot.title == "2 h 05 avec Claude aujourd'hui")
        #expect(snapshot.rows.map(\.label) == ["3", "2 h 05", "42 k", "1,2 M", snapshot.status])
        #expect(snapshot.status.contains("4,20"))
        #expect(snapshot.primarySymbol == "arrow.clockwise")
    }

    @Test func itReadsInEnglish() {
        AppLanguage.$forced.withValue("en") {
            let snapshot = ClaudeUsageReader.snapshot(ClaudeUsageDay(sessions: 3, activeSeconds: 600, outputTokens: 1, inputTokens: 1))
            #expect(snapshot.name == "Claude usage")
            #expect(snapshot.title == "10 min with Claude today")
            #expect(snapshot.subtitle == "3 sessions · 2 tokens")
        }
    }

    @Test func tokensReadShort() {
        #expect(ClaudeUsageReader.tokens(850) == "850")
        #expect(ClaudeUsageReader.tokens(12_400) == "12 k")
    }
}
