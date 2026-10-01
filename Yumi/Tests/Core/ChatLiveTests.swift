import Testing
import Foundation

// From the output of Claude Code to what the island shows live (Contracts/ChatLive.swift).
// The lines are real output of claude 2.1.185 with --include-partial-messages, shortened.

@Suite struct PartialMessageTests {
    @Test func wordsArriveAsTheyAreWritten() {
        let start = #"{"type":"stream_event","event":{"type":"message_start","message":{"id":"msg_01","role":"assistant","content":[]}},"session_id":"ec1f","parent_tool_use_id":null,"uuid":"7ffc"}"#
        let delta = #"{"type":"stream_event","event":{"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"Waves"}},"session_id":"ec1f","parent_tool_use_id":null}"#
        #expect(ClaudeStream.events(fromLine: start) == [.messageStarted])
        #expect(ClaudeStream.events(fromLine: delta) == [.textDelta("Waves")])
    }

    @Test func aToolIsAnnouncedBeforeItsInputIsKnown() {
        let line = #"{"type":"stream_event","event":{"type":"content_block_start","index":1,"content_block":{"type":"tool_use","id":"toolu_01","name":"Write","input":{}}},"parent_tool_use_id":null}"#
        #expect(ClaudeStream.events(fromLine: line) == [.toolAnnounced(id: "toolu_01", name: "Write")])
        let text = #"{"type":"stream_event","event":{"type":"content_block_start","index":1,"content_block":{"type":"text","text":""}},"parent_tool_use_id":null}"#
        #expect(ClaudeStream.events(fromLine: text).isEmpty)
    }

    @Test func aToolResultGivenAsBlocksIsRead() {
        let line = #"{"type":"user","message":{"role":"user","content":[{"tool_use_id":"toolu_02","type":"tool_result","content":[{"type":"text","text":"line 1"},{"type":"text","text":"line 2"}]}]},"parent_tool_use_id":null}"#
        #expect(ClaudeStream.events(fromLine: line) == [.toolFinished(id: "toolu_02", failed: false, output: "line 1\nline 2")])
    }
}

@Suite struct ChatLiveTrackerTests {
    private func tracker(_ events: [ChatStreamEvent]) -> ChatLiveTracker {
        var tracker = ChatLiveTracker()
        for event in events { tracker.apply(event) }
        return tracker
    }
    private let write = ChatToolUse(id: "w", name: "Write", detail: "/Users/moi/Downloads/bonjour.txt", content: "salut\n\ntoi")
    private let bash = ChatToolUse(id: "b", name: "Bash", detail: "swift test")
    private func request(for tool: ChatToolUse) -> ChatPermissionRequest {
        ChatPermissionRequest(requestID: "r-\(tool.id)", toolUseID: tool.id, toolName: tool.name, summary: tool.detail,
                              inputJSON: Data("{}".utf8), suggestionsJSON: nil)
    }

    @Test func nothingYet() {
        #expect(ChatLiveTracker().live == ChatLive())
        #expect(ChatLiveTracker.headline(ChatLive()) == "Yumi réfléchit")
    }

    @Test func theTextGrowsWordByWord() {
        let live = tracker([.started(sessionID: "s"), .messageStarted, .textDelta("Bon"), .textDelta("jour"), .textDelta(" toi")]).live
        #expect(live.text == "Bonjour toi")
        #expect(live.activity == nil)
        #expect(ChatLiveTracker.headline(live) == "Yumi répond")
    }

    @Test func aNewMessageReplacesTheTextAndTheFullBlockIsAuthoritative() {
        var tracker = tracker([.messageStarted, .textDelta("Je crée le fichier.")])
        tracker.apply(.messageStarted)
        #expect(tracker.live.text == "")
        tracker.apply(.textDelta("C'est fa"))
        tracker.apply(.text("C'est fait."))
        #expect(tracker.live.text == "C'est fait.")
    }

    @Test func anActionShowsAsSoonAsItIsNamedThenWithItsDetails() {
        var tracker = tracker([.toolAnnounced(id: "w", name: "Write")])
        #expect(tracker.live.activity == ChatActivity(id: "w", kind: .writing, label: "Écrit un fichier", detail: nil))

        tracker.apply(.toolStarted(write))
        #expect(tracker.live.activity == ChatActivity(id: "w", kind: .writing, label: "Écrit bonjour.txt", detail: "salut\ntoi"))
        #expect(tracker.live.done.isEmpty)
        #expect(ChatLiveTracker.headline(tracker.live) == "Écrit bonjour.txt")
    }

    @Test func aFinishedActionMovesToDone() {
        let live = tracker([.toolStarted(write), .toolFinished(id: "w", failed: false, output: "File created successfully")]).live
        #expect(live.activity == nil)
        #expect(live.done == [ChatActivity(id: "w", kind: .writing, label: "Écrit bonjour.txt", detail: "salut\ntoi", succeeded: true)])
    }

    @Test func aCommandKeepsItsLastLines() {
        let output = (1...9).map { "ligne \($0)" }.joined(separator: "\n") + "\n\n"
        let live = tracker([.toolStarted(bash), .toolFinished(id: "b", failed: false, output: output)]).live
        #expect(live.done.first?.label == "Lance swift test")
        #expect(live.done.first?.kind == .running)
        #expect(live.done.first?.detail == "ligne 6\nligne 7\nligne 8\nligne 9")
        #expect(live.done.first?.succeeded == true)
    }

    @Test func aFailedCommandIsMarkedAndKeepsItsError() {
        let live = tracker([.toolStarted(bash), .toolFinished(id: "b", failed: true, output: "Exit code 1\nerror: no such module")]).live
        #expect(live.done.first?.succeeded == false)
        #expect(live.done.first?.detail == "Exit code 1\nerror: no such module")
    }

