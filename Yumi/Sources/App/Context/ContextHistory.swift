import Foundation

/// The recent events, in memory only. Bounded in number and in age, so that a Mac left on
/// for days keeps a small, constant footprint. Nothing is ever written to disk.
struct ContextHistory: Equatable, Sendable {
    /// Most events kept.
    let capacity: Int
    /// Oldest event kept, in seconds.
    let maxAge: TimeInterval

    private(set) var events: [ContextEvent] = []

    init(capacity: Int = 300, maxAge: TimeInterval = 4 * 3600) {
        self.capacity = max(1, capacity)
        self.maxAge = maxAge
    }

    mutating func append(_ event: ContextEvent) {
        events.append(event)
        prune(now: event.date)
    }

    /// Drops what is too old, then what is beyond the capacity, oldest first.
    mutating func prune(now: Date) {
        let limit = now.addingTimeInterval(-maxAge)
        if let firstKept = events.firstIndex(where: { $0.date >= limit }) {
            if firstKept > 0 { events.removeFirst(firstKept) }
        } else {
            events.removeAll()
        }
        if events.count > capacity { events.removeFirst(events.count - capacity) }
    }

    mutating func removeAll() { events.removeAll() }

    /// The last `limit` events, most recent first.
    func recent(_ limit: Int) -> [ContextEvent] {
        Array(events.suffix(limit).reversed())
    }

    /// Applications brought to the front, most recent first, each once, without `current`.
    func recentApplications(excluding current: ApplicationContext?, limit: Int) -> [ApplicationContext] {
        var seen: Set<String> = current.map { [$0.identity] } ?? []
        var result: [ApplicationContext] = []
        for event in events.reversed() {
            guard case .applicationChanged(let from, let to) = event.kind else { continue }
            for app in [to, from].compactMap({ $0 }) where !seen.contains(app.identity) {
                seen.insert(app.identity)
                result.append(app)
                if result.count == limit { return result }
            }
        }
        return result
    }

    /// Seconds spent with each application at the front since `start`, while a session was open.
    /// `current` is the front application now, at the front since `currentSince`, still counting
    /// until `now`; nil while the person is away.
    func timeSpent(since start: Date, now: Date,
                   current: ApplicationContext?, currentSince: Date?) -> [String: (app: ApplicationContext, seconds: TimeInterval)] {
        var totals: [String: (app: ApplicationContext, seconds: TimeInterval)] = [:]
        var front: ApplicationContext?
        var since: Date?
        var present = true

        func close(at date: Date) {
            guard let app = front, let from = since, present else { return }
            let seconds = date.timeIntervalSince(max(from, start))
            guard seconds > 0 else { return }
            totals[app.identity, default: (app, 0)].seconds += seconds
        }

        for event in events {
            switch event.kind {
            case .applicationChanged(_, let to):
                close(at: event.date)
                front = to
                since = event.date
            case .sessionEnded:
                close(at: event.date)
                present = false
            case .sessionStarted:
                present = true
                since = event.date
            default:
                break
            }
        }
        guard let current else { return totals }
        if current.isSameApplication(as: front) {
            close(at: now)
        } else if let currentSince {
            // Its arrival is older than the history: count from when the engine says it came.
            let seconds = now.timeIntervalSince(max(currentSince, start))
            if seconds > 0 { totals[current.identity, default: (current, 0)].seconds += seconds }
        }
        return totals
    }
}
