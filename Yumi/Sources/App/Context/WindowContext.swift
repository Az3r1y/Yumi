import Foundation

/// The focused window of the active application. Only available when the person has already
/// given Yumi the Accessibility permission: the engine never asks for it.
struct WindowContext: Hashable, Codable, Sendable {
    /// The title the application gives the window. Can be empty.
    var title: String
    /// The process that owns the window.
    var processID: Int32
    /// The file shown in the window, when the application says so (`AXDocument`). nil otherwise.
    var documentPath: String?

    init(title: String, processID: Int32, documentPath: String? = nil) {
        self.title = title
        self.processID = processID
        self.documentPath = documentPath
    }
}

/// Whether a capability that needs the person's consent is available.
enum ContextPermissionStatus: String, Codable, Sendable {
    /// Granted in System Settings.
    case granted
    /// Not granted. The engine works without it and never asks.
    case notGranted
    /// Not possible in this build (the App Store sandbox) or while filming.
    case unavailable
}
