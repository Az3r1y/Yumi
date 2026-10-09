import Foundation
import Testing

// « Prépare ma journée » and notes in the Notes app.

private let paris: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
    return calendar
}()
private func at(_ hour: Int, _ minute: Int = 0) -> Date {
    paris.date(from: DateComponents(year: 2026, month: 10, day: 12, hour: hour, minute: minute))!
}
private func context() -> ToolContext { ToolContext(runID: UUID(), stepID: "step-1", snapshot: nil, now: at(8)) }

@Suite struct PrepareDayToolTests {
    private let facts = TodayFacts(
        events: [AgendaEvent(id: "b", title: "Déjeuner", start: at(12, 30), end: at(13, 30), isAllDay: false, location: ""),
                 AgendaEvent(id: "a", title: "Point produit", start: at(10), end: at(10, 30), isAllDay: false, location: "")],
        reminders: [ReminderItem(id: "r", title: "Appeler le dentiste", due: at(15), hasTime: true)])

    @Test func theDayIsListedSoonestFirst() {
        let lines = PrepareDayTool.list(facts, calendar: paris)
        #expect(lines.first?.contains("Point produit") == true)
        #expect(lines.contains { $0.contains("Rappel : Appeler le dentiste") })
    }

    @Test func theEngineWritesThePlanFromTheDay() async throws {
        let writer = ScriptedLLMProvider(json: "9 h : courrier\n10 h : Point produit")
        let tool = PrepareDayTool(source: FixedToday(value: facts), writer: writer, calendar: paris)
        let output = try await tool.execute([:], in: context())
        #expect(output.values["reply"] == .string("9 h : courrier\n10 h : Point produit"))
        #expect(writer.requests.first?.messages.first?.content.contains("Déjeuner") == true)
    }

    @Test func withoutAnEngineTheDayIsStillGiven() async throws {
        let tool = PrepareDayTool(source: FixedToday(value: facts), writer: UnavailableLLMProvider(), calendar: paris)
        guard case .string(let reply)? = try await tool.execute([:], in: context()).values["reply"] else { Issue.record("no reply"); return }
        #expect(reply.contains("Point produit"))
        let empty = PrepareDayTool(source: FixedToday(value: TodayFacts()), writer: UnavailableLLMProvider(), calendar: paris)
        #expect(try await empty.execute([:], in: context()).values["reply"] == .string("Rien de prévu aujourd'hui : ta journée est à toi."))
    }
}

final class FakeNotes: AppleNotesApp, @unchecked Sendable {
    private let lock = NSLock()
    private var saved: [String: String] = [:]
    var titles: [String] { lock.withLock { Array(saved.keys) } }
    func add(title: String, body: String) throws { lock.withLock { saved[title] = body } }
    func exists(title: String) -> Bool { lock.withLock { saved[title] != nil } }
}

@Suite struct AddNoteToolTests {
    @Test func aNoteIsAskedThenCheckedInNotes() async throws {
        let notes = FakeNotes()
        let tool = AddNoteTool(notes: notes)
        let arguments: ToolArguments = ["title": .string("Idées"), "body": .string("Mode nuit pour Yumi")]
        let action = try #require(tool.action(for: arguments))
        #expect(action.kind == .create)
        #expect(action.content == "Mode nuit pour Yumi")
        #expect(action.headline == "Je dois créer la note « Idées » dans Notes.")
        let output = try await tool.execute(arguments, in: context())
        #expect(notes.titles == ["Idées"])
        #expect(await tool.verify(arguments, output: output) == nil)
        #expect(await AddNoteTool(notes: FakeNotes()).verify(arguments, output: output) != nil)
    }

    @Test func aTitleCannotBecomeAppleScript() {
        let trap = "x\" & (do shell script \"rm -rf ~\") & \""
        let quoted = ScriptedNotes.quoted(trap)
        // Every quote of the text is escaped: the literal never closes before its end
        #expect(quoted == "\"x\\\" & (do shell script \\\"rm -rf ~\\\") & \\\"\"")
        #expect(ScriptedNotes.quoted("a\\b") == "\"a\\\\b\"")
        #expect(ScriptedNotes.html("<b>&") == "&lt;b&gt;&amp;")
    }

    @Test func missingFieldsAreRefusedBeforeAsking() async {
        #expect(await AddNoteTool(notes: FakeNotes()).check(["title": .string("Sans texte")]) != nil)
    }
}
