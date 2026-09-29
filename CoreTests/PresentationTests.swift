import Testing
import Foundation
@testable import Yumi

/// Tests for the presentation layer (UI-side): state derivation from sessions
/// and the presentation → character mapping. These types live in the UI layer
/// now, but they carry logic that must stay verified.
@MainActor
@Suite struct PresentationTests {

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

    // MARK: - Presentation → Character mapping

    @Test func characterStateMapping() {
        let controller = CharacterController()
        controller.sync(presentationState: .idle)
        #expect(controller.animationController.state == .idle)
        controller.sync(presentationState: .working)
        #expect(controller.animationController.state == .working)
        controller.sync(presentationState: .permissionRequired)
        #expect(controller.animationController.state == .waiting)
        controller.sync(presentationState: .questionRequired)
        #expect(controller.animationController.state == .waiting)
        controller.sync(presentationState: .completed)
        #expect(controller.animationController.state == .happy)
        controller.sync(presentationState: .errored)
        #expect(controller.animationController.state == .errored)
    }

    @Test func transitionDetection() {
        #expect(YumiPresentationTransition.between(.idle, .working) == .toWorking)
        #expect(YumiPresentationTransition.between(.working, .completed) == .toCompleted)
        #expect(YumiPresentationTransition.between(.working, .working) == nil)
        #expect(YumiPresentationTransition.between(.completed, .errored) == .toErrored)
        #expect(YumiPresentationTransition.between(.working, .permissionRequired) == .toWaiting)
    }
}
