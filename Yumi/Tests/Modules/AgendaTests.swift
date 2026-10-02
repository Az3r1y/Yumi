import Testing
import Foundation

@Suite struct AgendaSummaryTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        return calendar
    }
    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }
    private func event(_ title: String, _ start: Date, minutes: Double = 30, allDay: Bool = false,
                       location: String = "", join: String? = nil) -> AgendaEvent {
        AgendaEvent(id: title, title: title, start: start, end: start.addingTimeInterval(minutes * 60),
                    isAllDay: allDay, location: location, joinURL: join.flatMap(URL.init(string:)))
    }
    private func snapshot(_ events: [AgendaEvent], access: PermissionState = .granted, now: Date) -> ModuleSnapshot {
        AgendaSummary.snapshot(events: events, access: access, now: now, calendar: calendar)
    }

    @Test func withoutPermissionItOffersToAsk() {
        let pending = snapshot([], access: .notDetermined, now: date(1, 10))
        #expect(pending.primaryAction == "Autoriser")
        #expect(pending.secondaryAction == nil)
        #expect(snapshot([], access: .denied, now: date(1, 10)).primaryAction == "Ouvrir les réglages")
    }

    @Test func aFreeDay() {
        let free = snapshot([event("Anniversaire", date(1, 0), minutes: 1440, allDay: true)], now: date(1, 10))
        #expect(free.status == "libre")
        #expect(free.title == "Rien de prévu.")
        #expect(free.primaryAction == "Voir la journée")
    }

    @Test func theNextEventWithinTheHour() {
        let result = snapshot([event("Déjeuner", date(1, 16)),
                               event("Point produit", date(1, 14, 30), join: "https://meet.google.com/abc-defg-hij")],
                              now: date(1, 14, 18))
        #expect(result.status == "14:30")
        #expect(result.title == "Point produit dans douze minutes.")
        #expect(result.subtitle == "14:30 à 15:00, en visio.")
        #expect(result.primaryAction == "Rejoindre")
        #expect(result.secondaryAction == "Voir la journée")
        #expect(!result.needsAttention)
    }

    @Test func aLaterEventShowsItsTimeAndPlace() {
        let result = snapshot([event("Dentiste", date(1, 17), minutes: 45, location: "12 rue des Lilas\nParis")], now: date(1, 9))
        #expect(result.title == "Dentiste à 17:00.")
        #expect(result.subtitle == "17:00 à 17:45, 12 rue des Lilas.")
        #expect(result.primaryAction == "Ouvrir")
    }

    @Test func anEventAboutToStartAsksForAttention() {
        let events = [event("Point produit", date(1, 14, 30))]
        #expect(snapshot(events, now: date(1, 14, 26)).needsAttention)
        #expect(snapshot(events, now: date(1, 14, 31)).needsAttention)
        #expect(!snapshot(events, now: date(1, 14, 40)).needsAttention)
    }

    @Test func anEventInProgress() {
        let result = snapshot([event("Atelier", date(1, 10), minutes: 120)], now: date(1, 11))
        #expect(result.status == "en cours")
        #expect(result.title == "Atelier a commencé.")
        #expect(result.subtitle == "10:00 à 12:00.")
    }

    @Test func theNextEventWinsOverTheEndingOneWhenItIsClose() {
        let events = [event("Atelier", date(1, 10), minutes: 120), event("Point produit", date(1, 11, 30))]
        #expect(AgendaSummary.featured(events, now: date(1, 11))?.title == "Atelier")
        #expect(AgendaSummary.featured(events, now: date(1, 11, 27))?.title == "Point produit")
        #expect(AgendaSummary.featured(events, now: date(1, 13)) == nil)
    }

    @Test func tomorrowIsAnnouncedWhenTodayIsOver() {
        let result = snapshot([event("Stand-up", date(2, 9, 30), minutes: 15)], now: date(1, 19))
        #expect(result.status == "libre")
        #expect(result.title == "Demain, Stand-up.")
        #expect(result.subtitle == "Plus rien aujourd'hui, demain 9:30 à 9:45.")
        #expect(!result.needsAttention)
    }

    @Test func meetingLinks() {
        #expect(AgendaSummary.joinURL(in: [nil, "Salle Lune", "Lien : https://us02web.zoom.us/j/123?pwd=x merci"])?.host == "us02web.zoom.us")
        #expect(AgendaSummary.joinURL(in: ["https://example.com/agenda"]) == nil)
        #expect(AgendaSummary.joinURL(in: ["https://notzoom.us.evil.example/j/1"]) == nil)
    }
}
