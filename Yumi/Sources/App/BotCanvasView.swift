import SwiftUI

/// The main character. The island places it where it wants, at the size it wants:
///
///     BotCanvasView(state: state).frame(width: d / 0.6, height: d / 0.6)
///
/// where `d` is the "diameter" of the layouts. Yumi's body is centred in that frame and is
/// 1.14 × d wide. The drawing itself is larger than the frame, so that jumps, droplets, smoke
/// and props are never cut by this view; it takes no extra room in the layout.
///
/// It follows `AppState.effectiveState`, and obeys the commands of
/// Contracts/CharacterCommands.swift (yumiPose, yumiHabit, yumiMood, yumiRim, yumiLit, yumiGaze).
struct BotCanvasView: View {
    @ObservedObject var state: AppState
    var particleOverhang: CGFloat = 0

    // One engine per view instance (main bot)
    @StateObject private var engine = BotEngine()

    var body: some View {
        YumiStage(engine: engine, particleOverhang: particleOverhang, paused: state.mode == .hidden)
            .onChange(of: state.effectiveState) { _, newState in
                engine.setState(newState)
            }
            .onChange(of: state.view) { _, newView in
                // Waiting for a file: he stretches up to catch it
                engine.setReceiving(state.mode == .expanded && newView == .upload)
            }
            .onChange(of: state.mode) { _, newMode in
                if newMode != .expanded { engine.setReceiving(false) }
            }
            .yumiCommands(engine)
            .legacyBotCommands(engine)
            .onAppear {
                engine.setState(state.effectiveState, force: true)
                #if DEBUG
                BotDemo.startIfRequested()
                #endif
            }
    }
}

private extension View {
    /// Contracts/CharacterCommands.swift: the island tells the character what to do.
    @MainActor func yumiCommands(_ engine: BotEngine) -> some View {
        self
            .onReceive(NotificationCenter.default.publisher(for: .yumiPose)) { notif in
                if let pose = notif.object as? YumiPose { engine.play(pose) }
            }
            .onReceive(NotificationCenter.default.publisher(for: .yumiScene)) { notif in
                if let scene = notif.object as? YumiScene {
                    engine.playScene(scene, count: notif.userInfo?["count"] as? Int ?? 1)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .yumiHabit)) { notif in
                engine.setHabit(notif.object as? YumiHabit)
            }
            .onReceive(NotificationCenter.default.publisher(for: .yumiMood)) { notif in
                engine.setMood(notif.object as? YumiMood)
            }
            .onReceive(NotificationCenter.default.publisher(for: .yumiRim)) { notif in
                engine.setRim(notif.object as? YumiRimTone)
            }
            .onReceive(NotificationCenter.default.publisher(for: .yumiLit)) { notif in
                if let on = notif.object as? Bool { engine.setLit(on) }
            }
            .onReceive(NotificationCenter.default.publisher(for: .yumiGaze)) { notif in
                engine.setGaze(notif.object as? CGPoint)
            }
    }

    /// Notifications the island was already sending before the contract existed.
    @MainActor func legacyBotCommands(_ engine: BotEngine) -> some View {
        self
            .onReceive(NotificationCenter.default.publisher(for: .triggerEmote)) { notif in
                if let emote = notif.object as? BotEmote {
                    engine.triggerEmote(emote)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .triggerSlap)) { _ in
                engine.slap()
            }
            .onReceive(NotificationCenter.default.publisher(for: .botBlink)) { _ in
                engine.blink()
            }
            .onReceive(NotificationCenter.default.publisher(for: .botSetTgEs)) { notif in
                if let v = notif.object as? CGFloat {
                    engine.tgEs = v
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .botGulp)) { _ in
                engine.gulp()
            }
            .onReceive(NotificationCenter.default.publisher(for: .botMorphTo)) { notif in
                if let target = notif.object as? CGFloat {
                    engine.setReceiving(target > 0.5)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .botGreet)) { _ in
                engine.greet()
            }
    }
}

/// TimelineView + Canvas for one engine. The canvas is larger than the frame it is given
/// (BotEngine.canvasRect) and centred on it, so the layout is unchanged and nothing is cut.
struct YumiStage: View {
    /// Observed for its cadence only: the engine publishes nothing else.
    @ObservedObject var engine: BotEngine
    var particleOverhang: CGFloat = 0
    var paused = false
    /// false for a character that must not react to the pointer (galleries).
    var followsPointer = true

