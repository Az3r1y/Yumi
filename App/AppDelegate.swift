import AppKit
import SwiftUI

/// Application lifecycle: accessory policy, menu bar, notch window setup.
///
/// This is Yumi's composition root: the Core instances (EventEngine,
/// SessionStore, YumiStateModel) are created here and passed explicitly to
/// whoever needs them — no singletons, no global mutable state.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var notchController: NotchWindowController?

    // Core
    private let engine = EventEngine()
    private let store = SessionStore()
    // Presentation layer (UI)
    private let stateModel = YumiStateModel()
    private let character = CharacterController()
    private var pumpTask: Task<Void, Never>?

    // Demo session used by the "Simulate" menu (replaced by the Claude Code
    // connector in step 3).
    private let demoAgent = Agent(id: AgentID("demo-agent"), name: "Demo Agent", kind: .coding)
    private let demoSession = SessionID("demo-session")

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        startEventPump()
        setupMenuBarItem()
        setupNotch()
    }

    // MARK: - Core wiring

    /// The single consumer loop: engine → store → presentation → character.
    /// Runs on the main actor; events are infrequent so this costs nothing
    /// when idle (the `for await` suspends until an event arrives).
    private func startEventPump() {
        pumpTask = Task { [engine, store, stateModel, character] in
            let events = await engine.subscribe()
            var lastPresentation: YumiPresentationState?
            for await event in events {
                let snapshot = await store.apply(event)
                stateModel.update(from: snapshot)
                // Character reactions on presentation transitions.
                if let transition = YumiPresentationTransition.between(lastPresentation ?? .idle,
                                                                      stateModel.presentationState) {
                    character.react(to: transition)
                }
                character.sync(presentationState: stateModel.presentationState)
                lastPresentation = stateModel.presentationState
            }
        }
    }

    private func publish(_ event: YumiEvent) {
        Task { await engine.publish(event) }
    }

    // MARK: - Menu bar

    private func setupMenuBarItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "seal", accessibilityDescription: "Yumi")
            button.image?.isTemplate = true
        }

        let menu = NSMenu()
        menu.addItem(withTitle: "Open Yumi", action: #selector(openNotch), keyEquivalent: "")

        let simulate = NSMenu(title: "Simulate")
        simulate.addItem(withTitle: "Start session", action: #selector(simSessionStart), keyEquivalent: "")
        simulate.addItem(withTitle: "Tool started", action: #selector(simToolStarted), keyEquivalent: "")
        simulate.addItem(withTitle: "Permission requested", action: #selector(simPermission), keyEquivalent: "")
        simulate.addItem(withTitle: "Question asked", action: #selector(simQuestion), keyEquivalent: "")
        simulate.addItem(withTitle: "Task completed", action: #selector(simComplete), keyEquivalent: "")
        simulate.addItem(withTitle: "Error", action: #selector(simError), keyEquivalent: "")
        simulate.addItem(withTitle: "End session", action: #selector(simSessionEnd), keyEquivalent: "")
        let simulateItem = NSMenuItem(title: "Simulate", action: nil, keyEquivalent: "")
        simulateItem.submenu = simulate
        menu.addItem(simulateItem)

        menu.addItem(.separator())
        menu.addItem(withTitle: "Character designer…", action: #selector(openCharacterDesigner), keyEquivalent: "")
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Yumi", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
    }

    // MARK: - Notch

    private func setupNotch() {
        let controller = NotchWindowController(stateModel: stateModel, characterController: character)
        controller.showWindow(nil)
        controller.fsm.launch()
        notchController = controller
    }

    // MARK: - Simulated events (step 3 replaces these with the Claude connector)

    @objc private func simSessionStart() {
        publish(.sessionStarted(demoSession, demoAgent, title: "Demo session"))
        reveal()
    }

    @objc private func simToolStarted() {
        publish(.toolStarted(demoSession, ToolInfo(name: "Edit", summary: "YumiApp.swift")))
    }

    @objc private func simPermission() {
        publish(.permissionRequested(demoSession, PermissionRequest(tool: "Bash", command: "swift test")))
        reveal()
    }

    @objc private func simQuestion() {
        publish(.questionRequested(demoSession, Question(text: "Meilisearch or Postgres?", options: ["Meilisearch", "Postgres"])))
        reveal()
    }

    @objc private func simComplete() {
        publish(.taskCompleted(demoSession))
    }

    @objc private func simError() {
        publish(.sessionErrored(demoSession, YumiError(message: "Simulated failure")))
    }

    @objc private func simSessionEnd() {
        publish(.sessionEnded(demoSession))
    }

    private func reveal() {
        if notchController?.fsm.state == .hidden {
            notchController?.fsm.reveal()
        }
    }

    // MARK: - Actions

    @objc private func openNotch() {
        notchController?.fsm.reveal()
    }

    private var settingsWindow: NSWindow?
    private var designerWindow: NSWindow?

    /// Character designer (expression/animation development tool).
    @objc private func openCharacterDesigner() {
        if let window = designerWindow, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 640),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Yumi — Character designer"
        window.contentView = NSHostingView(rootView: CharacterPreview())
        window.center()
        window.isReleasedWhenClosed = false
        designerWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func openSettings() {
        if let window = settingsWindow, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 120),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings — Yumi"
        window.contentView = NSHostingView(rootView: Text("Yumi — settings coming soon."))
        window.center()
        window.isReleasedWhenClosed = false
        settingsWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
