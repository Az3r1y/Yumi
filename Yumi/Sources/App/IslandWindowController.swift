import AppKit
import Combine
import SwiftUI

@MainActor
final class IslandWindowController: NSWindowController {

    private var islandPanel: IslandPanel!
    private var state: AppState { AppState.shared }
    private let model = IslandModel.shared

    // State machine (hover, auto-close, launch)
    let fsm = IslandStateMachine()
    private let launch = IslandLaunch()

    private var wasInIsland = false
    /// Debug walk-through: the island does not fold by itself.
    var holdsOpen = false
    private var frameTimer: Timer?
    private var monitors: [Any] = []
    private var subscriptions: Set<AnyCancellable> = []

    /// The view the island opens on, when something other than a click opens it.
    private var pendingView: IslandView?
    /// Modules that were already asking for attention: only a new one opens the island.
    private var attentive: Set<String> = []

    // Window attach drag (M8)
    private var attachDragStart: NSPoint? = nil
    private var pendingIslandClick = false   // any island click → expand on mouseUp
    private var inAttachDrag = false
    private var dragGhostPanel: NSPanel? = nil
    private var dragGhostSize: CGFloat = 0
    private var ghostCurrentOrigin: NSPoint = .zero
    private var highlightPanel: NSPanel? = nil
    private var highlightWindowPid: pid_t = 0

    convenience init() {
        let notch = Self.notchScreen()
        let screen = notch ?? NSScreen.main ?? NSScreen.screens[0]

        let panelW = IslandConst.panelWidth
        let panelH = IslandConst.panelHeight
        let sf = screen.frame
        let panel = IslandPanel(
            contentRect: NSRect(x: sf.midX - panelW/2, y: sf.maxY - panelH,
                                width: panelW, height: panelH),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )

        self.init(window: panel)
        self.islandPanel = panel
        model.layout = IslandLayout(notchWidth: Self.notchWidth(for: screen),
                                    notchHeight: Self.notchHeight(for: screen),
                                    hasNotch: notch != nil)
        setupPanel()
    }

    private func setupPanel() {
        guard let panel = window as? IslandPanel else { return }
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 3)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.ignoresMouseEvents = true

        // Propagate real notch dimensions to AppState
        state.notchWidth  = model.layout.notchWidth
        state.notchHeight = model.layout.notchHeight
        attentive = Set(state.modules.filter(\.needsAttention).map(\.id))

        let contentSize = panel.contentRect(forFrameRect: panel.frame).size

        // Apple-recommended pattern: put NSHostingView and drag destination as siblings
        // inside a common superview, rather than embedding one inside the other.
        let container = NSView(frame: NSRect(origin: .zero, size: contentSize))
        container.autoresizingMask = [.width, .height]

        let hosting = NSHostingView(rootView: IslandRootView().environmentObject(AppState.shared))
        hosting.frame = NSRect(origin: .zero, size: contentSize)
        hosting.autoresizingMask = [.width, .height]

        // FileDropNSView sits above the hosting view (hitTest returns nil → no mouse interference).
        // AppKit routes NSDraggingDestination events to registered views independently of hitTest.
        let dropView = FileDropNSView(frame: NSRect(origin: .zero, size: contentSize))
        dropView.autoresizingMask = [.width, .height]
        dropView.onDragEntered = { [weak self] in
            // He opens on the drop view and stretches up to catch the file
            AppState.shared.fileDragOver = true
            self?.expand(to: .upload)
        }
        dropView.onDragExited = {
            // Do NOT collapse — drag session still active; island stays open.
            AppState.shared.fileDragOver = false
        }
        dropView.onFilesDropped = { urls in
            FileDropHandler.handle(urls: urls, state: AppState.shared)
        }

        container.addSubview(hosting)    // z-bottom: SwiftUI + mouse events
        container.addSubview(dropView)   // z-top: drag only (hitTest→nil, transparent to mouse)
        panel.contentView = container

