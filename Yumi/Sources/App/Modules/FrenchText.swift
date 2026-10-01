import Foundation

/// Small French phrasings shared by the modules. Yumi speaks short.
enum FrenchText {
    /// "14:30"
    static func clock(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }

    /// "18 h" or "18 h 30"
    static func spokenHour(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let minute = parts.minute ?? 0
        return minute == 0 ? "\(parts.hour ?? 0) h" : String(format: "%d h %02d", parts.hour ?? 0, minute)
    }

    /// "18:42" for a countdown. Seconds are rounded up so a timer never shows 00:00 while running.
    static func countdown(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.up)))
        return String(format: "%02d:%02d", total / 60, total % 60)
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

    /// "1 session", "2 sessions"
    static func count(_ value: Int, _ singular: String, _ plural: String) -> String {
        "\(value) \(value > 1 ? plural : singular)"
    }
}
