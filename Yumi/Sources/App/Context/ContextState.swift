import Foundation

/// The rules of the Context Engine, as a pure value: observations go in, the events they
/// cause come out. No clock, no system call: everything is testable without a Mac session.
struct ContextState: Equatable, Sendable {
    struct Limits: Equatable, Sendable {
        var recentApplications = 8
        var recentEvents = 12
        /// How far back the activity shares look, in seconds.
        var activityWindow: TimeInterval = 15 * 60
        var historyCapacity = 300
        var historyMaxAge: TimeInterval = 4 * 3600
    }

    let limits: Limits
    private(set) var application: ApplicationContext?
    private(set) var applicationSince: Date?
    private(set) var previousApplication: ApplicationContext?
    private(set) var window: WindowContext?
    private(set) var windowSince: Date?
    private(set) var sessionStartedAt: Date?
    private(set) var accessibility: ContextPermissionStatus = .notGranted
    private(set) var history: ContextHistory
    private(set) var facets: [String: ContextFacet] = [:]
    /// The screen is locked or another account has it: nothing but an unlock brings the person back.
    private(set) var locked = false
    private var lastSignal: ContextSystemSignal?
    private var nextID = 1

    init(limits: Limits = Limits()) {
        self.limits = limits
        history = ContextHistory(capacity: limits.historyCapacity, maxAge: limits.historyMaxAge)
    }

    var isPresent: Bool { sessionStartedAt != nil }

    // MARK: - Monitoring

    /// The engine starts watching: the person is here, unless the screen is known to be locked.
    mutating func begin(at now: Date) -> [ContextEvent] {
        var events: [ContextEvent] = []
        if !isPresent, !locked { startSession(at: now, into: &events) }
        return events
    }

    /// The engine stops watching: the session ends.
    mutating func end(at now: Date) -> [ContextEvent] {
        var events: [ContextEvent] = []
        endSession(at: now, into: &events)
        return events
    }

    // MARK: - Observations

    mutating func apply(_ observation: ContextObservation, at now: Date) -> [ContextEvent] {
        var events: [ContextEvent] = []
        switch observation {
        case .applicationActivated(let app):
            if app.isSameApplication(as: application) {
                // The same process again: macOS repeats itself, nothing changed.
                application = app
                break
            }
            // Bringing an application forward means someone is there.
            if !isPresent, !locked { startSession(at: now, into: &events) }
            let from = application
            previousApplication = from
            application = app
            applicationSince = now
            // The window belonged to the previous application; the new one is reported next.
            window = nil
            windowSince = nil
            record(.applicationChanged(from: from, to: app), at: now, into: &events)

        case .windowFocused(let newWindow):
            guard let application else { break }
            // A late report about an application that is no longer in front.
            if let newWindow, newWindow.processID != application.processID { break }
            guard newWindow != window else { break }
            let from = window
            window = newWindow
            windowSince = newWindow == nil ? nil : now
            record(.windowChanged(from: from, to: newWindow), at: now, into: &events)

        case .applicationLaunched(let app):
            record(.applicationLaunched(app), at: now, into: &events)

        case .applicationTerminated(let app):
            if app.isSameApplication(as: previousApplication) { previousApplication = nil }
            record(.applicationQuit(app), at: now, into: &events)

        case .system(let signal):
            // Several notifications of the system can repeat one another (two wakes in a row).
            guard signal != lastSignal else { break }
            lastSignal = signal
            record(.system(signal), at: now, into: &events)
            switch signal {
            case .screenLocked, .sessionResigned: locked = true
            case .screenUnlocked, .sessionResumed: locked = false
            default: break
            }
            if signal.isDeparture {
                endSession(at: now, into: &events)
            } else if !isPresent, !locked {
                startSession(at: now, into: &events)
            }

        case .accessibility(let status):
            guard status != accessibility else { break }
            accessibility = status
            if status != .granted {
                window = nil
                windowSince = nil
            }
            record(.permissionChanged(accessibility: status), at: now, into: &events)

        case .facet(let facet):
            guard facets[facet.kind.rawValue]?.values != facet.values else { break }
            facets[facet.kind.rawValue] = facet
            record(.facetChanged(facet.kind), at: now, into: &events)
        }
        return events
    }

    // MARK: - Snapshot

    func snapshot(at now: Date, presence: ContextPresence) -> ContextSnapshot {
        var history = history
        history.prune(now: now)
        return ContextSnapshot(
            capturedAt: now,
            isEnabled: true,
            presence: presence,
            accessibility: accessibility,
            activeApplication: application,
            activeApplicationSince: applicationSince,
            activeWindow: window,
            activeWindowSince: windowSince,
            previousApplication: previousApplication,
            sessionStartedAt: sessionStartedAt,
            recentApplications: history.recentApplications(excluding: application, limit: limits.recentApplications),
            recentEvents: history.recent(limits.recentEvents),
            activity: activity(in: history, at: now),
            facets: facets)
    }

    private func activity(in history: ContextHistory, at now: Date) -> [ContextActivityShare] {
        let spent = history.timeSpent(since: now.addingTimeInterval(-limits.activityWindow), now: now,
                                      current: isPresent ? application : nil, currentSince: applicationSince)
        var byCategory: [ApplicationCategory?: TimeInterval] = [:]
        for (_, entry) in spent { byCategory[entry.app.category, default: 0] += entry.seconds }
        let total = byCategory.values.reduce(0, +)
        guard total > 0 else { return [] }
        return byCategory
            .map { ContextActivityShare(category: $0.key, seconds: $0.value, share: $0.value / total) }
            .sorted { $0.seconds != $1.seconds ? $0.seconds > $1.seconds : $0.label < $1.label }
    }

    // MARK: - Private

    private mutating func startSession(at now: Date, into events: inout [ContextEvent]) {
        sessionStartedAt = now
        // Time away does not count as time spent with the application in front.
        if application != nil { applicationSince = now }
        if window != nil { windowSince = now }
        record(.sessionStarted, at: now, into: &events)
    }

    private mutating func endSession(at now: Date, into events: inout [ContextEvent]) {
        guard let start = sessionStartedAt else { return }
        sessionStartedAt = nil
        record(.sessionEnded(duration: now.timeIntervalSince(start)), at: now, into: &events)
    }

    private mutating func record(_ kind: ContextEvent.Kind, at now: Date, into events: inout [ContextEvent]) {
        let event = ContextEvent(id: nextID, date: now, kind: kind)
        nextID += 1
        history.append(event)
        events.append(event)
    }
}
