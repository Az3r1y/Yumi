import Testing
import Foundation

// Core/ is compiled straight into this bundle (see project.yml): it has no dependency
// on the rest of the app, so these tests run without launching Yumi.

@Suite struct EventEngineTests {

    @Test func publishesToASingleSubscriber() async {
        let engine = EventEngine()
        let stream = await engine.subscribe()

        let collector = Task {
            var events: [YumiEvent] = []
            for await event in stream { events.append(event) }
            return events
        }

        await engine.publish(.sessionStarted(SessionID("s1"), Agent(name: "A", kind: .coding), title: "T"))
        await engine.shutdown()

        let events = await collector.value
        #expect(events.count == 1)
        if case .sessionStarted(let id, _, _) = events.first {
            #expect(id == SessionID("s1"))
        } else {
            Issue.record("Expected a sessionStarted event")
        }
    }

    @Test func deliversToMultipleSubscribers() async {
        let engine = EventEngine()
        let streamA = await engine.subscribe()
        let streamB = await engine.subscribe()

        func collect(_ stream: AsyncStream<YumiEvent>) -> Task<[YumiEvent], Never> {
            Task {
                var events: [YumiEvent] = []
                for await event in stream { events.append(event) }
                return events
            }
        }
        let collectorA = collect(streamA)
        let collectorB = collect(streamB)

        await engine.publish(.taskCompleted(SessionID("s1")))
        await engine.shutdown()

        let a = await collectorA.value
        let b = await collectorB.value
        #expect(a.count == 1)
        #expect(b.count == 1)
    }

    @Test func cancelledSubscriptionStopsReceiving() async {
        let engine = EventEngine()
        let streamA = await engine.subscribe()
        let streamB = await engine.subscribe()

        let collectorA = Task {
            var events: [YumiEvent] = []
            for await event in streamA { events.append(event) }
            return events
        }
        let collectorB = Task {
            var events: [YumiEvent] = []
            for await event in streamB { events.append(event) }
            return events
        }

        // A unsubscribes by cancelling its consuming task.
        collectorA.cancel()
        await waitFor(timeout: 2) { await engine.subscriberCount() == 1 }

        await engine.publish(.taskCompleted(SessionID("s1")))
        await engine.shutdown()

        let a = await collectorA.value
        let b = await collectorB.value
        #expect(a.isEmpty)
        #expect(b.count == 1)
    }

    @Test func publishAfterShutdownIsIgnored() async {
        let engine = EventEngine()
        let stream = await engine.subscribe()
        await engine.shutdown()

        await engine.publish(.taskCompleted(SessionID("s1")))  // must not crash

        var received: [YumiEvent] = []
        for await event in stream { received.append(event) }
        #expect(received.isEmpty)  // the stream ended at shutdown
    }
}

// MARK: - Helpers

/// Polls a condition until it holds or the timeout expires.
func waitFor(timeout seconds: Double, _ condition: () async -> Bool) async {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
        if await condition() { return }
        try? await Task.sleep(for: .milliseconds(20))
    }
    Issue.record("Condition not met within \(seconds)s")
}
