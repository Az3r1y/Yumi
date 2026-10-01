import Foundation

/// Pure 4-state FSM for island open/close logic.
/// No AppKit / AppState dependencies — communicates via `onTransition`.
/// (This file is compiled as is into the unit tests, with the module contract.)
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

// MARK: - The folded island: what is live

/// Pure rules of the folded island (Contracts/ModuleTypes.swift): which module it shows on
/// the right of the notch, and how wide it may grow for it. No view, no state.
enum FoldedIsland {

    /// The live module with the highest priority. With several at that priority, the one
    /// already shown stays, so that the island does not flicker between them; otherwise the
    /// first in the user's order. nil when nothing is live: the island shows nothing.
    static func live(in modules: [ModuleSnapshot], shown: String?) -> ModuleSnapshot? {
        guard let top = modules.compactMap({ $0.live?.priority }).max() else { return nil }
        let best = modules.filter { $0.live?.priority == top }
        return best.first { $0.id == shown } ?? best.first
    }

    /// True when the change of text is a new thing to read (the next track) rather than the
    /// same thing ticking (a countdown): only the first one slides.
    static func isNewLine(_ old: String, _ new: String) -> Bool {
        skeleton(old) != skeleton(new)
    }

    /// The text without what ticks: every digit reads the same.
    static func skeleton(_ text: String) -> String {
        String(text.map { $0.isNumber ? "0" : $0 })
    }

    /// Width of one ear (the island sticks out by this much on each side of the notch): wide
    /// enough for `content`, never narrower than `minimum`, and never so wide that the folded
    /// island would be wider than the open one.
    static func ear(content: Double, minimum: Double, notchWidth: Double, openWidth: Double) -> Double {
        let widest = max(minimum, (openWidth - notchWidth) / 2)
        return min(max(minimum, content), widest)
    }
}

// MARK: - The chat answering live

/// Pure rules of the talk view while an answer is being made (Contracts/ChatLive.swift).
enum LiveChat {

    /// The conversation follows its last line only while the reader is at the bottom:
    /// someone who scrolled up to read is left where they are.
    static func followsBottom(offset: Double, viewport: Double, content: Double, slack: Double = 12) -> Bool {
        content <= viewport || offset + viewport >= content - slack
    }

    /// Kinds of action (`ChatActivity.Kind` raw values) that leave something behind.
    static let changes: Set<String> = ["writing", "editing"]

    /// Yumi celebrates an answer that created or modified something, and only if it worked.
    static func celebrates(done: [(kind: String, succeeded: Bool)]) -> Bool {
        done.contains { changes.contains($0.kind) && $0.succeeded }
    }
}
