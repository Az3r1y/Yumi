import Testing
import Foundation

/// The calendars shown and the one where events are created (Réglages > Modules > Agenda).
@Suite struct AgendaCalendarsTests {
    private func defaults() -> UserDefaults { UserDefaults(suiteName: "agenda-\(UUID().uuidString)")! }

    @Test func everyCalendarByDefault() {
        let store = defaults()
        #expect(AgendaCalendars.shown(among: ["a", "b"], store) == nil)
        #expect(AgendaCalendars.target(store) == nil)
    }

    @Test func hidingAndShowingAgain() {
        let store = defaults()
        AgendaCalendars.setShown("b", false, store)
        #expect(AgendaCalendars.shown(among: ["a", "b", "c"], store) == ["a", "c"])
        // A calendar added later shows.
        #expect(AgendaCalendars.shown(among: ["a", "b", "d"], store) == ["a", "d"])
        AgendaCalendars.setShown("a", false, store)
        AgendaCalendars.setShown("d", false, store)
        #expect(AgendaCalendars.shown(among: ["a", "b", "d"], store) == [])
        AgendaCalendars.setShown("b", true, store)
        #expect(AgendaCalendars.shown(among: ["a", "b", "d"], store) == ["b"])
    }

    @Test func target() {
        let store = defaults()
        AgendaCalendars.setTarget("work", store)
        #expect(AgendaCalendars.target(store) == "work")
        AgendaCalendars.setTarget(nil, store)
        #expect(AgendaCalendars.target(store) == nil)
    }
}
