import Foundation

/// How far an approval reaches. Always explicit and always bounded: no scope means "anything on
/// the Mac". Every one is for one tool and one kind of action, and never covers a high or
/// critical risk: those are approved one time at a time.
enum PermissionScope: String, Codable, Sendable, CaseIterable {
    /// These exact actions, in this run. Gone when the run ends.
    case oneTime
    /// The same kind of action with the same tool, inside the same project (or on the same
    /// resources when there is no project), until Yumi quits.
    case session
    /// The same kind of action with the same tool, anywhere inside the project. Remembered.
    case project
    /// The same kind of action with the same tool, on these exact resources. Remembered.
    case resource
    /// The same tool, for any action up to the approved risk, inside the same project or account,
    /// until Yumi quits.
    case tool

    /// Lasts after Yumi quits.
    var isRemembered: Bool { self == .project || self == .resource }

    /// Needs a project or an account to stay bounded.
    var needsContainer: Bool { self == .session || self == .project || self == .tool }

    /// Words for the details and the history.
    var label: String {
        switch self {
        case .oneTime: loc("une fois")
        case .session: loc("cette session")
        case .project: loc("le projet")
        case .resource: loc("ces fichiers")
        case .tool: loc("cet outil, cette session")
        }
    }
}
