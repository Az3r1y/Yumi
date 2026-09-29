import Foundation

/// Central hub of Yumi: connectors publish `YumiEvent`s, consumers receive
/// them as an `AsyncStream`.
///
/// Why an actor + AsyncStream: the actor makes publishing thread-safe with no
/// locks and no global state; the AsyncStream gives each consumer a simple
/// `for await` loop with unbounded buffering and clean cancellation (every
/// stream ends automatically on `shutdown()`). No Combine, no delegates, no
/// singleton — instances are created in the composition root and passed
/// around explicitly.
actor EventEngine {
    private var continuations: [UUID: AsyncStream<YumiEvent>.Continuation] = [:]
    private var finished = false

    /// Subscribes a consumer. Stop iterating (or cancel the consuming task)
    /// to unsubscribe; the stream also ends automatically on `shutdown()`.
    func subscribe() -> AsyncStream<YumiEvent> {
        let id = UUID()
        return AsyncStream(bufferingPolicy: .unbounded) { continuation in
            self.continuations[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeContinuation(id: id) }
            }
        }
    }

    /// Number of live subscriptions (tests and debugging).
    func subscriberCount() -> Int {
        continuations.count
    }

    /// Publishes an event to every current subscriber.
    func publish(_ event: YumiEvent) {
        guard !finished else { return }
        for continuation in continuations.values {
            continuation.yield(event)
        }
    }

    /// Ends every subscription. The engine cannot be reused after this.
    func shutdown() {
        finished = true
        for continuation in continuations.values {
            continuation.finish()
        }
        continuations.removeAll()
    }

    private func removeContinuation(id: UUID) {
        continuations[id] = nil
    }
}
