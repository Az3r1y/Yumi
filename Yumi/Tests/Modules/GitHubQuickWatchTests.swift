import Testing
import Foundation

@Suite struct GitHubQuickWatchTests {

    @Test func theFirstLookOnlyLearns() {
        var watch = GitHubQuickWatch()
        #expect(watch.counts(of: "a/b", stars: 10, forks: 2).isEmpty)
        #expect(watch.head(of: "a/b", sha: "111", message: "init", author: "x") == nil)
    }

    @Test func aNewStarAForkAndACommitAreAnnounced() {
        var watch = GitHubQuickWatch()
        _ = watch.counts(of: "a/b", stars: 10, forks: 2)
        _ = watch.head(of: "a/b", sha: "111", message: "init", author: "x")
        #expect(watch.counts(of: "a/b", stars: 12, forks: 3).map(\.kind) == [.star, .star, .fork])
        let push = watch.head(of: "a/b", sha: "222", message: "Fix the island", author: "esteban")
        #expect(push?.kind == .push && push?.headline == "Fix the island" && push?.actor == "esteban")
        #expect(watch.head(of: "a/b", sha: "222", message: "Fix the island", author: "esteban") == nil)
    }

    @Test func whatWasAnnouncedIsNotSaidAgainByTheFeeds() {
        var watch = GitHubQuickWatch()
        _ = watch.counts(of: "a/b", stars: 1, forks: 0)
        _ = watch.counts(of: "a/b", stars: 2, forks: 0)
        let star = GitHubEvent(id: 9, kind: .star, repo: "a/b", actor: "lea")
        let other = GitHubEvent(id: 10, kind: .star, repo: "c/d", actor: "lea")
        #expect(watch.swallow([star, other]) == [other])
        #expect(watch.swallow([star]) == [star])
    }

    @Test func readsTheAnswers() {
        let repo = #"{"stargazers_count": 128, "forks_count": 12}"#.data(using: .utf8)!
        #expect(GitHubQuickWatch.counts(from: repo)! == (128, 12))
        let commits = #"[{"sha": "abc", "commit": {"message": "First line\n\nbody", "author": {"name": "E"}}, "author": {"login": "esteban"}}]"#.data(using: .utf8)!
        let head = GitHubQuickWatch.head(from: commits)
        #expect(head?.sha == "abc" && head?.message == "First line" && head?.author == "esteban")
    }
}
