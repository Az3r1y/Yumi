import AppKit
import SwiftUI
import Combine

/// Owns the transparent NSPanel glued to the notch, feeds hover state to
/// IslandStateMachine, and hosts the SwiftUI content.
///
/// New Yumi code (adaptation of Coucou's IslandWindowController patterns):
/// hover polling and FSM wiring are kept; none of Coucou's drag-attach,
/// ghost panels, file-drop, keyboard monitors or AppState coupling is carried
/// over. The sprite placeholder is not interactive yet.
@MainActor
final class NotchWindowController: NSWindowController {

    let fsm = IslandStateMachine()

    private static let panelWidth: CGFloat = 720
    private static let panelHeight: CGFloat = 320

    private var wasInIsland = false
    private var frameTimer: Timer?
    private var container: MouseTargetView!
    private var greetingController = GreetingSequenceController()

    private let stateModel: YumiStateModel
    private let characterController: CharacterController

    init(stateModel: YumiStateModel, characterController: CharacterController) {
        self.stateModel = stateModel
        self.characterController = characterController
        let screen = Self.notchScreen() ?? NSScreen.main ?? NSScreen.screens[0]
        let sf = screen.frame
        let panel = NotchPanel(
            contentRect: NSRect(x: sf.midX - Self.panelWidth / 2, y: sf.maxY - Self.panelHeight,
                                width: Self.panelWidth, height: Self.panelHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        super.init(window: panel)
        setupPanel(screen: screen)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private func setupPanel(screen: NSScreen) {
        guard let panel = window as? NotchPanel else { return }
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 3)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        // The panel participates in event routing; MouseTargetView.hitTest
        // decides per point what reaches the content and what falls through
        // to the window behind.
        panel.ignoresMouseEvents = false

        let contentSize = panel.contentRect(forFrameRect: panel.frame).size
        let hosting = NSHostingView(
            rootView: YumiRootView()
                .environmentObject(greetingController)
                .environmentObject(stateModel)
                .environmentObject(characterController)
        )
        hosting.frame = NSRect(origin: .zero, size: contentSize)
        hosting.autoresizingMask = [.width, .height]

        // The panel (720×320) is much larger than the island (up to 640×150).
        // AppKit has no per-region click-through on a borderless window, so the
        // container below performs the hit-testing: clicks inside the island
        // reach the SwiftUI content, clicks in the transparent area fall
        // through to the window behind — even while the panel accepts events.
        let container = MouseTargetView(frame: NSRect(origin: .zero, size: contentSize))
        container.autoresizingMask = [.width, .height]
        container.addSubview(hosting)
        panel.contentView = container
        self.container = container

        wireFSM()
        startPolling()
        startClickMonitor()

        // Follow the notch screen across display configuration changes
        // (plug/unplug HDMI, lid open/close, display rearrangement).
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.retargetToNotchScreen() }
        }
    }

    /// Repositions the panel on the notch screen after a display change.
    private func retargetToNotchScreen() {
        guard let panel = window as? NotchPanel else { return }
        guard let screen = Self.notchScreen() else { return }
        let sf = screen.frame
        let newFrame = NSRect(x: sf.midX - Self.panelWidth / 2, y: sf.maxY - Self.panelHeight,
                              width: Self.panelWidth, height: Self.panelHeight)
        if panel.frame != newFrame {
            panel.setFrame(newFrame, display: true)
        }
    }

    // MARK: - FSM wiring

