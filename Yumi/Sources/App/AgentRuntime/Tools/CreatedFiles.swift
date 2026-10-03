import Foundation

/// The files Yumi created itself (`CreateFileTool`), the only ones `AppendToFileTool` may add
/// to. Written by the tools' code, never by a plan or a model.
protocol CreatedFilesLog: Sendable {
    func record(_ path: String)
    /// Absolute paths, most recent last.
    func paths() -> [String]
}

/// Kept in Yumi's folder, as a JSON list of paths. Nothing else: no content, no date.
final class FileCreatedFilesLog: CreatedFilesLog, @unchecked Sendable {
    static let limit = 200
    private let url: URL
    private let lock = NSLock()

    init(url: URL) { self.url = url }

    func record(_ path: String) {
        lock.withLock {
            var all = read().filter { $0 != path }
            all.append(path)
            if all.count > Self.limit { all.removeFirst(all.count - Self.limit) }
            guard let data = try? JSONEncoder().encode(all) else { return }
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: url, options: .atomic)
        }
    }

    func paths() -> [String] { lock.withLock { read() } }

    private func read() -> [String] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }
}

/// In memory, for the tests and for a run without a folder.
final class MemoryCreatedFilesLog: CreatedFilesLog, @unchecked Sendable {
    private let lock = NSLock()
    private var all: [String] = []
    init(_ paths: [String] = []) { all = paths }
    func record(_ path: String) { lock.withLock { all.removeAll { $0 == path }; all.append(path) } }
    func paths() -> [String] { lock.withLock { all } }
}
