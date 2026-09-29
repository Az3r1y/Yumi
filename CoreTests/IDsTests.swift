import Testing
import Foundation
@testable import Yumi

@Suite struct IDTests {

    @Test func generatedIDsAreUnique() {
        #expect(SessionID() != SessionID())
        #expect(AgentID() != AgentID())
        #expect(EventID() != EventID())
    }

    @Test func sameValueIDsAreEqual() {
        #expect(SessionID("abc") == SessionID("abc"))
        #expect(SessionID("abc") != SessionID("other"))
    }

    @Test func idsHashConsistently() {
        #expect(SessionID("k").hashValue == SessionID("k").hashValue)
        #expect(SessionID("k").hashValue != SessionID("other").hashValue)
    }

    @Test func idsCodableRoundtrip() throws {
        let original = SessionID("session-42")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SessionID.self, from: data)
        #expect(decoded == original)
    }

    @Test func sessionCodableRoundtrip() throws {
        let agent = Agent(id: AgentID("claude-code"), name: "Claude Code", kind: .coding)
        var session = Session(id: SessionID("s1"), agent: agent, title: "Refactor")
        session.activity = .working(ToolInfo(id: "t1", name: "Edit", summary: "a.swift"))

        let data = try JSONEncoder().encode(session)
        let decoded = try JSONDecoder().decode(Session.self, from: data)

        #expect(decoded == session)
    }
}
