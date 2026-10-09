import EventKit

/// The Reminders app through EventKit, for `AddReminderTool`. Only adds and reads: it never
/// changes, completes or removes a reminder. Asks for access only when nobody answered yet
/// (`requestAccess`), the same question the Notes module asks.
final class EventKitReminderStore: ReminderStore, @unchecked Sendable {
    // EKEventStore is thread-safe for these calls; the lock keeps save and fetch in order.
    private let store = EKEventStore()
    private let lock = NSLock()

    var access: PermissionState { EventKitAccess.state(for: .reminder) }

    func requestAccess() async -> Bool {
        guard access == .notDetermined else { return access == .granted }
        let granted = (try? await store.requestFullAccessToReminders()) ?? false
        EventKitAccess.answered(granted, for: .reminder, store: store)
        return granted
    }

    func defaultListName() -> String? {
        guard access == .granted else { return nil }
        return lock.withLock { store.defaultCalendarForNewReminders()?.title }
    }

    func add(title: String, due: DateComponents?) throws -> String {
        try lock.withLock {
            guard let list = store.defaultCalendarForNewReminders() else {
                throw NSError(domain: EKErrorDomain, code: EKError.Code.noCalendar.rawValue)
            }
            let reminder = EKReminder(eventStore: store)
            reminder.title = title
            reminder.calendar = list
            if let due {
                reminder.dueDateComponents = due
                // Rappels notifies at a reminder's time only through an alarm.
                if due.hour != nil, let date = Calendar.current.date(from: due) {
                    reminder.addAlarm(EKAlarm(absoluteDate: date))
                }
            }
            try store.save(reminder, commit: true)
            return reminder.calendarItemIdentifier
        }
    }

    func reminder(id: String) -> StoredReminder? {
        lock.withLock {
            store.refreshSourcesIfNecessary()
            guard let reminder = store.calendarItem(withIdentifier: id) as? EKReminder else { return nil }
            let fields: Set<Calendar.Component> = [.year, .month, .day, .hour, .minute]
            let due = reminder.dueDateComponents.map { components in
                var kept = DateComponents()
                for field in fields { if let value = components.value(for: field) { kept.setValue(value, for: field) } }
                return kept
            }
            return StoredReminder(title: reminder.title ?? "", due: due, list: reminder.calendar?.title ?? "")
        }
    }
}