    @State private var probe = YumiScreenProbe()
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        GeometryReader { geo in
            let frame = CGRect(origin: .zero, size: geo.size)
            let room = BotEngine.canvasRect(for: frame, overhang: particleOverhang)
            // Every frame while he moves, fifteen a second while he only breathes, none while
            // nothing changes or he is not shown
            TimelineView(.animation(minimumInterval: engine.cadence == .low ? 1.0 / 15 : nil,
                                    paused: paused || engine.cadence == .still)) { timeline in
                Canvas { context, _ in
                    engine.particleOverhang = particleOverhang
                    engine.displayScale = displayScale
                    if followsPointer, let look = probe.look() { engine.pointer = look }
                    engine.advance(to: timeline.date)
                    var ctx = context
                    ctx.translateBy(x: -room.minX, y: -room.minY)
                    engine.draw(context: ctx, frame: frame)
                }
            }
            .frame(width: room.width, height: room.height)
            .position(x: room.midX, y: room.midY)
        }
        .background(YumiProbeView(probe: probe))
    }
}

/// Knows where the character is on screen, to turn the pointer position into a look direction.
@MainActor
final class YumiScreenProbe {
    weak var view: NSView?

    /// Same falloff as the mock-up: tanh of the distance over 220 pt sideways, 180 pt vertically.
    func look() -> CGPoint? {
        guard let view, let window = view.window else { return nil }
        let rect = window.convertToScreen(view.convert(view.bounds, to: nil))
        let mouse = NSEvent.mouseLocation
        return CGPoint(x: tanh((mouse.x - rect.midX) / 220), y: tanh((rect.midY - mouse.y) / 180))
    }
}

private struct YumiProbeView: NSViewRepresentable {
    let probe: YumiScreenProbe

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        probe.view = view
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        probe.view = nsView
    }
}

/// Mini character (for agent pills/column): the outline in the colour of its task, two eyes.
struct MiniBotCanvasView: View {
    let task: AgentTask
    @StateObject private var engine: BotEngine

    init(task: AgentTask) {
        self.task = task
        _engine = StateObject(wrappedValue: {
            let e = BotEngine()
            e.isMini = true
            e.bodyColor = cgColorFromHex(task.color)
            return e
        }())
    }

    /// A blink now and then is all the life it has: it is only redrawn while it blinks.
    @State private var blinking = false

    var body: some View {
        TimelineView(.animation(paused: !blinking)) { timeline in
            Canvas { context, size in
                engine.advance(to: timeline.date)
                engine.draw(context: context, frame: CGRect(origin: .zero, size: size))
            }
        }
        .task {
            // Each one starts at its own moment, then blinks every 5.4 s like the main character
            try? await Task.sleep(nanoseconds: UInt64.random(in: 0...5_000_000_000))
            while !Task.isCancelled {
                engine.blink()
                blinking = true
                try? await Task.sleep(nanoseconds: 300_000_000)
                blinking = false
                try? await Task.sleep(nanoseconds: 5_100_000_000)
            }
        }
        .onChange(of: task.state) { _, newState in
            engine.setState(newState)
        }
        .onAppear {
            engine.setState(task.state, force: true)
        }
    }
}

// MARK: - CGColor from hex string

func cgColorFromHex(_ hex: String) -> CGColor? {
    let h = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
    guard let val = UInt64(h, radix: 16) else { return nil }
    let r = CGFloat((val >> 16) & 0xFF) / 255
    let g = CGFloat((val >> 8)  & 0xFF) / 255
    let b = CGFloat( val        & 0xFF) / 255
    return CGColor(red: r, green: g, blue: b, alpha: 1)
}

extension CGColor {
    static func from(_ hex: String) -> CGColor {
        cgColorFromHex(hex) ?? CGColor(gray: 0.5, alpha: 1)
    }
}

// MARK: - Character demo (Debug builds only)

#if DEBUG
/// Two ways to check the character by eye against design/yumi/maquette/reference.html:
///
/// - `YUMI_DEMO=gallery` opens a window laid out like the character sheet of the mock-up
///   (habits, poses, expressions, rim colours).
/// - `YUMI_DEMO=open` opens the island on its home view after the launch and leaves it there.
/// - `YUMI_DEMO=1` plays the launch sequence, then every pose and habit, in the island,
///   through the notifications of Contracts/CharacterCommands.swift.
///
/// With `YUMI_DEMO_SHOTS=<folder>`, PNG snapshots are saved along the way.
@MainActor
enum BotDemo {
    private static var started = false
    private static var gallery: NSWindow?

