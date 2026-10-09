import Foundation

/// Claude Code gives its status line what `/usage` shows: how much of the five-hour and of the
/// weekly allowance is used, and what each session cost so far. Yumi's relay stands in front of
/// the person's own status line: it keeps a copy of what Claude Code sent, then hands it to the
/// status line that was there, whose display does not change.
///
/// In ~/.claude/settings.json only `statusLine` changes, after the person read it, with a backup;
/// the status line it replaced is kept beside the relay and put back when the relay is removed.
enum StatusLineRelay {
    static let scriptName = "yumi-statusline.sh"
    /// The command of the status line that was there, run after the copy is made.
    static let nextName = "statusline-next"
    /// The `statusLine` object that was there, to put back.
    static let previousName = "statusline-previous.json"
    /// One copy per session, by session id.
    static let reportsFolder = "status"

    static func scriptURL(in folder: URL) -> URL { folder.appendingPathComponent(scriptName) }

    static func command(in folder: URL) -> String {
        "/bin/sh \"\(scriptURL(in: folder).path.replacingOccurrences(of: "\"", with: "\\\""))\""
    }

    /// What Claude Code runs. It copies its input and hands it on; without a session id it only
    /// hands it on. Never fails Claude Code: every step may fail on its own.
    static let script = """
        #!/bin/sh
        # yumi-statusline.sh: keeps what Claude Code tells its status line (allowance used, cost of
        # the session) for Yumi, then hands it to the status line that was there before.
        here="$(dirname "$0")"
        dir="$here/\(reportsFolder)"
        mkdir -p "$dir" 2>/dev/null
        input="$dir/.input.$$"
        cat > "$input"
        id=$(sed -n 's/.*"session_id" *: *"\\([A-Za-z0-9_-]*\\)".*/\\1/p' "$input" | head -n 1)
        if [ -n "$id" ]; then cp "$input" "$dir/.$id.$$" 2>/dev/null && mv -f "$dir/.$id.$$" "$dir/$id.json"; fi
        if [ -s "$here/\(nextName)" ]; then /bin/sh -c "$(cat "$here/\(nextName)")" < "$input"; fi
        rm -f "$input"

        """

    // MARK: - settings.json

    /// The settings with the relay as status line, everything else kept. `previous` is the status
    /// line that was there, nil when there was none or it was already the relay.
    static func install(_ data: Data?, command: String) throws(HookSettings.Problem) -> (data: Data, previous: [String: Any]?) {
        var settings = try HookSettings.parse(data)
        let current = settings["statusLine"] as? [String: Any]
        let isOwn = (current?["command"] as? String) == command
        var line = current ?? [:]
        line["type"] = "command"
        line["command"] = command
        settings["statusLine"] = line
        return (try encode(settings), isOwn ? nil : current)
    }

    /// The settings with the status line that was there before the relay, or none.
    static func remove(_ data: Data?, command: String, previous: [String: Any]?) throws(HookSettings.Problem) -> Data {
        var settings = try HookSettings.parse(data)
        // Changed by someone since: theirs now, left alone
        guard (settings["statusLine"] as? [String: Any])?["command"] as? String == command else { return try encode(settings) }
        settings["statusLine"] = previous
        return try encode(settings)
    }

    static func isInstalled(_ data: Data?, command: String) -> Bool {
        guard let settings = try? HookSettings.parse(data) else { return false }
        return (settings["statusLine"] as? [String: Any])?["command"] as? String == command
    }

    private static func encode(_ settings: [String: Any]) throws(HookSettings.Problem) -> Data {
        guard let data = try? JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys]) else {
            throw .notAnObject
        }
        return data
    }

    // MARK: - On disk

    static var folder: URL { AppIdentity.supportDirectory }
    static var settingsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")
    }

    static var isInstalled: Bool { isInstalled(try? Data(contentsOf: settingsURL), command: command(in: folder)) }

    /// The settings as they will be written, without writing anything.
    static func prepareInstall() throws -> (data: Data, previous: [String: Any]?) {
        try install(currentSettings(), command: command(in: folder))
    }

    /// Writes the relay, remembers the status line it stands in front of, then the settings,
    /// after a backup of them. Nothing is written in the settings if a step before fails.
    static func confirmInstall(_ prepared: (data: Data, previous: [String: Any]?)) throws {
        let manager = FileManager.default
        try manager.createDirectory(at: folder, withIntermediateDirectories: true)
        try script.write(to: scriptURL(in: folder), atomically: true, encoding: .utf8)
        try manager.setAttributes([.posixPermissions: 0o755 as NSNumber], ofItemAtPath: scriptURL(in: folder).path)
        // Installed again over itself: what it stands in front of is already kept
        if let previous = prepared.previous {
            try JSONSerialization.data(withJSONObject: previous).write(to: folder.appendingPathComponent(previousName), options: .atomic)
            try ((previous["command"] as? String) ?? "").write(to: folder.appendingPathComponent(nextName), atomically: true, encoding: .utf8)
        } else if !manager.fileExists(atPath: folder.appendingPathComponent(previousName).path) {
            try "".write(to: folder.appendingPathComponent(nextName), atomically: true, encoding: .utf8)
        }
        try backUpAndWrite(prepared.data)
    }

    /// Puts back the status line that was there; the copies of the sessions go too.
    static func uninstall() throws {
        let previousURL = folder.appendingPathComponent(previousName)
        let previous = (try? Data(contentsOf: previousURL)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        try backUpAndWrite(try remove(currentSettings(), command: command(in: folder), previous: previous))
        for name in [previousName, nextName, scriptName, reportsFolder] {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(name))
        }
    }

    private static func currentSettings() throws -> Data? {
        guard FileManager.default.fileExists(atPath: settingsURL.path) else { return nil }
        return try Data(contentsOf: settingsURL)
    }

    private static func backUpAndWrite(_ data: Data) throws {
        let manager = FileManager.default
        try manager.createDirectory(at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if manager.fileExists(atPath: settingsURL.path) {
            try manager.copyItem(at: settingsURL, to: HookSettings.backupURL(for: settingsURL, now: Date()) { manager.fileExists(atPath: $0.path) })
        }
        try data.write(to: settingsURL, options: .atomic)
    }

    // MARK: - What Claude Code said

    /// The allowance and the cost, from the copies of the sessions.
    struct Report: Equatable, Sendable {
        struct Allowance: Equatable, Sendable {
            /// 0 to 100.
            var usedPercent: Double
            var resetsAt: Date?
        }
        var fiveHour: Allowance?
        var sevenDay: Allowance?
        /// What each session cost so far at the API price, in dollars, by session id.
        var sessionCosts: [String: Double] = [:]
    }

    /// The allowances of the latest copy that has them, and the cost of every session copied
    /// since `since`. Copies older than two days are deleted.
    static func report(in folder: URL, since: Date, now: Date = Date()) -> Report {
        let manager = FileManager.default
        let reports = folder.appendingPathComponent(reportsFolder)
        let files = (try? manager.contentsOfDirectory(at: reports, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        var report = Report()
        var latest = Date.distantPast
        for file in files where file.pathExtension == "json" && !file.lastPathComponent.hasPrefix(".") {
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            if now.timeIntervalSince(modified) > 2 * 86_400 { try? manager.removeItem(at: file); continue }
            guard modified >= since, let data = try? Data(contentsOf: file),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            let session = file.deletingPathExtension().lastPathComponent
            if let cost = (object["cost"] as? [String: Any])?["total_cost_usd"] as? Double { report.sessionCosts[session] = cost }
            guard let limits = object["rate_limits"] as? [String: Any], modified > latest else { continue }
            latest = modified
            report.fiveHour = allowance(limits["five_hour"])
            report.sevenDay = allowance(limits["seven_day"])
        }
        return report
    }

    private static func allowance(_ value: Any?) -> Report.Allowance? {
        guard let object = value as? [String: Any], let used = (object["used_percentage"] as? NSNumber)?.doubleValue else { return nil }
        let resets: Date? = switch object["resets_at"] {
        case let seconds as NSNumber: Date(timeIntervalSince1970: seconds.doubleValue)
        case let text as String: ISO8601DateFormatter().date(from: text)
        default: nil
        }
        return Report.Allowance(usedPercent: used, resetsAt: resets)
    }
}
