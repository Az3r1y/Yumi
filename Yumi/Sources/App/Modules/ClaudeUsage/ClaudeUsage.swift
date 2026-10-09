import Foundation

// MARK: - Claude Code usage of the day
// Read from the transcripts Claude Code keeps on this Mac (~/.claude/projects/*/*.jsonl). Nothing
// leaves the Mac and nothing of what was said is kept: only times, token counts and the cost
// Claude Code works out itself (its `cost-state` lines).

/// What a day of Claude Code amounts to.
struct ClaudeUsageDay: Equatable, Sendable {
    /// Sessions with at least one message today.
    var sessions = 0
    /// Time spent in them: the gaps between two messages, when shorter than `ClaudeUsageReader.pause`.
    var activeSeconds: TimeInterval = 0
    /// Tokens written by the model, and read by it (the cache included).
    var outputTokens = 0
    var inputTokens = 0
    /// What Claude Code counted today, in dollars at the API price. nil until it wrote a cost
    /// since midnight: it writes one when a session ends or resumes, not at every message.
    var costUSD: Double?
}

enum ClaudeUsageReader {
    /// A longer silence is a break, not work.
    static let pause: TimeInterval = 5 * 60

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

    /// The day since `midnight`, from these transcripts.
    static func day(files: [URL], since midnight: Date) -> ClaudeUsageDay {
        var day = ClaudeUsageDay()
        var times: [String: [Date]] = [:]
        var countedMessages: Set<String> = []
        var cost: Double?
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        for file in files {
            // ponytail: each changed transcript is read whole at every refresh; keep the read
            // offset per file if a long day of sessions makes it slow
            guard let data = try? Data(contentsOf: file, options: .mappedIfSafe) else { continue }
            var latest: Date?
            /// The session's cost before midnight, and its last cost since.
            var before = 0.0, after: Double?
            for line in data.split(separator: UInt8(ascii: "\n")) {
                guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
                if let stamp = object["timestamp"] as? String, let date = iso.date(from: stamp) { latest = date }
                if object["type"] as? String == "cost-state", let total = object["totalCostUSD"] as? Double {
                    if let latest, latest >= midnight { after = total } else { before = total }
                    continue
                }
                guard let latest, latest >= midnight, let session = object["sessionId"] as? String,
                      ["user", "assistant"].contains(object["type"] as? String) else { continue }
                times[session, default: []].append(latest)
                // A reply is written once per block of content, with the same message and usage
                guard let message = object["message"] as? [String: Any], let usage = message["usage"] as? [String: Any],
                      let id = message["id"] as? String, countedMessages.insert(id).inserted else { continue }
                day.outputTokens += usage["output_tokens"] as? Int ?? 0
                day.inputTokens += ["input_tokens", "cache_read_input_tokens", "cache_creation_input_tokens"]
                    .reduce(0) { $0 + (usage[$1] as? Int ?? 0) }
            }
            if let after { cost = (cost ?? 0) + max(0, after - before) }
        }
        day.sessions = times.count
        day.activeSeconds = times.values.reduce(0) { total, dates in
            let sorted = dates.sorted()
            return total + zip(sorted, sorted.dropFirst()).reduce(0) { sum, pair in
                let gap = pair.1.timeIntervalSince(pair.0)
                return sum + (gap <= pause ? gap : 0)
            }
        }
        day.costUSD = cost
        return day
    }

    // MARK: - On screen

    static func snapshot(_ day: ClaudeUsageDay?) -> ModuleSnapshot {
        let name = loc("Usage Claude")
        guard let day else {
            return ModuleSnapshot(id: ClaudeUsageReader.moduleID, name: name, colorHex: color, status: "…",
                                  title: loc("Je compte ta journée avec Claude"), subtitle: "",
                                  primaryAction: loc("Actualiser"), secondaryAction: nil).withSymbols(symbol)
        }
        guard day.sessions > 0 else {
            return ModuleSnapshot(id: ClaudeUsageReader.moduleID, name: name, colorHex: color, status: "0",
                                  title: loc("Pas encore de Claude aujourd'hui"),
                                  subtitle: loc("Les sessions de Claude Code de la journée s'afficheront ici."),
                                  primaryAction: loc("Actualiser"), secondaryAction: nil).withSymbols(symbol)
        }
        let time = FrenchText.minutes(day.activeSeconds)
        let money = day.costUSD.map(dollars)
        var parts = [day.sessions == 1 ? loc("1 session") : loc("\(day.sessions) sessions"),
                     loc("\(tokens(day.outputTokens + day.inputTokens)) tokens")]
        if let money { parts.append(money) }
        var rows = [
            ModuleRow(id: "sessions", title: loc("Sessions"), detail: "", state: .neutral, label: "\(day.sessions)"),
            ModuleRow(id: "time", title: loc("Temps actif"), detail: "", state: .neutral, label: time),
            ModuleRow(id: "written", title: loc("Tokens écrits par Claude"), detail: "", state: .neutral, label: tokens(day.outputTokens)),
            ModuleRow(id: "read", title: loc("Tokens lus (cache compris)"), detail: "", state: .neutral, label: tokens(day.inputTokens)),
        ]
        rows.append(ModuleRow(id: "cost", title: loc("Coût au tarif API"),
                              detail: money == nil ? loc("compté par Claude Code à la fin d'une session") : "",
                              state: .neutral, label: money ?? "…"))
        return ModuleSnapshot(id: ClaudeUsageReader.moduleID, name: name, colorHex: color, status: money ?? time,
                              title: loc("\(time) avec Claude aujourd'hui"), subtitle: parts.joined(separator: " · "),
                              primaryAction: loc("Actualiser"), secondaryAction: nil, rows: rows).withSymbols(symbol)
    }

    static let moduleID = "claude-usage"
    static let color = "#D97757"
    static let symbol = "chart.bar.fill"

    /// "850", "12 k", "1,2 M"
    static func tokens(_ count: Int) -> String {
        switch count {
        case ..<1_000: return "\(count)"
        case ..<1_000_000: return "\(count / 1_000) k"
        default: return (Double(count) / 1_000_000).formatted(.number.precision(.fractionLength(1)).locale(AppLanguage.locale)) + " M"
        }
    }

    /// "4,20 $" in French, "$4.20" in English.
    static func dollars(_ value: Double) -> String {
        value.formatted(.currency(code: "USD").locale(AppLanguage.locale))
    }
}
