import Testing
import Foundation

// IslandStateMachine.swift is compiled straight into this bundle (see project.yml):
// it has no dependency, so the tests run without launching the app.

@Suite @MainActor struct IslandStateMachineTests {

    typealias State = IslandStateMachine.State

    /// Short enough to keep the suite fast, long enough to be observed.
    static let short: TimeInterval = 0.05
    /// Longer than any test waits: a timer set to this never fires during a test.
    static let never: TimeInterval = 60
    /// How long we watch a state that must not change.
    static let settle: Duration = .milliseconds(250)

    /// Records every (from, to) pair reported by `onTransition`.
    final class Log {
        var transitions: [[State]] = []
    }

    private func makeFSM(
        homeToPetit: TimeInterval = never,
        petitToHidden: TimeInterval = never,
        greetAuto: TimeInterval = never,
        greetHover: TimeInterval = never
    ) -> (IslandStateMachine, Log) {
        let fsm = IslandStateMachine()
        fsm.homeToPetitDelay = homeToPetit
        fsm.petitToHiddenDelay = petitToHidden
        fsm.greetAutoCollapseDelay = greetAuto
        fsm.greetHoverCollapseDelay = greetHover
        let log = Log()
        fsm.onTransition = { from, to in log.transitions.append([from, to]) }
        return (fsm, log)
    }

    /// Polls until the machine reaches `expected`, or gives up after `timeout`.
    private func reaches(_ expected: State, _ fsm: IslandStateMachine, timeout: TimeInterval = 5) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while fsm.state != expected {
            if Date() > deadline { return false }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return true
    }

    // MARK: – Initial state and launch

    @Test func startsHidden() {
        let (fsm, log) = makeFSM()
        #expect(fsm.state == .hidden)
        #expect(log.transitions.isEmpty)
    }

    @Test func launchOpensTheGreeting() {
        let (fsm, log) = makeFSM()
        fsm.launch()
        #expect(fsm.state == .coucou)
        #expect(log.transitions == [[.hidden, .coucou]])
    }

    @Test func launchingTwiceReportsOneTransition() {
        let (fsm, log) = makeFSM()
        fsm.launch()
        fsm.launch()
        #expect(log.transitions.count == 1)
    }

    @Test func launchCancelsAPendingHide() async {
        let (fsm, _) = makeFSM(petitToHidden: Self.short)
        fsm.mouseEntered()
        fsm.mouseLeft()
        fsm.launch()
        try? await Task.sleep(for: Self.settle)
        #expect(fsm.state == .coucou)
    }

    // MARK: – Hover

    @Test func hoverRevealsTheCompactIsland() {
        let (fsm, log) = makeFSM()
        fsm.mouseEntered()
        #expect(fsm.state == .petit)
        #expect(log.transitions == [[.hidden, .petit]])
    }

    @Test func leavingWhileHiddenDoesNothing() {
        let (fsm, log) = makeFSM()
        fsm.mouseLeft()
        #expect(fsm.state == .hidden)
        #expect(log.transitions.isEmpty)
    }

    @Test func compactIslandHidesAfterTheMouseLeaves() async {
        let (fsm, log) = makeFSM(petitToHidden: Self.short)
        fsm.mouseEntered()
        fsm.mouseLeft()
        #expect(fsm.state == .petit)
        #expect(await reaches(.hidden, fsm))
        #expect(log.transitions == [[.hidden, .petit], [.petit, .hidden]])
    }

    @Test func compactIslandStaysWhileHovered() async {
        let (fsm, _) = makeFSM(petitToHidden: Self.short)
        fsm.mouseEntered()
        try? await Task.sleep(for: Self.settle)
        #expect(fsm.state == .petit)
    }

    @Test func comingBackCancelsTheHide() async {
        let (fsm, _) = makeFSM(petitToHidden: Self.short)
        fsm.mouseEntered()
        fsm.mouseLeft()
        fsm.mouseEntered()
        try? await Task.sleep(for: Self.settle)
        #expect(fsm.state == .petit)
    }

    // MARK: – Click

    @Test func clickExpandsTheCompactIsland() {
        let (fsm, log) = makeFSM()
        fsm.mouseEntered()
        fsm.click()
        #expect(fsm.state == .home)
        #expect(log.transitions == [[.hidden, .petit], [.petit, .home]])
    }

    @Test func clickIsIgnoredOutsideTheCompactState() {
        let (hidden, _) = makeFSM()
        hidden.click()
        #expect(hidden.state == .hidden)

        let (greeting, _) = makeFSM()
        greeting.launch()
        greeting.click()
        #expect(greeting.state == .coucou)

        let (home, log) = makeFSM()
        home.mouseEntered()
        home.click()
        home.click()
        #expect(home.state == .home)
        #expect(log.transitions.count == 2)
    }

    @Test func clickCancelsAPendingHide() async {
        let (fsm, _) = makeFSM(petitToHidden: Self.short)
        fsm.mouseEntered()
        fsm.mouseLeft()
        fsm.click()
        try? await Task.sleep(for: Self.settle)
        #expect(fsm.state == .home)
    }

