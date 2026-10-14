import Foundation

// MARK: - Screen time
// The idea comes from temps-ecran (github.com/livio-emilio/temps-ecran, MIT): once a minute,
// decide whether the person is really in front of the Mac, and add that minute to the day.
// Everything here is pure: the module gives the sample and the time.

/// What the Mac says at one look.
struct ScreenSample: Equatable, Sendable {
    /// Seconds since the last key press, click or mouse move.
    var idle: TimeInterval
    /// The session is locked.
    var locked: Bool
    /// The main display is on (dimmed counts as on).
    var displayOn: Bool
    /// A program keeps the display awake: a video call, a film, a presentation.
    var watching: Bool
}

/// Whether a minute counts.
enum ScreenActivity {
    /// Without input for this long, the person is not there any more, unless they watch something.
    static let idleLimit: TimeInterval = 5 * 60
    /// Without input for this long, nothing counts, not even a film: the Mac was left open.
    static let absoluteLimit: TimeInterval = 2 * 3600

    static func counts(_ sample: ScreenSample) -> Bool {
        if sample.locked || sample.idle > absoluteLimit { return false }
        if sample.displayOn, sample.watching { return true }
        return sample.idle <= idleLimit
    }
}

/// Follows the minutes from one look to the next, to see a real break end.
struct ActivityStreak: Equatable, Sendable {
    private var wasActive: Bool?

    /// True when the person is back after at least one minute that did not count, that is after
    /// five minutes or more without touching the Mac (or a locked session).
    mutating func observe(active: Bool) -> Bool {
        defer { wasActive = active }
        return active && wasActive == false
    }
}

/// The minutes counted, by day and by hour. Saved as JSON in Yumi's folder.
struct ScreenTimeLog: Codable, Equatable, Sendable {
    /// Days kept in the daily history, and in the detail by hour.
    static let keptDays = 90
    static let keptHourDays = 14

    /// Minutes by day, "2026-10-14".
    private(set) var days: [String: Int] = [:]
    /// Minutes by hour (24 values) by day.
    private(set) var hours: [String: [Int]] = [:]
    /// The last threshold step already told, by day, in minutes.
    private(set) var told: [String: Int] = [:]

    init() {}

    /// Counts one minute at `date`.
    mutating func add(minutes: Int = 1, at date: Date, calendar: Calendar = .current) {
        let day = Self.day(date, calendar)
        let hour = calendar.component(.hour, from: date)
        days[day, default: 0] += minutes
        var byHour = hours[day] ?? Array(repeating: 0, count: 24)
        if byHour.count != 24 { byHour = Array(repeating: 0, count: 24) }
        byHour[hour] += minutes
        hours[day] = byHour
    }

    /// Forgets what is older than the history keeps.
    mutating func prune(now: Date, calendar: Calendar = .current) {
        let oldestDay = Self.day(calendar.date(byAdding: .day, value: -(Self.keptDays - 1), to: now) ?? now, calendar)
        let oldestHour = Self.day(calendar.date(byAdding: .day, value: -(Self.keptHourDays - 1), to: now) ?? now, calendar)
        days = days.filter { $0.key >= oldestDay }
        hours = hours.filter { $0.key >= oldestHour }
        told = told.filter { $0.key >= oldestHour }
    }

    func minutes(on date: Date, calendar: Calendar = .current) -> Int { days[Self.day(date, calendar)] ?? 0 }

    /// Today's minutes, hour by hour (24 values).
    func hours(on date: Date, calendar: Calendar = .current) -> [Int] {
        hours[Self.day(date, calendar)] ?? Array(repeating: 0, count: 24)
    }

    /// The last `count` days, oldest first, today last, with zero for a day without the Mac.
    func lastDays(_ count: Int, now: Date, calendar: Calendar = .current) -> [(date: Date, minutes: Int)] {
        (0..<count).reversed().compactMap { back in
            calendar.date(byAdding: .day, value: -back, to: now).map { ($0, minutes(on: $0, calendar: calendar)) }
        }
    }

    /// The minutes of the days used among the last `count` (a day without the Mac is left out,
    /// as it says nothing about a day of work).
    func usedDays(_ count: Int, now: Date, calendar: Calendar = .current) -> [Int] {
        lastDays(count, now: now, calendar: calendar).map(\.minutes).filter { $0 > 0 }
    }

    /// The threshold step reached today and not told yet: the threshold, then every hour above it.
    /// Each step is returned once.
    mutating func newStep(threshold: Int, now: Date, calendar: Calendar = .current) -> Int? {
        let total = minutes(on: now, calendar: calendar)
        guard threshold > 0, total >= threshold else { return nil }
        let step = threshold + (total - threshold) / 60 * 60
        let day = Self.day(now, calendar)
        guard step > (told[day] ?? 0) else { return nil }
        told[day] = step
        return step
    }

    static func day(_ date: Date, _ calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}

/// Average, median and 75th percentile of a few days.
enum ScreenTimeStats {
    static func average(_ values: [Int]) -> Int? {
        values.isEmpty ? nil : values.reduce(0, +) / values.count
    }

    static func median(_ values: [Int]) -> Int? {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return nil }
        let middle = sorted.count / 2
        return sorted.count % 2 == 0 ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }

