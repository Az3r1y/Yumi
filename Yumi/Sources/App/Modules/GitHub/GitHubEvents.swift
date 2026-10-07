import Foundation

/// One thing that happened on GitHub and concerns the person.
struct GitHubEvent: Equatable, Sendable {
    enum Kind: String, Sendable, Codable {
        case star, fork, pullRequest, merge, push, issue, release, follower

        var scene: YumiScene {
            switch self {
            case .star: return .star
            case .fork: return .fork
            case .pullRequest: return .pullRequest
            case .merge: return .merge
            case .push: return .push
            case .issue: return .issue
            case .release: return .release
            case .follower: return .follower
            }
        }

        /// The events Yumi says a word about; the others only get their scene.
        var isWorthAWord: Bool { [.star, .fork, .merge, .release].contains(self) }
    }

    /// GitHub's identifier of the event: they grow with time.
    var id: Int64
    var kind: Kind
    /// "owner/name".
    var repo: String
    /// Login of who did it.
    var actor: String
    /// Title of the pull request or issue, name of the release, branch of the push.
    var detail: String = ""
    var url: URL? = nil
    /// When it happened (`created_at`), when GitHub says.
    var date: Date? = nil
    /// A push: the commit before it and its head, to read its commits through compare.
    var before: String = ""
    var head: String = ""

    /// The repository's own name, without its owner.
    var repoName: String { repo.split(separator: "/").last.map(String.init) ?? repo }
}

/// What GitHub says about the person's most active repository.
struct GitHubRepo: Equatable, Sendable {
    var fullName: String
    var stars: Int
    var forks: Int
    var url: URL?
}

/// Where the checks (CI) of a pull request are.
enum GitHubChecks: String, Equatable, Sendable {
    case running, passed, failed
}

/// An open pull request of a followed repository.
struct GitHubPull: Equatable, Sendable {
    var repo: String
    var number: Int
    var title: String
    var author: String
    /// Head commit: its checks are the pull request's.
    var sha: String
    var url: URL?
    /// The person is asked to review it.
    var asksMyReview = false
    var updated: Date? = nil
    var checks: GitHubChecks? = nil

    var key: String { "\(repo)#\(number)" }
}

/// A pull request waiting for the person's review.
struct GitHubReview: Equatable, Sendable {
    var title: String
    var repo: String
    var url: URL?
}

