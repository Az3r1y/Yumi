import Testing
import Foundation

// Core/ is compiled straight into this bundle (see project.yml): it has no dependency
// on the rest of the app, so these tests run without launching Yumi.

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

@Suite struct SessionTurnTests {

    private let agent = Agent(name: "Test Agent", kind: .coding)
    private let id = SessionID("s1")

    private func started() -> [SessionID: Session] {
        SessionReducer.apply(.sessionStarted(id, agent, title: "T"), to: [:])
    }

    @Test func promptStartsATurn() {
        let sessions = SessionReducer.apply(.promptSubmitted(id, text: "hello"), to: started())
        #expect(sessions[id]?.activity == .thinking)
        #expect(sessions[id]?.isTurnActive == true)
    }

    @Test func aSessionBetweenTwoToolsIsStillInItsTurn() {
        let tool = ToolInfo(name: "Bash", summary: "ls")
        var sessions = SessionReducer.apply(.promptSubmitted(id, text: "hello"), to: started())
        sessions = SessionReducer.apply(.toolStarted(id, tool), to: sessions)
        sessions = SessionReducer.apply(.toolFinished(id, tool), to: sessions)
        #expect(sessions[id]?.activity == .idle)
        #expect(sessions[id]?.isTurnActive == true)
    }

    @Test func completionEndsTheTurn() {
        var sessions = SessionReducer.apply(.promptSubmitted(id, text: "hello"), to: started())
        sessions = SessionReducer.apply(.taskCompleted(id), to: sessions)
        #expect(sessions[id]?.isTurnActive == false)
    }

    @Test func toolFinishedKeepsAPendingPermissionOnScreen() {
        let request = PermissionRequest(tool: "Bash", command: "rm -rf build")
        var sessions = SessionReducer.apply(.permissionRequested(id, request), to: started())
        sessions = SessionReducer.apply(.toolFinished(id, ToolInfo(name: "Read")), to: sessions)
        #expect(sessions[id]?.activity == .requestingPermission(request))
        #expect(sessions[id]?.status == .waitingForUser)
    }

    @Test func permissionResolvedResumesTheSession() {
        let request = PermissionRequest(tool: "Bash", command: "swift test")
        var sessions = SessionReducer.apply(.permissionRequested(id, request), to: started())
        sessions = SessionReducer.apply(.permissionResolved(id, requestID: request.id), to: sessions)
        #expect(sessions[id]?.activity == .idle)
        #expect(sessions[id]?.status == .running)
        #expect(sessions[id]?.isTurnActive == true)
    }

    @Test func resolvingAnotherRequestChangesNothing() {
        let request = PermissionRequest(tool: "Bash", command: "swift test")
        var sessions = SessionReducer.apply(.permissionRequested(id, request), to: started())
        sessions = SessionReducer.apply(.permissionResolved(id, requestID: "someone-else"), to: sessions)
        #expect(sessions[id]?.activity == .requestingPermission(request))
    }

    @Test func locationIsRecorded() {
        let origin = SessionOrigin(workingDirectory: "/tmp/yumi", hostBundleID: "com.apple.Terminal", hostName: "Apple_Terminal")
        let sessions = SessionReducer.apply(.sessionLocated(id, origin), to: started())
        #expect(sessions[id]?.origin == origin)
    }

    @Test func rateLimitIsClearedByTheNextPrompt() {
        var sessions = SessionReducer.apply(.rateLimited(id), to: started())
        #expect(sessions[id]?.status == .rateLimited)
        sessions = SessionReducer.apply(.promptSubmitted(id, text: "again"), to: sessions)
        #expect(sessions[id]?.status == .running)
    }

    @Test func aNoteChangesNoState() {
        let before = started()
        var after = SessionReducer.apply(.activityNoted(id, "+ subagent"), to: before)
        after[id]?.recency = before[id]?.recency ?? 0
        #expect(after == before)
    }

    @Test func theLastSessionTouchedIsTheMostRecent() {
        let other = SessionID("s2")
        var sessions = SessionReducer.apply(.sessionStarted(other, agent, title: "U"), to: started())
        #expect((sessions[other]?.recency ?? 0) > (sessions[id]?.recency ?? 0))
        sessions = SessionReducer.apply(.activityNoted(id, "still here"), to: sessions)
        #expect((sessions[id]?.recency ?? 0) > (sessions[other]?.recency ?? 0))
    }
}
