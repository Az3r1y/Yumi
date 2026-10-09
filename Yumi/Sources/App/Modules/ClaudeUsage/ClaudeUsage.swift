import Foundation

// MARK: - Claude Code usage of the day
// Read on this Mac: the transcripts Claude Code keeps (~/.claude/projects/*/*.jsonl) for the
// sessions, time and tokens, and what Claude Code gives its status line (StatusLineRelay) for
// the allowances and the cost of each session. Nothing of what was said is kept, nothing leaves
// the Mac.

/// What a day of Claude Code amounts to.
struct ClaudeUsageDay: Equatable, Sendable {
    /// The person's own sessions with at least one message today (terminal, desktop app, editor).
    var sessions = 0
    /// Time spent in them: the gaps between two messages, when shorter than `ClaudeUsageReader.pause`.
    var activeSeconds: TimeInterval = 0
    /// Sessions started by a program through the SDK (a review after a commit, a script): their
    /// tokens and cost count, not their time.
    var backgroundSessions = 0
    /// Tokens written by the model, and read by it (the cache included).
    var outputTokens = 0
    var inputTokens = 0
    /// What the day would have cost at the API price, in dollars, as Claude Code counts it.
    /// nil when it has not said anything about today yet.
    var apiCostUSD: Double?
    /// Used of the five-hour and of the weekly allowance; nil until the status line said it.
    var fiveHour: StatusLineRelay.Report.Allowance?
    var sevenDay: StatusLineRelay.Report.Allowance?
    /// The status line relay is in place.
    var quotasConnected = false
}

enum ClaudeUsageReader {
    /// A longer silence is a break, not work.
    static let pause: TimeInterval = 5 * 60
    /// Dollars to euros, for the API price: the European Central Bank's of the day (`EuroRate`),
    /// kept under this default; `defaultRate` before the first one arrives.
    static let rateKey = "usdToEurRate"
    static let defaultRate = 0.86