        wireFSM()
        startPolling()
        startMonitors()
        startObservers()
        #if DEBUG
        IslandDemo.startIfRequested(controller: self)
        #endif
    }

    // MARK: - FSM wiring

    private func wireFSM() {
        launch.onComplete = { [weak self] in self?.fsm.greetComplete() }

        fsm.onTransition = { [weak self] from, to in
            guard let self else { return }
            switch to {
            case .hidden:
                self.setMode(.hidden)

            case .petit:
                if from == .hidden { SoundEngine.shared.play("peek") }
                // The launch plays its own sounds
                self.setMode(.compact, sound: from != .greeting)
                self.leaveOpenIsland()

            case .home:
                if from == .greeting { self.launch.cancel() }
                self.state.view = self.pendingView ?? .overview
                self.pendingView = nil
                self.setMode(.expanded, sound: from != .greeting)

            case .greeting:
                // Yumi only lives while the island is not hidden, and the launch draws its
                // own shapes: the mode is "expanded" for its whole length.
                self.state.view = .greeting
                self.setMode(.expanded, sound: false)
                self.launch.start(modules: self.model.pinned(self.state.modules).count)
            }
        }
    }

    /// What is left behind when the island folds: the view, the key window, a chat error.
    private func leaveOpenIsland() {
        IslandActions.leaveChatError(next: nil)
        state.isPinned = false
        fsm.pinned = false
        model.drawerOpen = false
        if state.view != .overview { state.view = .overview }
        window?.resignKey()
    }

    // MARK: - 60 Hz polling loop

    private func startPolling() {
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pollFrame() }
        }
        RunLoop.main.add(timer, forMode: .common)
        frameTimer = timer
    }

    private func pollFrame() {
        guard let panel = window as? IslandPanel else { return }

        let mouse = NSEvent.mouseLocation

        // Convert mouse to panel-local coords (macOS: origin bottom-left)
        let pf = panel.frame
        let local = CGPoint(x: mouse.x - pf.minX, y: mouse.y - pf.minY)

        // The island and, when it is out, the second square under it
        var inIsland = islandFrame().insetBy(dx: -6, dy: -6).contains(local)
        if !inIsland, let drawer = drawerFrame() {
            inIsland = drawer.insetBy(dx: -6, dy: -IslandConst.drawerGap).contains(local)
        }

        // Toggle click-through
        let shouldAcceptMouse = inIsland || inAttachDrag || attachDragStart != nil
        if panel.ignoresMouseEvents == shouldAcceptMouse {
            panel.ignoresMouseEvents = !shouldAcceptMouse
            if shouldAcceptMouse, let cv = panel.contentView {
                panel.invalidateCursorRects(for: cv)
            }
        }

        // An alert that waits for an answer keeps the island open; the delay is the user's
        fsm.pinned = state.isPinned
        if !holdsOpen { fsm.homeToPetitDelay = max(3, state.autoCloseInterval) }

        // Feed FSM hover enter/leave
        if inIsland && !wasInIsland {
            guard !inAttachDrag else { wasInIsland = inIsland; return }
            fsm.mouseEntered()
        }
        if !inIsland && wasInIsland {
            fsm.mouseLeft()
        }
        if inIsland { state.lastActivity = .now }
        wasInIsland = inIsland

        // Ghost character follows cursor + window highlight during drag (60 Hz, no throttle)
        if inAttachDrag {
            updateDragGhost()
            updateWindowHighlight()
        }
    }

    // MARK: - Geometry (panel coordinates, origin bottom-left)

    private func islandFrame() -> CGRect {
        let size = model.islandSize(for: state.mode)
        let panel = window?.frame.size ?? CGSize(width: IslandConst.panelWidth, height: IslandConst.panelHeight)
        return CGRect(x: (panel.width - size.width) / 2, y: panel.height - size.height,
                      width: size.width, height: size.height)
    }

    private func drawerFrame() -> CGRect? {
        guard model.drawerOpen, model.stage(for: state.mode) == .open, model.drawerHeight > 0 else { return nil }
        let island = islandFrame()
        return CGRect(x: island.maxX - IslandConst.drawerWidth,
                      y: island.minY - IslandConst.drawerGap - model.drawerHeight,
                      width: IslandConst.drawerWidth, height: model.drawerHeight)
    }

    /// Where Yumi is: his 100 × 84 box at the scale of his seat.
    private func isBotHit(_ windowPoint: CGPoint) -> Bool {
        let stage = model.stage(for: state.mode)
        guard stage == .open || stage == .compact else { return false }
        let seat = model.layout.seat(stage)
        let panel = window?.frame.size ?? CGSize(width: IslandConst.panelWidth, height: IslandConst.panelHeight)
        let dx = windowPoint.x - (panel.width / 2 + seat.x)
        let dy = windowPoint.y - (panel.height - seat.y)
        return abs(dx) <= 50 * seat.scale && abs(dy) <= 42 * seat.scale
    }

    // MARK: - Mode transitions

    private func setMode(_ mode: IslandMode, sound: Bool = true) {
        let prev = state.mode
        guard mode != prev else { return }
        state.mode = mode
        guard sound else { return }
        if mode == .expanded { SoundEngine.shared.play("open") }
        if prev == .expanded { SoundEngine.shared.play("close") }
    }

    /// Opens the island on a view. Alerts, the menu bar item, the shortcut, a file dragged
    /// over the notch and a window handed to Yumi all come through here.
    func expand(to view: IslandView) {
        if fsm.state == .home {
            IslandActions.leaveChatError(next: view)
            state.view = view
        } else {
            pendingView = view
            fsm.pinned = state.isPinned
            fsm.open()
        }
        state.lastActivity = .now
    }

    func collapse() {
        state.isPinned = false
        fsm.pinned = false
        fsm.collapse()
    }

    // MARK: - Mouse and keyboard

    private func startMonitors() {
        func keep(_ monitor: Any?) { if let monitor { monitors.append(monitor) } }

        // Escape folds the island: from another application (global), or while typing in ours (local)
        keep(NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let keyCode = event.keyCode
            let flags = event.modifierFlags.intersection([.command, .control, .option, .shift]).rawValue
            MainActor.assumeIsolated { self?.keyDown(keyCode: keyCode, flags: flags) }
        })
        keep(NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let handled = MainActor.assumeIsolated { () -> Bool in
                guard event.keyCode == 53, self.fsm.state == .home, !self.state.isPinned else { return false }
                self.collapse()
                return true
            }
            return handled ? nil : event
        })

        // Window attach drag, and the click that opens the compact island.
        // Uses MainActor.assumeIsolated (synchronous) to avoid race with pollFrame().
        // Global mouseUp is the reliable fallback when cursor is outside our panel frame.
        keep(NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard let self else { return event }
            MainActor.assumeIsolated {
                guard self.wasInIsland else { return }
                self.pendingIslandClick = true
                // Drag only starts when clicking directly on Yumi
                guard self.isBotHit(event.locationInWindow) else { return }
                self.attachDragStart = NSEvent.mouseLocation
            }
            return event
        })
        keep(NSEvent.addLocalMonitorForEvents(matching: .leftMouseDragged) { [weak self] event in
            guard let self else { return event }
            MainActor.assumeIsolated {
                guard let start = self.attachDragStart, !self.inAttachDrag else { return }
                let m = NSEvent.mouseLocation
                guard hypot(m.x - start.x, m.y - start.y) > 3 else { return }
                self.inAttachDrag = true
                self.showDragGhost()
            }
            return event
        })
        keep(NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
            guard let self else { return event }
            MainActor.assumeIsolated {
                let hadPendingClick = self.pendingIslandClick
                self.pendingIslandClick = false
                if self.inAttachDrag {
                    self.finishDrag()
                } else {
                    self.attachDragStart = nil
                    if hadPendingClick { self.fsm.click() }   // petit → home, ignored elsewhere
                }
            }
            return event
        })
        keep(NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in
            MainActor.assumeIsolated { self?.finishDrag() }
        })
    }

    private func keyDown(keyCode: UInt16, flags: UInt) {
        if keyCode == 53 { // Escape
            if fsm.state == .home && !state.isPinned { collapse() }
            return
        }
        // Global hotkey to show island
        guard state.hotkeyEnabled, flags == state.hotkeyFlags, keyCode == state.hotkeyCode else { return }
        if fsm.state != .home { expand(to: .overview) }
    }

    /// Yumi was dropped on a window: it becomes the context of the conversation.
    private func finishDrag() {
        guard inAttachDrag else { return }
        let mouse = NSEvent.mouseLocation
        inAttachDrag = false
        attachDragStart = nil
        hideDragGhost()
        #if !APPSTORE
        if let ctx = windowContextAtPoint(mouse) {
            IslandActions.newConversation()
            state.promptContext = ctx
            SoundEngine.shared.play("approve")
            expand(to: .prompt)
        }
        #endif
    }

    // MARK: - What the rest of the application asks of the island

    private func startObservers() {
        let center = NotificationCenter.default

        // Hook server expand requests (alerts only)
        center.publisher(for: .hookExpand)
            .sink { [weak self] note in
                guard let view = note.object as? IslandView else { return }
                self?.expand(to: view)
            }
            .store(in: &subscriptions)

        // Hook server compact reveal (non-alert work events: session start, tool use, etc.)
        center.publisher(for: .hookReveal)
            .sink { [weak self] _ in self?.fsm.reveal() }
            .store(in: &subscriptions)

        // Collapse requests from views (OK button, etc.)
        center.publisher(for: .islandCollapse)
            .sink { [weak self] _ in self?.collapse() }
            .store(in: &subscriptions)

        // Track last external app for window context capture
        let ourBundle = Bundle.main.bundleIdentifier ?? ""
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didActivateApplicationNotification)
            .sink { [weak self] note in
                if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                   app.bundleIdentifier != ourBundle {
                    self?.state.lastExternalApp = app
                }
            }
            .store(in: &subscriptions)

        // The text field of the talk view needs a key window; a nonactivating panel never
        // becomes key by itself.
        state.$view
            .receive(on: DispatchQueue.main)
            .sink { [weak self] view in
                guard let self, self.fsm.state == .home else { return }
                if IslandScreen.resolve(view: view, state: .idle, approvalPending: false) == .talk {
                    self.islandPanel.makeKey()
                } else if self.islandPanel.isKeyWindow {
                    self.islandPanel.resignKey()
                }
            }
            .store(in: &subscriptions)

        // A module that starts asking for the user opens the island on itself
        // (`ModuleSnapshot.needsAttention`: "the island may open by itself").
        state.$modules
            .receive(on: DispatchQueue.main)
            .sink { [weak self] modules in self?.modulesChanged(modules) }
            .store(in: &subscriptions)
    }

    private func modulesChanged(_ modules: [ModuleSnapshot]) {
        let now = Set(modules.filter(\.needsAttention).map(\.id))
        defer { attentive = now }
        guard let fresh = modules.first(where: { $0.needsAttention && !attentive.contains($0.id) }),
              fsm.state != .greeting, state.pendingApproval == nil else { return }
        model.selectedModuleID = fresh.id
        expand(to: .module)
    }

    // MARK: - Drag ghost window (character follows cursor during drag)

    private func showDragGhost() {
        guard dragGhostPanel == nil else { return }
        // Twice the compact size, for grab comfort
        let canvasSize: CGFloat = 40 / 0.6      // ~67
        dragGhostSize = canvasSize

        let mouse = NSEvent.mouseLocation
        let s = dragGhostSize
        ghostCurrentOrigin = NSPoint(x: mouse.x - s/2, y: mouse.y - s/2)

        let panel = NSPanel(
            contentRect: NSRect(x: ghostCurrentOrigin.x, y: ghostCurrentOrigin.y, width: s, height: s),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 4)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.ignoresMouseEvents = true

        let hosting = NSHostingView(
            rootView: GhostBotView(canvasSize: canvasSize)
        )
        hosting.frame = NSRect(x: 0, y: 0, width: s, height: s)
        panel.contentView = hosting
        panel.alphaValue = 0
        panel.orderFront(nil)
        dragGhostPanel = panel
        AppState.shared.isDraggingBot = true

        // Fade + scale-in handled by GhostBotView SwiftUI animation;
        // also fade in the window itself for extra smoothness
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
    }

    private func hideDragGhost() {
        dragGhostPanel?.close()
        dragGhostPanel = nil
        highlightPanel?.close()
        highlightPanel = nil
        highlightWindowPid = 0
        AppState.shared.isDraggingBot = false
    }

    private func updateDragGhost() {
        guard let panel = dragGhostPanel else { return }
        let s = dragGhostSize
        let mouse = NSEvent.mouseLocation
        // Direct follow — bot is "held", no trailing lag
        ghostCurrentOrigin = NSPoint(x: mouse.x - s/2, y: mouse.y - s/2)
        panel.setFrameOrigin(ghostCurrentOrigin)
    }

    // MARK: - Window highlight overlay (white border on target window during drag)

    private func updateWindowHighlight() {
        let mouse = NSEvent.mouseLocation
        guard let (appKitBounds, pid) = windowBoundsAtScreenPoint(mouse) else {
            // Fade out + close if no window under cursor
            if let old = highlightPanel {
                highlightPanel = nil
                highlightWindowPid = 0
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.12
                    ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
                    old.animator().alphaValue = 0
                }
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(130))
                    old.close()
                }
            }
            return
        }

        if pid == highlightWindowPid, let existing = highlightPanel {
            // Same window — just track position (windows rarely move, instant is fine)
            existing.setFrame(appKitBounds, display: false)
        } else {
            // New window — close old immediately, fade-in new
            highlightPanel?.close()
            highlightPanel = nil
            highlightWindowPid = pid

            let panel = NSPanel(
                contentRect: appKitBounds,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered, defer: false
            )
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = false
            panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 2)
            panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            panel.ignoresMouseEvents = true

            let hosting = NSHostingView(rootView:
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.75), lineWidth: 3)
                    .shadow(color: Color.white.opacity(0.5), radius: 16)
                    .padding(2)
                    .ignoresSafeArea()
            )
            hosting.frame = CGRect(origin: .zero, size: appKitBounds.size)
            hosting.autoresizingMask = [.width, .height]
            panel.contentView = hosting
            panel.alphaValue = 0
            panel.orderFront(nil)
            highlightPanel = panel

            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.14
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 1
            }
        }
    }

    /// The frontmost regular application window under a screen point (AppKit coordinates).
    private func externalWindow(at screenPoint: NSPoint) -> (bounds: CGRect, app: NSRunningApplication)? {
        guard let screen = window?.screen ?? NSScreen.main else { return nil }
        // CGWindowList uses top-left origin; NSEvent.mouseLocation uses bottom-left
        let screenMaxY = screen.frame.maxY
        let cgPoint = CGPoint(x: screenPoint.x, y: screenMaxY - screenPoint.y)

        guard let list = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] else { return nil }

        let ourBundle = Bundle.main.bundleIdentifier ?? ""
        for info in list {
            guard let b = info[kCGWindowBounds as String] as? [String: Any],
                  let x = b["X"] as? CGFloat, let y = b["Y"] as? CGFloat,
                  let w = b["Width"] as? CGFloat, let h = b["Height"] as? CGFloat else { continue }
            guard CGRect(x: x, y: y, width: w, height: h).contains(cgPoint) else { continue }
            let pid = info[kCGWindowOwnerPID as String] as? pid_t ?? 0
            guard let app = NSRunningApplication(processIdentifier: pid),
                  app.bundleIdentifier != ourBundle,
                  app.activationPolicy == .regular else { continue }
            // CG → AppKit: flip Y
            return (CGRect(x: x, y: screenMaxY - y - h, width: w, height: h), app)
        }
        return nil
    }

    private func windowBoundsAtScreenPoint(_ screenPoint: NSPoint) -> (CGRect, pid_t)? {
        externalWindow(at: screenPoint).map { ($0.bounds, $0.app.processIdentifier) }
    }

    // MARK: - Window context at screen point (for drag-attach)

    private func windowContextAtPoint(_ screenPoint: NSPoint) -> PromptContext? {
        externalWindow(at: screenPoint).flatMap { WindowContextCapture.captureActive(from: $0.app) }
    }

    // MARK: - Notch detection (static)

    static func notchScreen() -> NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 }
    }

    static func notchWidth(for screen: NSScreen) -> CGFloat {
        guard let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea else {
            return IslandConst.notchWidth
        }
        let w = screen.frame.width - left.width - right.width
        return w > 0 ? w : IslandConst.notchWidth
    }

    static func notchHeight(for screen: NSScreen) -> CGFloat {
        let h = screen.safeAreaInsets.top
        return h > 0 ? h : IslandConst.notchHeight
    }
}

