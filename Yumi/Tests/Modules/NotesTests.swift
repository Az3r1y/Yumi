import Testing
import Foundation

@Suite struct NotesStoreTests {
    private func makeStore() -> NotesStore {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("yumi-notes-\(UUID().uuidString)")
        return NotesStore(fileURL: folder.appendingPathComponent("notes.txt"))
    }

    @Test func aMissingFileHasNoNotes() {
        #expect(makeStore().load().isEmpty)
    }

    @Test func notesAreKeptInOrderAndSurviveAReload() {
        let store = makeStore()
        #expect(store.add("Idée : mode nuit pour Yumi") == "Idée : mode nuit pour Yumi")
        #expect(store.add("  Rappeler\nLéa   demain ") == "Rappeler Léa demain")
        #expect(store.load() == ["Idée : mode nuit pour Yumi", "Rappeler Léa demain"])
        try? FileManager.default.removeItem(at: store.fileURL.deletingLastPathComponent())
    }

    @Test func emptyTextAndImmediateDuplicatesAreRefused() {
        let store = makeStore()
        #expect(store.add("   \n ") == nil)
        #expect(store.add("une note") != nil)
        #expect(store.add("une note") == nil)
        #expect(store.load().count == 1)
        try? FileManager.default.removeItem(at: store.fileURL.deletingLastPathComponent())
    }

    @Test func linesWrittenByHandAreRead() throws {
        let store = makeStore()
        store.ensureFileExists()
        try "sans date\n\n[2026-10-01 09:00] avec date\n[note] entre crochets".write(to: store.fileURL, atomically: true, encoding: .utf8)
        #expect(store.load() == ["sans date", "avec date", "entre crochets"])
        #expect(store.add("suivante") != nil)
        #expect(store.load().last == "suivante")
        try? FileManager.default.removeItem(at: store.fileURL.deletingLastPathComponent())
    }

    @Test func longTextIsCut() {
        let cleaned = NotesStore.clean(String(repeating: "a", count: 500))
        #expect(cleaned.count == NotesStore.maxLength)
        #expect(cleaned.hasSuffix("…"))
    }
}

@Suite struct NotesSummaryTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        return calendar
    }
    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    @Test func nothingYet() {
        let snapshot = NotesSummary.snapshot(notes: [], reminders: [], remindersAccess: .notDetermined, now: date(1, 10), calendar: calendar)
        #expect(snapshot.status == "vide")
        #expect(snapshot.primaryAction == "Nouvelle note")
        #expect(snapshot.secondaryAction == "Activer les rappels")
    }

    @Test func theLastNoteIsShown() {
        let snapshot = NotesSummary.snapshot(notes: ["a", "b", "Idée : mode nuit pour Yumi"], reminders: [],
                                             remindersAccess: .denied, now: date(1, 10), calendar: calendar)
        #expect(snapshot.status == "3")
        #expect(snapshot.title == "Ta dernière note")
        #expect(snapshot.subtitle == "Idée : mode nuit pour Yumi")
        #expect(snapshot.secondaryAction == "Tout voir")
        #expect(!snapshot.needsAttention)
    }

    @Test func aDueReminderComesBeforeTheNotes() {
        let reminders = [
            ReminderItem(id: "2", title: "Envoyer le devis", due: date(1, 16, 30), hasTime: true),
            ReminderItem(id: "1", title: "Appeler le dentiste", due: date(1, 14, 30), hasTime: true),
            ReminderItem(id: "3", title: "Un jour", due: nil, hasTime: false),
        ]
        let snapshot = NotesSummary.snapshot(notes: ["a"], reminders: reminders, remindersAccess: .granted, now: date(1, 10), calendar: calendar)
        #expect(snapshot.status == "4")
        #expect(snapshot.title == "Rappel : Appeler le dentiste")
        #expect(snapshot.subtitle == "C'est pour 14:30. Deux autres attendent.")
        #expect(snapshot.primaryAction == "Terminé")
        #expect(snapshot.secondaryAction == "Tout voir")
        #expect(!snapshot.needsAttention)
    }

    @Test func lateRemindersAskForAttention() {
        let timed = NotesSummary.snapshot(notes: [], reminders: [ReminderItem(id: "1", title: "x", due: date(1, 9), hasTime: true)],
                                          remindersAccess: .granted, now: date(1, 10), calendar: calendar)
        #expect(timed.subtitle == "C'était pour 9:00.")
        #expect(timed.needsAttention)

        let yesterday = NotesSummary.snapshot(notes: [], reminders: [ReminderItem(id: "1", title: "x", due: date(0, 0), hasTime: false)],
                                              remindersAccess: .granted, now: date(1, 10), calendar: calendar)
        #expect(yesterday.subtitle == "C'était prévu avant aujourd'hui.")
        #expect(yesterday.needsAttention)

        let today = NotesSummary.snapshot(notes: [], reminders: [ReminderItem(id: "1", title: "x", due: date(1, 0), hasTime: false)],
                                          remindersAccess: .granted, now: date(1, 10), calendar: calendar)
        #expect(today.subtitle == "C'est pour aujourd'hui.")
        #expect(!today.needsAttention)
    }
}
