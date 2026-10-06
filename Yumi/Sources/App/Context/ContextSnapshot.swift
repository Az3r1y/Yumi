import Foundation

/// Everything the Context Engine knows at one moment. A plain value: consumers read it and
/// never change the engine through it. It stays on the Mac: nothing sends it anywhere.
struct ContextSnapshot: Equatable, Codable, Sendable {
    var capturedAt: Date
    /// false when the person turned the engine off, or while filming. Everything else is then empty.
    var isEnabled: Bool
    var presence: ContextPresence
    var accessibility: ContextPermissionStatus

    var activeApplication: ApplicationContext?
    var activeApplicationSince: Date?
    var activeWindow: WindowContext?
    var activeWindowSince: Date?
    var previousApplication: ApplicationContext?

    /// When the person sat down at the Mac this time. nil while away.
    var sessionStartedAt: Date?
    /// Most recent first, without the active one.
    var recentApplications: [ApplicationContext]
    /// Most recent first.
    var recentEvents: [ContextEvent]
    /// What the applications used in the last minutes say they are for, the largest share first.
    var activity: [ContextActivityShare]
    /// What future providers add, by kind.
    var facets: [String: ContextFacet]

    var sessionDuration: TimeInterval? { sessionDuration(at: capturedAt) }

    func sessionDuration(at now: Date) -> TimeInterval? {
        sessionStartedAt.map { max(0, now.timeIntervalSince($0)) }
    }

    func activeApplicationDuration(at now: Date) -> TimeInterval? {
        activeApplicationSince.map { max(0, now.timeIntervalSince($0)) }
    }

    /// The category the person seems to be working in: the one most of the recent time went to.
    var mainActivity: ContextActivityShare? { activity.first }

    static func disabled(at date: Date = Date()) -> ContextSnapshot {
        ContextSnapshot(capturedAt: date, isEnabled: false, presence: .idle, accessibility: .unavailable,
                        recentApplications: [], recentEvents: [], activity: [], facets: [:])
    }
}

/// Share of the recent time that went to applications of one category.
struct ContextActivityShare: Equatable, Codable, Sendable {
    /// nil for applications that declare no category.
    var category: ApplicationCategory?
    var seconds: TimeInterval
    /// 0 to 1.
    var share: Double

    var label: String { category?.label ?? loc("Other") }
}

/// What Yumi does with the context, as far as the character is concerned. He only looks:
/// none of these states lets him act.
enum ContextPresence: String, Equatable, Codable, Sendable {
    /// The engine is off, or the person is away.
    case idle
    /// The person is at the Mac and Yumi follows along.
    case observing
    /// The front application just changed. Lasts a moment, then back to observing.
    case contextChanged
}
