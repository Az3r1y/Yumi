import Foundation

/// What the modules already know about today. nil means the module is off or has no access:
/// it is left out, not reported as empty. A missing macOS access is said (`noAccess`): the
/// person asked about their day, they must know a part of it could not be read.
struct TodayFacts: Equatable, Sendable {
    enum Source: Equatable, Sendable { case agenda, reminders }

    /// Today's appointments still to come, the all-day ones aside, soonest first.
    var events: [AgendaEvent]?
    /// Incomplete reminders due today.
    var reminders: [ReminderItem]?
    var weather: WeatherReport?
    /// Modules that are on but that macOS does not let Yumi read.
    var noAccess: [Source] = []
    /// Every timed appointment of the day, ended ones included, to work out the free time.
    /// nil: the same as `events`.
    var dayEvents: [AgendaEvent]? = nil
}

/// Reads `TodayFacts` from the modules, on demand. Implemented by the modules' bridge.
protocol TodaySource: Sendable {
    func facts(now: Date) async -> TodayFacts
    /// The facts of another day: its appointments and the reminders due that day. No weather.
    func facts(on day: Date, now: Date) async -> TodayFacts
}

extension TodaySource {
    func facts(on day: Date, now: Date) async -> TodayFacts { await facts(now: now) }
}

/// "What do I have today, tomorrow, on Thursday?": the appointments and reminders of one day,
/// the weather for today, and the free time when asked. Reads the person's calendar and
/// reminders on this Mac, changes nothing, sends nothing.
struct GetTodayTool: Tool {
    /// How far ahead a day can be read.
    static let maxDaysAhead = 14
    /// The free time is counted within these hours.
    static let dayStartHour = 8
    static let dayEndHour = 20

    var source: any TodaySource
    var calendar: Calendar = .current

    var descriptor: ToolDescriptor {
        ToolDescriptor(
            id: "get_today",
            name: "Sum up a day",
            description: "Sums up one day of the person in one or two sentences: its appointments, the reminders due that day, the weather for today, and the free time between 8:00 and 20:00 when asked. Use it for every question about the person's calendar, reminders or free time, today or up to 14 days ahead.",
            inputSchema: ToolInputSchema(fields: [
                .init(name: "date", type: .string, required: false,
                      description: "YYYY-MM-DD worked out from <now> (tomorrow, Thursday…); omit for today; 14 days ahead at most"),
                .init(name: "free_time", type: .bool, required: false,
                      description: "true when the person asks how much free time or which free slots they have"),
            ]),
            risk: .read,
            outputKeys: ["reply"])
    }

    func check(_ arguments: ToolArguments) async -> String? {
        do {
            _ = try day(arguments, now: Date())
            return nil
        } catch {
            return error.reason
        }
    }

    /// The start of the day asked, today when none. Never in the past, never too far ahead.
    func day(_ arguments: ToolArguments, now: Date) throws(ToolError) -> Date {
        let today = calendar.startOfDay(for: now)
        guard let value = arguments["date"] else { return today }
        guard case .string(let raw) = value, let text = raw.nonEmptyTrimmed else { return today }
        let parts = text.split(separator: "-").map { Int($0) }
        guard parts.count == 3, let year = parts[0], let month = parts[1], let dayNumber = parts[2],
              let date = calendar.date(from: DateComponents(year: year, month: month, day: dayNumber)),
              calendar.dateComponents([.year, .month, .day], from: date) == DateComponents(year: year, month: month, day: dayNumber) else {
            throw .invalidInput("« \(text) » n'est pas une date que je comprends")
        }
        let offset = calendar.dateComponents([.day], from: today, to: date).day ?? 0
        if offset < 0 { throw .invalidInput("c'est un jour déjà passé, je ne regarde que les jours à venir") }
        if offset > Self.maxDaysAhead { throw .invalidInput("je ne regarde pas plus loin que \(FrenchText.spelled(Self.maxDaysAhead)) jours") }
        return date
    }

    /// Yumi reading its own modules: what the island already shows.
    func action(for arguments: ToolArguments) -> ToolAction? {
        ToolAction(kind: .read, resources: [ResourceRef(.yumi, "modules")], reversible: true)
    }

