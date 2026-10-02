import Testing
import Foundation

private let t0 = Date(timeIntervalSince1970: 1_790_000_000)
private func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }

private let code = ApplicationContext(bundleID: "com.microsoft.VSCode", name: "Visual Studio Code", processID: 101,
                                      category: ApplicationCategory("public.app-category.developer-tools"))
private let terminal = ApplicationContext(bundleID: "com.apple.Terminal", name: "Terminal", processID: 102,
                                          category: ApplicationCategory("public.app-category.utilities"))
private let chrome = ApplicationContext(bundleID: "com.google.Chrome", name: "Google Chrome", processID: 103,
                                        category: ApplicationCategory("public.app-category.productivity"))

private extension ContextState {
    /// Applies several observations, each `step` seconds after the previous one, from `start`.
    @discardableResult
    mutating func play(_ observations: [ContextObservation], from start: TimeInterval, step: TimeInterval = 1) -> [ContextEvent] {
        var events: [ContextEvent] = []
        for (index, observation) in observations.enumerated() {
            events += apply(observation, at: at(start + Double(index) * step))
        }
        return events
    }
}

private func kinds(_ events: [ContextEvent]) -> [String] { events.map(\.name) }

/// The rules of the Context Engine, without the Mac.
@Suite struct ContextStateTests {

    // MARK: Snapshot

    @Test func aSnapshotDescribesWhatIsInFront() {
        var state = ContextState()
        _ = state.begin(at: at(0))
        _ = state.apply(.applicationActivated(code), at: at(10))
        _ = state.apply(.windowFocused(WindowContext(title: "YumiApp.swift", processID: 101, documentPath: "/tmp/YumiApp.swift")), at: at(12))

        let snapshot = state.snapshot(at: at(70), presence: .observing)
        #expect(snapshot.isEnabled)
        #expect(snapshot.presence == .observing)
        #expect(snapshot.activeApplication == code)
        #expect(snapshot.activeWindow?.title == "YumiApp.swift")
        #expect(snapshot.activeWindow?.documentPath == "/tmp/YumiApp.swift")
        #expect(snapshot.previousApplication == nil)
        #expect(snapshot.sessionDuration == 70)
        #expect(snapshot.activeApplicationDuration(at: at(70)) == 60)
        #expect(snapshot.activeWindowSince == at(12))
        #expect(snapshot.recentApplications.isEmpty)
        #expect(kinds(snapshot.recentEvents) == ["windowChanged", "applicationChanged", "sessionStarted"])
        #expect(snapshot.mainActivity?.category == code.category)
        #expect(snapshot.mainActivity?.share == 1)
    }

    @Test func aSnapshotSurvivesEncoding() throws {
        var state = ContextState()
        _ = state.begin(at: at(0))
        state.play([.applicationActivated(code), .applicationActivated(chrome), .system(.screenLocked)], from: 1)
        let snapshot = state.snapshot(at: at(10), presence: .idle)
        let data = try JSONEncoder().encode(snapshot)
        #expect(try JSONDecoder().decode(ContextSnapshot.self, from: data) == snapshot)
    }

    @Test func theDisabledSnapshotIsEmpty() {
        let snapshot = ContextSnapshot.disabled(at: t0)
        #expect(!snapshot.isEnabled)
        #expect(snapshot.presence == .idle)
        #expect(snapshot.activeApplication == nil && snapshot.sessionStartedAt == nil)
        #expect(snapshot.recentEvents.isEmpty && snapshot.recentApplications.isEmpty)
    }

    // MARK: Applications

    @Test func codeTerminalChromeCode() {
        var state = ContextState()
        _ = state.begin(at: at(0))
        let events = state.play([.applicationActivated(code), .applicationActivated(terminal),
                                 .applicationActivated(chrome), .applicationActivated(code)], from: 1, step: 60)

        #expect(events.count == 4)
        #expect(events[0].kind == .applicationChanged(from: nil, to: code))
        #expect(events[1].kind == .applicationChanged(from: code, to: terminal))
        #expect(events[3].kind == .applicationChanged(from: chrome, to: code))

        let snapshot = state.snapshot(at: at(200), presence: .observing)
        #expect(snapshot.activeApplication == code)
        #expect(snapshot.previousApplication == chrome)
        #expect(snapshot.activeApplicationSince == at(181))
        #expect(snapshot.recentApplications.map(\.name) == ["Google Chrome", "Terminal"])
    }

    @Test func aRelaunchedApplicationIsListedOnce() {
        var state = ContextState()
        _ = state.begin(at: at(0))
        let relaunched = ApplicationContext(bundleID: chrome.bundleID, name: chrome.name, processID: 999, category: chrome.category)
        state.play([.applicationActivated(chrome), .applicationActivated(code), .applicationActivated(relaunched), .applicationActivated(terminal)], from: 1)
        let recent = state.snapshot(at: at(10), presence: .observing).recentApplications
        #expect(recent.map(\.processID) == [999, 101])
    }

