import Testing
import Foundation
import AppKit

private final class TestClock: @unchecked Sendable {
    var now = Date(timeIntervalSince1970: 1_790_000_000)
    func advance(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
}

@MainActor
private final class FakeProvider: ContextProvider {
    var report: (@MainActor (ContextObservation) -> Void)?
    var starts = 0
    var stops = 0
    var followed: [ApplicationContext?] = []

    func start(report: @escaping @MainActor (ContextObservation) -> Void) {
        starts += 1
        self.report = report
    }

    func stop() {
        stops += 1
        report = nil
    }

    func applicationDidChange(to application: ApplicationContext?) { followed.append(application) }

    func send(_ observation: ContextObservation) { report?(observation) }
}

private let code = ApplicationContext(bundleID: "com.microsoft.VSCode", name: "Visual Studio Code", processID: 101)
private let chrome = ApplicationContext(bundleID: "com.google.Chrome", name: "Google Chrome", processID: 103)

/// Waits a little for something asynchronous, without a fixed sleep.
@MainActor
private func eventually(_ condition: () -> Bool) async -> Bool {
    for _ in 0..<200 {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return condition()
}

/// The engine with fake providers: what it publishes, and when.
@MainActor
@Suite struct ContextEngineTests {
    private let clock = TestClock()
    private let provider = FakeProvider()

    private func makeEngine(settle: Duration = .seconds(60)) -> ContextEngine {
        ContextEngine(providers: [provider], changeSettle: settle, clock: { [clock] in clock.now })
    }

    @Test func itStartsOffAndWatchesNothing() {
        let engine = makeEngine()
        #expect(!engine.isEnabled)
        #expect(!engine.snapshot.isEnabled)
        #expect(provider.starts == 0)
        engine.receive(.applicationActivated(code))
        #expect(engine.snapshot.activeApplication == nil)
    }

    @Test func turningItOnStartsTheProvidersAndASession() {
        let engine = makeEngine()
        engine.setEnabled(true)
        #expect(provider.starts == 1)
        #expect(engine.snapshot.isEnabled)
        #expect(engine.snapshot.presence == .observing)
        #expect(engine.snapshot.sessionStartedAt == clock.now)
        engine.setEnabled(true)
        #expect(provider.starts == 1)
    }

    @Test func theFirstApplicationIsNotAChangeOfContext() {
        let engine = makeEngine()
        engine.setEnabled(true)
        provider.send(.applicationActivated(code))
        #expect(engine.snapshot.activeApplication == code)
        #expect(engine.snapshot.presence == .observing)
        #expect(provider.followed == [code])
    }

    @Test func aChangeOfApplicationIsNoticedThenSettles() async {
        let engine = makeEngine(settle: .milliseconds(30))
        engine.setEnabled(true)
        provider.send(.applicationActivated(code))
        clock.advance(5)
        provider.send(.applicationActivated(chrome))
        #expect(engine.snapshot.presence == .contextChanged)
        #expect(engine.snapshot.previousApplication == code)
        #expect(provider.followed == [code, chrome])
        #expect(await eventually { engine.snapshot.presence == .observing })
    }

    @Test func aRepeatedObservationPublishesNothing() async {
        let engine = makeEngine()
        engine.setEnabled(true)
        provider.send(.applicationActivated(code))
        let before = engine.snapshot
        clock.advance(3)
        provider.send(.applicationActivated(code))
        #expect(engine.snapshot == before)
        #expect(provider.followed == [code])
    }

    @Test func leavingTheMacMakesYumiIdle() {
        let engine = makeEngine()
        engine.setEnabled(true)
        provider.send(.applicationActivated(code))
        provider.send(.system(.screenLocked))
        #expect(engine.snapshot.presence == .idle)
        #expect(engine.snapshot.sessionStartedAt == nil)
        provider.send(.system(.screenUnlocked))
        #expect(engine.snapshot.presence == .observing)
    }

    @Test func turningItOffForgetsEverything() {
        let engine = makeEngine()
        engine.setEnabled(true)
        provider.send(.applicationActivated(code))
        provider.send(.applicationActivated(chrome))
        engine.setEnabled(false)
        #expect(provider.stops == 1)
        #expect(!engine.snapshot.isEnabled)
        #expect(engine.snapshot.activeApplication == nil)
        #expect(engine.snapshot.recentEvents.isEmpty)

        engine.setEnabled(true)
        #expect(engine.snapshot.recentApplications.isEmpty)
        #expect(engine.snapshot.recentEvents.map(\.name) == ["sessionStarted"])
    }

    @Test func subscribersReceiveEventsThenTheSnapshot() async {
        let engine = makeEngine()
        let messages = engine.messages()
        engine.setEnabled(true)
        provider.send(.applicationActivated(code))
        clock.advance(60)
        engine.setEnabled(false)

        var names: [String] = []
        var lastSnapshot: ContextSnapshot?
        for await message in messages {
            switch message {
            case .event(let event): names.append(event.name)
            case .contextUpdated(let snapshot):
                names.append("contextUpdated")
                lastSnapshot = snapshot
            }
            if lastSnapshot?.isEnabled == false { break }
        }
        #expect(names == ["sessionStarted", "contextUpdated",
                          "applicationChanged", "contextUpdated",
                          "sessionEnded", "contextUpdated"])
    }

    @Test func aStoppedSubscriberIsForgotten() async {
        let engine = makeEngine()
        let task = Task { for await _ in engine.messages() {} }
        await Task.yield()
        task.cancel()
        _ = await task.value
        engine.setEnabled(true)
        #expect(engine.snapshot.isEnabled)
    }
}

/// The real providers, against this Mac. They need no permission and never ask for one.
@MainActor
@Suite struct ContextProviderIntegrationTests {
    @Test func theWorkspaceProviderReportsTheFrontApplication() {
        let engine = ContextEngine(providers: [WorkspaceContextProvider(ignoredBundleID: nil)])
        engine.setEnabled(true)
        defer { engine.setEnabled(false) }
        if let front = NSWorkspace.shared.frontmostApplication {
            #expect(engine.snapshot.activeApplication?.processID == front.processIdentifier)
        } else {
            #expect(engine.snapshot.activeApplication == nil)
        }
    }

    @Test func theWindowProviderReportsThePermissionWithoutAsking() {
        let engine = ContextEngine(providers: [WindowContextProvider()])
        engine.setEnabled(true)
        defer { engine.setEnabled(false) }
        #expect(engine.snapshot.accessibility == AccessibilityPermission.status())
        if engine.snapshot.accessibility != .granted {
            #expect(engine.snapshot.activeWindow == nil)
        }
    }

    @Test func bothProvidersTogether() {
        let engine = ContextEngine(providers: [WorkspaceContextProvider(ignoredBundleID: nil), WindowContextProvider()])
        engine.setEnabled(true)
        engine.setEnabled(false)
        #expect(!engine.snapshot.isEnabled)
        #expect(engine.snapshot.activeApplication == nil)
    }
}