    func execute(_ arguments: ToolArguments, in context: ToolContext) async throws -> ToolOutput {
        let day = try day(arguments, now: context.now)
        let isToday = calendar.isDate(day, inSameDayAs: context.now)
        let facts = isToday ? await source.facts(now: context.now) : await source.facts(on: day, now: context.now)
        try Task.checkCancellation()
        let wantsFree = arguments["free_time"] == .bool(true)
        let reply = TodayPhrase.reply(facts, day: day, now: context.now, freeTime: wantsFree, calendar: calendar)
        return ToolOutput(summary: reply, values: ["reply": .string(reply)])
    }

    /// The answer is said, not listed: one or two sentences on one line.
    func verify(_ arguments: ToolArguments, output: ToolOutput) async -> String? {
        guard case .string(let reply)? = output.values["reply"], !reply.isEmpty else { return "la réponse est vide" }
        if reply.contains(where: \.isNewline) || reply.hasPrefix("-") || reply.contains("•") { return "la réponse est une liste" }
        // A sentence ends with a stop followed by a space or the end: "v1.2" is not two.
        let ends = reply.matches(of: /[.!?](\s|$)/).count
        return ends > 2 ? "la réponse fait plus de deux phrases" : nil
    }
}

/// The day said in Yumi's voice: one or two sentences, never a list.
enum TodayPhrase {
    static func reply(_ facts: TodayFacts, now: Date, calendar: Calendar = .current) -> String {
        reply(facts, day: calendar.startOfDay(for: now), now: now, freeTime: false, calendar: calendar)
    }

    static func reply(_ facts: TodayFacts, day: Date, now: Date, freeTime: Bool, calendar: Calendar = .current) -> String {
        let isToday = calendar.isDate(day, inSameDayAs: now)
        let label = isToday ? "aujourd'hui" : dayLabel(day, now: now, calendar: calendar)
        let first = [agenda(facts.events, label: label, isToday: isToday, calendar: calendar),
                     reminders(facts.reminders, label: isToday ? nil : label)].compactMap { $0 }
        var sentences: [String] = []
        if !first.isEmpty { sentences.append(FrenchText.sentenceStart(first.joined(separator: ", et ")) + ".") }
        if freeTime, let free = free(facts.dayEvents ?? facts.events, day: day, now: now, calendar: calendar) {
            sentences.append(FrenchText.sentenceStart(free) + ".")
        } else if isToday, let weather = facts.weather {
            sentences.append("Dehors, \(Int(weather.temperature.rounded()))° et \(WeatherSummary.sky(weather.code)).")
        }
        if let missing = missing(facts.noAccess) {
            // Still two sentences at most: the gap joins the last one when there are already two.
            if sentences.count < 2 {
                sentences.append(FrenchText.sentenceStart(missing) + ".")
            } else {
                sentences[sentences.count - 1] = String(sentences[sentences.count - 1].dropLast()) + ", mais " + missing + "."
            }
        }
        if sentences.isEmpty {
            return "Je ne vois ni ton agenda, ni tes rappels, ni la météo. Active-les dans mes réglages et je te dirai."
        }
        return sentences.joined(separator: " ")
    }

    /// "je n'ai pas accès à ton agenda ni à tes rappels (Réglages Système, Confidentialité et sécurité)".
    private static func missing(_ sources: [TodayFacts.Source]) -> String? {
        let names = [TodayFacts.Source.agenda, .reminders].filter(sources.contains).map { $0 == .agenda ? "à ton agenda" : "à tes rappels" }
        guard !names.isEmpty else { return nil }
        return "je n'ai pas accès \(names.joined(separator: " ni ")), autorise Yumi dans Réglages Système, Confidentialité et sécurité"
    }

    private static func agenda(_ events: [AgendaEvent]?, label: String, isToday: Bool, calendar: Calendar) -> String? {
        guard let events else { return nil }
        guard let next = events.first else { return isToday ? "plus aucun rendez-vous aujourd'hui" : "aucun rendez-vous \(label)" }
        let what = "\(oneLine(next.title)) à \(FrenchText.clock(next.start, calendar: calendar))"
        if isToday {
            if events.count == 1 { return "encore un rendez-vous aujourd'hui : \(what)" }
            return "encore \(FrenchText.spelled(events.count)) rendez-vous aujourd'hui, le prochain c'est \(what)"
        }
        if events.count == 1 { return "\(label), un rendez-vous : \(what)" }
        return "\(label), \(FrenchText.spelled(events.count)) rendez-vous, le premier c'est \(what)"
    }

