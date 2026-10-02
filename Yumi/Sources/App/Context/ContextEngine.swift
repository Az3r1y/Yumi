import Foundation
import Observation

/// The source of truth about what the person is doing on the Mac.
///
/// Providers report observations, `ContextState` turns them into events, and the engine
/// publishes both the events and the new snapshot (`ContextMessage`) to every subscriber. It
/// only looks: it never acts, never stores anything on disk and never sends anything away.
///
/// Costs nothing at rest: no timer runs, except a single one-shot after an application change
/// to let Yumi's presence go back from `contextChanged` to `observing`.
@MainActor
@Observable
final class ContextEngine {
    /// The latest snapshot. Observable, for SwiftUI.
    private(set) var snapshot: ContextSnapshot
    private(set) var isEnabled = false

    @ObservationIgnored private let providers: [ContextProvider]
    @ObservationIgnored private let clock: () -> Date
    @ObservationIgnored private let limits: ContextState.Limits
    @ObservationIgnored private let changeSettle: Duration
    @ObservationIgnored private var state: ContextState
    @ObservationIgnored private var presence = ContextPresence.idle
    @ObservationIgnored private var settleTask: Task<Void, Never>?
    @ObservationIgnored private var subscribers: [UUID: AsyncStream<ContextMessage>.Continuation] = [:]

    /// - Parameters:
    ///   - changeSettle: how long Yumi's presence stays `contextChanged` after an application change.
    ///   - clock: injected by the tests.
    init(providers: [ContextProvider],
         limits: ContextState.Limits = .init(),
         changeSettle: Duration = .milliseconds(1500),
         clock: @escaping () -> Date = Date.init) {
        self.providers = providers
        self.limits = limits
        self.changeSettle = changeSettle
        self.clock = clock
        state = ContextState(limits: limits)
        snapshot = .disabled(at: clock())
    }

    // MARK: - Subscribing

    /// Every message from now on. The stream ends when the subscriber stops iterating.
    func messages() -> AsyncStream<ContextMessage> {
        let id = UUID()
        let (stream, continuation) = AsyncStream.makeStream(of: ContextMessage.self, bufferingPolicy: .bufferingNewest(64))
        subscribers[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor in self?.subscribers[id] = nil }
        }
        return stream
    }

    // MARK: - Turning on and off

    /// Starts or stops watching. Turning it off forgets everything that was observed.
    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        let now = clock()
        if enabled {
            state = ContextState(limits: limits)
            presence = .observing
            publish(state.begin(at: now), at: now)
            for provider in providers {
                provider.start { [weak self] observation in self?.receive(observation) }
            }
        } else {
            for provider in providers { provider.stop() }
            settleTask?.cancel()
            settleTask = nil
            let events = state.end(at: now)
            for event in events { send(.event(event)) }
            state = ContextState(limits: limits)
            presence = .idle
            snapshot = .disabled(at: now)
            send(.contextUpdated(snapshot))
        }
    }

    // MARK: - Observations

    /// What a provider saw. Public so that tests and future providers can feed the engine.
    func receive(_ observation: ContextObservation) {
        guard isEnabled else { return }
        let now = clock()
        let applicationBefore = state.application
        let events = state.apply(observation, at: now)
        guard !events.isEmpty else { return }

        if !state.isPresent {
            presence = .idle
        } else if events.contains(where: { if case .applicationChanged(.some, _) = $0.kind { true } else { false } }) {
            // The very first application of a session is not a change of context.
            presence = .contextChanged
            settle()
        } else if presence == .idle {
            presence = .observing
        }
        publish(events, at: now)

        if !state.application.isSame(as: applicationBefore) {
            for provider in providers { provider.applicationDidChange(to: state.application) }
        }
    }

    // MARK: - Private

    private func settle() {
        settleTask?.cancel()
        settleTask = Task { [weak self, changeSettle] in
            try? await Task.sleep(for: changeSettle)
            guard !Task.isCancelled, let self, self.presence == .contextChanged else { return }
            self.presence = self.state.isPresent ? .observing : .idle
            self.refreshSnapshot(at: self.clock())
        }
    }

    private func publish(_ events: [ContextEvent], at now: Date) {
        for event in events { send(.event(event)) }
        refreshSnapshot(at: now)
    }

    private func refreshSnapshot(at now: Date) {
        snapshot = state.snapshot(at: now, presence: presence)
        send(.contextUpdated(snapshot))
    }

    private func send(_ message: ContextMessage) {
        for continuation in subscribers.values { continuation.yield(message) }
    }
}

private extension Optional where Wrapped == ApplicationContext {
    func isSame(as other: ApplicationContext?) -> Bool {
        switch (self, other) {
        case (nil, nil): true
        case (let a?, _): a.isSameApplication(as: other)
        default: false
        }
    }
}
