import AppKit

/// GitHub, as a module: the person's repositories, what happens on them, and a small scene of
/// Yumi for each event (Contracts/EventAnimations.swift).
///
/// It asks GitHub the way GitHub wants to be asked: every request carries the `ETag` of the last
/// answer, so an unchanged feed costs nothing of the quota, and the event feeds are never asked
/// more often than their `X-Poll-Interval` header says (one minute or more).
@MainActor
final class GitHubModule: YumiModule {
    let id = "github"

    /// One answer of the API.
    struct Response: Sendable {
        var status: Int
        var data: Data
        var headers: [String: String]
    }
    typealias Fetch = @Sendable (URLRequest) async throws -> Response

    /// Seconds between two looks at the event feeds, unless GitHub asks for more.
    static let pollInterval: TimeInterval = 60
    /// Repositories, followers and reviews change slowly: asked every fifth look.
    static let slowEvery = 5
    private static let trackerKey = "githubTracker"

    private let token: @MainActor () -> String?
    private let fetch: Fetch
    private let defaults: UserDefaults
    private let onConnect: @MainActor () -> Void
    /// Events worth a word of Yumi (a star, a fork, a merge, a release), with how many came together.
    private let onNews: @MainActor (GitHubEvent, Int) -> Void
    /// Total repositories and stars, for the old integration card.
    private let onTotals: @MainActor (Int, Int) -> Void
    /// Plays a scene: by default, the notification of the contract.
    private let play: @MainActor (YumiScene, Int) -> Void

    private var onChange: (@MainActor () -> Void)?
    private var polling: Task<Void, Never>?
    private var tracker: GitHubTracker
    private var etags: [String: String] = [:]
    private var login: String?
    private var connection = GitHubSummary.Connection.noToken
    private var repo: GitHubRepo?
    private var openPulls: Int?
    private var review: GitHubReview?
    private var last: (event: GitHubEvent, count: Int)?
    private var wait = GitHubModule.pollInterval
    private var looks = 0

    init(token: @escaping @MainActor () -> String?,
         defaults: UserDefaults = .standard,
         fetch: @escaping Fetch = GitHubModule.network,
         onConnect: @escaping @MainActor () -> Void = {},
         onNews: @escaping @MainActor (GitHubEvent, Int) -> Void = { _, _ in },
         onTotals: @escaping @MainActor (Int, Int) -> Void = { _, _ in },
         play: @escaping @MainActor (YumiScene, Int) -> Void = { scene, count in
             NotificationCenter.default.post(name: .yumiScene, object: scene, userInfo: count > 1 ? ["count": count] : nil)
         }) {
        self.play = play
        self.token = token
        self.defaults = defaults
        self.fetch = fetch
        self.onConnect = onConnect
        self.onNews = onNews
        self.onTotals = onTotals
        tracker = defaults.data(forKey: Self.trackerKey).flatMap { try? JSONDecoder().decode(GitHubTracker.self, from: $0) } ?? GitHubTracker()
    }

    var snapshot: ModuleSnapshot {
        GitHubSummary.snapshot(connection: connection, repo: repo, openPulls: openPulls, last: last, review: review)
    }

    // MARK: Lifecycle

    func start(onChange: @escaping @MainActor () -> Void) {
        self.onChange = onChange
        restart()
    }

    func stop() {
        onChange = nil
        polling?.cancel()
        polling = nil
    }