    private func wireFSM() {
        fsm.onTransition = { [weak self] from, to in
            guard let self else { return }
            switch to {
            case .hidden:
                self.setMode(.hidden)

            case .petit:
                if from == .coucou {
                    NotificationCenter.default.post(name: .greetingInterrupt, object: nil)
                }
                self.setMode(.compact)
                if from == .coucou { self.greetingController.reset() }
                // Start the hide timer if the mouse is not over the island
                if !self.wasInIsland { self.fsm.mouseLeft() }

            case .home:
                self.setMode(.expanded)
                self.greetingController.reset()

            case .coucou:
                self.setMode(.expanded)
                self.greetingController.begin()
            }
        }

        NotificationCenter.default.addObserver(
            forName: .greetComplete, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.fsm.greetComplete()
            }
        }
    }

    // MARK: - Mode transitions (drive the SwiftUI mode)

    private func setMode(_ mode: NotchMode) {
        guard greetingController.mode != mode else { return }
        withAnimation(animation(for: mode, from: greetingController.mode)) {
            greetingController.mode = mode
        }
    }

    private func animation(for new: NotchMode, from old: NotchMode) -> Animation {
        let order: [NotchMode: Int] = [.hidden: 0, .compact: 1, .expanded: 2]
        let shrinking = (order[new] ?? 0) < (order[old] ?? 0)
        return shrinking
            ? .timingCurve(0.45, 0, 0.2, 1, duration: 0.34)
            : .spring(response: 0.5, dampingFraction: 0.72)
    }

    // MARK: - 60 Hz hover polling (same pattern as Coucou)

    // MARK: - Click handling

    /// Clicking the compact island expands it (same rule as Coucou:
    /// hover keeps it awake, click opens). AppKit local monitor so the whole
    /// island rect is clickable, not just SwiftUI-drawn elements.
    private func startClickMonitor() {
        NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard let self, let panel = self.window as? NotchPanel else { return event }
            MainActor.assumeIsolated {
                guard self.fsm.state == .petit else { return }
                // locationInWindow is already in window coords (origin bottom-left),
                // same space as currentIslandFrame.
                let island = panel.currentIslandFrame(mode: self.greetingController.mode)
                if island.insetBy(dx: -6, dy: -6).contains(event.locationInWindow) {
                    self.fsm.click()
                }
            }
            return event
        }
    }

    // MARK: - Notch screen detection

    /// The screen carrying the physical notch: the built-in display on MacBooks.
    /// Detection uses CGDisplayIsBuiltin — never "main screen" or screens[0],
    /// which follow the user's display arrangement (an external HDMI monitor
    /// can be the main screen). Fallbacks: any screen reporting a top safe-area
    /// inset (notch-like), then the first screen (the one with the menu bar).
    static func notchScreen() -> NSScreen? {
        let screens = NSScreen.screens
        if let builtin = screens.first(where: { screen in
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
                as? CGDirectDisplayID else { return false }
            return CGDisplayIsBuiltin(id) != 0
        }) {
            return builtin
        }
        if let notched = screens.first(where: { $0.safeAreaInsets.top > 0 }) {
            return notched
        }
        return screens.first
    }

    private func startPolling() {
        frameTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pollFrame() }
        }
        if let frameTimer {
            RunLoop.main.add(frameTimer, forMode: .common)
        }
    }

    private func pollFrame() {
        guard let panel = window as? NotchPanel else { return }

        let mouse = NSEvent.mouseLocation
        let pf = panel.frame
        let local = CGPoint(x: mouse.x - pf.minX, y: mouse.y - pf.minY)

        let islandRect = panel.currentIslandFrame(mode: greetingController.mode)
        let inIsland = islandRect.insetBy(dx: -6, dy: -6).contains(local)

        // Per-point click handling lives in MouseTargetView.hitTest (island
        // only). The panel always accepts mouse events; the transparent area
        // around the island falls through to the window behind. The 60 Hz
        // polling here feeds the FSM hover enter/leave.
        container.islandMode = greetingController.mode

        // Feed the FSM hover enter/leave
        if inIsland && !wasInIsland {
            fsm.mouseEntered()
        }
        if !inIsland && wasInIsland {
            fsm.mouseLeft()
        }
        wasInIsland = inIsland
    }
}

// MARK: - Panel

/// Borderless panel allowed to sit over the menu bar / notch area.
final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Don't let macOS push the panel below the menu bar.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }

    /// Island rect in panel coordinates (origin bottom-left), for hover hit-testing.
    func currentIslandFrame(mode: NotchMode) -> CGRect {
        let w = NotchGeometry.width(for: mode)
        let h = NotchGeometry.height(for: mode)
        return CGRect(x: (frame.width - w) / 2, y: frame.height - h, width: w, height: h)
    }
}

/// Content view of the panel: only the island rect is a valid hit target.
/// A click outside returns nil so macOS forwards the event to the window
/// behind (standard AppKit per-view passthrough — no extra windows, no
/// global toggle).
///
/// Coordinates: `hitTest(_:)` receives the point in this view's own space
/// (origin bottom-left), the same space as `NotchPanel.currentIslandFrame` —
/// no conversion needed. SwiftUI hover uses a top-left origin but the 60 Hz
/// FSM polling runs in AppKit coordinates and is unaffected.
final class MouseTargetView: NSView {
    /// Current island mode, mirrored from the controller each poll tick so
    /// hit-testing always matches the drawn island size.
    var islandMode: NotchMode = .hidden

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Hidden island: fully click-through (the FSM wake-on-hover runs on
        // the 60 Hz polling, which does not depend on hit-testing).
        guard let panel = window as? NotchPanel, islandMode != .hidden else { return nil }
        let island = panel.currentIslandFrame(mode: islandMode)
        return island.contains(point) ? super.hitTest(point) : nil
    }
}

// MARK: - Notifications

extension Notification.Name {
    /// Posted by GreetingCanvasView when the scripted greeting finishes.
    static let greetComplete = Notification.Name("yumi.greetComplete")
    /// Posted to interrupt the greeting early (mouse left / collapse).
    static let greetingInterrupt = Notification.Name("yumi.greetingInterrupt")
}
