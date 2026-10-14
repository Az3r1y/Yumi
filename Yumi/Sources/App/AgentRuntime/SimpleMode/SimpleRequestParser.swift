import Foundation

/// A common request, understood without any model: what the simple mode can turn into a plan.
enum SimpleRequest: Equatable, Sendable {
    /// « rappelle-moi d'appeler maman demain 18 h »
    case reminder(QuickTaskDraft)
    /// « ajoute pain à mes tâches »
    case task(QuickTaskDraft)
    /// « bloque jeudi 14 h réunion »: a day and a start time are needed.
    case event(title: String, date: String, time: String, minutes: Int?)
    /// « concentre-moi 25 min »
    case focus(minutes: Int)
    /// « quelle heure est-il ? »
    case time
    /// « qu'est-ce que j'ai demain ? »: nil date for today.
    case day(date: String?, freeTime: Bool)
    /// « mets de la musique », « pause », « suivant »
    case music(MusicCommand)
}

/// Reads the requests people make every day, in French and in English, with a few fixed forms
/// and the dates of `QuickTaskParser` (plus `NSDataDetector` for an English date such as
/// "November 3"). Pure: no network, no model, nothing personal. When a sentence does not fit,
/// it answers nil rather than guess.
struct SimpleRequestParser: Sendable {
    var calendar: Calendar = .current
    var now: @Sendable () -> Date = { Date() }

    func parse(_ text: String) -> SimpleRequest? {
        // The words keep their case for the titles (« Paul »); the forms are read in lowercase.
        let original = Self.clean(text)
        let sentence = original.lowercased()
        guard !sentence.isEmpty else { return nil }
        if let command = Self.music(sentence) { return .music(command) }
        if Self.asksTime(sentence) { return .time }
        if let minutes = Self.focus(sentence) { return .focus(minutes: minutes) }
        if let rest = Self.strip(original, prefixes: Self.reminderPrefixes) {
            let draft = dated(Self.dropConnector(rest))
            return draft.title.isEmpty ? nil : .reminder(draft)
        }
        if let title = Self.task(original) {
            let draft = dated(title)
            return draft.title.isEmpty ? nil : .task(draft)
        }
        if let rest = Self.strip(original, prefixes: Self.eventPrefixes) { return event(rest) }
        if Self.asksDay(sentence) {
            let draft = dated(Self.timesNormalised(sentence))
            return .day(date: draft.dateArgument, freeTime: Self.containsAny(sentence, Self.freeTimeWords))
        }
        return nil
    }

    // MARK: - Dates

    /// The title and the day and time found in it. The first letter of the title is capitalised.
    func dated(_ text: String) -> QuickTaskDraft {
        let parser = QuickTaskParser(calendar: calendar, now: now)
        var draft = parser.parse(Self.timesNormalised(text))
        if draft.day == nil, let found = englishDate(in: draft.title) ?? frenchDate(in: draft.title) {
            draft.title = found.rest
            draft.day = found.day
            if draft.hour == nil, let hour = found.hour { draft.hour = hour; draft.minute = found.minute }
        }
        draft.title = Self.capitalised(draft.title.trimmingCharacters(in: CharacterSet(charactersIn: " ,;:-.")))
        return draft
    }

    /// « le 20 octobre », « 3 novembre »: this year, or next year once it has gone by.
    private func frenchDate(in text: String) -> (rest: String, day: DateComponents, hour: Int?, minute: Int?)? {
        let months = ["janvier", "février", "fevrier", "mars", "avril", "mai", "juin", "juillet", "août", "aout",
                      "septembre", "octobre", "novembre", "décembre", "decembre"]
        let numbers = [1, 2, 2, 3, 4, 5, 6, 7, 8, 8, 9, 10, 11, 12, 12]
        let pattern = "(?:\\ble\\s+)?\\b(\\d{1,2})(?:er)?\\s+(\(months.joined(separator: "|")))\\b"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let dayRange = Range(match.range(at: 1), in: text), let monthRange = Range(match.range(at: 2), in: text),
              let whole = Range(match.range, in: text), let dayNumber = Int(text[dayRange]),
              let index = months.firstIndex(of: text[monthRange].lowercased()) else { return nil }
        guard let day = nextDate(month: numbers[index], day: dayNumber) else { return nil }
        var rest = text
        rest.removeSubrange(whole)
        return (Self.squeezed(rest), day, nil, nil)
    }