/// Reads the answers of the GitHub API. Pure: data in, values out.
enum GitHubFeed {
    /// The events of a feed (`/users/{login}/events` or `/received_events`) that Yumi follows.
    /// - Parameter received: true for what others did. Only the person's own repositories count
    ///   there, and never what the person did (it is already in their own feed).
    /// - Parameter repos: the person's repositories (owned, shared, of their organisations). In
    ///   the received feed, what others do on them counts; nil keeps the person's own namespace.
    static func events(from data: Data, login: String, received: Bool, repos: Set<String>? = nil) -> [GitHubEvent] {
        guard let items = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return items.compactMap { item in
            guard let id = (item["id"] as? String).flatMap(Int64.init),
                  let repo = (item["repo"] as? [String: Any])?["name"] as? String,
                  let actor = (item["actor"] as? [String: Any])?["login"] as? String else { return nil }
            if received {
                let mine = repos.map { $0.contains(repo) } ?? false
                guard mine || repo.lowercased().hasPrefix(login.lowercased() + "/"), actor.lowercased() != login.lowercased() else { return nil }
            }
            let payload = item["payload"] as? [String: Any] ?? [:]
            let action = payload["action"] as? String ?? ""
            let page = URL(string: "https://github.com/\(repo)")
            let date = (item["created_at"] as? String).flatMap { try? Date($0, strategy: .iso8601) }
            let event: GitHubEvent? = {
            switch item["type"] as? String {
            case "WatchEvent" where action == "started":
                return GitHubEvent(id: id, kind: .star, repo: repo, actor: actor, url: page)
            case "ForkEvent":
                return GitHubEvent(id: id, kind: .fork, repo: repo, actor: actor, url: page)
            case "PullRequestEvent":
                let pull = payload["pull_request"] as? [String: Any] ?? [:]
                let url = (pull["html_url"] as? String).flatMap(URL.init(string:)) ?? page
                let title = pull["title"] as? String ?? ""
                if action == "opened" { return GitHubEvent(id: id, kind: .pullRequest, repo: repo, actor: actor, detail: title, url: url) }
                if action == "closed", pull["merged"] as? Bool == true || action == "merged" {
                    return GitHubEvent(id: id, kind: .merge, repo: repo, actor: actor, detail: title, url: url)
                }
                if action == "merged" { return GitHubEvent(id: id, kind: .merge, repo: repo, actor: actor, detail: title, url: url) }
                return nil
            case "PushEvent":
                let branch = (payload["ref"] as? String ?? "").replacingOccurrences(of: "refs/heads/", with: "")
                return GitHubEvent(id: id, kind: .push, repo: repo, actor: actor, detail: branch, url: page,
                                   before: payload["before"] as? String ?? "", head: payload["head"] as? String ?? "")
            case "IssuesEvent" where action == "opened":
                let issue = payload["issue"] as? [String: Any] ?? [:]
                return GitHubEvent(id: id, kind: .issue, repo: repo, actor: actor, detail: issue["title"] as? String ?? "",
                                   url: (issue["html_url"] as? String).flatMap(URL.init(string:)) ?? page)
            case "ReleaseEvent" where action == "published":
                let release = payload["release"] as? [String: Any] ?? [:]
                let name = (release["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? release["tag_name"] as? String ?? ""
                return GitHubEvent(id: id, kind: .release, repo: repo, actor: actor, detail: name,
                                   url: (release["html_url"] as? String).flatMap(URL.init(string:)) ?? page)
            default:
                return nil
            }
            }()
            return event.map { var dated = $0; dated.date = date; return dated }
        }
    }

    /// The open pull requests of a repository, from `/repos/{owner}/{name}/pulls`.
    static func pulls(from data: Data, repo: String, login: String?) -> [GitHubPull] {
        guard let items = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return items.compactMap { item in
            guard let number = item["number"] as? Int else { return nil }
            let reviewers = (item["requested_reviewers"] as? [[String: Any]] ?? []).compactMap { $0["login"] as? String }
            return GitHubPull(repo: repo, number: number, title: item["title"] as? String ?? "",
                              author: (item["user"] as? [String: Any])?["login"] as? String ?? "",
                              sha: (item["head"] as? [String: Any])?["sha"] as? String ?? "",
                              url: (item["html_url"] as? String).flatMap(URL.init(string:)),
                              asksMyReview: login.map { me in reviewers.contains { $0.lowercased() == me.lowercased() } } ?? false,
                              updated: (item["updated_at"] as? String).flatMap { try? Date($0, strategy: .iso8601) })
        }
    }

    /// Where the checks of a commit are, from `/repos/{owner}/{name}/commits/{sha}/check-runs`.
    /// nil when the commit has no checks.
    static func checks(from data: Data) -> GitHubChecks? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let runs = object["check_runs"] as? [[String: Any]], !runs.isEmpty else { return nil }
        let bad: Set<String> = ["failure", "timed_out", "cancelled", "action_required", "startup_failure"]
        if runs.contains(where: { bad.contains($0["conclusion"] as? String ?? "") }) { return .failed }
        if runs.contains(where: { ($0["status"] as? String ?? "completed") != "completed" }) { return .running }
        return .passed
    }

    /// The person's own repositories pushed to most recently, at most `limit`: the ones followed.
    static func followedRepos(from data: Data, limit: Int = 3) -> [String] {
        guard let items = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return Array(items.filter { $0["fork"] as? Bool != true && $0["archived"] as? Bool != true }
            .compactMap { $0["full_name"] as? String }.prefix(limit))
    }

    /// Login and number of followers, from `/user`.
    static func user(from data: Data) -> (login: String, followers: Int)? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let login = object["login"] as? String else { return nil }
        return (login, object["followers"] as? Int ?? 0)
    }

