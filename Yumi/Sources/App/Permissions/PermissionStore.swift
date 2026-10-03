import Foundation

/// What lasts after Yumi quits: the rules of the settings and the permissions the person chose
/// to remember (`.project`, `.resource`). No secret lives here: tokens and keys stay in the
/// Keychain (`KeychainStore`), and a permission never holds one.
struct PermissionRecord: Equatable, Codable, Sendable {
    var rules: [PolicyRule] = []
    var permissions: [Permission] = []
}

protocol PermissionStore: Sendable {
    func load() -> PermissionRecord
    func save(_ record: PermissionRecord)
}

/// In memory: the tests, and filming.
final class MemoryPermissionStore: PermissionStore, @unchecked Sendable {
    private let lock = NSLock()
    private var record: PermissionRecord

    init(_ record: PermissionRecord = PermissionRecord()) { self.record = record }

    func load() -> PermissionRecord { lock.withLock { record } }
    func save(_ record: PermissionRecord) { lock.withLock { self.record = record } }
}

/// `permissions.json` in Yumi's folder, written atomically, readable by the person only. What is
/// read back is checked again: a rule too broad or a permission above medium written by hand
/// is dropped.
final class FilePermissionStore: PermissionStore, @unchecked Sendable {
    private let url: URL
    private let lock = NSLock()

    init(url: URL) { self.url = url }

    func load() -> PermissionRecord {
        lock.withLock {
            guard let data = try? Data(contentsOf: url) else { return PermissionRecord() }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            if let record = try? decoder.decode(PermissionRecord.self, from: data) { return record }
            // Unreadable (edited by hand, cut short): put aside, never overwritten by the next save,
            // so that the person's refusals can still be read and restored.
            try? FileManager.default.moveItem(at: url, to: unreadableCopy)
            return PermissionRecord()
        }
    }

    /// Where an unreadable file is put aside: `permissions.unreadable-<seconds>.json`.
    private var unreadableCopy: URL {
        let name = url.deletingPathExtension().lastPathComponent
        return url.deletingLastPathComponent()
            .appendingPathComponent("\(name).unreadable-\(Int(Date().timeIntervalSince1970)).\(url.pathExtension)")
    }

    func save(_ record: PermissionRecord) {
        lock.withLock {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            guard let data = try? encoder.encode(record) else { return }
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: url, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
    }
}
