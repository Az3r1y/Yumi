import Foundation

/// The quick look at the person's repositories, every minute: the star and fork counts of each
/// one and its latest commit. GitHub's event feeds can lag by minutes; these answers do not, and
/// asked with their `ETag` they cost nothing while nothing changes. What it finds first is
/// announced at once; when the same thing shows up later in the event feeds, it is swallowed
/// there, so Yumi never says it twice.
struct GitHubQuickWatch: Equatable, Sendable {
    private struct Counts: Equatable, Sendable { var stars: Int; var forks: Int }

    private var counts: [String: Counts] = [:]
    private var heads: [String: String] = [:]
    /// Events already announced from the counts, by "repo|kind", still to swallow in the feeds.
    private var echoes: [String: Int] = [:]

    init() {}

    /// The counts of a repository were read. Returns a star or fork event per one gained,
    /// nothing the first time a repository is seen.
    mutating func counts(of repo: String, stars: Int, forks: Int) -> [GitHubEvent] {
        defer { counts[repo] = Counts(stars: stars, forks: forks) }
        guard let before = counts[repo] else { return [] }
        var events: [GitHubEvent] = []
        for (kind, gained) in [(GitHubEvent.Kind.star, stars - before.stars), (.fork, forks - before.forks)] where gained > 0 {
            events += Array(repeating: GitHubEvent(id: 0, kind: kind, repo: repo, actor: ""), count: min(gained, 20))
            echoes[Self.key(repo, kind), default: 0] += gained
        }
        return events
    }

    /// The latest commit of a repository was read. Returns a push event when it changed, with
    /// the commit's message, nothing the first time.
    mutating func head(of repo: String, sha: String, message: String, author: String) -> GitHubEvent? {
        defer { heads[repo] = sha }
        guard let before = heads[repo], before != sha, !sha.isEmpty else { return nil }
        echoes[Self.key(repo, .push), default: 0] += 1
        var event = GitHubEvent(id: 0, kind: .push, repo: repo, actor: author)
        event.headline = message
        return event
    }

    /// Events of the feeds, without those already announced from the quick look.
    mutating func swallow(_ events: [GitHubEvent]) -> [GitHubEvent] {
        events.filter { event in
            let key = Self.key(event.repo, event.kind)
            guard let left = echoes[key], left > 0 else { return true }
            echoes[key] = left - 1
            return false
        }
    }

    private static func key(_ repo: String, _ kind: GitHubEvent.Kind) -> String { "\(repo)|\(kind.rawValue)" }

    // MARK: Reading the answers

    /// `stargazers_count` and `forks_count` of `/repos/{owner}/{name}`.
    static func counts(from data: Data) -> (stars: Int, forks: Int)? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let stars = object["stargazers_count"] as? Int, let forks = object["forks_count"] as? Int else { return nil }
        return (stars, forks)
    }

    /// The newest commit of `/repos/{owner}/{name}/commits?per_page=1`: its sha, the first line
    /// of its message, its author's login (or name).
    static func head(from data: Data) -> (sha: String, message: String, author: String)? {
        guard let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]], let first = list.first,
              let sha = first["sha"] as? String else { return nil }
        let commit = first["commit"] as? [String: Any]
        let message = (commit?["message"] as? String ?? "").split(separator: "\n").first.map(String.init) ?? ""
        let author = (first["author"] as? [String: Any])?["login"] as? String
            ?? (commit?["author"] as? [String: Any])?["name"] as? String ?? ""
        return (sha, message, author)
    }
}