    private static func reminders(_ reminders: [ReminderItem]?, label: String?) -> String? {
        guard let reminders else { return nil }
        let when = label.map { " pour \($0)" } ?? ""
        guard let first = NotesSummary.ordered(reminders).first else { return "aucun rappel\(when)" }
        if reminders.count == 1 { return "un rappel\(when) : \(oneLine(first.title))" }
        return "\(FrenchText.spelledCount(reminders.count, "rappel", "rappels"))\(when), dont \(oneLine(first.title))"
    }

    /// "demain", "après-demain", "jeudi 9 octobre".
    static func dayLabel(_ day: Date, now: Date, calendar: Calendar) -> String {
        let offset = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: day)).day ?? 0
        if offset == 1 { return "demain" }
        if offset == 2 { return "après-demain" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "EEEE d MMMM"
        return formatter.string(from: day)
    }

    /// "du temps libre entre 8 h et 20 h : 6 h 30, le plus long créneau de 14 h à 17 h". nil when
    /// the calendar cannot be read.
    static func free(_ events: [AgendaEvent]?, day: Date, now: Date, calendar: Calendar) -> String? {
        guard let events else { return nil }
        let slots = FreeTime.slots(events: events, day: day, now: now, calendar: calendar)
        let total = slots.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) }
        let window = "entre \(GetTodayTool.dayStartHour) h et \(GetTodayTool.dayEndHour) h"
        guard total >= 15 * 60, let longest = slots.max(by: { $0.end.timeIntervalSince($0.start) < $1.end.timeIntervalSince($1.start) }) else {
            return "plus de temps libre \(window)"
        }
        return "du temps libre \(window) : \(FreeTime.duration(total)), le plus long créneau de \(FreeTime.clock(longest.start, calendar)) à \(FreeTime.clock(longest.end, calendar))"
    }

    private static func oneLine(_ text: String) -> String {
        ApprovalRequest.oneLine(text, limit: 60) ?? "sans titre"
    }
}

/// The free slots of a day between 8:00 and 20:00, around its timed appointments.
enum FreeTime {
    struct Slot: Equatable { var start: Date; var end: Date }

    /// Gaps of 15 minutes or more. Today starts from now; all-day events take no time.
    static func slots(events: [AgendaEvent], day: Date, now: Date, calendar: Calendar) -> [Slot] {
        let startOfDay = calendar.startOfDay(for: day)
        guard let open = calendar.date(byAdding: .hour, value: GetTodayTool.dayStartHour, to: startOfDay),
              let close = calendar.date(byAdding: .hour, value: GetTodayTool.dayEndHour, to: startOfDay) else { return [] }
        var cursor = max(open, calendar.isDate(day, inSameDayAs: now) ? now : open)
        var slots: [Slot] = []
        for event in events.filter({ !$0.isAllDay && $0.end > open && $0.start < close }).sorted(by: { $0.start < $1.start }) {
            if event.start > cursor, event.start.timeIntervalSince(cursor) >= 15 * 60 {
                slots.append(Slot(start: cursor, end: min(event.start, close)))
            }
            cursor = max(cursor, event.end)
        }
        if close.timeIntervalSince(cursor) >= 15 * 60 { slots.append(Slot(start: cursor, end: close)) }
        return slots
    }

    /// "6 h 30", "45 min", "2 h".
    static func duration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        let hours = minutes / 60, rest = minutes % 60
        if hours == 0 { return "\(rest) min" }
        return rest == 0 ? "\(hours) h" : String(format: "%d h %02d", hours, rest)
    }

    /// "14 h", "14 h 30".
    static func clock(_ date: Date, _ calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let minute = parts.minute ?? 0
        return minute == 0 ? "\(parts.hour ?? 0) h" : String(format: "%d h %02d", parts.hour ?? 0, minute)
    }
}
