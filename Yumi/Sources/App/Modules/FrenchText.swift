import Foundation

/// Small phrasings shared by the modules, in the language Yumi speaks (AppLanguage). The name
/// stays from when he only spoke French. Yumi speaks short.
enum FrenchText {
    /// "14:30"
    static func clock(_ date: Date, calendar: Calendar = .current) -> String {
        if AppLanguage.isEnglish { return englishTime(date, calendar: calendar) }
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }

    /// "18 h" or "18 h 30"
    static func spokenHour(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let minute = parts.minute ?? 0
        if AppLanguage.isEnglish { return englishTime(date, calendar: calendar, dropZeroMinutes: minute == 0) }
        return minute == 0 ? "\(parts.hour ?? 0) h" : String(format: "%d h %02d", parts.hour ?? 0, minute)
    }

    /// "2:30 PM" or "14:30", as the Mac's region writes a time; "6 PM" for a round hour.
    private static func englishTime(_ date: Date, calendar: Calendar, dropZeroMinutes: Bool = false) -> String {
        let formatter = DateFormatter()
        formatter.locale = AppLanguage.locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        let twelveHours = (DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: AppLanguage.locale) ?? "").contains("a")
        formatter.setLocalizedDateFormatFromTemplate(dropZeroMinutes && twelveHours ? "j" : "jmm")
        return formatter.string(from: date)
    }

    /// "18:42" for a countdown. Seconds are rounded up so a timer never shows 00:00 while running.
    static func countdown(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.up)))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    /// "1:52", "25:00", "1:02:07": a position in a track or a timer.
    static func trackTime(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        return total >= 3600 ? String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
                             : String(format: "%d:%02d", total / 60, total % 60)
    }

    /// "18 min 42", "42 s", "1 h 05"
    static func duration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.up)))
        if total < 60 { return "\(total) s" }
        if total < 3600 {
            let rest = total % 60
            return rest == 0 ? "\(total / 60) min" : String(format: "%d min %02d", total / 60, rest)
        }
        return String(format: "%d h %02d", total / 3600, (total % 3600) / 60)
    }

    /// "12 min", "1 h 05": a delay rounded to the minute.
    static func minutes(_ seconds: TimeInterval) -> String {
        let total = max(1, Int((seconds / 60).rounded(.up)))
        return total < 60 ? "\(total) min" : String(format: "%d h %02d", total / 60, total % 60)
    }

    /// A small number in letters, the way Yumi says it in a sentence: "douze", "vingt et une".
    /// Above 99 the figures are kept: nobody reads "cent quarante-trois" at a glance.
    static func spelled(_ value: Int, feminine: Bool = false) -> String {
        guard (0...99).contains(value) else { return "\(value)" }
        if AppLanguage.isEnglish {
            let formatter = NumberFormatter()
            formatter.locale = Locale(identifier: "en")
            formatter.numberStyle = .spellOut
            return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
        }
        let units = ["zéro", feminine ? "une" : "un", "deux", "trois", "quatre", "cinq", "six", "sept", "huit", "neuf", "dix",
                     "onze", "douze", "treize", "quatorze", "quinze", "seize", "dix-sept", "dix-huit", "dix-neuf"]
        if value < 20 { return units[value] }
        let tens = ["", "", "vingt", "trente", "quarante", "cinquante", "soixante", "soixante", "quatre-vingt", "quatre-vingt"]
        let ten = value / 10, unit = value % 10
        // 70 to 79 and 90 to 99 count on from sixty and eighty: soixante-douze, quatre-vingt-treize.
        let rest = (ten == 7 || ten == 9) ? unit + 10 : unit
        if rest == 0 { return ten == 8 ? "quatre-vingts" : tens[ten] }
        if (rest == 1 || rest == 11) && ten != 8 && ten != 9 { return "\(tens[ten]) et \(units[rest])" }
        return "\(tens[ten])-\(units[rest])"
    }

    /// "douze minutes", "une heure cinq": a delay said the way a person would.
    static func spokenMinutes(_ seconds: TimeInterval) -> String {
        let total = max(1, Int((seconds / 60).rounded(.up)))
        if total < 60 { return "\(spelled(total, feminine: true)) \(total > 1 ? loc("minutes") : loc("minute"))" }
        let hours = total / 60, rest = total % 60
        let hourText = "\(spelled(hours, feminine: true)) \(hours > 1 ? loc("heures") : loc("heure"))"
        if rest == 0 { return hourText }
        // "one hour and five minutes" in English, "une heure cinq" in French
        guard AppLanguage.isEnglish else { return "\(hourText) \(spelled(rest))" }
        return "\(hourText) and \(spelled(rest)) \(rest > 1 ? "minutes" : "minute")"
    }

    /// "une session", "deux sessions": a small count in letters.
    static func spelledCount(_ value: Int, _ singular: String, _ plural: String, feminine: Bool = false) -> String {
        "\(spelled(value, feminine: feminine)) \(value > 1 ? plural : singular)"
    }

    private static func capitalized(_ text: String) -> String {
        text.prefix(1).uppercased() + text.dropFirst()
    }

    /// The same, at the start of a sentence: "Deux sessions".
    static func sentenceStart(_ text: String) -> String { capitalized(text) }

    /// "1 session", "2 sessions"
    static func count(_ value: Int, _ singular: String, _ plural: String) -> String {
        "\(value) \(value > 1 ? plural : singular)"
    }
}
