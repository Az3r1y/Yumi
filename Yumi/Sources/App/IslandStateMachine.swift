import Foundation

/// Pure 4-state FSM for island open/close logic.
/// No AppKit / AppState dependencies — communicates via `onTransition`.
@MainActor
final class IslandStateMachine {

    enum State: Equatable {
        case hidden   // island invisible (notch size)
        case petit    // compact island (notch + ears)
        case home     // open island
        case greeting // launch sequence: drop, greeting, fold
    }

    private(set) var state: State = .hidden

    /// Fired on every transition: (from, to)
    var onTransition: ((State, State) -> Void)?

    /// home → petit delay (seconds). Override for debug.
    var homeToPetitDelay: TimeInterval = 15
    /// petit → hidden delay (seconds). Override for debug.
    var petitToHiddenDelay: TimeInterval = 60
    /// greeting → petit if `greetComplete()` never comes. The launch lasts about 5 s.
    var greetingTimeout: TimeInterval = 8

    /// An alert waits for an answer: the open island never closes by itself.
    var pinned = false {
        didSet {
            guard pinned != oldValue, state == .home else { return }
            if pinned {
                homeCollapseWork?.cancel()
                homeCollapseWork = nil
            } else if !hovered {
                scheduleHomeCollapse()
            }
        }
    }

    /// The pointer is on the island. Kept here so that every way of reaching a state
    /// (click, alert, end of the launch) starts the right timer.
    private var hovered = false

    private var petitHideWork: DispatchWorkItem?
    private var homeCollapseWork: DispatchWorkItem?
    private var greetTimeoutWork: DispatchWorkItem?

    // MARK: – Inputs

    /// App launched or debug "launch greeting"
    func launch() {
        cancelTimers()
        transition(to: .greeting)
        scheduleGreetTimeout()
    }

    /// Mouse entered the island
    func mouseEntered() {
        hovered = true
        switch state {
        case .hidden:
            cancelTimers()
            transition(to: .petit)
        case .petit:
            petitHideWork?.cancel()
            petitHideWork = nil
        case .home:
            homeCollapseWork?.cancel()
            homeCollapseWork = nil
        case .greeting:
            // The launch plays to its end whatever the pointer does
            break
        }
    }

    /// Mouse left the island
    func mouseLeft() {
        hovered = false
        switch state {
        case .hidden, .greeting:
            break
        case .petit:
            schedulePetitHide()
        case .home:
            if !pinned { scheduleHomeCollapse() }
        }
    }

    /// Compact island clicked
    func click() {
        guard state == .petit else { return }
        enterHome()
    }

    /// The island opens by itself: an alert, the shortcut, a file dragged over it.
    func open() {
        guard state != .home else { return }
        enterHome()
    }

    /// The open island folds back now: Escape, an "OK" button.
    func collapse() {
        guard state == .home else { return }
        enterPetit()
    }

    /// The launch sequence reached its end (about 4.9 s).
    func greetComplete() {
        guard state == .greeting else { return }
        enterPetit()
    }

    /// Non-alert work event: show compact from hidden (HookServer reveal)
    func reveal() {
        guard state == .hidden else { return }
        enterPetit()
    }

    // MARK: – Entering a state

    private func enterHome() {
        cancelTimers()
        transition(to: .home)
        if !hovered && !pinned { scheduleHomeCollapse() }
    }

    private func enterPetit() {
        cancelTimers()
        transition(to: .petit)
        if !hovered { schedulePetitHide() }
    }

    // MARK: – Timers

    private func schedulePetitHide() {
        petitHideWork?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.state == .petit else { return }
            self.transition(to: .hidden)
        }
        petitHideWork = item
        DispatchQueue.main.asyncAfter(deadline: .now() + petitToHiddenDelay, execute: item)
    }

    private func scheduleHomeCollapse() {
        homeCollapseWork?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.state == .home, !self.pinned else { return }
            self.enterPetit()
        }
        homeCollapseWork = item
        DispatchQueue.main.asyncAfter(deadline: .now() + homeToPetitDelay, execute: item)
    }

    private func scheduleGreetTimeout() {
        greetTimeoutWork?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.state == .greeting else { return }
            self.enterPetit()
        }
        greetTimeoutWork = item
        DispatchQueue.main.asyncAfter(deadline: .now() + greetingTimeout, execute: item)
    }

    func cancelTimers() {
        petitHideWork?.cancel();    petitHideWork = nil
        homeCollapseWork?.cancel(); homeCollapseWork = nil
        greetTimeoutWork?.cancel(); greetTimeoutWork = nil
    }

    private func transition(to new: State) {
        guard new != state else { return }
        let old = state
        state = new
        onTransition?(old, new)
    }

}
