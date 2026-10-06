import Foundation

/// Reading and merging Claude Code's `~/.claude/settings.json` for Yumi's hooks. Pure: the
/// caller reads and writes the file. What cannot be read safely is refused, never replaced:
/// the file is the person's, and only Yumi's own hooks may change in it.
enum HookSettings {
    enum Problem: Error, Equatable, LocalizedError {
        /// The file exists but is not valid JSON.
        case notJSON
        /// Valid JSON, but not an object at the top.
        case notAnObject
        /// "hooks" is there but is not an object, or one of its events is not a list.
        case unexpectedHooks(String)

        var errorDescription: String? {
            switch self {
            case .notJSON: loc("~/.claude/settings.json n'est pas un JSON valide. Corrige-le (ou supprime-le s'il est vide), puis réessaie : je n'y ai pas touché.")
            case .notAnObject: loc("~/.claude/settings.json ne contient pas un objet JSON. Je n'y ai pas touché.")
            case .unexpectedHooks(let key): loc("Dans ~/.claude/settings.json, « \(key) » n'a pas la forme attendue. Je n'y ai pas touché.")
            }
        }
    }

    /// The settings as an object. A missing or blank file is an empty object; anything else
    /// that is not a JSON object is a problem.
    static func parse(_ data: Data?) throws(Problem) -> [String: Any] {
        guard let data, !String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [:] }
        let object: Any
        do { object = try JSONSerialization.jsonObject(with: data) } catch { throw .notJSON }
        guard let settings = object as? [String: Any] else { throw .notAnObject }
        if let hooks = settings["hooks"] {
            guard let events = hooks as? [String: Any] else { throw .unexpectedHooks("hooks") }
            for (key, value) in events where !(value is [[String: Any]]) { throw .unexpectedHooks("hooks.\(key)") }
        }
        return settings
    }

    /// The settings with Yumi's hooks, once per event, and without Coucou's or NotchBuddy's.
    /// Everything else is kept as it was.
    static func merge(_ data: Data?, command: String, events: [(String, Int)],
                      isOwn: (String) -> Bool, isLegacy: (String) -> Bool) throws(Problem) -> (data: Data, legacyRemoved: Int) {
        var settings = try parse(data)
        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        var legacy = 0
        for key in hooks.keys {
            guard var matchers = hooks[key] as? [[String: Any]] else { continue }
            legacy += strip(&matchers, where: isLegacy)
            _ = strip(&matchers, where: isOwn)
            if matchers.isEmpty { hooks.removeValue(forKey: key) } else { hooks[key] = matchers }
        }
        for (event, timeout) in events {
            var existing = hooks[event] as? [[String: Any]] ?? []
            existing.append(["hooks": [["type": "command", "command": command, "timeout": timeout]]])
            hooks[event] = existing
        }
        settings["hooks"] = hooks
        guard let out = try? JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys]) else { throw .notAnObject }
        return (out, legacy)
    }

    /// Removes the hooks whose command matches; a matcher left empty is dropped. Returns how many.
    static func strip(_ matchers: inout [[String: Any]], where shouldRemove: (String) -> Bool) -> Int {
        var removed = 0
        matchers = matchers.compactMap { matcher in
            let list = matcher["hooks"] as? [[String: Any]] ?? []
            let kept = list.filter { !(($0["command"] as? String).map(shouldRemove) ?? false) }
            guard kept.count < list.count else { return matcher }
            removed += list.count - kept.count
            guard !kept.isEmpty else { return nil }
            var matcher = matcher
            matcher["hooks"] = kept
            return matcher
        }
        return removed
    }

    /// A backup name that does not exist yet: `settings.json.bak-20261005-1412`, then `-2`, `-3`…
    static func backupURL(for settings: URL, now: Date, exists: (URL) -> Bool) -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmm"
        let base = settings.deletingLastPathComponent().appendingPathComponent("settings.json.bak-\(formatter.string(from: now))")
        var candidate = base
        var index = 2
        while exists(candidate) {
            candidate = URL(fileURLWithPath: base.path + "-\(index)")
            index += 1
        }
        return candidate
    }
}
