import Testing
import Foundation

@Suite struct EventIngressTests {

    @Test func keepsTheOrderOfArrival() async {
        let engine = EventEngine()
        let stream = await engine.subscribe()
        let ingress = EventIngress(engine: engine)
        let id = SessionID("s1")

        let collector = Task {
            var notes: [String] = []
            for await event in stream {
                if case .activityNoted(_, let note) = event { notes.append(note) }
                if notes.count == 200 { break }
            }
            return notes
        }

        // Posted from a thread that cannot await, the way the socket threads do.
        let poster = Thread {
            for index in 0..<100 {
                ingress.post([.activityNoted(id, "\(index)a"), .activityNoted(id, "\(index)b")])
            }
        }
        poster.start()

        let notes = await collector.value
        let expected = (0..<100).flatMap { ["\($0)a", "\($0)b"] }
        #expect(notes == expected)
        await engine.shutdown()
    }

    @Test func anEmptyBatchIsIgnored() async {
        let engine = EventEngine()
        let stream = await engine.subscribe()
        let ingress = EventIngress(engine: engine)

        ingress.post([])
        ingress.post(.taskCompleted(SessionID("s1")))

        var iterator = stream.makeAsyncIterator()
        let first = await iterator.next()
        #expect(first == .taskCompleted(SessionID("s1")))
        await engine.shutdown()
    }
}