    /// The transcripts written to since `midnight`.
    static func files(in folder: URL, since midnight: Date) -> [URL] {
        let manager = FileManager.default
        guard let projects = try? manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { return [] }
        return projects.flatMap { project in
            ((try? manager.contentsOfDirectory(at: project, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [])
                .filter { $0.pathExtension == "jsonl" }
                .filter { ((try? $0.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast) >= midnight }
        }
    }

    /// The day since `midnight`, from these transcripts (named after their session).
    /// - Parameter live: what each session cost so far by its status line, fresher than the
    ///   `cost-state` lines Claude Code writes only when a session ends or resumes.
    static func day(files: [URL], since midnight: Date, live: [String: Double] = [:]) -> ClaudeUsageDay {
        var day = ClaudeUsageDay()
        var times: [String: [Date]] = [:]
        var background: Set<String> = []
        var countedMessages: Set<String> = []
        var cost: Double?
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        for file in files {
            // ponytail: each changed transcript is read whole at every refresh; keep the read
            // offset per file if a long day of sessions makes it slow
            guard let data = try? Data(contentsOf: file, options: .mappedIfSafe) else { continue }
            var latest: Date?
            var activeToday = false
            var program = false
            /// The session's cost before midnight, and its last cost since.
            var before = 0.0, after: Double?
            for line in data.split(separator: UInt8(ascii: "\n")) {
                guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
                if let stamp = object["timestamp"] as? String, let date = iso.date(from: stamp) { latest = date }
                if (object["entrypoint"] as? String)?.hasPrefix("sdk") == true { program = true }
                if object["type"] as? String == "cost-state", let total = object["totalCostUSD"] as? Double {
                    if let latest, latest >= midnight { after = total } else { before = total }
                    continue
                }
                guard let latest, latest >= midnight, let session = object["sessionId"] as? String,
                      ["user", "assistant"].contains(object["type"] as? String) else { continue }
                activeToday = true
                if program { background.insert(session) } else { times[session, default: []].append(latest) }
                // A reply is written once per block of content, with the same message and usage
                guard let message = object["message"] as? [String: Any], let usage = message["usage"] as? [String: Any],
                      let id = message["id"] as? String, countedMessages.insert(id).inserted else { continue }
                day.outputTokens += usage["output_tokens"] as? Int ?? 0
                day.inputTokens += ["input_tokens", "cache_read_input_tokens", "cache_creation_input_tokens"]
                    .reduce(0) { $0 + (usage[$1] as? Int ?? 0) }
            }
            if let total = live[file.deletingPathExtension().lastPathComponent] ?? after, activeToday || after != nil {
                cost = (cost ?? 0) + max(0, total - before)
            }
        }
        day.sessions = times.count
        day.backgroundSessions = background.subtracting(times.keys).count
        day.activeSeconds = times.values.reduce(0) { total, dates in
            let sorted = dates.sorted()
            return total + zip(sorted, sorted.dropFirst()).reduce(0) { sum, pair in
                let gap = pair.1.timeIntervalSince(pair.0)
                return sum + (gap <= pause ? gap : 0)
            }
        }
        day.apiCostUSD = cost
        return day
    }

    // MARK: - On screen

    static let moduleID = "claude-usage"
    static let color = "#D97757"
    static let symbol = "chart.bar.fill"

    static func snapshot(_ day: ClaudeUsageDay?, rate: Double = defaultRate, now: Date = Date()) -> ModuleSnapshot {
        let name = loc("Usage Claude")
        guard let day else {
            return ModuleSnapshot(id: moduleID, name: name, colorHex: color, status: "…",
                                  title: loc("Je compte ta journée avec Claude"), subtitle: "",
                                  primaryAction: loc("Actualiser"), secondaryAction: nil).withSymbols(symbol)
        }
        let time = FrenchText.minutes(day.activeSeconds)
        let euros = day.apiCostUSD.map { self.euros($0 * rate) }
        var rows: [ModuleRow] = []
        if let five = day.fiveHour {
            rows.append(quotaRow("five", loc("Quota 5 h"), five, now: now))
        }
        if let week = day.sevenDay {
            rows.append(quotaRow("week", loc("Quota semaine"), week, now: now))
        }
        if day.fiveHour == nil && day.sevenDay == nil {
            rows.append(ModuleRow(id: "quotas", title: loc("Quotas"),
                                  detail: day.quotasConnected ? loc("arrivent dès qu'une session Claude Code tourne")
                                                              : loc("à brancher dans Réglages › Claude Code › Quotas"),
                                  state: .neutral, label: day.quotasConnected ? "…" : loc("à brancher")))
        }
        rows += [
            ModuleRow(id: "sessions", title: loc("Sessions"), detail: "", state: .neutral, label: "\(day.sessions)"),
            ModuleRow(id: "time", title: loc("Temps actif"), detail: "", state: .neutral, label: time),
            ModuleRow(id: "tokens", title: loc("Tokens"),
                      detail: loc("\(tokens(day.outputTokens)) écrits, \(tokens(day.inputTokens)) lus (cache compris)"),
                      state: .neutral, label: tokens(day.outputTokens + day.inputTokens)),
        ]
        if day.backgroundSessions > 0 {
            rows.append(ModuleRow(id: "background", title: loc("En arrière-plan"),
                                  detail: loc("tâches lancées par un programme : comptées dans les tokens et le tarif API"),
                                  state: .neutral, label: day.backgroundSessions == 1 ? loc("1 session") : loc("\(day.backgroundSessions) sessions")))
        }
        rows += [
            ModuleRow(id: "api", title: loc("Au tarif API"),
                      detail: euros == nil ? loc("compté par Claude Code pendant les sessions") : loc("ce que la journée aurait coûté sans abonnement"),
                      state: .neutral, label: euros.map { "≈ \($0)" } ?? "…"),
        ]

        var snapshot: ModuleSnapshot
        if let five = day.fiveHour {
            let percent = self.percent(five.usedPercent)
            let week = day.sevenDay.map { loc("semaine \(self.percent($0.usedPercent))") }
            snapshot = ModuleSnapshot(id: moduleID, name: name, colorHex: color, status: percent,
                                      title: loc("Quota 5 h : \(percent)"),
                                      subtitle: [week, time, euros.map { "≈ \($0)" }].compactMap { $0 }.joined(separator: " · "),
                                      primaryAction: loc("Actualiser"), secondaryAction: nil, rows: rows)
            snapshot.progress = ModuleProgress(fraction: min(1, max(0, five.usedPercent / 100)), leading: loc("5 h"),
                                               trailing: five.resetsAt.map { resets($0, now: now) } ?? percent)
            // Close to the limit: the folded island says it
            if five.usedPercent >= 80 {
                snapshot.live = ModuleLive(text: loc("Quota 5 h : \(percent)"), priority: ModuleLivePriority.ambient)
            }
        } else if day.sessions == 0 && day.backgroundSessions == 0 {
            snapshot = ModuleSnapshot(id: moduleID, name: name, colorHex: color, status: "0",
                                      title: loc("Pas encore de Claude aujourd'hui"),
                                      subtitle: loc("Les sessions de Claude Code de la journée s'afficheront ici."),
                                      primaryAction: loc("Actualiser"), secondaryAction: nil, rows: rows)
        } else {
            snapshot = ModuleSnapshot(id: moduleID, name: name, colorHex: color, status: time,
                                      title: loc("\(time) avec Claude aujourd'hui"),
                                      subtitle: [day.sessions == 1 ? loc("1 session") : loc("\(day.sessions) sessions"),
                                                 euros.map { "≈ \($0)" }].compactMap { $0 }.joined(separator: " · "),
                                      primaryAction: loc("Actualiser"), secondaryAction: nil, rows: rows)
        }
        return snapshot.withSymbols(symbol)
    }

    private static func quotaRow(_ id: String, _ title: String, _ allowance: StatusLineRelay.Report.Allowance, now: Date) -> ModuleRow {
        let state: ModuleRowState = allowance.usedPercent >= 90 ? .failure : allowance.usedPercent >= 70 ? .waiting : .neutral
        return ModuleRow(id: id, title: title, detail: allowance.resetsAt.map { loc("repart \(resets($0, now: now))") } ?? "",
                         state: state, label: percent(allowance.usedPercent))
    }

    /// "à 14 h 50" today, "lundi à 9 h" later.
    static func resets(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        let hour = FrenchText.spokenHour(date, calendar: calendar)
        if calendar.isDate(date, inSameDayAs: now) { return loc("à \(hour)") }
        let formatter = DateFormatter()
        formatter.locale = AppLanguage.locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate("EEEE")
        return loc("\(formatter.string(from: date)) à \(hour)")
    }

    static func percent(_ value: Double) -> String { "\(Int(value.rounded())) %" }

    /// "850", "12 k", "1,2 M"
    static func tokens(_ count: Int) -> String {
        switch count {
        case ..<1_000: return "\(count)"
        case ..<1_000_000: return "\(count / 1_000) k"
        default: return (Double(count) / 1_000_000).formatted(.number.precision(.fractionLength(1)).locale(AppLanguage.locale)) + " M"
        }
    }

    /// "5,57 €" in French, "€5.57" in English.
    static func euros(_ value: Double) -> String {
        value.formatted(.currency(code: "EUR").locale(AppLanguage.locale))
    }
}