    @Test func launchesAndQuitsAreRecorded() {
        var state = ContextState()
        _ = state.begin(at: at(0))
        state.play([.applicationActivated(code), .applicationActivated(chrome)], from: 1)
        let events = state.play([.applicationLaunched(terminal), .applicationTerminated(code)], from: 5)
        #expect(events.map(\.kind) == [.applicationLaunched(terminal), .applicationQuit(code)])
        #expect(state.previousApplication == nil)
    }

    // MARK: Windows

    @Test func windowChangesAreFollowed() {
        var state = ContextState()
        _ = state.begin(at: at(0))
        _ = state.apply(.applicationActivated(code), at: at(1))
        let first = WindowContext(title: "YumiApp.swift", processID: 101)
        let second = WindowContext(title: "ContextEngine.swift", processID: 101)

        #expect(state.apply(.windowFocused(first), at: at(2)).map(\.kind) == [.windowChanged(from: nil, to: first)])
        #expect(state.apply(.windowFocused(second), at: at(3)).map(\.kind) == [.windowChanged(from: first, to: second)])
        #expect(state.apply(.windowFocused(nil), at: at(4)).map(\.kind) == [.windowChanged(from: second, to: nil)])
        #expect(state.windowSince == nil)
    }

    @Test func aLateWindowOfAnotherApplicationIsIgnored() {
        var state = ContextState()
        _ = state.begin(at: at(0))
        state.play([.applicationActivated(code), .applicationActivated(chrome)], from: 1)
        let stale = WindowContext(title: "YumiApp.swift", processID: code.processID)
        #expect(state.apply(.windowFocused(stale), at: at(5)).isEmpty)
        #expect(state.window == nil)
    }

    @Test func changingApplicationForgetsTheWindowOfThePreviousOne() {
        var state = ContextState()
        _ = state.begin(at: at(0))
        state.play([.applicationActivated(code), .windowFocused(WindowContext(title: "a", processID: 101)),
                    .applicationActivated(chrome)], from: 1)
        #expect(state.window == nil)
    }

    @Test func noWindowWithoutAnApplication() {
        var state = ContextState()
        _ = state.begin(at: at(0))
        #expect(state.apply(.windowFocused(WindowContext(title: "x", processID: 1)), at: at(1)).isEmpty)
    }

    @Test func losingTheAccessibilityPermissionForgetsTheWindow() {
        var state = ContextState()
        _ = state.begin(at: at(0))
        state.play([.accessibility(.granted), .applicationActivated(code), .windowFocused(WindowContext(title: "a", processID: 101))], from: 1)
        let events = state.apply(.accessibility(.notGranted), at: at(9))
        #expect(events.map(\.kind) == [.permissionChanged(accessibility: .notGranted)])
        #expect(state.window == nil)
        #expect(state.apply(.accessibility(.notGranted), at: at(10)).isEmpty)
    }

    // MARK: Deduplication

    @Test func theSameApplicationTwiceIsOneChange() {
        var state = ContextState()
        _ = state.begin(at: at(0))
        let events = state.play([.applicationActivated(code), .applicationActivated(code), .applicationActivated(code)], from: 1)
        #expect(kinds(events) == ["applicationChanged"])
        #expect(state.applicationSince == at(1))
    }

    @Test func theSameWindowTwiceIsOneChange() {
        var state = ContextState()
        _ = state.begin(at: at(0))
        let window = WindowContext(title: "a", processID: 101)
        let events = state.play([.applicationActivated(code), .windowFocused(window), .windowFocused(window), .windowFocused(nil), .windowFocused(nil)], from: 1)
        #expect(kinds(events) == ["applicationChanged", "windowChanged", "windowChanged"])
    }

    @Test func aRepeatedSystemSignalIsRecordedOnce() {
        var state = ContextState()
        _ = state.begin(at: at(0))
        let events = state.play([.system(.didWake), .system(.didWake), .system(.screensDidWake)], from: 1)
        #expect(events.map(\.kind) == [.system(.didWake), .system(.screensDidWake)])
    }

    @Test func anUnchangedFacetIsNotAnEvent() {
        var state = ContextState()
        let facet = ContextFacet(kind: .git, values: ["branch": "main"], date: t0)
        #expect(state.apply(.facet(facet), at: at(1)).map(\.kind) == [.facetChanged(.git)])
        var later = facet
        later.date = at(5)
        #expect(state.apply(.facet(later), at: at(5)).isEmpty)
        later.values["branch"] = "yumi/contexte"
        #expect(state.apply(.facet(later), at: at(6)).count == 1)
        #expect(state.snapshot(at: at(7), presence: .observing).facets["git"]?.values["branch"] == "yumi/contexte")
    }

    // MARK: Session