    /// "November 3", "on Nov 3 at 9am": read by `NSDataDetector`, only when a month is named.
    private func englishDate(in text: String) -> (rest: String, day: DateComponents, hour: Int?, minute: Int?)? {
        let months = ["january", "february", "march", "april", "may", "june", "july", "august", "september",
                      "october", "november", "december", "jan", "feb", "mar", "apr", "jun", "jul", "aug", "sep", "sept", "oct", "nov", "dec"]
        let words = Set(text.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init))
        guard !words.isDisjoint(with: months),
              let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = detector.firstMatch(in: text, range: range), let date = match.date,
              let whole = Range(match.range, in: text) else { return nil }
        let found = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        guard let month = found.month, let dayNumber = found.day, let day = nextDate(month: month, day: dayNumber) else { return nil }
        let matched = text[whole].lowercased()
        let hasTime = matched.contains(":") || matched.contains("am") || matched.contains("pm")
        var rest = text
        rest.removeSubrange(whole)
        rest = rest.replacingOccurrences(of: #"\b(on|the)\s*$"#, with: "", options: [.regularExpression, .caseInsensitive])
        return (Self.squeezed(rest), day, hasTime ? found.hour : nil, hasTime ? found.minute : nil)
    }

    private func nextDate(month: Int, day: Int) -> DateComponents? {
        let today = calendar.startOfDay(for: now())
        var year = calendar.component(.year, from: today)
        guard var date = calendar.date(from: DateComponents(year: year, month: month, day: day)),
              calendar.component(.day, from: date) == day else { return nil }
        if date < today {
            year += 1
            guard let next = calendar.date(from: DateComponents(year: year, month: month, day: day)) else { return nil }
            date = next
        }
        return calendar.dateComponents([.year, .month, .day], from: date)
    }

