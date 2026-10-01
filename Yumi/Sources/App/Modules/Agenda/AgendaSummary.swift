import Foundation

/// One calendar event, reduced to what the island shows.
struct AgendaEvent: Equatable, Sendable {
    let id: String
    var title: String
    var start: Date
    var end: Date
    var isAllDay: Bool
    var location: String
    /// Link to join the meeting, when the event carries one.
    var joinURL: URL?
}

enum AgendaSummary {
    /// An event starting within this delay asks for attention.
    private static let soon: TimeInterval = 5 * 60

    /// Hosts of the video meeting services recognised in an event.
    private static let meetingHosts = ["zoom.us", "meet.google.com", "teams.microsoft.com", "teams.live.com",
                                       "webex.com", "whereby.com", "facetime.apple.com", "meet.jit.si", "gotomeet.me"]

    /// The first video meeting link found in the texts of an event (URL field, location, notes).
    static func joinURL(in texts: [String?]) -> URL? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        for text in texts.compactMap({ $0 }) {
            let range = NSRange(text.startIndex..., in: text)
            for match in detector.matches(in: text, range: range) {
                guard let url = match.url, let host = url.host?.lowercased() else { continue }
                if meetingHosts.contains(where: { host == $0 || host.hasSuffix(".\($0)") }) { return url }
            }
        }
        return nil
    }

    /// The event to show: the one in progress, otherwise the next one. All-day events are left out.
    static func featured(_ events: [AgendaEvent], now: Date) -> AgendaEvent? {
        let timed = events.filter { !$0.isAllDay && $0.end > now }.sorted { $0.start < $1.start }
        // An event about to start matters more than one that is ending.
        if let next = timed.first(where: { $0.start > now }), next.start.timeIntervalSince(now) <= soon { return next }
        return timed.first
    }

    static func snapshot(events: [AgendaEvent], access: PermissionState, now: Date,
                         calendar: Calendar = .current) -> ModuleSnapshot {
        var snapshot = ModuleSnapshot(id: "agenda", name: "Agenda", colorHex: "#5B8CFF", status: "libre",
                                      title: "Rien de prévu", subtitle: "Ta journée est libre",
                                      primaryAction: "Voir la journée", secondaryAction: nil)
        switch access {
        case .notDetermined:
            snapshot.status = "à brancher"
            snapshot.title = "Agenda pas encore branché"
            snapshot.subtitle = "Autorise Yumi à lire ton calendrier"
            snapshot.primaryAction = "Autoriser"
            return snapshot
        case .denied:
            snapshot.status = "bloqué"
            snapshot.title = "Agenda bloqué"
            snapshot.subtitle = "L'accès au calendrier est refusé dans Réglages Système"
            snapshot.primaryAction = "Ouvrir les réglages"
            return snapshot
        case .granted:
            break
        }

        guard let event = featured(events, now: now) else { return snapshot }

        let startsToday = calendar.isDate(event.start, inSameDayAs: now)
        let clock = FrenchText.clock(event.start, calendar: calendar)
        if event.start <= now {
            snapshot.status = "en cours"
            snapshot.title = "\(event.title) en cours"
        } else if !startsToday {
            snapshot.title = "Demain : \(event.title)"
            snapshot.subtitle = "Plus rien aujourd'hui"
        } else if event.start.timeIntervalSince(now) < 3600 {
            snapshot.status = clock
            snapshot.title = "\(event.title) dans \(FrenchText.minutes(event.start.timeIntervalSince(now)))"
        } else {
            snapshot.status = clock
            snapshot.title = "\(event.title) à \(clock)"
        }

        var details = ["\(clock) à \(FrenchText.clock(event.end, calendar: calendar))"]
        if event.joinURL != nil { details.append("en visio") }
        if !event.location.isEmpty && joinURL(in: [event.location]) == nil {
            details.append(event.location.split(whereSeparator: \.isNewline).first.map(String.init) ?? event.location)
        }
        if startsToday || event.start <= now {
            snapshot.subtitle = details.joined(separator: ", ")
        } else {
            snapshot.subtitle += ", demain " + details.joined(separator: ", ")
        }

        // The folded island announces today's events only: tomorrow is not happening now.
        // The button joins the featured event, so it is only offered when that is the one announced.
        if startsToday || event.start <= now {
            let upcoming = events.filter { !$0.isAllDay && $0.start > now && calendar.isDate($0.start, inSameDayAs: now) }
                .min { $0.start < $1.start }
            let announced = upcoming ?? event
            let join = ModuleControl(id: ModuleAction.primary.rawValue, symbol: "video.fill", label: "Rejoindre")
            let text = announced.start <= now ? "En cours : \(announced.title)"
                                              : "\(FrenchText.clock(announced.start, calendar: calendar)) \(announced.title)"
            snapshot.live = ModuleLive(text: text, priority: ModuleLivePriority.ambient,
                                       controls: announced == event && event.joinURL != nil ? [join] : [])
        }

        snapshot.primaryAction = event.joinURL != nil ? "Rejoindre" : "Ouvrir"
        snapshot.secondaryAction = "Voir la journée"
        let delay = event.start.timeIntervalSince(now)
        snapshot.needsAttention = delay <= soon && delay > -120
        return snapshot
    }
}