    @Test func beginningAndEndingTheEngineOpenAndCloseASession() {
        var state = ContextState()
        #expect(state.begin(at: at(0)).map(\.kind) == [.sessionStarted])
        #expect(state.begin(at: at(1)).isEmpty)
        #expect(state.end(at: at(90)).map(\.kind) == [.sessionEnded(duration: 90)])
        #expect(state.end(at: at(91)).isEmpty)
        #expect(!state.isPresent)
    }

    @Test func sleepEndsTheSessionAndWakeStartsANewOne() {
        var state = ContextState()
        _ = state.begin(at: at(0))
        _ = state.apply(.applicationActivated(code), at: at(5))
        let leaving = state.play([.system(.willSleep), .system(.screensDidSleep)], from: 600)
        #expect(leaving.map(\.kind) == [.system(.willSleep), .sessionEnded(duration: 600), .system(.screensDidSleep)])
        #expect(state.snapshot(at: at(700), presence: .idle).sessionDuration == nil)

        let back = state.apply(.system(.didWake), at: at(4000))
        #expect(back.map(\.kind) == [.system(.didWake), .sessionStarted])
        // Time asleep is not time spent in front of the application.
        #expect(state.applicationSince == at(4000))
        #expect(state.snapshot(at: at(4030), presence: .observing).sessionDuration == 30)
    }

    @Test func aLockedScreenKeepsThePersonAwayUntilUnlocked() {
        var state = ContextState()
        _ = state.begin(at: at(0))
        let events = state.play([.system(.screenLocked), .system(.screensDidSleep), .system(.screensDidWake),
                                 .applicationActivated(code)], from: 10)
        #expect(!events.contains { $0.kind == .sessionStarted })
        #expect(!state.isPresent)
        let unlocked = state.apply(.system(.screenUnlocked), at: at(100))
        #expect(unlocked.map(\.kind) == [.system(.screenUnlocked), .sessionStarted])
    }

    @Test func anApplicationBroughtForwardMeansSomeoneIsThere() {
        var state = ContextState()
        _ = state.begin(at: at(0))
        _ = state.apply(.system(.screensDidSleep), at: at(10))
        let events = state.apply(.applicationActivated(code), at: at(20))
        #expect(kinds(events) == ["sessionStarted", "applicationChanged"])
    }

    @Test func fastUserSwitchingIsADeparture() {
        var state = ContextState()
        _ = state.begin(at: at(0))
        #expect(kinds(state.apply(.system(.sessionResigned), at: at(30))) == ["system", "sessionEnded"])
        #expect(state.apply(.system(.didWake), at: at(40)).map(\.kind) == [.system(.didWake)])
        #expect(kinds(state.apply(.system(.sessionResumed), at: at(50))) == ["system", "sessionStarted"])
    }

    // MARK: Activity

    @Test func theActivityIsTheShareOfRecentTimeByCategory() {
        var state = ContextState()
        _ = state.begin(at: at(0))
        // 6 minutes in the editor, 3 in the terminal, 1 in the browser, then the editor again.
        _ = state.apply(.applicationActivated(code), at: at(0))
        _ = state.apply(.applicationActivated(terminal), at: at(360))
        _ = state.apply(.applicationActivated(chrome), at: at(540))
        _ = state.apply(.applicationActivated(code), at: at(600))

        let activity = state.snapshot(at: at(600), presence: .observing).activity
        #expect(activity.map(\.label) == ["Developer tools", "Utilities", "Productivity"])
        #expect(activity.map(\.seconds) == [360, 180, 60])
        #expect(abs(activity[0].share - 0.6) < 0.0001)
    }

    @Test func timeAwayIsNotCountedInTheActivity() {
        var state = ContextState()
        _ = state.begin(at: at(0))
        _ = state.apply(.applicationActivated(code), at: at(0))
        _ = state.apply(.system(.willSleep), at: at(60))
        _ = state.apply(.system(.didWake), at: at(500))
        let activity = state.snapshot(at: at(560), presence: .observing).activity
        #expect(activity.map(\.seconds) == [120])
    }

    @Test func theActivityOnlyLooksAtTheLastMinutes() {
        var limits = ContextState.Limits()
        limits.activityWindow = 100
        var state = ContextState(limits: limits)
        _ = state.begin(at: at(0))
        _ = state.apply(.applicationActivated(terminal), at: at(0))
        _ = state.apply(.applicationActivated(code), at: at(1000))
        let activity = state.snapshot(at: at(1050), presence: .observing).activity
        #expect(activity.map(\.label) == ["Developer tools", "Utilities"])
        #expect(activity.map(\.seconds) == [50, 50])
    }

    @Test func anApplicationWithoutCategoryCountsAsOther() {
        let bare = ApplicationContext(bundleID: "", name: "tool", processID: 7)
        var state = ContextState()
        _ = state.begin(at: at(0))
        _ = state.apply(.applicationActivated(bare), at: at(0))
        let activity = state.snapshot(at: at(30), presence: .observing).activity
        #expect(activity.first?.category == nil)
        #expect(activity.first?.label == "Other")
        #expect(bare.identity == "tool")
    }
}