    // MARK: – Expanded island

    @Test func expandedIslandCollapsesAfterTheMouseLeaves() async {
        let (fsm, _) = makeFSM(homeToPetit: Self.short)
        fsm.mouseEntered()
        fsm.click()
        fsm.mouseLeft()
        #expect(fsm.state == .home)
        #expect(await reaches(.petit, fsm))
    }

    @Test func expandedIslandStaysWhileHovered() async {
        let (fsm, _) = makeFSM(homeToPetit: Self.short)
        fsm.mouseEntered()
        fsm.click()
        try? await Task.sleep(for: Self.settle)
        #expect(fsm.state == .home)
    }

    @Test func comingBackCancelsTheCollapse() async {
        let (fsm, _) = makeFSM(homeToPetit: Self.short)
        fsm.mouseEntered()
        fsm.click()
        fsm.mouseLeft()
        fsm.mouseEntered()
        try? await Task.sleep(for: Self.settle)
        #expect(fsm.state == .home)
    }

    // MARK: – Greeting

    @Test func greetingCollapsesOnceTheAnimationEnds() async {
        let (fsm, log) = makeFSM(greetAuto: Self.short)
        fsm.launch()
        fsm.greetComplete()
        #expect(fsm.state == .coucou)
        #expect(await reaches(.petit, fsm))
        #expect(log.transitions == [[.hidden, .coucou], [.coucou, .petit]])
    }

    @Test func greetingStaysUntilTheAnimationEnds() async {
        let (fsm, _) = makeFSM(greetAuto: Self.short)
        fsm.launch()
        try? await Task.sleep(for: Self.settle)
        #expect(fsm.state == .coucou)
    }

    @Test func greetCompleteIsIgnoredOutsideTheGreeting() async {
        let (fsm, log) = makeFSM(greetAuto: Self.short)
        fsm.mouseEntered()
        fsm.greetComplete()
        try? await Task.sleep(for: Self.settle)
        #expect(fsm.state == .petit)
        #expect(log.transitions.count == 1)
    }

    @Test func hoveringTheGreetingUsesTheHoverDelay() async {
        let (fsm, _) = makeFSM(greetAuto: Self.never, greetHover: Self.short)
        fsm.launch()
        fsm.mouseEntered()
        #expect(fsm.state == .coucou)
        #expect(await reaches(.petit, fsm))
    }

    @Test func animationEndDoesNotShortenAHoveredGreeting() async {
        let (fsm, _) = makeFSM(greetAuto: Self.short, greetHover: Self.never)
        fsm.launch()
        fsm.mouseEntered()
        fsm.greetComplete()
        try? await Task.sleep(for: Self.settle)
        #expect(fsm.state == .coucou)
    }

    @Test func leavingTheGreetingCollapsesAtOnce() {
        let (fsm, log) = makeFSM()
        fsm.launch()
        fsm.mouseLeft()
        #expect(fsm.state == .petit)
        #expect(log.transitions == [[.hidden, .coucou], [.coucou, .petit]])
    }

    // MARK: – Reveal

    @Test func revealShowsTheCompactIslandThenHidesIt() async {
        let (fsm, log) = makeFSM(petitToHidden: Self.short)
        fsm.reveal()
        #expect(fsm.state == .petit)
        #expect(await reaches(.hidden, fsm))
        #expect(log.transitions == [[.hidden, .petit], [.petit, .hidden]])
    }

    @Test func revealIsIgnoredWhenTheIslandIsVisible() {
        let (fsm, log) = makeFSM()
        fsm.mouseEntered()
        fsm.click()
        fsm.reveal()
        #expect(fsm.state == .home)
        #expect(log.transitions.count == 2)
    }

    @Test func hoveringARevealedIslandKeepsItOpen() async {
        let (fsm, _) = makeFSM(petitToHidden: Self.short)
        fsm.reveal()
        fsm.mouseEntered()
        try? await Task.sleep(for: Self.settle)
        #expect(fsm.state == .petit)
    }

    // MARK: – Timers

    @Test func cancelTimersStopsEveryPendingTransition() async {
        let (fsm, _) = makeFSM(petitToHidden: Self.short)
        fsm.mouseEntered()
        fsm.mouseLeft()
        fsm.cancelTimers()
        try? await Task.sleep(for: Self.settle)
        #expect(fsm.state == .petit)
    }

    @Test func fullCycleReportsEveryTransitionInOrder() async {
        let (fsm, log) = makeFSM(homeToPetit: Self.short, petitToHidden: Self.short, greetAuto: Self.short)
        fsm.launch()
        fsm.greetComplete()
        #expect(await reaches(.petit, fsm))
        fsm.click()
        fsm.mouseLeft()
        #expect(await reaches(.petit, fsm))
        fsm.mouseEntered()
        fsm.mouseLeft()
        #expect(await reaches(.hidden, fsm))
        #expect(log.transitions == [
            [.hidden, .coucou],
            [.coucou, .petit],
            [.petit, .home],
            [.home, .petit],
            [.petit, .hidden],
        ])
    }
}
