import SwiftUI

/// SwiftUI wrapper: TimelineView drives a Canvas that calls BotEngine.draw().
/// Uses a shared engine per-task; the main bot uses AppState's shared engine.
struct BotCanvasView: View {
    @ObservedObject var state: AppState
    var particleOverhang: CGFloat = 0

    // One engine per view instance (main bot)
    @StateObject private var engine = BotEngine()

    var body: some View {
        TimelineView(.animation(paused: state.mode == .hidden)) { timeline in
            Canvas { context, size in
                let now = timeline.date.timeIntervalSinceReferenceDate
                let dtRaw = min(0.05, now - engine.lastTime)
                let dt = dtRaw
                engine.lookX = lookX(state: state, size: size)
                engine.lookY = lookY(state: state, size: size)
                engine.particleOverhang = particleOverhang
                // Widen slot when file is hovering over the mailbox (morph > 0.5)
                // Open mouth (hover=0.20R) when file dragged over box; close when not
                if engine.morph > 0.3 {
                    engine.slotHTarget = state.fileDragOver ? 0.20 : 0
                } else {
                    engine.slotHTarget = 0
                    if engine.morph < 0.05 { engine.slotH = 0; engine.slotHVel = 0 }
                }
                // The main character never takes a brand colour: its body stays black and its rim
                // light shows the state (working=blue, thinking=purple, etc.). Only the mini
                // characters of the integration pills carry their brand colour (bodyColor).
                engine.update(dt: dt)
                engine.drawHandsBehind(context: context, size: size)
                engine.draw(context: context, size: size)
                engine.drawHandsAndExtras(context: context, size: size)
            }
        }
        .onChange(of: state.effectiveState) { _, newState in
            engine.setState(newState)
        }
        .onChange(of: state.view) { _, newView in
            // Morph up when upload view is active
            if state.mode == .expanded && newView == .upload {
                engine.anim("morph", keys: [TweenKey(target: 1, duration: 550, ease: Ease.inOut)])
            } else if newView != .upload && newView != .uploading && engine.morph > 0.01 {
                // Any other view (not mid-gulp): morph back
                engine.anim("morph", keys: [TweenKey(target: 0, duration: 550, ease: Ease.inOut)])
            }
        }
        .onChange(of: state.mode) { _, newMode in
            // Hard-reset morph when island collapses
            if newMode != .expanded {
                engine.tweens.removeValue(forKey: "morph")
                engine.locks.remove("morph")
                engine.morph = 0
            }
        }
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
                let dur: CGFloat = target > 0.5 ? 550 : 650
                engine.anim("morph", keys: [TweenKey(target: target, duration: dur, ease: Ease.inOut)])
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .botGreet)) { _ in
            engine.greet()
        }
        .onAppear {
            engine.setState(state.effectiveState, force: true)
            #if DEBUG
            BotDemo.startIfRequested()
            #endif
        }
    }

    private func lookX(state: AppState, size: CGSize) -> CGFloat {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let (islandW, islandH) = islandSize(mode: state.mode, view: state.view,
                                             progress: state.uploadProgress,
                                             nw: state.notchWidth, nh: state.notchHeight)
        let (botCx, _, _, _) = botPosition(mode: state.mode, view: state.view,
                                            islandW: islandW, islandH: islandH,
                                            uploadProgress: state.uploadProgress)
        // Island is centered on screen; bot is at botCx within island coords
        let botScreenX = screen.frame.midX - islandW / 2 + botCx
        return tanh((state.mousePosition.x - botScreenX) / 260)
    }

    private func lookY(state: AppState, size: CGSize) -> CGFloat {
        let (islandW, islandH) = islandSize(mode: state.mode, view: state.view,
                                             progress: state.uploadProgress,
                                             nw: state.notchWidth, nh: state.notchHeight)
        let actualH: CGFloat = (state.mode == .expanded && state.view == .prompt)
            ? min(300, 240 + CGFloat(state.chatHistory.count) * 40)
            : islandH
        let (_, botCy, _, _) = botPosition(mode: state.mode, view: state.view,
                                             islandW: islandW, islandH: actualH,
                                             uploadProgress: state.uploadProgress)
        // Island top = screen top → bot screen Y = botCy from island top
        return -tanh((state.mousePosition.y - botCy) / 200)
    }
}

/// Mini bot canvas (for agent pills/column)
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

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let now = timeline.date.timeIntervalSinceReferenceDate
                let dt = min(0.05, now - engine.lastTime)
                engine.update(dt: dt)
                engine.draw(context: context, size: size)
            }
        }
        .onChange(of: task.state) { _, newState in
            engine.setState(newState)
        }
        .onAppear {
            engine.setState(task.state, force: true)
            if let emote = task.emote {
                engine.setPermanentEmote(emote)
            }
            // Direct eye override takes priority (e.g. .wide eyes for Research)
            if let eye = task.miniEye {
                engine.permanentEye = eye
                engine.eyeOverride = eye
                engine.eyeOverrideUntil = .greatestFiniteMagnitude
            }
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
/// Launch with `YUMI_DEMO=1` in the environment to walk the character through every state and
/// emote (compact, then expanded) and through the file-drop sequence, so the three renderers can
/// be checked by eye. With `YUMI_DEMO_SHOTS=<folder>`, a PNG of the island is saved at each step.
@MainActor
enum BotDemo {
    private static var started = false

    static func startIfRequested() {
        guard !started, ProcessInfo.processInfo.environment["YUMI_DEMO"] != nil else { return }
        started = true
        Task { @MainActor in
            let state = AppState.shared
            func pause(_ seconds: Double) async {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            }

            // Greeting (4.6 s), then the island settles in compact mode
            for i in 0..<14 { await pause(0.4); shot(String(format: "0-greeting-%02d", i)) }
            await pause(0.6)

            for s in BotState.allCases {
                state.stateOverride = s
                await pause(0.8); shot("1-compact-\(s.rawValue)")
            }
            NotificationCenter.default.post(name: .hookExpand, object: IslandView.overview)
            for s in BotState.allCases {
                state.stateOverride = s
                await pause(0.6); shot("2-state-\(s.rawValue)-a")
                await pause(1.2); shot("2-state-\(s.rawValue)-b")
            }
            state.stateOverride = nil
            for e in BotEmote.allCases {
                NotificationCenter.default.post(name: .triggerEmote, object: e)
                await pause(0.9); shot("3-emote-\(e.rawValue)")
                await pause(0.9)
            }

            // File drop: same calls as IslandWindowController and FileDropHandler, without a file
            UploadSequenceEngine.shared.enterZone(x: 330, y: 150)
            NotificationCenter.default.post(name: .hookExpand, object: IslandView.upload)
            for i in 0..<4 { await pause(0.35); shot("4-upload-\(i)") }
            UploadSequenceEngine.shared.performDrop(uploadDuration: 2.4)
            state.view = .uploading
            for i in 4..<20 { await pause(0.3); shot(String(format: "4-upload-%02d", i)) }
            state.view = .choose
            await pause(1.0); shot("4-upload-20")
            UploadSequenceEngine.shared.deactivate()
            NotificationCenter.default.post(name: .islandCollapse, object: nil)
        }
    }

    private static func shot(_ name: String) {
        guard let folder = ProcessInfo.processInfo.environment["YUMI_DEMO_SHOTS"],
              let view = NSApp.windows.first(where: { $0.windowController is IslandWindowController })?.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        let url = URL(fileURLWithPath: folder).appendingPathComponent(name + ".png")
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
#endif