// MARK: - IslandPanel

final class IslandPanel: NSPanel {
    override var canBecomeKey:  Bool { true }
    override var canBecomeMain: Bool { false }

    /// Allow panel to sit in the menu bar / notch area — don't let macOS push it down.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        return frameRect
    }
}

// MARK: - Ghost bot view (animated scale-in on appear)

struct GhostBotView: View {
    let canvasSize: CGFloat
    @State private var scale: CGFloat = 0.35

    var body: some View {
        BotCanvasView(state: AppState.shared)
            .frame(width: canvasSize, height: canvasSize)
            .scaleEffect(scale)
            .onAppear {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.55)) {
                    scale = 1.0
                }
            }
    }
}

// MARK: - Notification names

extension Notification.Name {
    // The character listens to these (BotCanvasView); the island itself now only uses
    // Contracts/CharacterCommands.swift.
    static let triggerEmote     = AppIdentity.notification("triggerEmote")
    static let triggerSlap      = AppIdentity.notification("triggerSlap")
    static let botDizzy         = AppIdentity.notification("botDizzy")
    static let botGreet         = AppIdentity.notification("botGreet")
    static let botBlink         = AppIdentity.notification("botBlink")
    static let botSetTgEs       = AppIdentity.notification("botSetTgEs")
    static let botGulp          = AppIdentity.notification("botGulp")
    static let botMorphTo       = AppIdentity.notification("botMorphTo")
    // Requests to the island
    static let islandCollapse   = AppIdentity.notification("islandCollapse")
    static let openFullSettings = AppIdentity.notification("openFullSettings")
    static let hookReveal       = AppIdentity.notification("hookReveal")
}