    @Test func waitingForAPermissionThenAllowed() {
        var tracker = tracker([.toolStarted(bash), .permissionRequested(request(for: bash))])
        #expect(tracker.live.activity == ChatActivity(id: "b", kind: .waiting, label: "Attend ton accord", detail: "swift test"))

        tracker.permissionAnswered(toolUseID: "b", allowed: true)
        #expect(tracker.live.activity?.kind == .running)
        #expect(tracker.live.activity?.label == "Lance swift test")

        tracker.apply(.toolFinished(id: "b", failed: false, output: "ok"))
        #expect(tracker.live.done == [ChatActivity(id: "b", kind: .running, label: "Lance swift test", detail: "ok", succeeded: true)])
    }

    @Test func aRefusedActionEndsAsNotSucceeded() {
        var tracker = tracker([.toolStarted(write), .permissionRequested(request(for: write))])
        tracker.permissionAnswered(toolUseID: "w", allowed: false)
        #expect(tracker.live.activity?.kind == .waiting)
        tracker.apply(.toolFinished(id: "w", failed: true, output: "L'utilisateur a refusé"))
        #expect(tracker.live.activity == nil)
        #expect(tracker.live.done == [ChatActivity(id: "w", kind: .writing, label: "Écrit bonjour.txt", detail: "salut\ntoi", succeeded: false)])
    }

    @Test func aRefusedCommandShowsNoOutput() {
        var tracker = tracker([.toolStarted(bash), .permissionRequested(request(for: bash))])
        tracker.permissionAnswered(toolUseID: "b", allowed: false)
        tracker.apply(.toolFinished(id: "b", failed: true, output: "L'utilisateur a refusé cette action"))
        #expect(tracker.live.done.first?.succeeded == false)
        #expect(tracker.live.done.first?.detail == nil)
    }

    @Test func severalActionsAtOnceShowTheOldestAndFinishInAnyOrder() {
        var tracker = tracker([.toolStarted(ChatToolUse(id: "1", name: "Read", detail: "/a/Budget.pdf")), .toolStarted(bash)])
        #expect(tracker.live.activity?.label == "Lit Budget.pdf")
        // The one that waits for the user is shown first, whatever its place.
        tracker.apply(.permissionRequested(request(for: bash)))
        #expect(tracker.live.activity?.kind == .waiting)
        tracker.permissionAnswered(toolUseID: "b", allowed: true)
        #expect(tracker.live.activity?.label == "Lit Budget.pdf")
        tracker.apply(.toolFinished(id: "b", failed: false, output: ""))
        #expect(tracker.live.activity?.label == "Lit Budget.pdf")
        tracker.apply(.toolFinished(id: "1", failed: false, output: "contenu"))
        #expect(tracker.live.activity == nil)
        #expect(tracker.live.done.map(\.id) == ["b", "1"])
        // Reading shows no preview of what was read.
        #expect(tracker.live.done.last?.detail == nil)
    }

    @Test func aResultForAnUnknownToolChangesNothing() {
        let live = tracker([.toolFinished(id: "ghost", failed: false, output: "x"), .permissionRequested(request(for: bash))]).live
        #expect(live == ChatLive())
    }

    @Test func everyToolHasAShortFrenchLabel() {
        func activity(_ name: String, _ detail: String) -> ChatActivity {
            ChatLiveTracker.activity(for: ChatToolUse(id: "t", name: name, detail: detail))
        }
        #expect(activity("Read", "/a/Budget.pdf").label == "Lit Budget.pdf")
        #expect(activity("Read", "/a/Budget.pdf").kind == .reading)
        #expect(activity("Edit", "/a/main.swift").label == "Modifie main.swift")
        #expect(activity("Edit", "/a/main.swift").kind == .editing)
        #expect(activity("Grep", "TODO").label == "Cherche TODO")
        #expect(activity("Grep", "TODO").kind == .searching)
        #expect(activity("WebSearch", "météo Paris").label == "Cherche sur le web : météo Paris")
        #expect(activity("WebFetch", "https://open-meteo.com/en/docs").label == "Lit open-meteo.com")
        #expect(activity("TodoWrite", "").kind == .thinking)
        #expect(activity("mcp__mail__send", "").label == "Utilise mcp__mail__send")
        #expect(activity("Bash", "").label == "Lance une commande")
        let long = activity("Bash", String(repeating: "x", count: 100) + "\nsecond")
        #expect(long.label.count == "Lance ".count + 40)
        #expect(!long.label.contains("\n"))
    }

    @Test func previewsAreCut() {
        let text = (1...10).map { "l\($0) " + String(repeating: "a", count: 200) }.joined(separator: "\n")
        let first = ChatLiveTracker.preview(text, last: false)!
        #expect(first.split(separator: "\n").count == ChatLiveTracker.previewLines)
        #expect(first.hasPrefix("l1 "))
        #expect(first.split(separator: "\n").allSatisfy { $0.count == ChatLiveTracker.previewWidth })
        #expect(ChatLiveTracker.preview(text, last: true)!.hasPrefix("l7 "))
        #expect(ChatLiveTracker.preview(" \n\n", last: true) == nil)
    }
}

@Suite struct PublishThrottleTests {
    @Test func atMostOncePerInterval() {
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        var throttle = PublishThrottle(interval: 0.1)
        #expect(throttle.delay(now: t0) == 0)
        throttle.published(at: t0)
        #expect(abs(throttle.delay(now: t0.addingTimeInterval(0.03)) - 0.07) < 0.0001)
        #expect(throttle.delay(now: t0.addingTimeInterval(0.1)) == 0)
        #expect(throttle.delay(now: t0.addingTimeInterval(5)) == 0)
    }
}
