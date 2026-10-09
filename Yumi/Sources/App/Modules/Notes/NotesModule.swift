import AppKit
import EventKit

/// Notes and reminders: Yumi's own notes (a text file), and the reminders of the Reminders app
/// that are due today or late, once the user allowed it.
@MainActor
final class NotesModule: YumiModule {
    let id = "notes"

    private let store: NotesStore
    private let eventStore = EKEventStore()
    private var notes: [String] = []
    private var reminders: [ReminderItem] = []
    private var onChange: (@MainActor () -> Void)?
    private var storeObserver: NSObjectProtocol?
    private var refreshing: Task<Void, Never>?

    init(store: NotesStore = NotesStore(fileURL: AppIdentity.supportDirectory.appendingPathComponent("notes.txt"))) {
        self.store = store
    }

    var snapshot: ModuleSnapshot {
        NotesSummary.snapshot(notes: notes, reminders: reminders, remindersAccess: access, now: Date())
    }

    /// On, but macOS does not let Yumi read the reminders.
    var runsWithoutAccess: Bool { onChange != nil && access != .granted }

    /// Incomplete reminders due today, for whoever needs more than the snapshot. nil while the
    /// module is stopped or the reminders cannot be read.
    func remindersDue(on day: Date, calendar: Calendar = .current) -> [ReminderItem]? {
        guard onChange != nil, access == .granted else { return nil }
        return reminders.filter { $0.due.map { calendar.isDate($0, inSameDayAs: day) } ?? false }
    }

    private var access: PermissionState { EventKitAccess.state(for: .reminder) }

    // MARK: Lifecycle

    func start(onChange: @escaping @MainActor () -> Void) {
        self.onChange = onChange
        notes = store.load()
        storeObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: eventStore, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.fetchReminders() }
        }
        // Reminders become due and days change without any notification: look again now and then.
        refreshing = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.notes = self.store.load()
                self.fetchReminders()
                self.onChange?()
                try? await Task.sleep(for: .seconds(600), tolerance: .seconds(60))
            }
        }
    }

    func stop() {
        onChange = nil
        refreshing?.cancel()
        refreshing = nil
        if let storeObserver { NotificationCenter.default.removeObserver(storeObserver) }
        storeObserver = nil
        reminders = []
    }

    // MARK: Actions

    func perform(_ action: ModuleAction) {
        let featured = NotesSummary.ordered(reminders).first
        switch action {
        case .primary:
            if let featured {
                complete(featured)
            } else if let text = NSPasteboard.general.string(forType: .string), store.add(text) != nil {
                notes = store.load()
            }
        case .secondary:
            if access == .notDetermined {
                requestAccess()
            } else if featured != nil {
                openReminders()
            } else {
                store.ensureFileExists()
                NSWorkspace.shared.open(store.fileURL)
            }
        }
    }

    private func requestAccess() {
        eventStore.requestFullAccessToReminders { @Sendable [weak self] granted, _ in
            Task { @MainActor in
                guard let self else { return }
                EventKitAccess.answered(granted, for: .reminder, store: self.eventStore)
                self.fetchReminders()
                self.onChange?()
            }
        }
    }

    private func openReminders() {
        guard let application = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.reminders") else { return }
        NSWorkspace.shared.openApplication(at: application, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
    }

    private func complete(_ item: ReminderItem) {
        guard let reminder = eventStore.calendarItem(withIdentifier: item.id) as? EKReminder else { return }
        reminder.isCompleted = true
        guard (try? eventStore.save(reminder, commit: true)) != nil else { return }
        reminders.removeAll { $0.id == item.id }
    }

    // MARK: Reminders

    /// Incomplete reminders due on one day, read from Rappels when asked. nil while the module is
    /// stopped or without access.
    func reminders(on day: Date, calendar: Calendar = .current) async -> [ReminderItem]? {
        guard onChange != nil, access == .granted else { return nil }
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return nil }
        let predicate = eventStore.predicateForIncompleteReminders(withDueDateStarting: start, ending: end, calendars: nil)
        return await withCheckedContinuation { continuation in
            // EventKit answers on its own queue: the closure must not be isolated to the main actor.
            eventStore.fetchReminders(matching: predicate) { @Sendable found in
                let items = (found ?? []).map { reminder in
                    let components = reminder.dueDateComponents
                    return ReminderItem(id: reminder.calendarItemIdentifier, title: reminder.title ?? loc("Rappel"),
                                        due: components.flatMap { calendar.date(from: $0) }, hasTime: components?.hour != nil)
                }
                continuation.resume(returning: items)
            }
        }
    }

    /// Reads the incomplete reminders due up to the end of today. Does nothing without the permission.
    private func fetchReminders() {
        guard access == .granted else {
            if !reminders.isEmpty { reminders = []; onChange?() }
            return
        }
        let calendar = Calendar.current
        let endOfToday = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date()))
        let predicate = eventStore.predicateForIncompleteReminders(withDueDateStarting: nil, ending: endOfToday, calendars: nil)
        // EventKit answers on its own queue: the closure must not be isolated to the main actor,
        // or Swift stops the app the moment it runs
        eventStore.fetchReminders(matching: predicate) { @Sendable [weak self] found in
            let items = (found ?? []).map { reminder in
                let components = reminder.dueDateComponents
                return ReminderItem(id: reminder.calendarItemIdentifier,
                                    title: reminder.title ?? loc("Rappel"),
                                    due: components.flatMap { calendar.date(from: $0) },
                                    hasTime: components?.hour != nil)
            }
            Task { @MainActor in
                guard let self, self.onChange != nil, items != self.reminders else { return }
                self.reminders = items
                self.onChange?()
            }
        }
    }
}
