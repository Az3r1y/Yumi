import EventKit
import Testing

// A yes given while Yumi runs counts at once, without waiting for macOS to say it too.
@Suite struct EventKitAccessTests {
    @Test func aYesCountsAtOnceAndANoChangesNothing() {
        let store = EKEventStore()
        let before = EventKitAccess.state(for: .event)
        EventKitAccess.answered(false, for: .event, store: store)
        #expect(EventKitAccess.state(for: .event) == before)
        EventKitAccess.answered(true, for: .event, store: store)
        #expect(EventKitAccess.state(for: .event) == .granted)
    }
}
