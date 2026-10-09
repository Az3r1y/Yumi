import Foundation

/// How much Claude Code was used today: sessions, time, tokens and cost, read from its
/// transcripts on this Mac. It reads every two minutes while selected, away from the main actor.
@MainActor
final class ClaudeUsageModule: YumiModule {
    let id = ClaudeUsageReader.moduleID
    private static let refreshInterval: Duration = .seconds(120)

    private let folder: URL
    private var day: ClaudeUsageDay?
    private var onChange: (@MainActor () -> Void)?
    private var refreshing: Task<Void, Never>?

    init(folder: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects")) {
        self.folder = folder
    }

    var snapshot: ModuleSnapshot { ClaudeUsageReader.snapshot(day) }

    func start(onChange: @escaping @MainActor () -> Void) {
        self.onChange = onChange
        refreshing?.cancel()
        refreshing = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: Self.refreshInterval, tolerance: .seconds(10))
            }
        }
    }

    func stop() {
        refreshing?.cancel()
        refreshing = nil
        onChange = nil
    }

    func perform(_ action: ModuleAction) {
        Task { await refresh() }
    }

    private func refresh() async {
        let folder = folder
        let midnight = Calendar.current.startOfDay(for: Date())
        let day = await Task.detached(priority: .utility) {
            ClaudeUsageReader.day(files: ClaudeUsageReader.files(in: folder, since: midnight), since: midnight)
        }.value
        guard day != self.day else { return }
        self.day = day
        onChange?()
    }
}
