import Foundation

/// The modules as the agent's tools see them: the Focus timer, and what the day holds. Reads
/// the modules on the main actor when a tool asks, never before; holds nothing itself.
@MainActor
final class ModuleBridge: FocusControl, TodaySource, MusicControl {
    private weak var focus: FocusModule?
    private weak var agenda: AgendaModule?
    private weak var notes: NotesModule?
    private weak var weather: WeatherModule?
    private weak var notion: NotionModule?
    private weak var music: MusicModule?

    init(focus: FocusModule, agenda: AgendaModule, notes: NotesModule, weather: WeatherModule, notion: NotionModule? = nil,
         music: MusicModule? = nil) {
        self.music = music
        self.focus = focus
        self.agenda = agenda
        self.notes = notes
        self.weather = weather
        self.notion = notion
    }

    func status() async -> FocusStatus { focus?.status ?? .off }

    func start(minutes: Int) async -> Bool { focus?.startSession(minutes: minutes) ?? false }

    func perform(_ command: MusicCommand) async -> String? {
        guard let music else { return loc("je n'ai pas de lecteur de musique sous la main") }
        return music.control(command)
    }

    func facts(now: Date) async -> TodayFacts {
        var noAccess: [TodayFacts.Source] = []
        if agenda?.runsWithoutAccess == true { noAccess.append(.agenda) }
        if notes?.runsWithoutAccess == true { noAccess.append(.reminders) }
        return TodayFacts(events: agenda?.upcomingTodayIfRunning,
                          reminders: notes?.remindersDue(on: now),
                          weather: weather?.currentReport,
                          noAccess: noAccess,
                          dayEvents: agenda?.events(on: now),
                          notionTasks: await notion?.tasks(on: now))
    }

    func facts(on day: Date, now: Date) async -> TodayFacts {
        var noAccess: [TodayFacts.Source] = []
        if agenda?.runsWithoutAccess == true { noAccess.append(.agenda) }
        if notes?.runsWithoutAccess == true { noAccess.append(.reminders) }
        let events = agenda?.events(on: day).map { $0.filter { !$0.isAllDay } }
        return TodayFacts(events: events, reminders: await notes?.reminders(on: day), weather: nil,
                          noAccess: noAccess, dayEvents: events, notionTasks: await notion?.tasks(on: day))
    }
}
