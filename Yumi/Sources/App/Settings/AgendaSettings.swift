import SwiftUI
import EventKit

/// Settings, Modules, Agenda: the calendars Yumi shows, the one where he creates events, and
/// how to see Notion Calendar's appointments through the Calendar app.
struct AgendaSettingsSection: View {
    private struct Entry: Identifiable {
        let id: String
        var title: String
        var account: String
        var writable: Bool
    }

    @State private var calendars: [Entry] = []
    @State private var hidden = AgendaCalendars.hidden()
    @State private var target = AgendaCalendars.target() ?? ""
    @State private var defaultTitle: String?
    @State private var access = EKEventStore.authorizationStatus(for: .event)

    var body: some View {
        Section {
            if access != .fullAccess {
                SettingsHelp(loc("Autorise d'abord Yumi à lire ton calendrier : ouvre le module Agenda dans l'île, ou Réglages Système, Confidentialité et sécurité, Calendriers."))
            } else {
                ForEach(calendars) { entry in
                    Toggle(isOn: Binding(get: { !hidden.contains(entry.id) }, set: { shown in
                        AgendaCalendars.setShown(entry.id, shown)
                        hidden = AgendaCalendars.hidden()
                        NotificationCenter.default.post(name: .agendaCalendarsChanged, object: nil)
                    })) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(verbatim: entry.title)
                            Text(verbatim: entry.account).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Picker(loc("Créer les événements dans"), selection: Binding(get: { target }, set: { value in
                    target = value
                    AgendaCalendars.setTarget(value.isEmpty ? nil : value)
                })) {
                    Text(defaultTitle.map { loc("Calendrier par défaut (\($0))") } ?? loc("Calendrier par défaut")).tag("")
                    ForEach(calendars.filter(\.writable)) { entry in
                        Text(verbatim: "\(entry.title) · \(entry.account)").tag(entry.id)
                    }
                }
            }
        } header: {
            Text("Agenda")
        } footer: {
            SettingsHelp(loc("Tu utilises Notion Calendar ? Il n'a pas d'API publique : ajoute le même compte Google ou iCloud dans Calendrier (Réglages Système > Comptes Internet), Yumi verra et créera les mêmes rendez-vous."))
        }
        .task { load() }
    }

    private func load() {
        access = EKEventStore.authorizationStatus(for: .event)
        guard access == .fullAccess else { return }
        let store = EKEventStore()
        defaultTitle = store.defaultCalendarForNewEvents?.title
        calendars = store.calendars(for: .event)
            .map { calendar in
                Entry(id: calendar.calendarIdentifier, title: calendar.title, account: calendar.source?.title ?? "",
                      writable: calendar.allowsContentModifications && !calendar.isSubscribed
                        && calendar.type != .subscription && calendar.type != .birthday)
            }
            .sorted { ($0.account, $0.title) < ($1.account, $1.title) }
        // A chosen calendar that no longer exists: back to the default one.
        if !target.isEmpty, !calendars.contains(where: { $0.id == target && $0.writable }) { target = "" }
    }
}
