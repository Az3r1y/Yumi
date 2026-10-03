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

    /// The usual rounds, from the button.
    mutating func start(now: Date) {
        plan = Plan()
        state = .running(.focus, round: 1, endsAt: now.addingTimeInterval(plan.focus))
    }

    /// One work session of this length, asked for in words ("je bosse 45 minutes").
    mutating func start(now: Date, minutes: Int) {
        plan = Plan(focus: TimeInterval(minutes * 60), rest: Plan().rest, rounds: 1)
        state = .running(.focus, round: 1, endsAt: now.addingTimeInterval(plan.focus))
    }

    /// A break on its own, outside a session: when it ends the timer goes back to rest.
    mutating func startBreak(now: Date) {
        state = .running(.rest, round: 0, endsAt: now.addingTimeInterval(plan.rest))
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
        case .rest where round == 0:
            return .idle
        case .rest:
            return .running(.focus, round: round + 1, endsAt: start.addingTimeInterval(plan.focus))
        }
    }
}

extension FocusTimer {
    /// Seconds a phase change keeps asking for attention.
    static let attentionSpan: TimeInterval = 10

    func snapshot(now: Date) -> ModuleSnapshot {
        plainSnapshot(now: now).withSymbols("timer")
    }

    private func plainSnapshot(now: Date) -> ModuleSnapshot {
        var snapshot = ModuleSnapshot(id: "focus", name: "Focus", colorHex: "#8B6CFF", status: "prêt",
                                      title: "On s'y met ?",
                                      subtitle: "\(FrenchText.sentenceStart(FrenchText.spelledCount(plan.rounds, "session", "sessions", feminine: true))) de \(FrenchText.spokenMinutes(plan.focus)), \(FrenchText.spelled(Int(plan.rest / 60))) de pause.",
                                      primaryAction: "Démarrer", secondaryAction: nil)
        switch state {
        case .idle:
            break

        case .running(.focus, let round, let endsAt):
            let left = max(0, endsAt.timeIntervalSince(now))
            snapshot.status = FrenchText.countdown(left)
            snapshot.title = "Tu es dedans. Je me tais."
            snapshot.subtitle = "Session \(round) sur \(plan.rounds), encore \(FrenchText.duration(left))."
            snapshot.primaryAction = "Pause"
            snapshot.secondaryAction = "Arrêter"
            // The first round was started by hand; the next ones start by themselves.
            snapshot.needsAttention = round > 1 && plan.focus - left < Self.attentionSpan

        case .running(.rest, let round, let endsAt):
            let left = max(0, endsAt.timeIntervalSince(now))
            snapshot.status = FrenchText.countdown(left)
            snapshot.title = "Pause. Souffle un peu."
            snapshot.subtitle = round == 0 ? "Je te rappelle dans \(FrenchText.duration(left))." : "Session \(round + 1) sur \(plan.rounds) dans \(FrenchText.duration(left))."
            snapshot.primaryAction = "Passer"
            snapshot.secondaryAction = "Arrêter"
            snapshot.needsAttention = plan.rest - left < Self.attentionSpan

        case .paused(let phase, let round, let remaining):
            snapshot.status = "pause"
            snapshot.title = phase == .focus ? "En pause. Je garde ta place." : "La pause attend aussi."
            snapshot.subtitle = "Session \(round) sur \(plan.rounds), encore \(FrenchText.duration(remaining))."
            snapshot.primaryAction = "Reprendre"
            snapshot.secondaryAction = "Arrêter"

        case .finished(let at):
            snapshot.status = "fini"
            snapshot.title = "\(FrenchText.sentenceStart(FrenchText.spelledCount(plan.rounds, "session", "sessions", feminine: true))). C'est fait."
            snapshot.subtitle = "Va prendre l'air, je garde la maison."
            snapshot.primaryAction = "Recommencer"
            snapshot.secondaryAction = "Fermer"
            snapshot.needsAttention = now.timeIntervalSince(at) < Self.attentionSpan
        }
        snapshot.live = live(now: now)
        snapshot.progress = progress(now: now)
        return snapshot
    }

    /// How far the current phase is: time spent on the left, its length on the right.
    func progress(now: Date) -> ModuleProgress? {
        let phase: Phase
        switch state {
        case .running(let current, _, _), .paused(let current, _, _): phase = current
        case .idle, .finished: return nil
        }
        let total = phase == .focus ? plan.focus : plan.rest
        guard total > 0, let left = remaining(now: now) else { return nil }
        let spent = min(total, max(0, total - left))
        return ModuleProgress(fraction: spent / total, leading: FrenchText.trackTime(spent), trailing: FrenchText.trackTime(total))
    }

    /// The folded island shows the countdown while it runs, with the button of the moment.
    /// A paused timer stays visible, more quietly, so it can be resumed from there.
    func live(now: Date) -> ModuleLive? {
        let primary = ModuleAction.primary.rawValue
        switch state {
        case .idle, .finished:
            return nil
        case .running(.focus, _, let endsAt):
            return ModuleLive(text: FrenchText.countdown(endsAt.timeIntervalSince(now)),
                              priority: ModuleLivePriority.activity,
                              controls: [ModuleControl(id: primary, symbol: "pause.fill", label: "Pause")])
        case .running(.rest, _, let endsAt):
            return ModuleLive(text: "Pause \(FrenchText.countdown(endsAt.timeIntervalSince(now)))",
                              priority: ModuleLivePriority.activity,
                              controls: [ModuleControl(id: primary, symbol: "forward.fill", label: "Passer")])
        case .paused(_, _, let remaining):
            return ModuleLive(text: "\(FrenchText.countdown(remaining)) en pause",
                              priority: ModuleLivePriority.ambient,
                              controls: [ModuleControl(id: primary, symbol: "play.fill", label: "Reprendre")])
        }
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
