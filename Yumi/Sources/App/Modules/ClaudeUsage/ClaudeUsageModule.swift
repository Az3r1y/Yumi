import Foundation

/// How much Claude Code was used today: the allowances, sessions, time, tokens and what it
/// would have cost at the API price. It reads every two minutes while selected, away from the
/// main actor.
@MainActor
final class ClaudeUsageModule: YumiModule {
    let id = ClaudeUsageReader.moduleID
    private static let refreshInterval: Duration = .seconds(120)

    private let folder: URL
    private var day: ClaudeUsageDay?
    private var onChange: (@MainActor () -> Void)?
    private var refreshing: Task<Void, Never>?
    /// The last allowances Anthropic gave, and when they were asked.
    private var quotas: (fiveHour: StatusLineRelay.Report.Allowance?, sevenDay: StatusLineRelay.Report.Allowance?)?
    private var quotasAsked = Date.distantPast
    private static let quotasInterval: TimeInterval = 5 * 60

    init(folder: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects")) {
        self.folder = folder
    }

    var snapshot: ModuleSnapshot { ClaudeUsageReader.snapshot(day, rate: EuroRate.current()) }

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
        // « Actualiser » asks Anthropic again, even within the five minutes
        quotasAsked = .distantPast
        Task { await refresh() }
    }

    private func refresh() async {
        let folder = folder
        let midnight = Calendar.current.startOfDay(for: Date())
        let measured = await Task.detached(priority: .utility) {
            let report = StatusLineRelay.report(in: StatusLineRelay.folder, since: midnight)
            var day = ClaudeUsageReader.day(files: ClaudeUsageReader.files(in: folder, since: midnight), since: midnight,
                                            live: report.sessionCosts)
            day.fiveHour = report.fiveHour
            day.sevenDay = report.sevenDay
            day.quotasConnected = StatusLineRelay.isInstalled
            return day
        }.value
        var day = measured
        // The day's euro, once a day
        let rateChanged = await EuroRate.refresh()
        #if !APPSTORE
        // Anthropic's own figures, at most every five minutes; the status line's otherwise
        if Date().timeIntervalSince(quotasAsked) >= Self.quotasInterval {
            quotasAsked = Date()
            let fetched = await Task.detached(priority: .utility) { () -> (fiveHour: StatusLineRelay.Report.Allowance?, sevenDay: StatusLineRelay.Report.Allowance?)? in
                guard let token = ClaudeQuotaAPI.accessToken() else { return nil }
                return await ClaudeQuotaAPI.fetch(token: token)
            }.value
            if let fetched { quotas = fetched }
        }
        if let quotas {
            day.fiveHour = quotas.fiveHour ?? measured.fiveHour
            day.sevenDay = quotas.sevenDay ?? measured.sevenDay
            day.quotasConnected = true
        }
        #endif
        guard day != self.day || rateChanged else { return }
        self.day = day
        onChange?()
    }
}
