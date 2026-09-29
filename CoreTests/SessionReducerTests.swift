import Testing
import Foundation
@testable import Yumi

@Suite struct SessionReducerTests {

    private let agent = Agent(name: "Test Agent", kind: .coding)

    @Test func sessionStartedCreatesSession() {
        let id = SessionID("s1")
        let sessions = SessionReducer.apply(.sessionStarted(id, agent, title: "Build"), to: [:])
        #expect(sessions.count == 1)
        #expect(sessions[id]?.title == "Build")
        #expect(sessions[id]?.status == .running)
        #expect(sessions[id]?.activity == .idle)
    }

    @Test func sessionStartedTwiceDoesNotDuplicate() {
        let id = SessionID("s1")
        var sessions = SessionReducer.apply(.sessionStarted(id, agent, title: "First"), to: [:])
        sessions = SessionReducer.apply(.sessionStarted(id, agent, title: "Second"), to: sessions)
        #expect(sessions.count == 1)
        #expect(sessions[id]?.title == "First")
    }

    @Test func sessionEndedRemovesSession() {
        let id = SessionID("s1")
        var sessions = SessionReducer.apply(.sessionStarted(id, agent, title: "T"), to: [:])
        sessions = SessionReducer.apply(.sessionEnded(id), to: sessions)
        #expect(sessions.isEmpty)
    }

    @Test func toolStartedMovesToWorking() {
        let id = SessionID("s1")
        let tool = ToolInfo(name: "Edit", summary: "main.swift")
        var sessions = SessionReducer.apply(.sessionStarted(id, agent, title: "T"), to: [:])
        sessions = SessionReducer.apply(.toolStarted(id, tool), to: sessions)
        #expect(sessions[id]?.status == .running)
        #expect(sessions[id]?.activity == .working(tool))
    }

    @Test func toolFinishedReturnsToIdle() {
        let id = SessionID("s1")
        let tool = ToolInfo(name: "Bash", summary: "ls")
        var sessions = SessionReducer.apply(.sessionStarted(id, agent, title: "T"), to: [:])
        sessions = SessionReducer.apply(.toolStarted(id, tool), to: sessions)
        sessions = SessionReducer.apply(.toolFinished(id, tool), to: sessions)
        #expect(sessions[id]?.status == .running)
        #expect(sessions[id]?.activity == .idle)
    }

    @Test func permissionRequestWaitsForUser() {
        let id = SessionID("s1")
        let request = PermissionRequest(tool: "Bash", command: "swift test")
        var sessions = SessionReducer.apply(.sessionStarted(id, agent, title: "T"), to: [:])
        sessions = SessionReducer.apply(.permissionRequested(id, request), to: sessions)
        #expect(sessions[id]?.status == .waitingForUser)
        #expect(sessions[id]?.activity == .requestingPermission(request))
    }

    @Test func questionWaitsForUser() {
        let id = SessionID("s1")
        let question = Question(text: "Which engine?", options: ["A", "B"])
        var sessions = SessionReducer.apply(.sessionStarted(id, agent, title: "T"), to: [:])
        sessions = SessionReducer.apply(.questionRequested(id, question), to: sessions)
        #expect(sessions[id]?.status == .waitingForUser)
        #expect(sessions[id]?.activity == .asking(question))
    }

    @Test func taskCompletedMarksSession() {
        let id = SessionID("s1")
        var sessions = SessionReducer.apply(.sessionStarted(id, agent, title: "T"), to: [:])
        sessions = SessionReducer.apply(.taskCompleted(id), to: sessions)
        #expect(sessions[id]?.status == .completed)
        #expect(sessions[id]?.activity == .idle)
    }

    @Test func sessionErrorMarksSession() {
        let id = SessionID("s1")
        var sessions = SessionReducer.apply(.sessionStarted(id, agent, title: "T"), to: [:])
        sessions = SessionReducer.apply(.sessionErrored(id, YumiError(message: "boom")), to: sessions)
        #expect(sessions[id]?.status == .errored)
        #expect(sessions[id]?.activity == .idle)
    }

    @Test func eventsForUnknownSessionsAreIgnored() {
        let sessions = SessionReducer.apply(.toolStarted(SessionID("ghost"), ToolInfo(name: "X")), to: [:])
        #expect(sessions.isEmpty)
    }

    @Test func multipleSessionsStayIndependent() {
        let a = SessionID("a")
        let b = SessionID("b")
        var sessions = SessionReducer.apply(.sessionStarted(a, agent, title: "A"), to: [:])
        sessions = SessionReducer.apply(.sessionStarted(b, agent, title: "B"), to: sessions)
        sessions = SessionReducer.apply(.permissionRequested(a, PermissionRequest(tool: "Bash")), to: sessions)
        sessions = SessionReducer.apply(.toolStarted(b, ToolInfo(name: "Edit")), to: sessions)

        #expect(sessions[a]?.status == .waitingForUser)
        #expect(sessions[b]?.status == .running)
    }
}

@Suite struct PresentationStateTests {

    private let agent = Agent(name: "Test Agent", kind: .coding)

    private func makeSession(status: SessionStatus, activity: YumiActivity) -> Session {
        var session = Session(id: SessionID(), agent: agent, title: "T")
        session.status = status
        session.activity = activity
        return session
    }

    @Test func emptyIsIdle() {
        #expect(YumiPresentationState(sessions: []) == .idle)
    }

    @Test func runningIsWorking() {
        let sessions = [makeSession(status: .running, activity: .idle)]
        #expect(YumiPresentationState(sessions: sessions) == .working)
    }

    @Test func permissionTakesPrecedenceOverWorking() {
        let sessions = [
            makeSession(status: .running, activity: .idle),
            makeSession(status: .waitingForUser, activity: .requestingPermission(PermissionRequest(tool: "Bash"))),
        ]
        #expect(YumiPresentationState(sessions: sessions) == .permissionRequired)
    }

    @Test func questionIsRecognized() {
        let sessions = [makeSession(status: .waitingForUser, activity: .asking(Question(text: "?")))]
        #expect(YumiPresentationState(sessions: sessions) == .questionRequired)
    }

    @Test func completedIsRecognized() {
        let sessions = [makeSession(status: .completed, activity: .idle)]
        #expect(YumiPresentationState(sessions: sessions) == .completed)
    }

    @Test func errorTakesPrecedenceOverEverything() {
        let sessions = [
            makeSession(status: .waitingForUser, activity: .requestingPermission(PermissionRequest(tool: "Bash"))),
            makeSession(status: .errored, activity: .idle),
        ]
        #expect(YumiPresentationState(sessions: sessions) == .errored)
    }
}