    /// « 18 h », « 18 h 30 », « 18 heures », « midi », « minuit », "noon", "3 pm" become the forms
    /// `QuickTaskParser` reads (« 18h », « 18h30 », "3pm"). « ce soir » is today.
    static func timesNormalised(_ text: String) -> String {
        var result = text
        let replacements: [(String, String)] = [
            (#"\bmidi et demie?\b"#, "12h30"),
            (#"\bminuit et demie?\b"#, "0h30"),
            (#"\b(\d{1,2})\s*h(?:eures?)?\s+et\s+demie?\b"#, "$1h30"),
            (#"\b(\d{1,2})\s*h(?:eures?)?\s+et\s+quart\b"#, "$1h15"),
            (#"\bmidi\b"#, "12h"),
            (#"\bminuit\b"#, "0h"),
            (#"\bnoon\b"#, "12:00"),
            (#"\bmidnight\b"#, "0:00"),
            (#"\b(\d{1,2})\s*(?:h|heures?)\s*(\d{2})\b"#, "$1h$2"),
            (#"\b(\d{1,2})\s+(?:h|heures?)\b"#, "$1h"),
            (#"\b(\d{1,2})heures?\b"#, "$1h"),
            (#"\b(\d{1,2}(?::\d{2})?)\s+([ap])\.?m\.?(?=\s|$)"#, "$1$2m"),
            (#"\b(\d{1,2})\s*o'?clock\b"#, "$1:00"),
            (#"\bce soir\b"#, "aujourd'hui"),
            (#"\bce matin\b"#, "aujourd'hui"),
            (#"\bcet après-midi\b"#, "aujourd'hui"),
            (#"\btonight\b"#, "today"),
            (#"\bnext (monday|tuesday|wednesday|thursday|friday|saturday|sunday)\b"#, "$1"),
            (#"\bthis (?:morning|afternoon|evening)\b"#, "today"),
        ]
        for (pattern, template) in replacements {
            result = result.replacingOccurrences(of: pattern, with: template, options: [.regularExpression, .caseInsensitive])
        }
        return result
    }

    // MARK: - Events

    private func event(_ rest: String) -> SimpleRequest? {
        var text = Self.dropConnector(rest)
        var minutes: Int?
        // « pendant 2 h », « 30 min », "for 2 hours": the length, before the time is read.
        let lengths: [(String, Int)] = [
            (#"\b(?:pendant|durant|for)\s+(\d{1,2})\s*(?:h|heures?|hours?)\b"#, 60),
            (#"\b(?:pendant|durant|for)?\s*(\d{1,3})\s*(?:min|mn|minutes?)\b"#, 1),
        ]
        for (pattern, unit) in lengths where minutes == nil {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
               let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               let numberRange = Range(match.range(at: 1), in: text), let number = Int(text[numberRange]),
               let whole = Range(match.range, in: text) {
                minutes = number * unit
                text.removeSubrange(whole)
            }
        }
        var draft = dated(text)
        // Only a date and a time: the title is everything else, here nothing.
        if draft.day == nil, draft.hour == nil {
            let alone = dated("§ " + text)
            if alone.title == "§", alone.day != nil { draft = alone; draft.title = "" }
        }
        guard let date = draft.dateArgument, let time = draft.timeArgument else { return nil }
        let title = Self.dropConnector(draft.title).isEmpty ? loc("Occupé") : Self.capitalised(Self.dropConnector(draft.title))
        return .event(title: title, date: date, time: time, minutes: minutes.map { min(max($0, 5), 720) })
    }

    // MARK: - Fixed forms

    static let reminderPrefixes = [
        "rappelle-moi", "rappelle moi", "rappelles-moi", "fais-moi penser", "fais moi penser", "fais-moi un rappel",
        "n'oublie pas de me rappeler", "ajoute un rappel", "crée un rappel", "cree un rappel", "mets un rappel",
        "nouveau rappel", "un rappel", "rappel",
        "remind me", "set a reminder", "add a reminder", "create a reminder", "new reminder", "reminder",
    ]

    static let eventPrefixes = [
        "ajoute un rendez-vous", "ajoute un rdv", "ajoute un événement", "ajoute un evenement", "ajoute une réunion",
        "ajoute une reunion", "crée un événement", "cree un evenement", "crée un rendez-vous", "nouveau rendez-vous",
        "nouvel événement", "nouvel evenement", "mets un rendez-vous", "mets une réunion", "note un rendez-vous",
        "bloque-moi", "bloque moi", "bloque", "bloquer", "réserve", "reserve", "planifie", "cale-moi", "cale moi", "cale",
        "rendez-vous", "rdv",
        "add an event", "add a meeting", "add an appointment", "create an event", "new event", "new meeting",
        "schedule", "block", "book",
    ]

    /// The small words between the verb and what to do: « de », « d' », "to".
    static func dropConnector(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespaces)
        for connector in [":", "de ", "d'", "à ", "a ", "que ", "qu'", "pour ", "to ", "that ", "about ", "of ", "me ", "moi "] {
            if result.lowercased().hasPrefix(connector) {
                result = String(result.dropFirst(connector.count)).trimmingCharacters(in: .whitespaces)
            }
        }
        return result
    }

    /// « ajoute pain à mes tâches », « mets lait sur ma liste », "add bread to my to-do list",
    /// « nouvelle tâche : pain », "todo: bread".
    static func task(_ sentence: String) -> String? {
        let lists = #"(?:ma |mes |la |les |my |the |our )?(?:liste(?: de courses| de tâches| de taches)?|tâches|taches|tâche|tache|to-?dos?(?: list)?|tasks|task list|list|shopping list|courses)"#
        let suffix = #"^(?:ajoute|rajoute|mets|met|note|ajouter|add|put)\s+(.+?)\s+(?:à|a|aux|dans|sur|to|on|in|onto)\s+"# + lists + "$"
        if let title = firstGroup(suffix, in: sentence) { return title }
        let prefix = #"^(?:nouvelle tâche|nouvelle tache|ajoute une tâche|ajoute une tache|crée une tâche|cree une tache|tâche|tache|à faire|a faire|new task|add a task|add task|create a task|task|todo|to-do|to do)\s*:?\s+(.+)$"#
        return firstGroup(prefix, in: sentence)
    }

    static func focus(_ sentence: String) -> Int? {
        let starts = ["concentre-moi", "concentre moi", "je veux me concentrer", "aide-moi à me concentrer", "mode concentration",
                      "lance un focus", "démarre un focus", "demarre un focus", "lance une session", "session de concentration",
                      "lance un minuteur", "mets un minuteur", "minuteur", "pomodoro", "focus", "concentration",
                      "start a focus", "start focus", "focus mode", "help me focus", "start a timer", "set a timer", "timer"]
        guard starts.contains(where: { sentence.hasPrefix($0) }) else { return nil }
        if let hours = firstGroup(#"\b(\d)\s*(?:h|heures?|hours?)\b"#, in: sentence).flatMap(Int.init) { return clampFocus(hours * 60) }
        if containsAny(sentence, ["une demi-heure", "une demi heure", "half an hour"]) { return 30 }
        if containsAny(sentence, ["une heure", "an hour", "one hour"]) { return 60 }
        if let minutes = firstGroup(#"\b(\d{1,3})\s*(?:min|mn|minutes?|m)?\b"#, in: sentence).flatMap(Int.init) { return clampFocus(minutes) }
        return StartFocusTool.defaultMinutes
    }

    private static func clampFocus(_ minutes: Int) -> Int {
        min(max(minutes, StartFocusTool.minutes.lowerBound), StartFocusTool.minutes.upperBound)
    }

    static func music(_ sentence: String) -> MusicCommand? {
        let exact: [MusicCommand: Set<String>] = [
            .play: ["musique", "music", "play", "lecture", "reprends", "reprends la musique", "resume", "resume music", "joue",
                    "mets de la musique", "mets la musique", "mets du son", "lance la musique", "lance de la musique",
                    "joue de la musique", "play music", "play some music", "put on some music", "start the music"],
            .pause: ["pause", "mets pause", "mets en pause", "stop", "pause music", "stop music", "stop the music", "pause the music"],
            .next: ["suivant", "suivante", "next", "skip", "passe", "passe au suivant", "chanson suivante", "morceau suivant",
                    "titre suivant", "musique suivante", "next song", "next track", "skip this song", "skip song"],
            .previous: ["précédent", "precedent", "précédente", "previous", "chanson précédente", "morceau précédent",
                        "titre précédent", "previous song", "previous track", "last song"],
        ]
        for (command, phrases) in exact where phrases.contains(sentence) { return command }
        let aboutMusic = containsAny(sentence, ["musique", "music", "chanson", "morceau", "song", "track", "spotify", "deezer"])
        guard aboutMusic else { return nil }
        if containsAny(sentence, ["suivant", "suivante", "next", "skip", "passe "]) { return .next }
        if containsAny(sentence, ["précédent", "precedent", "précédente", "previous"]) { return .previous }
        if containsAny(sentence, ["pause", "arrête", "arrete", "stop", "coupe"]) { return .pause }
        if containsAny(sentence, ["mets", "lance", "joue", "play", "start", "démarre", "demarre", "reprends", "resume", "put on"]) { return .play }
        return nil
    }

    static func asksTime(_ sentence: String) -> Bool {
        if containsAny(sentence, ["à quelle heure", "a quelle heure", "at what time"]) { return false }
        return containsAny(sentence, ["quelle heure", "quelle heure il est", "l'heure qu'il est", "il est quelle heure",
                                      "donne-moi l'heure", "donne moi l'heure", "what time is it", "what's the time",
                                      "whats the time", "what is the time", "tell me the time", "current time"])
            || sentence == "l'heure" || sentence == "heure" || sentence == "time"
    }

    static func asksDay(_ sentence: String) -> Bool {
        ChatRoute.isPersonalAgenda(sentence)
            || containsAny(sentence, ["ma journée", "ma journee", "mon programme", "mon agenda", "my day", "my schedule", "my agenda", "my calendar",
                                      "suis-je libre", "suis-je dispo", "je suis libre", "am i free", "am i busy", "am i available"])
    }

    static let freeTimeWords = ["temps libre", "libre", "dispo", "créneau", "creneau", "free", "available"]

    // MARK: - Text

    /// Straight apostrophes, single spaces, without « s'il te plaît », "please" or a question mark
    /// around it. The case is kept.
    static func clean(_ text: String) -> String {
        var result = text.replacingOccurrences(of: "’", with: "'")
        result = squeezed(result).trimmingCharacters(in: CharacterSet(charactersIn: " ?!.…"))
        let politeness = [#"^(?:yumi|hey yumi|dis yumi|salut yumi)\s*,?\s*"#, #"^(?:est-ce que tu peux|est ce que tu peux|tu peux|tu pourrais|peux-tu|pourrais-tu|can you|could you|would you|please)\s+"#,
                          #"[,\s]*(?:s'il te plaît|s'il te plait|stp|svp|please|merci)$"#, #"^(?:please)\s+"#]
        for pattern in politeness {
            result = result.replacingOccurrences(of: pattern, with: "", options: [.regularExpression, .caseInsensitive])
        }
        return result.trimmingCharacters(in: CharacterSet(charactersIn: " ?!.…,"))
    }

    /// What follows one of the prefixes, when the sentence starts with it as a whole word.
    static func strip(_ sentence: String, prefixes: [String]) -> String? {
        let lowered = sentence.lowercased()
        for prefix in prefixes where lowered.hasPrefix(prefix) {
            let rest = sentence.dropFirst(prefix.count)
            guard rest.isEmpty || rest.first == " " || rest.first == ":" || rest.first == "," || prefix.hasSuffix("'") else { continue }
            return String(rest).trimmingCharacters(in: CharacterSet(charactersIn: " ,:"))
        }
        return nil
    }

    static func containsAny(_ sentence: String, _ words: [String]) -> Bool { words.contains(where: sentence.contains) }

    static func firstGroup(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range]).trimmingCharacters(in: .whitespaces)
    }

    static func squeezed(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    static func capitalised(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
    }
}
