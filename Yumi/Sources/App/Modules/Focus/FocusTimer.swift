import Foundation

/// A local focus timer: rounds of work separated by short breaks. Pure logic, the clock is passed in.
struct FocusTimer: Equatable, Sendable {
    struct Plan: Equatable, Sendable {
        var focus: TimeInterval = 25 * 60
        var rest: TimeInterval = 5 * 60
        var rounds = 4
    }

    enum Phase: Equatable, Sendable { case focus, rest }

    enum State: Equatable, Sendable {
        case idle
        case running(Phase, round: Int, endsAt: Date)
        case paused(Phase, round: Int, remaining: TimeInterval)
        /// Every round is done.
        case finished(at: Date)
    }

    var plan = Plan()
    private(set) var state: State = .idle

    var isRunning: Bool {
        if case .running = state { return true }
        return false
    }

    mutating func start(now: Date) {
        state = .running(.focus, round: 1, endsAt: now.addingTimeInterval(plan.focus))
    }

    mutating func pause(now: Date) {
        guard case .running(let phase, let round, let endsAt) = state else { return }
        state = .paused(phase, round: round, remaining: max(0, endsAt.timeIntervalSince(now)))
    }

    mutating func resume(now: Date) {
        guard case .paused(let phase, let round, let remaining) = state else { return }
        state = .running(phase, round: round, endsAt: now.addingTimeInterval(remaining))
    }

    mutating func stop() {
        state = .idle
    }

    /// Ends the current phase now.
    mutating func skip(now: Date) {
        guard case .running(let phase, let round, _) = state else { return }
        state = next(after: phase, round: round, from: now)
    }

    /// Moves to the phase `now` falls in. Returns true when the phase changed.
    /// Each phase starts when the previous one ended, so a late call does not shift the schedule.
    @discardableResult
    mutating func advance(now: Date) -> Bool {
        var changed = false
        while case .running(let phase, let round, let endsAt) = state, now >= endsAt {
            state = next(after: phase, round: round, from: endsAt)
            changed = true
        }
        return changed
    }

    func remaining(now: Date) -> TimeInterval? {
        switch state {
        case .running(_, _, let endsAt):  return max(0, endsAt.timeIntervalSince(now))
        case .paused(_, _, let remaining): return remaining
        case .idle, .finished:             return nil
        }
    }

    private func next(after phase: Phase, round: Int, from start: Date) -> State {
        switch phase {
        case .focus where round >= plan.rounds:
            return .finished(at: start)
        case .focus:
            return .running(.rest, round: round, endsAt: start.addingTimeInterval(plan.rest))
        case .rest:
            return .running(.focus, round: round + 1, endsAt: start.addingTimeInterval(plan.focus))
        }
    }
}

extension FocusTimer {
    /// Seconds a phase change keeps asking for attention.
    private static let attentionSpan: TimeInterval = 10

    func snapshot(now: Date) -> ModuleSnapshot {
        var snapshot = ModuleSnapshot(id: "focus", name: "Focus", colorHex: "#8B6CFF", status: "prêt",
                                      title: "Prêt à te concentrer ?",
                                      subtitle: "\(plan.rounds) sessions de \(FrenchText.minutes(plan.focus)), \(FrenchText.minutes(plan.rest)) de pause",
                                      primaryAction: "Démarrer", secondaryAction: nil)
        switch state {
        case .idle:
            break

        case .running(.focus, let round, let endsAt):
            let left = max(0, endsAt.timeIntervalSince(now))
            snapshot.status = FrenchText.countdown(left)
            snapshot.title = "Focus en cours"
            snapshot.subtitle = "Session \(round) sur \(plan.rounds), reste \(FrenchText.duration(left))"
            snapshot.primaryAction = "Pause"
            snapshot.secondaryAction = "Arrêter"
            // The first round was started by hand; the next ones start by themselves.
            snapshot.needsAttention = round > 1 && plan.focus - left < Self.attentionSpan

        case .running(.rest, let round, let endsAt):
            let left = max(0, endsAt.timeIntervalSince(now))
            snapshot.status = FrenchText.countdown(left)
            snapshot.title = "Pause, souffle un peu"
            snapshot.subtitle = "Session \(round + 1) sur \(plan.rounds) dans \(FrenchText.duration(left))"
            snapshot.primaryAction = "Passer"
            snapshot.secondaryAction = "Arrêter"
            snapshot.needsAttention = plan.rest - left < Self.attentionSpan

        case .paused(let phase, let round, let remaining):
            snapshot.status = "pause"
            snapshot.title = phase == .focus ? "Focus en pause" : "Pause suspendue"
            snapshot.subtitle = "Session \(round) sur \(plan.rounds), reste \(FrenchText.duration(remaining))"
            snapshot.primaryAction = "Reprendre"
            snapshot.secondaryAction = "Arrêter"

        case .finished(let at):
            snapshot.status = "fini"
            snapshot.title = "Bravo, \(FrenchText.count(plan.rounds, "session terminée", "sessions terminées"))"
            snapshot.subtitle = "Tu as bien mérité une vraie pause"
            snapshot.primaryAction = "Recommencer"
            snapshot.secondaryAction = "Fermer"
            snapshot.needsAttention = now.timeIntervalSince(at) < Self.attentionSpan
        }
        return snapshot
    }

    /// What a button does in the current state.
    mutating func perform(_ action: ModuleAction, now: Date) {
        switch (state, action) {
        case (.idle, .primary), (.finished, .primary): start(now: now)
        case (.running(.focus, _, _), .primary):       pause(now: now)
        case (.running(.rest, _, _), .primary):        skip(now: now)
        case (.paused, .primary):                      resume(now: now)
        case (.idle, .secondary):                      break
        case (_, .secondary):                          stop()
        }
    }
}
