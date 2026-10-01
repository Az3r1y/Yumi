import Foundation

// MARK: - Quitting contract
// Yumi says goodbye before the app ends. The core delays the end of the app and tells the
// island; the island plays the goodbye and tells the core when it is over. Both sides rely
// on this file, so neither edits it during the parallel work (see YUMI.md).

extension Notification.Name {
    /// Posted by the core when the user quits. The island plays the goodbye sequence.
    static let yumiQuitRequested = AppIdentity.notification("yumiQuitRequested")
    /// Posted by the island when the goodbye is over. The core then lets the app end.
    /// The core must also end the app by itself after a few seconds if this never comes.
    static let yumiQuitReady = AppIdentity.notification("yumiQuitReady")
}
