import Foundation
import Observation

/// One permission decision, as kept on this Mac. What was decided, about what, by whom; never
/// the arguments, the content of a file, the planner's text, or anything that looks like a secret.
struct PermissionAuditEntry: Identifiable, Equatable, Codable, Sendable {
    enum Decision: String, Codable, Sendable {
        /// Ran without asking (safe, a rule, or something allowed before).
        case allowed
        /// The person approved.
        case approved
        /// The person refused.
        case denied
        /// Nobody answered in time.
        case expired
        /// The run or the request was cancelled.
        case cancelled
        /// Refused without asking: a rule, a critical risk, an invalid resource.
        case blocked
    }

    enum DecidedBy: String, Codable, Sendable {
        /// Nothing to ask: a safe action, or a default.
        case defaults
        /// A rule of the settings.
        case rule
        /// Something the person allowed before.
        case permission
        /// The person, now.
        case user
        /// The system: an expiry, a cancellation, an invalid request.
        case system
    }

    var id = UUID()
    var date: Date
    var runID: UUID?
    var stepID: String?
    var approvalID: UUID?
    var toolID: String
    var action: String?
    /// At most five, relative to their project, cleaned of anything that looks like a secret.
    var resources: [String]
    var resourceCount: Int
    var risk: RiskLevel
    var decision: Decision
    var scope: PermissionScope?
    var decidedBy: DecidedBy
}

/// Where the history is kept. A file in Yumi's folder in the app, memory in the tests.
protocol AuditSink: Sendable {
    func load() -> [PermissionAuditEntry]
    func append(_ entry: PermissionAuditEntry)
    func clear()
}

/// The history of permission decisions, newest last. The person can read and clear it from
/// the settings. Kept on this Mac only.
@MainActor
@Observable
final class PermissionAuditLog {
    static let memoryLimit = 300

    @ObservationIgnored private let sink: any AuditSink
    private(set) var entries: [PermissionAuditEntry]

    init(sink: any AuditSink) {
        self.sink = sink
        entries = Array(sink.load().suffix(Self.memoryLimit))
    }

    func record(_ entry: PermissionAuditEntry) {
        var clean = entry
        clean.toolID = AuditRedactor.clean(entry.toolID)
        clean.stepID = entry.stepID.map(AuditRedactor.clean)
        clean.resources = entry.resources.prefix(5).map(AuditRedactor.clean)
        entries.append(clean)
        if entries.count > Self.memoryLimit { entries.removeFirst(entries.count - Self.memoryLimit) }
        sink.append(clean)
    }

    func clear() {
        entries = []
        sink.clear()
    }
}

/// Removes from a line what must never be written down: keys, tokens, passwords, query strings.
enum AuditRedactor {
    private static let patterns: [String] = [
        // Known token shapes.
        #"gh[pousr]_[A-Za-z0-9]{20,}"#, #"github_pat_[A-Za-z0-9_]{20,}"#, #"sk-[A-Za-z0-9_\-]{16,}"#,
        #"xox[abposr]-[A-Za-z0-9\-]{10,}"#, #"AKIA[0-9A-Z]{16}"#, #"AIza[0-9A-Za-z_\-]{30,}"#,
        #"eyJ[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{5,}"#,
        // key=value, password: value, Bearer value.
        #"(?i)\bauthorization\s*[:=].*"#,
        #"(?i)\b(password|passwd|pwd|secret|token|api[_-]?key|apikey)\s*[:=]\s*\S+"#,
        #"(?i)\bbearer\s+\S+"#,
        // Credentials in a URL, and query strings.
        #"://[^/\s:@]+:[^/\s@]+@"#, #"\?[^\s]*"#,
        // Long runs of letters and digits that look like keys.
        #"[A-Za-z0-9+_\-]{32,}={0,2}"#,
    ]
    private static let expressions = patterns.compactMap { try? NSRegularExpression(pattern: $0) }

    static func clean(_ text: String) -> String {
        var result = text
        for expression in expressions {
            let range = NSRange(result.startIndex..., in: result)
            result = expression.stringByReplacingMatches(in: result, range: range, withTemplate: "•••")
        }
        return result.count > 160 ? String(result.prefix(159)) + "…" : result
    }
}

/// The history in memory: for the tests, and while filming.
final class MemoryAuditSink: AuditSink, @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [PermissionAuditEntry] = []

    init(_ entries: [PermissionAuditEntry] = []) { lines = entries }

    func load() -> [PermissionAuditEntry] { lock.withLock { lines } }
    func append(_ entry: PermissionAuditEntry) { lock.withLock { lines.append(entry) } }
    func clear() { lock.withLock { lines = [] } }
}

/// The history in a file of Yumi's folder, one JSON object per line, readable by the person only.
/// Past `limit` lines, the oldest half is dropped.
final class FileAuditSink: AuditSink, @unchecked Sendable {
    private let url: URL
    private let limit: Int
    private let lock = NSLock()

    init(url: URL, limit: Int = 2_000) {
        self.url = url
        self.limit = limit
    }

    func load() -> [PermissionAuditEntry] {
        lock.withLock { readAll() }
    }

    func append(_ entry: PermissionAuditEntry) {
        lock.withLock {
            guard let line = Self.encode(entry) else { return }
            let manager = FileManager.default
            if !manager.fileExists(atPath: url.path) {
                try? manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                manager.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600])
            }
            guard let handle = try? FileHandle(forWritingTo: url) else { return }
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data((line + "\n").utf8))
            trimIfNeeded()
        }
    }

    func clear() {
        lock.withLock { try? FileManager.default.removeItem(at: url) }
    }

    private func readAll() -> [PermissionAuditEntry] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return String(decoding: data, as: UTF8.self).split(separator: "\n").compactMap {
            try? decoder.decode(PermissionAuditEntry.self, from: Data($0.utf8))
        }
    }

    private func trimIfNeeded() {
        let entries = readAll()
        guard entries.count > limit else { return }
        let kept = entries.suffix(limit / 2).compactMap(Self.encode).joined(separator: "\n") + "\n"
        try? Data(kept.utf8).write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private static func encode(_ entry: PermissionAuditEntry) -> String? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(entry)).map { String(decoding: $0, as: UTF8.self) }
    }
}
