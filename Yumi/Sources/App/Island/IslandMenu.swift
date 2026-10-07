import AppKit

/// The menu of a right click on Yumi or the island: what the menu bar item gives, for when the
/// notch hides it (a small screen with many icons).
@MainActor
enum IslandMenu {
    static func pop(at point: NSPoint, in view: NSView) {
        let menu = NSMenu()
        menu.addItem(item(loc("Réglages…"), key: ",") { IslandActions.openSettings() })
        menu.addItem(item(loc("Envoyer un retour"), key: "") {
            if let url = YumiUpdates.feedbackURL() { NSWorkspace.shared.open(url) }
        })
        menu.addItem(.separator())
        menu.addItem(item(loc("Quitter Yumi"), key: "q") { NSApp.terminate(nil) })
        menu.popUp(positioning: nil, at: point, in: view)
    }

    private static func item(_ title: String, key: String, action: @escaping @MainActor () -> Void) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(Target.run(_:)), keyEquivalent: key)
        let target = Target(action)
        item.target = target
        item.representedObject = target   // keeps the target alive as long as the item
        return item
    }

    private final class Target: NSObject {
        let action: @MainActor () -> Void
        init(_ action: @escaping @MainActor () -> Void) { self.action = action }
        @MainActor @objc func run(_ sender: Any?) { action() }
    }
}
