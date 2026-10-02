import Foundation

/// The focus timer as a module. It ticks once a second while a countdown is on screen
/// and keeps no timer at all the rest of the time.
@MainActor
final class FocusModule: YumiModule {
    let id = "focus"

    private var timer = FocusTimer()
    private var onChange: (@MainActor () -> Void)?
    private var ticking: Task<Void, Never>?

    var snapshot: ModuleSnapshot { timer.snapshot(now: Date()) }

    func start(onChange: @escaping @MainActor () -> Void) {
        self.onChange = onChange
        syncTicking()
    }

    /// Deselecting the module also ends the session in progress.
    func stop() {
        onChange = nil
        timer.stop()
        syncTicking()
    }

    /// True while a focus phase runs (not a break): Yumi does not speak then.
    var isFocusing: Bool {
        if case .running(.focus, _, _) = timer.state { return true }
        return false
    }

    /// Starts a five-minute break on its own, unless a session is already under way.
    func takeBreak() {
        guard case .idle = timer.state else { return }
        timer.startBreak(now: Date())
        syncTicking()
        onChange?()
    }

    func perform(_ action: ModuleAction) {
        timer.perform(action, now: Date())
        syncTicking()
    }

    private func syncTicking() {
        if timer.isRunning, onChange != nil {
            guard ticking == nil else { return }
            ticking = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(1), tolerance: .milliseconds(100))
                    guard !Task.isCancelled, let self else { return }
                    self.tick()
                }
            }
        } else {
            ticking?.cancel()
            ticking = nil
        }
    }

    private func tick() {
        let changed = timer.advance(now: Date())
        onChange?()
        syncTicking()
        // A phase change asks for attention for a few seconds; once every round is done nothing
        // ticks any more, so say again when that moment has passed.
        if changed, !timer.isRunning {
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(FocusTimer.attentionSpan + 1))
                self?.onChange?()
            }
        }
    }
}
