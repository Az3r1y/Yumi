import EventKit
import Foundation

/// Where a macOS permission stands, whatever the framework behind it.
/// A module never asks by itself: the request starts from a button the user presses.
enum PermissionState: Equatable, Sendable {
    case notDetermined
    case granted
    case denied
}

/// Panes of System Settings a module can send the user to when a permission was refused.
enum PrivacySettings {
    static let calendars = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!
    static let reminders = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders")!
    static let location  = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices")!
    static let automation = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!
}

/// What macOS says about the calendars and the reminders. Its status can stay "not determined"
/// in a running app after the person said yes, until Yumi starts again: a yes given in this run
/// is kept here and counts at once.
enum EventKitAccess {
    nonisolated(unsafe) private static var grantedNow: Set<EKEntityType> = []
    private static let lock = NSLock()

    static func state(for type: EKEntityType) -> PermissionState {
        if lock.withLock({ grantedNow.contains(type) }) { return .granted }
        switch EKEventStore.authorizationStatus(for: type) {
        case .fullAccess:    return .granted
        case .notDetermined: return .notDetermined
        default:             return .denied
        }
    }

    /// The answer to a request: a yes counts from now, and the store reads its calendars again.
    static func answered(_ granted: Bool, for type: EKEntityType, store: EKEventStore) {
        guard granted else { return }
        lock.withLock { _ = grantedNow.insert(type) }
        store.reset()
    }
}
