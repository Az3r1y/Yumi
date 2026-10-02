import Testing
import Foundation

private let t0 = Date(timeIntervalSince1970: 1_790_000_000)
private func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }
private func app(_ id: Int32) -> ApplicationContext {
    ApplicationContext(bundleID: "app.\(id)", name: "App \(id)", processID: id)
}
private func change(_ id: Int, to target: Int32, from origin: Int32? = nil, at seconds: TimeInterval) -> ContextEvent {
    ContextEvent(id: id, date: at(seconds), kind: .applicationChanged(from: origin.map(app), to: app(target)))
}

/// The history stays small whatever happens: bounded in number and in age.
@Suite struct ContextHistoryTests {
    @Test func theCapacityDropsTheOldestFirst() {
        var history = ContextHistory(capacity: 3, maxAge: 3600)
        for index in 1...5 { history.append(ContextEvent(id: index, date: at(Double(index)), kind: .system(.didWake))) }
        #expect(history.events.map(\.id) == [3, 4, 5])
    }

    @Test func eventsExpireWithAge() {
        var history = ContextHistory(capacity: 100, maxAge: 60)
        history.append(ContextEvent(id: 1, date: at(0), kind: .sessionStarted))
        history.append(ContextEvent(id: 2, date: at(30), kind: .system(.didWake)))
        history.append(ContextEvent(id: 3, date: at(70), kind: .system(.screensDidWake)))
        #expect(history.events.map(\.id) == [2, 3])
        history.prune(now: at(500))
        #expect(history.events.isEmpty)
    }

    @Test func recentIsMostRecentFirst() {
        var history = ContextHistory()
        for index in 1...4 { history.append(ContextEvent(id: index, date: at(Double(index)), kind: .sessionStarted)) }
        #expect(history.recent(2).map(\.id) == [4, 3])
        #expect(history.recent(10).count == 4)
    }

    @Test func recentApplicationsAreDistinctAndLimited() {
        var history = ContextHistory()
        history.append(change(1, to: 1, at: 1))
        history.append(change(2, to: 2, from: 1, at: 2))
        history.append(change(3, to: 3, from: 2, at: 3))
        history.append(change(4, to: 1, from: 3, at: 4))
        history.append(change(5, to: 4, from: 1, at: 5))
        #expect(history.recentApplications(excluding: app(4), limit: 10).map(\.processID) == [1, 3, 2])
        #expect(history.recentApplications(excluding: app(4), limit: 2).map(\.processID) == [1, 3])
    }

    @Test func theSnapshotForgetsWhatExpired() {
        var limits = ContextState.Limits()
        limits.historyMaxAge = 60
        limits.historyCapacity = 4
        var state = ContextState(limits: limits)
        _ = state.begin(at: at(0))
        _ = state.apply(.applicationActivated(app(1)), at: at(1))
        _ = state.apply(.applicationActivated(app(2)), at: at(2))
        // Long after: the engine still knows what is in front, but the history is gone.
        let snapshot = state.snapshot(at: at(1000), presence: .observing)
        #expect(snapshot.recentEvents.isEmpty)
        #expect(snapshot.recentApplications.isEmpty)
        #expect(snapshot.activeApplication == app(2))
        #expect(snapshot.previousApplication == app(1))
        // Its time in front still counts, from when it came.
        #expect(snapshot.mainActivity?.seconds == 900)
    }

    @Test func manyChangesNeverGrowTheHistoryBeyondItsCapacity() {
        var limits = ContextState.Limits()
        limits.historyCapacity = 50
        var state = ContextState(limits: limits)
        _ = state.begin(at: at(0))
        for index in 0..<1000 { _ = state.apply(.applicationActivated(app(Int32(index % 7))), at: at(Double(index))) }
        #expect(state.history.events.count == 50)
        #expect(state.snapshot(at: at(1000), presence: .observing).recentApplications.count == 6)
    }
}
