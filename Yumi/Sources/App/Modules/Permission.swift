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
