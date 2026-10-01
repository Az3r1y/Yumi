import Foundation

/// Entry point to the engine for code that cannot await: socket threads, C callbacks.
///
/// `post` returns at once and keeps the arrival order: one task drains the queue into
/// the engine, so two hooks fired a millisecond apart reach the subscribers in the order
/// they were received. A batch is delivered whole, never interleaved with another one.
final class EventIngress: Sendable {
    private let continuation: AsyncStream<[YumiEvent]>.Continuation

    init(engine: EventEngine) {
        let (stream, continuation) = AsyncStream.makeStream(of: [YumiEvent].self,
                                                            bufferingPolicy: .unbounded)
        self.continuation = continuation
        Task {
            for await batch in stream {
                for event in batch { await engine.publish(event) }
            }
        }
    }

    func post(_ events: [YumiEvent]) {
        guard !events.isEmpty else { return }
        continuation.yield(events)
    }

    func post(_ event: YumiEvent) {
        continuation.yield([event])
    }

    /// Stops forwarding. Events already queued are still delivered.
    func finish() {
        continuation.finish()
    }
}
