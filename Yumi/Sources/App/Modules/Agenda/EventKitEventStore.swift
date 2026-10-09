import EventKit

/// The Calendar app through EventKit, for `AddEventTool`. Only adds and reads: it never changes
/// or removes an event, and never adds attendees (EventKit cannot, and nothing here tries).
final class EventKitEventStore: EventStore, @unchecked Sendable {
    // EKEventStore is thread-safe for these calls; the lock keeps save and fetch in order.
    private let store = EKEventStore()
    private let lock = NSLock()

    var access: PermissionState { EventKitAccess.state(for: .event) }

    func requestAccess() async -> Bool {
        guard access == .notDetermined else { return access == .granted }
        let granted = (try? await store.requestFullAccessToEvents()) ?? false
        EventKitAccess.answered(granted, for: .event, store: store)
        return granted
    }

    func defaultCalendar() -> EventCalendarInfo? {
        guard access == .granted else { return nil }
        return lock.withLock {
            guard let calendar = target() else { return nil }
            let usable = calendar.allowsContentModifications && !calendar.isSubscribed
                && calendar.type != .subscription && calendar.type != .birthday
            return EventCalendarInfo(title: calendar.title, acceptsNewEvents: usable)
        }
    }

    func add(title: String, start: Date, end: Date, location: String?) throws -> String {
        try lock.withLock {
            guard let calendar = target(), calendar.allowsContentModifications, !calendar.isSubscribed else {
                throw NSError(domain: EKErrorDomain, code: EKError.Code.calendarReadOnly.rawValue)
            }
            let event = EKEvent(eventStore: store)
            event.title = title
            event.startDate = start
            event.endDate = end
            event.location = location
            event.calendar = calendar
            try store.save(event, span: .thisEvent, commit: true)
            return event.eventIdentifier
        }
    }

    /// The calendar chosen in Réglages > Modules > Agenda when it still exists and accepts
    /// events, else the Calendar app's default one. Called with the lock held.
    private func target() -> EKCalendar? {
        if let id = AgendaCalendars.target(), let chosen = store.calendar(withIdentifier: id),
           chosen.allowsContentModifications, !chosen.isSubscribed {
            return chosen
        }
        return store.defaultCalendarForNewEvents
    }

    func event(id: String) -> StoredEvent? {
        lock.withLock {
            store.refreshSourcesIfNecessary()
            guard let event = store.event(withIdentifier: id) else { return nil }
            return StoredEvent(title: event.title ?? "", start: event.startDate, end: event.endDate, location: event.location,
                               calendar: event.calendar?.title ?? "", hasAttendees: !(event.attendees ?? []).isEmpty)
        }
    }
}