    static func startIfRequested() {
        guard !started, let mode = ProcessInfo.processInfo.environment["YUMI_DEMO"] else { return }
        started = true
        switch mode {
        case "gallery": openGallery()
        case "open":    holdOpen()
        default:        playInIsland()
        }
    }

    private static func pause(_ seconds: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    private static func send(_ name: Notification.Name, _ object: Any?) {
        NotificationCenter.default.post(name: name, object: object)
    }

    /// Opens the island on its home view and keeps it open, to measure Yumi at rest.
    private static func holdOpen() {
        Task { @MainActor in
            await pause(8)
            guard let controller = NSApp.windows.compactMap({ $0.windowController as? IslandWindowController }).first else { return }
            controller.holdsOpen = true
            controller.fsm.homeToPetitDelay = 3600
            controller.expand(to: .overview)
        }
    }

    private static func openGallery() {
        let model = YumiGalleryModel()
        let host = NSHostingView(rootView: YumiGalleryView(model: model))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 980, height: 850),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Yumi : planche du personnage"
        window.contentView = host
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        gallery = window
        Task { @MainActor in
            // Habits have a routine of up to six seconds; poses replay every 1.9 s like the mock-up
            for i in 0..<16 {
                if i % 4 == 0 { model.playPoses() }
                if i % 5 == 0 { model.playScenes() }
                for j in 0..<4 {
                    await pause(0.475)
                    shot(host, String(format: "gallery-%02d-%d", i, j))
                }
            }
        }
    }

    private static func playInIsland() {
        Task { @MainActor in
            await pause(7)   // the island's own greeting, then compact
            shot("0-compact")
            NotificationCenter.default.post(name: .hookExpand, object: IslandView.overview)
            await pause(1)

            // The launch of the mock-up, character side: dark, asleep, eyes open, light on
            send(.yumiLit, false); send(.yumiMood, YumiMood.asleep)
            await pause(0.7); shot("1-launch-0-asleep")
            send(.yumiMood, YumiMood.surprised); send(.yumiPose, YumiPose.pop)
            await pause(0.35); send(.yumiGaze, CGPoint(x: -1, y: 0))
            await pause(0.3); shot("1-launch-1-left"); send(.yumiGaze, CGPoint(x: 1, y: 0))
            await pause(0.35); shot("1-launch-2-right")
            send(.yumiMood, YumiMood.curious); send(.yumiGaze, nil)
            await pause(0.5)
            send(.yumiLit, true); send(.yumiMood, YumiMood.happy); send(.yumiRim, YumiRimTone.joy); send(.yumiPose, YumiPose.boing)
            for i in 0..<4 { await pause(0.16); shot("1-launch-3-light-\(i)") }
            send(.yumiPose, YumiPose.wave)
            for i in 0..<4 { await pause(0.3); shot("1-launch-4-wave-\(i)") }
            send(.yumiMood, YumiMood.wink); send(.yumiRim, YumiRimTone.calm)
            await pause(0.5); shot("1-launch-5-wink")
            send(.yumiMood, nil); send(.yumiRim, nil)

            for pose in YumiPose.allCases {
                NotificationCenter.default.post(name: .hookExpand, object: IslandView.overview)
                send(.yumiPose, pose)
                for i in 0..<4 { await pause(0.3); shot("2-pose-\(pose.rawValue)-\(i)") }
                await pause(0.5)
            }
            for habit in YumiHabit.allCases {
                NotificationCenter.default.post(name: .hookExpand, object: IslandView.overview)
                send(.yumiHabit, habit)
                await pause(1.2); shot("3-habit-\(habit.rawValue)-0")
                await pause(3.2); shot("3-habit-\(habit.rawValue)-1")
            }
            send(.yumiHabit, nil)
            NotificationCenter.default.post(name: .islandCollapse, object: nil)
            await pause(1); shot("4-compact")
        }
    }

    private static func shot(_ name: String) {
        guard let view = NSApp.windows.first(where: { $0.windowController is IslandWindowController })?.contentView else { return }
        shot(view, name)
    }

    private static func shot(_ view: NSView, _ name: String) {
        guard let folder = ProcessInfo.processInfo.environment["YUMI_DEMO_SHOTS"],
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        let url = URL(fileURLWithPath: folder).appendingPathComponent(name + ".png")
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
#endif