    /// The repository pushed to most recently, from `/user/repos?sort=pushed`. Forks of other
    /// people's work come after the person's own repositories.
    static func mostActiveRepo(from data: Data) -> GitHubRepo? {
        guard let items = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return nil }
        let own = items.first { $0["fork"] as? Bool != true } ?? items.first
        guard let repo = own, let name = repo["full_name"] as? String else { return nil }
        return GitHubRepo(fullName: name, stars: repo["stargazers_count"] as? Int ?? 0, forks: repo["forks_count"] as? Int ?? 0,
                          url: (repo["html_url"] as? String).flatMap(URL.init(string:)))
    }

    /// The answer of a search of issues: how many, and the first one.
    static func search(from data: Data) -> (count: Int, first: GitHubReview?) {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return (0, nil) }
        let first = (object["items"] as? [[String: Any]])?.first.map { item -> GitHubReview in
            let repo = (item["repository_url"] as? String ?? "").components(separatedBy: "/repos/").last ?? ""
            return GitHubReview(title: item["title"] as? String ?? "", repo: repo,
                                url: (item["html_url"] as? String).flatMap(URL.init(string:)))
        }
        return (object["total_count"] as? Int ?? 0, first)
    }
}

/// Tells what is new from what was already seen. The first time, everything already there is
/// history: it is recorded and nothing is reported.
struct GitHubTracker: Codable, Equatable, Sendable {
    /// The newest event seen in each feed.
    private var newest: [String: Int64] = [:]
    private var followers: Int?

    init() {}

    /// The events of this answer that were not seen before, oldest first.
    mutating func fresh(_ events: [GitHubEvent], feed: String) -> [GitHubEvent] {
        // An empty feed is a first look too: whatever comes next is new.
        let latest = events.map(\.id).max() ?? 0
        defer { newest[feed] = max(latest, newest[feed] ?? 0) }
        guard let seen = newest[feed] else { return [] }
        return events.filter { $0.id > seen }.sorted { $0.id < $1.id }
    }

    /// How many followers were gained since the last count. Never negative, and zero the first time.
    mutating func gained(followers count: Int) -> Int {
        defer { followers = count }
        guard let before = followers else { return 0 }
        return max(0, count - before)
    }
}

/// What to play for a batch of new events: one scene per kind, with how many there were.
enum GitHubScenes {
    static func scenes(for events: [GitHubEvent]) -> [(scene: YumiScene, count: Int)] {
        var order: [GitHubEvent.Kind] = []
        var counts: [GitHubEvent.Kind: Int] = [:]
        for event in events {
            if counts[event.kind] == nil { order.append(event.kind) }
            counts[event.kind, default: 0] += 1
        }
        return order.map { ($0.scene, counts[$0] ?? 1) }
    }

    /// True for a shell command that makes a commit.
    static func isCommit(_ command: String) -> Bool {
        command.range(of: #"(^|[;&|]\s*|\s)git\s+(-\S+\s+([^-\s]\S*\s+)?)*commit(\s|$)"#, options: .regularExpression) != nil
    }
}

/// What the module shows, in Yumi's voice.
enum GitHubSummary {
    enum Connection: Equatable, Sendable { case noToken, refused, offline, connected }

