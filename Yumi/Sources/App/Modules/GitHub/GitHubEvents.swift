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
    static func events(from data: Data, login: String, received: Bool) -> [GitHubEvent] {
        guard let items = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return items.compactMap { item in
            guard let id = (item["id"] as? String).flatMap(Int64.init),
                  let repo = (item["repo"] as? [String: Any])?["name"] as? String,
                  let actor = (item["actor"] as? [String: Any])?["login"] as? String else { return nil }
            if received {
                guard repo.lowercased().hasPrefix(login.lowercased() + "/"), actor.lowercased() != login.lowercased() else { return nil }
            }
            let payload = item["payload"] as? [String: Any] ?? [:]
            let action = payload["action"] as? String ?? ""
            let page = URL(string: "https://github.com/\(repo)")
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
                return GitHubEvent(id: id, kind: .push, repo: repo, actor: actor, detail: branch, url: page)
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
        }
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

    /// Total stars and number of repositories, for the old integration card.
    static func totals(from data: Data) -> (repos: Int, stars: Int) {
        let items = (try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
        return (items.count, items.reduce(0) { $0 + ($1["stargazers_count"] as? Int ?? 0) })
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
            return count > 1 ? "\(FrenchText.sentenceStart(FrenchText.spelled(count, feminine: true))) étoiles de plus sur \(repo)."
                             : "Une étoile de plus, de la part de \(event.actor)."
        case .fork:        return "\(event.actor) a forké \(repo)."
        case .pullRequest: return event.detail.isEmpty ? "Une pull request arrive sur \(repo)." : "Une pull request arrive : \(event.detail)"
        case .merge:       return event.detail.isEmpty ? "C'est fusionné sur \(repo)." : "C'est fusionné : \(event.detail)"
        case .push:        return event.detail.isEmpty ? "Du code est parti sur \(repo)." : "Du code est parti sur \(event.detail)."
        case .issue:       return event.detail.isEmpty ? "Une issue s'ouvre sur \(repo)." : "Une issue s'ouvre : \(event.detail)"
        case .release:     return event.detail.isEmpty ? "Une version de \(repo) est sortie." : "\(event.detail) est sortie."
        case .follower:    return count > 1 ? "\(FrenchText.sentenceStart(FrenchText.spelled(count))) personnes de plus te suivent." : "Quelqu'un de plus te suit."
        }
    }

    /// - Parameters:
    ///   - openPulls: open pull requests on the repository, when known.
    ///   - last: the latest event, with how many of its kind came together.
    static func snapshot(connection: Connection, repo: GitHubRepo?, openPulls: Int?, last: (event: GitHubEvent, count: Int)?,
                         review: GitHubReview?) -> ModuleSnapshot {
        var snapshot = ModuleSnapshot(id: "github", name: "GitHub", colorHex: "#A371F7", status: "à brancher",
                                      title: "Je ne vois pas ton GitHub.", subtitle: "Donne-moi un jeton, je surveille tes dépôts.",
                                      primaryAction: "Brancher", secondaryAction: nil)
        switch connection {
        case .noToken:
            return snapshot.withSymbols("arrow.triangle.branch")
        case .refused:
            snapshot.status = "refusé"
            snapshot.title = "Ton jeton GitHub ne passe plus."
            snapshot.subtitle = "Donne-m'en un neuf, je reprends ma garde."
            return snapshot.withSymbols("arrow.triangle.branch")
        case .offline:
            snapshot.status = "hors ligne"
            snapshot.title = "Je n'arrive pas à joindre GitHub."
            snapshot.subtitle = "Je réessaie dans un moment."
            snapshot.primaryAction = "Ouvrir"
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
            snapshot.subtitle = "Je regarde tes dépôts."
        }
        snapshot.title = last.map { sentence(for: $0.event, count: $0.count) } ?? "Rien de neuf. Je surveille."
        snapshot.primaryAction = "Ouvrir"

        if let review {
            snapshot.title = review.title.isEmpty ? "Une pull request t'attend." : "Une pull request t'attend : \(review.title)"
            snapshot.primaryAction = "Relire"
            snapshot.needsAttention = true
            snapshot.live = ModuleLive(text: review.title.isEmpty ? "Une relecture t'attend" : "Relecture : \(review.title)",
                                       priority: ModuleLivePriority.attention,
                                       controls: [ModuleControl(id: ModuleAction.primary.rawValue, symbol: "eye.fill", label: "Relire")])
        }
        return snapshot.withSymbols("arrow.triangle.branch")
    }
}
