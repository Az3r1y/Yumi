import Foundation
import Testing

// yumi/github: all of the person's repositories, pushes with their exact commits, grouped and counted.

private let paris: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
    return calendar
}()

private func iso(_ date: Date) -> String { ISO8601DateFormatter().string(from: date) }

private func push(_ id: Int, repo: String, actor: String = "estebanbaigts", branch: String = "main",
                  before: String, head: String, at date: Date) -> String {
    #"{"id": "\#(id)", "type": "PushEvent", "actor": {"login": "\#(actor)"}, "repo": {"name": "\#(repo)"}, "created_at": "\#(iso(date))", "payload": {"repository_id": 1, "push_id": \#(id), "ref": "refs/heads/\#(branch)", "head": "\#(head)", "before": "\#(before)"}}"#
}

private func compare(_ commits: [(sha: String, message: String, author: String)], repo: String) -> String {
    let items = commits.map { #"{"sha": "\#($0.sha)", "html_url": "https://github.com/\#(repo)/commit/\#($0.sha)", "author": {"login": "\#($0.author)"}, "commit": {"message": "\#($0.message)\n\nbody", "author": {"name": "X"}}}"# }
    return #"{"total_commits": \#(commits.count), "commits": [\#(items.joined(separator: ","))]}"#
}

@MainActor
@Suite struct GitHubActivityModuleTests {
    private final class Fake: @unchecked Sendable {
        private let lock = NSLock()
        private var bodies: [String: String] = [:]
        private(set) var requests: [URLRequest] = []
        var status = 200
        var headers: [String: String] = [:]
        func set(_ path: String, _ body: String) { lock.withLock { bodies[path] = body } }
        func asked(_ part: String) -> Int { lock.withLock { requests.filter { $0.url?.absoluteString.contains(part) == true }.count } }

        var fetch: GitHubModule.Fetch {
            { [self] request in
                lock.withLock {
                    requests.append(request)
                    let url = request.url?.absoluteString ?? ""
                    guard status == 200 else { return GitHubModule.Response(status: status, data: Data(), headers: headers) }
                    let match = bodies.filter { $0.key.hasPrefix("=") ? url.hasSuffix(String($0.key.dropFirst())) : url.contains($0.key) }
                        .max { $0.key.count < $1.key.count }
                    guard let (_, body) = match else { return GitHubModule.Response(status: 404, data: Data(), headers: [:]) }
                    let tag = "\"\(body.hashValue)\""
                    if request.value(forHTTPHeaderField: "If-None-Match") == tag {
                        return GitHubModule.Response(status: 304, data: Data(), headers: ["x-poll-interval": "60"])
                    }
                    return GitHubModule.Response(status: 200, data: Data(body.utf8), headers: ["etag": tag, "x-poll-interval": "60"])
                }
            }
        }
    }

    private let now = Date()

    private func make(hidden: Set<String> = []) -> (GitHubModule, Fake, UserDefaults) {
        let name = "yumi.tests.github-activity.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        GitHubRepos.setHidden(hidden, in: defaults)
        let fake = Fake()
        fake.set("=api.github.com/user", #"{"login": "estebanbaigts", "followers": 1}"#)
        fake.set("/user/repos", #"[{"full_name": "estebanbaigts/Yumi", "stargazers_count": 3}, {"full_name": "acme/site", "stargazers_count": 0}, {"full_name": "estebanbaigts/notes"}]"#)
        let own = [push(3, repo: "estebanbaigts/Yumi", before: "a0", head: "a3", at: now.addingTimeInterval(-60)),
                   push(2, repo: "estebanbaigts/notes", before: "b0", head: "b1", at: now.addingTimeInterval(-3600))]
        fake.set("/users/estebanbaigts/events", "[" + own.joined(separator: ",") + "]")
        // Someone else pushing on an organisation repository the person belongs to.
        fake.set("/users/estebanbaigts/received_events", "[" + push(4, repo: "acme/site", actor: "lea", before: "c0", head: "c2", at: now.addingTimeInterval(-120)) + "]")
        fake.set("/repos/estebanbaigts/Yumi/compare/a0...a3", compare([("a1", "Premier", "estebanbaigts"), ("a2", "Deuxième", "estebanbaigts"), ("a3", "Troisième", "estebanbaigts")], repo: "estebanbaigts/Yumi"))
        fake.set("/repos/estebanbaigts/notes/compare/b0...b1", compare([("b1", "Notes", "estebanbaigts")], repo: "estebanbaigts/notes"))
        fake.set("/repos/acme/site/compare/c0...c2", compare([("c1", "Header", "lea"), ("c2", "Footer", "lea")], repo: "acme/site"))
        fake.set("review%2Drequested", #"{"total_count": 0, "items": []}"#)
        fake.set("is%3Aopen", #"{"total_count": 0, "items": []}"#)
        let module = GitHubModule(token: { "ghp_test" }, defaults: defaults, fetch: fake.fetch, play: { _, _ in })
        return (module, fake, defaults)
    }

    @Test func pushesOnEveryRepositoryWithTheirExactCommits() async {
        let (module, fake, defaults) = make()
        await module.look()
        #expect(fake.asked("affiliation=owner,collaborator,organization_member") == 1)
        let rows = module.snapshot.rows
        let sections = rows.compactMap(\.section)
        #expect(sections.first?.hasPrefix("Yumi · 3 aujourd'hui, 3 cette semaine") == true)
        #expect(sections.contains { $0.hasPrefix("site") })
        #expect(rows.contains { $0.title == "3 commits sur main" })
        let commit = rows.first { $0.id.hasSuffix("-a3") }
        #expect(commit?.title.trimmingCharacters(in: .whitespaces) == "Troisième")
        #expect(commit?.detail == "a3 · estebanbaigts")
        #expect(commit?.action == "https://github.com/estebanbaigts/Yumi/commit/a3")
        #expect(GitHubRepos.known(in: defaults).contains("acme/site"))
        #expect(module.snapshot.live?.text == "Yumi · 3 commits sur main")
    }

    @Test func aPushIsComparedOnceAndAnUnchangedFeedCostsNothing() async {
        let (module, fake, _) = make()
        await module.look()
        await module.look()
        #expect(fake.asked("/compare/a0...a3") == 1)
        #expect(module.snapshot.rows.contains { $0.title == "3 commits sur main" })
    }

    @Test func aHiddenRepositoryIsNeitherReadNorShown() async {
        let (module, fake, _) = make(hidden: ["acme/site"])
        await module.look()
        #expect(fake.asked("/repos/acme/site/compare") == 0)
        #expect(!module.snapshot.rows.contains { ($0.section ?? "").hasPrefix("site") || $0.id.contains("-c") })
    }

    @Test func aRateLimitStopsTheLookAndKeepsWhatWasShown() async {
        let (module, fake, _) = make()
        await module.look()
        let before = module.snapshot.rows
        fake.status = 403
        fake.headers = ["x-ratelimit-remaining": "0", "x-ratelimit-reset": "\(Int(Date().timeIntervalSince1970) + 600)"]
        await module.look()
        #expect(module.snapshot.rows == before)
    }
}

@Suite struct GitHubActivityTests {
    @Test func countsPerRepositoryTodayAndThisWeek() {
        let now = paris.date(from: DateComponents(year: 2026, month: 10, day: 7, hour: 15))!
        let pushes = [GitHubPush(eventID: 1, repo: "a/x", branch: "main", actor: "me", date: now, total: 3, commits: []),
                      GitHubPush(eventID: 2, repo: "a/x", branch: "main", actor: "me", date: now.addingTimeInterval(-3 * 86_400), total: 4, commits: []),
                      GitHubPush(eventID: 3, repo: "a/x", branch: "main", actor: "me", date: now.addingTimeInterval(-10 * 86_400), total: 9, commits: []),
                      GitHubPush(eventID: 4, repo: "b/y", branch: "dev", actor: "me", date: now, total: 1, commits: [])]
        let counts = GitHubActivity.counts(pushes, now: now, calendar: paris)
        #expect(counts["a/x"]?.today == 3 && counts["a/x"]?.week == 7)
        #expect(counts["b/y"]?.today == 1)
    }

    @Test func compareAndNewBranches() {
        #expect(GitHubFeed.comparePath(repo: "a/x", before: "0000000000", head: "abc") == "/repos/a/x/commits/abc")
        #expect(GitHubFeed.comparePath(repo: "a/x", before: "111", head: "abc") == "/repos/a/x/compare/111...abc")
        #expect(GitHubFeed.comparePath(repo: "a/x", before: "111", head: "") == nil)
        let single = #"{"sha": "abc123456", "html_url": "https://github.com/a/x/commit/abc123456", "author": null, "commit": {"message": "Init", "author": {"name": "Léa"}}}"#
        let read = GitHubFeed.commits(fromCompare: Data(single.utf8))
        #expect(read?.total == 1 && read?.commits.first?.author == "Léa" && read?.commits.first?.shortSHA == "abc1234")
    }

    @Test func receivedActivityCountsOnSharedRepositoriesOnly() {
        let body = "[" + push(9, repo: "acme/site", actor: "lea", before: "1", head: "2", at: Date()) + "," + push(8, repo: "other/thing", actor: "bob", before: "1", head: "2", at: Date()) + "]"
        let events = GitHubFeed.events(from: Data(body.utf8), login: "estebanbaigts", received: true, repos: ["acme/site"])
        #expect(events.map(\.repo) == ["acme/site"])
        #expect(events.first?.head == "2")
    }
}