    /// The last event in one sentence.
    static func sentence(for event: GitHubEvent, count: Int = 1) -> String {
        let repo = event.repoName
        switch event.kind {
        case .star:
            return count > 1 ? loc("\(FrenchText.sentenceStart(FrenchText.spelled(count, feminine: true))) étoiles de plus sur \(repo).")
                             : loc("Une étoile de plus, de la part de \(event.actor).")
        case .fork:        return loc("\(event.actor) a forké \(repo).")
        case .pullRequest: return event.detail.isEmpty ? loc("Une pull request arrive sur \(repo).") : loc("Une pull request arrive : \(event.detail)")
        case .merge:       return event.detail.isEmpty ? loc("C'est fusionné sur \(repo).") : loc("C'est fusionné : \(event.detail)")
        case .push:        return event.detail.isEmpty ? loc("Du code est parti sur \(repo).") : loc("Du code est parti sur \(event.detail).")
        case .issue:       return event.detail.isEmpty ? loc("Une issue s'ouvre sur \(repo).") : loc("Une issue s'ouvre : \(event.detail)")
        case .release:     return event.detail.isEmpty ? loc("Une version de \(repo) est sortie.") : loc("\(event.detail) est sortie.")
        case .follower:    return count > 1 ? loc("\(FrenchText.sentenceStart(FrenchText.spelled(count))) personnes de plus te suivent.") : loc("Quelqu'un de plus te suit.")
        }
    }

    /// - Parameters:
    ///   - openPulls: open pull requests on the repository, when known.
    ///   - last: the latest event, with how many of its kind came together.
    ///   - pulls: open pull requests of the followed repositories, with their checks.
    ///   - recent: the latest events, newest first.
    ///   - red: a pull request whose checks just turned red.
    static func snapshot(connection: Connection, repo: GitHubRepo?, openPulls: Int?, last: (event: GitHubEvent, count: Int)?,
                         review: GitHubReview?, pulls: [GitHubPull] = [], recent: [GitHubEvent] = [],
                         red: GitHubPull? = nil) -> ModuleSnapshot {
        var snapshot = ModuleSnapshot(id: "github", name: "GitHub", colorHex: "#A371F7", status: loc("à brancher"),
                                      title: loc("Je ne vois pas ton GitHub."), subtitle: loc("Donne-moi un jeton, je surveille tes dépôts."),
                                      primaryAction: loc("Brancher"), secondaryAction: nil)
        switch connection {
        case .noToken:
            return snapshot.withSymbols("arrow.triangle.branch")
        case .refused:
            snapshot.status = loc("refusé")
            snapshot.title = loc("Ton jeton GitHub ne passe plus.")
            snapshot.subtitle = loc("Donne-m'en un neuf, je reprends ma garde.")
            return snapshot.withSymbols("arrow.triangle.branch")
        case .offline:
            snapshot.status = loc("hors ligne")
            snapshot.title = loc("Je n'arrive pas à joindre GitHub.")
            snapshot.subtitle = loc("Je réessaie dans un moment.")
            snapshot.primaryAction = loc("Ouvrir")
            return snapshot.withSymbols("arrow.triangle.branch")
        case .connected:
            break
        }

        // Stars, forks, open pull requests of the most active repository, in that order.
        if let repo {
            snapshot.status = openPulls.map { "\(repo.stars) · \(repo.forks) · \($0)" } ?? "\(repo.stars)"
            snapshot.subtitle = repo.fullName
        } else {
            snapshot.status = "…"
            snapshot.subtitle = loc("Je regarde tes dépôts.")
        }
        snapshot.title = last.map { sentence(for: $0.event, count: $0.count) } ?? loc("Rien de neuf. Je surveille.")
        snapshot.primaryAction = loc("Ouvrir")

        if let review {
            snapshot.title = review.title.isEmpty ? loc("Une pull request t'attend.") : loc("Une pull request t'attend : \(review.title)")
            snapshot.primaryAction = loc("Relire")
            snapshot.needsAttention = true
            snapshot.live = ModuleLive(text: review.title.isEmpty ? loc("Une relecture t'attend") : loc("Relecture : \(review.title)"),
                                       priority: ModuleLivePriority.attention,
                                       controls: [ModuleControl(id: ModuleAction.primary.rawValue, symbol: "eye.fill", label: loc("Relire"))])
        }
        // Checks gone red come before everything: something is broken now.
        if let red {
            snapshot.title = loc("La CI ne passe plus : \(red.title)")
            snapshot.primaryAction = loc("Voir")
            snapshot.needsAttention = true
            snapshot.live = ModuleLive(text: loc("CI rouge : \(red.title)"), priority: ModuleLivePriority.attention,
                                       controls: [ModuleControl(id: ModuleAction.primary.rawValue, symbol: "eye.fill", label: loc("Voir"))])
        }
        snapshot.rows = GitHubBoard.rows(pulls: pulls, recent: recent)
        return snapshot.withSymbols("arrow.triangle.branch")
    }
}

/// The list of the GitHub activity: the open pull requests of each followed repository, then
/// the latest events.
enum GitHubBoard {
    /// Pull requests shown per repository, events shown in all.
    static let pullsPerRepo = 4
    static let events = 4

