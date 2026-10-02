import Foundation

/// A source of context. Each provider listens to one part of the Mac and reports raw
/// observations; the engine alone decides what they mean (`ContextState`).
///
/// Providers must be event driven: they react to notifications of the system and never poll.
/// Adding a source (screen, clipboard, files, browser, calendar, git, project) means writing a
/// provider that reports `.facet` observations: neither the engine nor its consumers change.
@MainActor
protocol ContextProvider: AnyObject {
    /// Starts listening. `report` must be called on the main actor.
    func start(report: @escaping @MainActor (ContextObservation) -> Void)
    /// Stops listening and releases everything it holds.
    func stop()
    /// The engine accepted a new front application. Lets a provider follow it (its windows).
    func applicationDidChange(to application: ApplicationContext?)
}

extension ContextProvider {
    func applicationDidChange(to application: ApplicationContext?) {}
}

/// What a provider saw, before the engine decides whether it changes anything.
enum ContextObservation: Equatable, Sendable {
    case applicationActivated(ApplicationContext)
    /// The focused window of the front application, nil when there is none.
    case windowFocused(WindowContext?)
    case applicationLaunched(ApplicationContext)
    case applicationTerminated(ApplicationContext)
    case system(ContextSystemSignal)
    case accessibility(ContextPermissionStatus)
    case facet(ContextFacet)
}

/// What a future provider adds to the context: a kind and a few readable values.
/// Kept deliberately loose until a real provider needs more.
struct ContextFacet: Equatable, Codable, Sendable {
    /// Open set: the raw value is what gets stored, new kinds break nothing.
    struct Kind: RawRepresentable, Hashable, Codable, Sendable {
        let rawValue: String
        init(rawValue: String) { self.rawValue = rawValue }

        static let screen = Kind(rawValue: "screen")
        static let clipboard = Kind(rawValue: "clipboard")
        static let file = Kind(rawValue: "file")
        static let browser = Kind(rawValue: "browser")
        static let calendar = Kind(rawValue: "calendar")
        static let git = Kind(rawValue: "git")
        static let project = Kind(rawValue: "project")
    }

    var kind: Kind
    var values: [String: String]
    var date: Date
}