    /// Looks now, then again at GitHub's pace. Without a token nothing is asked and nothing loops.
    private func restart() {
        polling?.cancel()
        polling = nil
        guard token() != nil else {
            set(.noToken)
            return
        }
        polling = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.look()
                try? await Task.sleep(for: .seconds(self.wait), tolerance: .seconds(10))
            }
        }
    }

    private func set(_ new: GitHubSummary.Connection) {
        guard new != connection else { return }
        connection = new
        onChange?()
    }

    // MARK: Actions

    func perform(_ action: ModuleAction) {
        switch action {
        case .primary:
            if connection == .noToken || connection == .refused {
                onConnect()
            } else if let url = review?.url ?? repo?.url ?? URL(string: "https://github.com") {
                NSWorkspace.shared.open(url)
            }
        case .secondary:
            // The settings just saved a token: read it again without waiting.
            etags = [:]
            login = nil
            restart()
        }
    }

    // MARK: Local commits

    func receive(_ event: YumiEvent, sessions: [SessionID: Session]) {
        // A commit made by a Claude Code session is known the moment its command ends: nothing
        // watches the disk for it.
        guard case .toolFinished(_, let tool) = event, tool.name == "Bash", GitHubScenes.isCommit(tool.summary) else { return }
        play(.commit, 1)
    }

    // MARK: Asking GitHub

    /// One look at GitHub. Internal so tests can drive it without waiting.
    func look() async {
        guard let token = token() else {
            set(.noToken)
            return
        }
        looks += 1
        let slow = looks % Self.slowEvery == 1 || login == nil

        if slow {
            switch await get("/user", token: token) {
            case .fresh(let data):
                guard let user = GitHubFeed.user(from: data) else { break }
                login = user.login
                let gained = tracker.gained(followers: user.followers)
                if gained > 0 {
                    let event = GitHubEvent(id: 0, kind: .follower, repo: "", actor: "")
                    announce([GitHubEvent](repeating: event, count: gained))
                }
            case .refused:
                set(.refused)
                return
            case .failed:
                if login == nil { set(.offline) }
                return
            case .unchanged:
                break
            }
        }
        guard let login else { return }
        set(.connected)

        for (feed, received) in [("events", false), ("received_events", true)] {
            if case .fresh(let data) = await get("/users/\(login)/\(feed)?per_page=30", token: token, paced: true) {
                announce(tracker.fresh(GitHubFeed.events(from: data, login: login, received: received), feed: feed))
            }
        }
        if slow {
            if case .fresh(let data) = await get("/user/repos?per_page=100&affiliation=owner&sort=pushed", token: token) {
                repo = GitHubFeed.mostActiveRepo(from: data)
                let totals = GitHubFeed.totals(from: data)
                onTotals(totals.repos, totals.stars)
            }
            if let repo, case .fresh(let data) = await get("/search/issues?per_page=1&q=" + Self.query("repo:\(repo.fullName) is:pr is:open"), token: token) {
                openPulls = GitHubFeed.search(from: data).count
            }
            if case .fresh(let data) = await get("/search/issues?per_page=1&q=" + Self.query("is:pr is:open review-requested:\(login)"), token: token) {
                review = GitHubFeed.search(from: data).first
            }
        }
        if let data = try? JSONEncoder().encode(tracker) { defaults.set(data, forKey: Self.trackerKey) }
        onChange?()
    }

    /// Plays the scenes of new events and tells Yumi about the ones that count.
    private func announce(_ events: [GitHubEvent]) {
        guard let latest = events.last else { return }
        for (scene, count) in GitHubScenes.scenes(for: events) {
            play(scene, count)
        }
        last = (latest, events.filter { $0.kind == latest.kind }.count)
        // One word at most for a batch: about the latest event that counts.
        if let worth = events.last(where: { $0.kind.isWorthAWord }) {
            onNews(worth, events.filter { $0.kind == worth.kind }.count)
        }
        onChange?()
    }

    private enum Answer { case fresh(Data), unchanged, refused, failed }

    /// A conditional request: the tag of the last answer goes with it, and "not modified" costs nothing.
    private func get(_ path: String, token: String, paced: Bool = false) async -> Answer {
        guard let url = URL(string: "https://api.github.com" + path) else { return .failed }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        if let tag = etags[path] { request.setValue(tag, forHTTPHeaderField: "If-None-Match") }
        guard let response = try? await fetch(request) else { return .failed }
        if paced, let asked = response.headers["x-poll-interval"].flatMap(Double.init) {
            wait = max(Self.pollInterval, asked)
        }
        switch response.status {
        case 200:
            if let tag = response.headers["etag"] { etags[path] = tag }
            return .fresh(response.data)
        case 304:
            return .unchanged
        case 401:
            return .refused
        case 403, 429:
            // Out of quota: wait until GitHub says it is back, an hour at most.
            if let reset = response.headers["x-ratelimit-reset"].flatMap(Double.init) {
                wait = min(3600, max(Self.pollInterval, reset - Date().timeIntervalSince1970))
            } else {
                wait = max(wait, 300)
            }
            return .failed
        default:
            return .failed
        }
    }

    private static func query(_ text: String) -> String {
        text.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? text
    }

    /// The real network. Header names are lowercased so they can be read whatever their case.
    nonisolated static let network: Fetch = { request in
        let (data, response) = try await URLSession.shared.data(for: request)
        let http = response as? HTTPURLResponse
        var headers: [String: String] = [:]
        for (key, value) in http?.allHeaderFields ?? [:] {
            if let key = key as? String, let value = value as? String { headers[key.lowercased()] = value }
        }
        return Response(status: http?.statusCode ?? 0, data: data, headers: headers)
    }
}