    static func rows(pulls: [GitHubPull], recent: [GitHubEvent]) -> [ModuleRow] {
        var rows: [ModuleRow] = []
        var repos: [String] = []
        for pull in pulls where !repos.contains(pull.repo) { repos.append(pull.repo) }
        for repo in repos {
            let ordered = pulls.filter { $0.repo == repo }.sorted { rank($0) != rank($1) ? rank($0) < rank($1) : $0.number > $1.number }
            for (index, pull) in ordered.prefix(pullsPerRepo).enumerated() {
                rows.append(row(pull, section: index == 0 ? repo : nil))
            }
        }
        for (index, event) in recent.prefix(events).enumerated() {
            rows.append(ModuleRow(id: "event-\(event.id)", title: title(event), detail: "\(event.actor) · \(event.repoName)",
                                  state: .neutral, label: label(event.kind), date: event.date,
                                  section: index == 0 ? "Derniers événements" : nil,
                                  action: event.url?.absoluteString))
        }
        return rows
    }

    /// Asked for review first, then red, running, green, without checks.
    private static func rank(_ pull: GitHubPull) -> Int {
        if pull.asksMyReview { return 0 }
        switch pull.checks {
        case .failed:  return 1
        case .running: return 2
        case .passed:  return 3
        case nil:      return 4
        }
    }

    static func row(_ pull: GitHubPull, section: String?) -> ModuleRow {
        var row = ModuleRow(id: pull.key, title: pull.title.isEmpty ? loc("#\(pull.number)") : pull.title,
                            detail: loc("#\(pull.number) · \(pull.author)"), state: .neutral, label: loc("ouverte"),
                            date: pull.updated, section: section, action: pull.url?.absoluteString)
        switch pull.checks {
        case .failed:  row.state = .failure; row.label = loc("CI rouge")
        case .running: row.state = .busy;    row.label = loc("CI en cours")
        case .passed:  row.state = .success; row.label = loc("CI verte")
        case nil:      break
        }
        if pull.asksMyReview {
            row.state = .waiting
            row.label = loc("ta review")
        }
        return row
    }

    private static func title(_ event: GitHubEvent) -> String {
        switch event.kind {
        case .star:        return loc("Une étoile")
        case .fork:        return loc("Un fork")
        case .follower:    return "Quelqu'un te suit"
        case .push:        return event.detail.isEmpty ? loc("Du code poussé") : loc("Poussé sur \(event.detail)")
        default:           return event.detail.isEmpty ? event.repoName : event.detail
        }
    }

    private static func label(_ kind: GitHubEvent.Kind) -> String {
        switch kind {
        case .star: return "star"
        case .fork: return "fork"
        case .pullRequest: return "pull request"
        case .merge: return "merge"
        case .push: return "push"
        case .issue: return "issue"
        case .release: return "version"
        case .follower: return loc("abonné")
        }
    }

    /// Pull requests whose checks turned red since the last look. A first look reports nothing:
    /// what was already red is history.
    static func turnedRed(before: [GitHubPull]?, after: [GitHubPull]) -> [GitHubPull] {
        guard let before else { return [] }
        let was = Dictionary(before.map { ($0.key, $0.checks) }, uniquingKeysWith: { a, _ in a })
        return after.filter { pull in
            guard pull.checks == .failed, let old = was[pull.key] else { return false }
            return old != .failed
        }
    }
}
