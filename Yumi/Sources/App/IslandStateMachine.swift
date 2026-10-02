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

    /// home → petit delay (seconds): the user's setting.
    var homeToPetitDelay: TimeInterval = 15 {
        didSet {
            // A countdown already running starts again with the new delay
            guard homeToPetitDelay != oldValue, homeCollapseWork != nil else { return }
            scheduleHomeCollapse()
        }
    }
    /// false when the user chose "never": the open island only folds when asked to.
    var foldsByItself = true {
        didSet {
            guard foldsByItself != oldValue, state == .home else { return }
            if !foldsByItself {
                homeCollapseWork?.cancel()
                homeCollapseWork = nil
            } else if !hovered && !pinned {
                scheduleHomeCollapse()
            }
        }
    }
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

    /// The user quits: the goodbye plays like the launch, and nothing interrupts it.
    func leave() {
        cancelTimers()
        transition(to: .greeting)
    }

    /// The launch sequence reached its end (about 4.5 s).
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
        homeCollapseWork = nil
        guard foldsByItself else { return }
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

    /// The second activity, shown in the bubble that detaches from the folded island: the
    /// live module with the highest priority once the main one is set aside.
    static func second(in modules: [ModuleSnapshot], after main: String?) -> ModuleSnapshot? {
        guard let main else { return nil }
        return live(in: modules.filter { $0.id != main }, shown: nil)
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

// MARK: - Asking the first name

/// Yumi asks the person's first name once, after the launch, and does not insist
/// (design/yumi/voix.md): passed over, he asks again some days later.
enum FirstName {
    /// How long he waits before asking again.
    static let patience: TimeInterval = 3 * 24 * 3600

    static func shouldAsk(name: String?, lastAsked: Date?, now: Date) -> Bool {
        guard clean(name ?? "") == nil else { return false }
        guard let lastAsked else { return true }
        return now.timeIntervalSince(lastAsked) >= patience
    }

    /// What was typed, as a first name: trimmed, one line, not endless. nil when empty.
    static func clean(_ typed: String) -> String? {
        let line = typed.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let name = line.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : String(name.prefix(40))
    }
}

// MARK: - Yumi's voice

/// How Yumi writes numbers and durations (design/yumi/voix.md): small numbers in letters
/// inside a sentence, figures only for values read at a glance.
enum Voice {
    /// "douze" up to ninety-nine, figures beyond.
    static func number(_ n: Int) -> String {
        guard (0...99).contains(n) else { return String(n) }
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.numberStyle = .spellOut
        return formatter.string(from: NSNumber(value: n)) ?? String(n)
    }

    /// "une" before a feminine noun: "une minute", "vingt-et-une minutes".
    private static func feminine(_ n: Int) -> String {
        let text = number(n)
        return text == "un" || text.hasSuffix(" un") || text.hasSuffix("-un") ? text + "e" : text
    }

    /// "moins d'une minute", "une minute", "douze minutes", "une heure", "deux heures dix".
    static func duration(_ seconds: TimeInterval) -> String {
        let minutes = Int(max(0, seconds) / 60)
        if minutes < 1 { return "moins d'une minute" }
        if minutes < 60 { return "\(feminine(minutes)) \(minutes == 1 ? "minute" : "minutes")" }
        let hours = minutes / 60, rest = minutes % 60
        let head = "\(feminine(hours)) \(hours == 1 ? "heure" : "heures")"
        return rest == 0 ? head : "\(head) \(number(rest))"
    }

    /// "un fichier touché", "trois fichiers touchés"; nil for none.
    static func files(_ count: Int) -> String? {
        guard count > 0 else { return nil }
        return count == 1 ? "un fichier touché" : "\(number(count)) fichiers touchés"
    }

    /// A sentence starts with a capital.
    static func sentence(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
    }

    /// The first name, when it is worth saying: he uses it rarely.
    static func goodbye(name: String?) -> String {
        guard let name = FirstName.clean(name ?? "") else { return "À tout à l'heure" }
        return "À tout à l'heure, \(name)"
    }
}
