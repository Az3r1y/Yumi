import AppKit
import EventKit

/// The Mac's calendars through EventKit: what is on now, what comes next.
@MainActor
final class AgendaModule: YumiModule {
    let id = "agenda"

    private let eventStore = EKEventStore()
    private var events: [AgendaEvent] = []
    private var onChange: (@MainActor () -> Void)?
    private var storeObserver: NSObjectProtocol?
    private var ticking: Task<Void, Never>?

    var snapshot: ModuleSnapshot {
        AgendaSummary.snapshot(events: events, access: access, now: Date())
    }

    /// Today's appointments still to come (not the all-day ones), for whoever needs more than the snapshot.
    /// nil when the calendar cannot be read.
    var upcomingToday: [AgendaEvent]? {
        guard access == .granted else { return nil }
        let now = Date()
        return events.filter { !$0.isAllDay && $0.start > now && Calendar.current.isDate($0.start, inSameDayAs: now) }
            .sorted { $0.start < $1.start }
    }

    private var access: PermissionState {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess:    return .granted
        case .notDetermined: return .notDetermined
        default:             return .denied
        }
    }

    // MARK: Lifecycle

    func start(onChange: @escaping @MainActor () -> Void) {
        self.onChange = onChange
        storeObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: eventStore, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
        // "dans 12 min" changes every minute. Without the permission a tick costs nothing.
        ticking = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.reload()
                let wait = 60 - Date().timeIntervalSince1970.truncatingRemainder(dividingBy: 60)
                try? await Task.sleep(for: .seconds(wait), tolerance: .seconds(1))
            }
        }
    }

    func stop() {
        onChange = nil
        ticking?.cancel()
        ticking = nil
        if let storeObserver { NotificationCenter.default.removeObserver(storeObserver) }
        storeObserver = nil
        events = []
    }

    // MARK: Actions

    func perform(_ action: ModuleAction) {
        switch access {
        case .notDetermined:
            guard action == .primary else { return }
            eventStore.requestFullAccessToEvents { [weak self] _, _ in
                Task { @MainActor in self?.reload() }
            }
        case .denied:
            if action == .primary { NSWorkspace.shared.open(PrivacySettings.calendars) }
        case .granted:
            if action == .primary, let url = AgendaSummary.featured(events, now: Date())?.joinURL {
                NSWorkspace.shared.open(url)
            } else {
                openCalendar()
            }
        }
    }

    private func openCalendar() {
        guard let application = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") else { return }
        NSWorkspace.shared.openApplication(at: application, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
    }

    // MARK: Events

    /// Reads today's and tomorrow's events, then reports. Does nothing without the permission.
    private func reload() {
        if access == .granted {
            let calendar = Calendar.current
            let start = Date()
            let end = calendar.date(byAdding: .day, value: 2, to: calendar.startOfDay(for: start)) ?? start
            let predicate = eventStore.predicateForEvents(withStart: start, end: end, calendars: nil)
            events = eventStore.events(matching: predicate)
                .filter { $0.status != .canceled }
                .map { event in
                    AgendaEvent(id: event.eventIdentifier ?? UUID().uuidString,
                                title: event.title ?? "Événement",
                                start: event.startDate, end: event.endDate, isAllDay: event.isAllDay,
                                location: event.location ?? "",
                                joinURL: AgendaSummary.joinURL(in: [event.url?.absoluteString, event.location, event.notes]))
                }
        } else {
            events = []
        }
        onChange?()
    }
}
