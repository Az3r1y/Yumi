import SwiftUI

/// The launch of the mock-up (`launch()` in design/yumi/maquette/reference.html), with the
/// same chronology: a drop swells under the notch, two sleeping eyes open in the dark and
/// look around, the island opens, the light comes on and the rim draws itself, he waves,
/// his name writes itself, his modules arrive, a wink, and everything folds back.
///
/// The island shapes come from `IslandModel.launchStage`; Yumi is the one `BotCanvasView`
/// of the island, driven through Contracts/CharacterCommands.swift.
@MainActor
final class IslandLaunch {
    private let model = IslandModel.shared
    private var timers: [DispatchWorkItem] = []
    private(set) var running = false

    /// Called when the sequence reaches its end (not when it is cancelled).
    var onComplete: (() -> Void)?

    /// Milliseconds, as in the mock-up.
    private func after(_ ms: Double, _ work: @escaping @MainActor () -> Void) {
        let item = DispatchWorkItem { MainActor.assumeIsolated { work() } }
        timers.append(item)
        DispatchQueue.main.asyncAfter(deadline: .now() + ms / 1000, execute: item)
    }

    private func sound(_ name: String) { SoundEngine.shared.play(name) }

    func start(modules: Int) {
        cancelTimers()
        running = true

        // The island is the notch again, the greeting layer is ready behind it
        model.forgetCommands()
        model.drawerOpen = false
        model.greeting = .init()
        model.sparksStart = nil
        model.snap = true
        model.launchStage = .hidden

        // The character has to be on screen to hear the first commands
        model.onActorReady { [weak self] in
            self?.after(40) { self?.play(modules: modules) }
        }
    }

    private func play(modules: Int) {
        guard running else { return }
        let m = model

        // He starts unlit and asleep: a black body on a black island, so only two closed eyes will show
        m.setHabit(nil)
        m.setLit(false)
        m.setMood(.asleep, force: true)
        m.setRim(.calm)

        // 1. a drop swells under the notch, two sleeping eyes inside it
        after(60) { [weak self] in
            m.snap = false
            m.launchStage = .drip
            self?.sound("pop")
        }
        // 2. the eyes snap open in the dark and check left, then right
        after(700) { [weak self] in
            m.setMood(.surprised)
            m.pose(.pop)
            self?.sound("blip")
        }
        after(1050) { m.setGaze(CGPoint(x: -1, y: 0)) }
        after(1350) { m.setGaze(CGPoint(x: 1, y: 0)) }
        // 3. the island opens wide; still dark, the eyes find you
        after(1700) { [weak self] in
            m.launchStage = .greet
            m.setMood(.curious)   // a new mood frees the gaze: he follows the pointer again
            self?.sound("open")
        }
        // 4. the light comes on: the rim draws itself round him, the glow blooms, he bounces with joy
        after(2200) { [weak self] in
            m.setLit(true)
            m.greeting.lit = true
            m.setMood(.happy)
            m.setRim(.joy)
            m.pose(.boing)
            m.sparksStart = .now
            self?.sound("greet")
        }
        // 5. he waves, his name writes itself, then the modules he watches
        after(2850) {
            m.pose(.wave)
            m.greeting.say = true
        }
        after(3450) { [weak self] in
            m.greeting.mods = true
            m.setMood(.neutral)
            m.setRim(.joy)
            m.setGaze(CGPoint(x: 0.9, y: 0.25))
            for i in 0..<modules {
                self?.after(Double(i) * 95) { self?.sound("blip") }
            }
        }
        // 6. a wink, and he goes to his seat while everything folds back
        after(4250) {
            m.setMood(.wink)
            m.setRim(.calm)
        }
        after(4700) { m.greeting.bye = true }
        after(4900) { [weak self] in
            guard let self else { return }
            self.finish()
            self.sound("close")
            self.onComplete?()
        }
    }

    /// Something more important came up (an alert): the island takes over at once.
    func cancel() {
        guard running else { return }
        finish()
    }

    private func finish() {
        cancelTimers()
        running = false
        model.snap = false
        model.setLit(true)
        model.setGaze(nil)
        model.forgetCommands()
        NotificationCenter.default.post(name: .yumiMood, object: nil)
        NotificationCenter.default.post(name: .yumiRim, object: nil)
        model.launchStage = nil
    }

    private func cancelTimers() {
        timers.forEach { $0.cancel() }
        timers = []
    }
}