    /// Nearest rank: the smallest value with at least three quarters of the days at or below it.
    static func percentile75(_ values: [Int]) -> Int? {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return nil }
        let rank = (sorted.count * 75 + 99) / 100
        return sorted[min(max(rank, 1), sorted.count) - 1]
    }
}

/// What the island shows.
enum ScreenTimeSummary {
    static let moduleID = "screen-time"
    static let calm = "#5ED3C3"
    static let close = "#FFB547"
    static let over = "#FF5D6C"
    /// The daily thresholds offered, in hours, and the one chosen until the person picks another.
    static let thresholds = [4, 6, 8, 10, 12]
    static let defaultThreshold = 8

    /// "42 min", "5 h 12".
    static func time(_ minutes: Int) -> String {
        minutes < 60 ? loc("\(minutes) min") : String(format: "%d h %02d", minutes / 60, minutes % 60)
    }

    /// "8 h".
    static func hours(_ minutes: Int) -> String {
        minutes % 60 == 0 ? loc("\(minutes / 60) h") : time(minutes)
    }

    /// The colour of a day against the threshold: calm, close (80 %), over.
    static func color(minutes: Int, threshold: Int) -> String {
        guard threshold > 0 else { return calm }
        if minutes >= threshold { return over }
        return minutes * 100 >= threshold * 80 ? close : calm
    }

    static func snapshot(_ log: ScreenTimeLog, threshold: Int, now: Date, calendar: Calendar = .current) -> ModuleSnapshot {
        let today = log.minutes(on: now, calendar: calendar)
        var snapshot = ModuleSnapshot(id: moduleID, name: loc("Temps d'écran"), colorHex: color(minutes: today, threshold: threshold),
                                      status: time(today), title: "", subtitle: "",
                                      primaryAction: loc("Ouvrir les réglages"), secondaryAction: nil)
        if today == 0 {
            snapshot.title = loc("Pas encore d'écran aujourd'hui.")
        } else {
            snapshot.title = loc("\(time(today)) devant l'écran aujourd'hui.")
        }
        if today >= threshold {
            snapshot.subtitle = loc("\(time(today - threshold)) au-delà de ton seuil de \(hours(threshold)).")
        } else {
            snapshot.subtitle = loc("Encore \(time(threshold - today)) avant ton seuil de \(hours(threshold)).")
        }
        snapshot.progress = ModuleProgress(fraction: min(1, Double(today) / Double(max(threshold, 1))),
                                           leading: time(today), trailing: hours(threshold))

        // Today, hour by hour, from the first hour used to the current one
        let byHour = log.hours(on: now, calendar: calendar)
        let current = calendar.component(.hour, from: now)
        if let first = byHour.firstIndex(where: { $0 > 0 }) {
            snapshot.pages["hours"] = (first...max(first, current)).map { hour in
                ModuleRow(id: "h\(hour)", title: "\(hour)", detail: "\(byHour[hour])", state: .neutral, label: time(byHour[hour]))
            }
        }
        // The last seven days, oldest first
        let weekday = DateFormatter()
        weekday.locale = AppLanguage.locale
        weekday.calendar = calendar
        weekday.timeZone = calendar.timeZone
        weekday.setLocalizedDateFormatFromTemplate("EEEEE")
        snapshot.pages["days"] = log.lastDays(7, now: now, calendar: calendar).map { day in
            ModuleRow(id: ScreenTimeLog.day(day.date, calendar), title: weekday.string(from: day.date), detail: "\(day.minutes)",
                      state: day.minutes >= threshold ? .failure : .neutral, label: time(day.minutes))
        }
        // Average of the week, median and 75th percentile of two weeks (days used only)
        var figures: [ModuleRow] = []
        if let average = ScreenTimeStats.average(log.usedDays(7, now: now, calendar: calendar)) {
            figures.append(ModuleRow(id: "average", title: loc("moyenne"), detail: "\(average)", state: .neutral, label: time(average)))
        }
        let twoWeeks = log.usedDays(14, now: now, calendar: calendar)
        if let median = ScreenTimeStats.median(twoWeeks), let p75 = ScreenTimeStats.percentile75(twoWeeks) {
            figures.append(ModuleRow(id: "median", title: loc("médiane"), detail: "\(median)", state: .neutral, label: time(median)))
            figures.append(ModuleRow(id: "p75", title: loc("3 jours sur 4 sous"), detail: "\(p75)", state: .neutral, label: time(p75)))
        }
        if !figures.isEmpty { snapshot.pages["figures"] = figures }
        return snapshot.withSymbols("hourglass")
    }
}

extension ScreenTimeLog {
    /// Made-up days for the filming mode: nothing real is read.
    static func example(now: Date, calendar: Calendar = .current) -> ScreenTimeLog {
        var log = ScreenTimeLog()
        // The six days before today, the most recent first; the fifth one the Mac stayed closed
        let week = [455, 0, 512, 298, 415, 362]
        for (back, minutes) in week.enumerated() where minutes > 0 {
            if let day = calendar.date(byAdding: .day, value: -(back + 1), to: now) { log.add(minutes: minutes, at: day, calendar: calendar) }
        }
        let current = calendar.component(.hour, from: now)
        let today = [42, 55, 38, 12, 47, 58, 51, 33, 26]
        for (index, minutes) in today.enumerated() {
            let hour = current - (today.count - 1) + index
            guard hour >= 0, let date = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: now) else { continue }
            log.add(minutes: minutes, at: date, calendar: calendar)
        }
        return log
    }
}
