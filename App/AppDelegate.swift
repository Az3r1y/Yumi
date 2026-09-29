import AppKit
import SwiftUI

/// Application lifecycle: accessory policy, menu bar item, notch window setup.
///
/// New Yumi code. Modeled on Coucou's AppDelegate (adaptation, not a port):
/// starts only the window and the state machine — no servers, no pollers.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var notchController: NotchWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupMenuBarItem()
        setupNotch()
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
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Yumi", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
    }

    // MARK: - Notch

    private func setupNotch() {
        let controller = NotchWindowController()
        controller.showWindow(nil)
        controller.fsm.launch()
        notchController = controller
    }

    // MARK: - Actions

    @objc private func openNotch() {
        notchController?.fsm.reveal()
    }

    private var settingsWindow: NSWindow?

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
