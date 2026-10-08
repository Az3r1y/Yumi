import Foundation

/// Which calendars of the Mac Yumi shows, and the one where he creates events. Chosen in
/// Réglages > Modules > Agenda. Calendars are kept by their EventKit identifier.
enum AgendaCalendars {
    /// The calendars hidden from the module and from `get_today`. Empty: every calendar shows,
    /// and a calendar added later shows too.
    static let hiddenKey = "agendaHiddenCalendars"
    /// Where `add_event` writes. Absent: the default calendar of the Calendar app.
    static let targetKey = "agendaTargetCalendar"

    static func hidden(_ defaults: UserDefaults = .standard) -> Set<String> {
        Set(defaults.stringArray(forKey: hiddenKey) ?? [])
    }

    static func setShown(_ id: String, _ shown: Bool, _ defaults: UserDefaults = .standard) {
        var hidden = hidden(defaults)
        if shown { hidden.remove(id) } else { hidden.insert(id) }
        defaults.set(hidden.sorted(), forKey: hiddenKey)
    }

    /// The identifiers to read among `all`. nil means all of them (EventKit's own "no filter").
    /// Empty when every calendar is hidden: the caller then reads nothing (EventKit would read
    /// an empty list as all of them).
    static func shown(among all: [String], _ defaults: UserDefaults = .standard) -> [String]? {
        let hidden = hidden(defaults)
        guard all.contains(where: hidden.contains) else { return nil }
        return all.filter { !hidden.contains($0) }
    }

    static func target(_ defaults: UserDefaults = .standard) -> String? {
        defaults.string(forKey: targetKey)
    }

    static func setTarget(_ id: String?, _ defaults: UserDefaults = .standard) {
        if let id { defaults.set(id, forKey: targetKey) } else { defaults.removeObject(forKey: targetKey) }
    }
}

extension Notification.Name {
    /// Posted by the settings when the calendars shown change.
    static let agendaCalendarsChanged = AppIdentity.notification("agendaCalendarsChanged")
}
