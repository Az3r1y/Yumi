import Foundation

/// A task typed in the quick field, read: its title, and the day and time found in it.
struct QuickTaskDraft: Equatable, Sendable {
    var title: String
    /// Year, month and day; nil when the text gives no day and no time.
    var day: DateComponents?
    var hour: Int?
    var minute: Int?

    /// "YYYY-MM-DD", the form `add_reminder` and `add_notion_task` take.
    var dateArgument: String? {
        guard let day, let year = day.year, let month = day.month, let date = day.day else { return nil }
        return String(format: "%04d-%02d-%02d", year, month, date)
    }

    /// "HH:mm", 24 hours.
    var timeArgument: String? {
        guard let hour else { return nil }
        return String(format: "%02d:%02d", hour, minute ?? 0)
    }
}

/// Reads a simple date in a task typed in French or in English: « demain », « jeudi 15h »,
/// « après-demain à 9h30 », "tomorrow 3pm", "friday at 10:15". What is recognised leaves the
/// title; anything else stays in it, word for word. Never guesses beyond these forms.
struct QuickTaskParser: Sendable {
    var calendar: Calendar = .current
    var now: @Sendable () -> Date = { Date() }

    /// Weekday words, numbered like `Calendar` (1 is Sunday).
    private static let weekdays: [String: Int] = [
        "dimanche": 1, "lundi": 2, "mardi": 3, "mercredi": 4, "jeudi": 5, "vendredi": 6, "samedi": 7,
        "sunday": 1, "monday": 2, "tuesday": 3, "wednesday": 4, "thursday": 5, "friday": 6, "saturday": 7,
    ]
    /// Days from today.
    private static let relative: [String: Int] = [
        "aujourd'hui": 0, "aujourdhui": 0, "today": 0,
        "demain": 1, "tomorrow": 1,
        "après-demain": 2, "apres-demain": 2, "aprèsdemain": 2,
    ]
    /// Small words that only lead to a day or a time: dropped with it.
    private static let leading: Set<String> = ["le", "à", "a", "at", "on", "pour", "for", "ce", "this"]
    private static let trailing: Set<String> = ["prochain", "next"]

    func parse(_ text: String) -> QuickTaskDraft {
        let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var words = raw.split(whereSeparator: \.isWhitespace).map(String.init)
        var offset: Int?
        var time: (hour: Int, minute: Int)?

        // From the end: a date usually closes the sentence, and the title keeps its own words.
        var index = words.count - 1
        while index >= 0 {
            let word = Self.key(words[index])
            if time == nil, let found = Self.time(word) {
                time = found
                words.remove(at: index)
                index = dropLeading(&words, before: index)
            } else if offset == nil, let days = Self.relative[word] {
                offset = days
                words.remove(at: index)
                index = dropLeading(&words, before: index)
            } else if offset == nil, let weekday = Self.weekdays[word] {
                offset = daysUntil(weekday)
                words.remove(at: index)
                if index < words.count, Self.trailing.contains(Self.key(words[index])) { words.remove(at: index) }
                index = dropLeading(&words, before: index)
            } else if offset == nil, Self.trailing.contains(word), index > 0, let weekday = Self.weekdays[Self.key(words[index - 1])] {
                offset = daysUntil(weekday)
                words.removeSubrange((index - 1)...index)
                index = dropLeading(&words, before: index - 1)
            } else {
                index -= 1
            }
        }

        let title = words.joined(separator: " ").trimmingCharacters(in: CharacterSet(charactersIn: " ,;:-"))
        // Nothing but a date: it is the title, not a date.
        guard !title.isEmpty else { return QuickTaskDraft(title: raw) }
        guard offset != nil || time != nil else { return QuickTaskDraft(title: title) }

        let today = calendar.startOfDay(for: now())
        var days = offset ?? 0
        // A time alone that has already gone by today is for tomorrow.
        if offset == nil, let time, let moment = calendar.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: today),
           moment <= now() {
            days = 1
        }
        let date = calendar.date(byAdding: .day, value: days, to: today) ?? today
        return QuickTaskDraft(title: title, day: calendar.dateComponents([.year, .month, .day], from: date),
                              hour: time?.hour, minute: time.map { $0.minute })
    }

    /// Removes the small word just before `index` (« le », « à »…). Returns where to look next.
    private func dropLeading(_ words: inout [String], before index: Int) -> Int {
        var next = index - 1
        while next >= 0, Self.leading.contains(Self.key(words[next])) {
            words.remove(at: next)
            next -= 1
        }
        return next
    }

    /// 1 to 7: « jeudi » said on a Thursday is next week's.
    private func daysUntil(_ weekday: Int) -> Int {
        let current = calendar.component(.weekday, from: now())
        let ahead = (weekday - current + 7) % 7
        return ahead == 0 ? 7 : ahead
    }

    private static func key(_ word: String) -> String {
        word.lowercased().replacingOccurrences(of: "’", with: "'").trimmingCharacters(in: CharacterSet(charactersIn: ",;.!?"))
    }

    /// « 15h », « 15h30 », « 9:30 », "3pm", "10:15am".
    static func time(_ word: String) -> (hour: Int, minute: Int)? {
        var text = word
        var meridiem: String?
        for suffix in ["am", "pm"] where text.hasSuffix(suffix) {
            meridiem = suffix
            text.removeLast(2)
        }
        let parts: [Substring]
        if meridiem == nil, text.contains("h") {
            parts = text.split(separator: "h", omittingEmptySubsequences: false)
        } else if text.contains(":") {
            parts = text.split(separator: ":", omittingEmptySubsequences: false)
        } else if meridiem != nil {
            parts = [Substring(text)]
        } else {
            return nil
        }
        guard (1...2).contains(parts.count), let first = parts.first, (1...2).contains(first.count),
              first.allSatisfy(\.isNumber), var hour = Int(first) else { return nil }
        var minute = 0
        if parts.count == 2, !parts[1].isEmpty {
            guard parts[1].count == 2, parts[1].allSatisfy(\.isNumber), let value = Int(parts[1]) else { return nil }
            minute = value
        } else if parts.count == 2, text.contains(":") {
            return nil
        }
        if let meridiem {
            guard (1...12).contains(hour) else { return nil }
            hour = hour % 12 + (meridiem == "pm" ? 12 : 0)
        }
        guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        return (hour, minute)
    }
}
