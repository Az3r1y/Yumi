import Foundation
import Testing

/// The chat's permission requests go in the same history as the agent's, and keep no argument.
@Suite struct ChatPermissionAuditTests {
    private let home = "/Users/someone"

    private func input(_ object: [String: Any]) -> Data { try! JSONSerialization.data(withJSONObject: object) }

    @Test func aPageIsKeptByItsHostOnly() {
        let entry = ChatPermissionAudit.entry(tool: "WebFetch", input: input(["url": "https://Example.com/private/path?token=abc", "prompt": "résume"]),
                                              outcome: .approved(always: false), date: Date(), home: home)
        #expect(entry.toolID == "chat:WebFetch")
        #expect(entry.resources == ["example.com"])
        #expect(entry.risk == .high)
        #expect(entry.decision == .approved)
        #expect(entry.decidedBy == .user)
        #expect(entry.scope == .oneTime)
        #expect(entry.runID == nil)
    }

    @Test func aFileIsKeptByItsPlaceFromHome() {
        let entry = ChatPermissionAudit.entry(tool: "Read", input: input(["file_path": "/Users/someone/Documents/contrat.pdf"]),
                                              outcome: .denied, date: Date(), home: home)
        #expect(entry.resources == ["~/Documents/contrat.pdf"])
        #expect(entry.risk == .low)
        #expect(entry.action == "read")
        #expect(entry.decision == .denied)
    }

    @Test func aSearchKeepsNothingOfWhatWasSearched() {
        let entry = ChatPermissionAudit.entry(tool: "WebSearch", input: input(["query": "mon diagnostic médical"]),
                                              outcome: .expired, date: Date(), home: home)
        #expect(entry.resources.isEmpty)
        #expect(entry.decision == .expired)
        #expect(entry.decidedBy == .system)
    }

    @Test func everyWayARequestEndsIsRecorded() {
        let read = input(["file_path": "/tmp/a"])
        #expect(ChatPermissionAudit.entry(tool: "Read", input: read, outcome: .approved(always: true), date: Date()).scope == .session)
        let blocked = ChatPermissionAudit.entry(tool: "Bash", input: input(["command": "rm -rf ~"]), outcome: .blocked, date: Date())
        #expect(blocked.decision == .blocked)
        #expect(blocked.risk == .high)
        #expect(blocked.resources.isEmpty)
        #expect(ChatPermissionAudit.entry(tool: "Read", input: read, outcome: .cancelled, date: Date()).decision == .cancelled)
    }

    @Test func theIslandsAnswersMapToOutcomes() {
        #expect(ChatPermissionAudit.outcome(islandAnswer: "allow") == .approved(always: false))
        #expect(ChatPermissionAudit.outcome(islandAnswer: "always") == .approved(always: true))
        #expect(ChatPermissionAudit.outcome(islandAnswer: "deny") == .denied)
        #expect(ChatPermissionAudit.outcome(islandAnswer: "ask") == .expired)
    }

    @MainActor
    @Test func theyLandInTheSameHistoryAsTheAgent() {
        let log = PermissionAuditLog(sink: MemoryAuditSink())
        log.record(ChatPermissionAudit.entry(tool: "WebFetch", input: input(["url": "https://example.com"]), outcome: .denied, date: Date()))
        #expect(log.entries.map(\.toolID) == ["chat:WebFetch"])
    }
}
