import Testing
import Foundation

private var paris: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
    return calendar
}
/// October 2026, Paris. The 1st is a Thursday, the 2nd a Friday.
private func at(_ hour: Int, _ minute: Int = 0, day: Int = 1) -> Date {
    paris.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
}

/// How what happens on the Mac becomes an occasion, each one once.
@Suite struct InitiativeWatchTests {
    private let agent = ClaudeHookTranslator.agent

    @Test func theFirstArrivalOfTheDayIsAGreetingOnlyOnce() {
        var watch = InitiativeWatch()
        let first = watch.arrived(now: at(8), calendar: paris, eventsToday: 2, firstEventAt: at(10))
        #expect(first == .firstWake(events: 2, firstAt: at(10)))
        let again = watch.arrived(now: at(8, 5), calendar: paris, eventsToday: 2, firstEventAt: at(10))
        #expect(again == nil)
        watch.left(now: at(23))
        let nextDay = watch.arrived(now: at(8, 0, day: 2), calendar: paris, eventsToday: nil, firstEventAt: nil)
        #expect(nextDay == .firstWake(events: nil, firstAt: nil))
    }

    @Test func aLongAbsenceIsAReturnAndAShortOneIsNot() {
        var watch = InitiativeWatch()
        _ = watch.arrived(now: at(8), calendar: paris, eventsToday: 0, firstEventAt: nil)
        watch.left(now: at(12))
        let short = watch.arrived(now: at(12, 10), calendar: paris, eventsToday: 0, firstEventAt: nil)
        #expect(short == nil)
        watch.left(now: at(13))
        let long = watch.arrived(now: at(13, 45), calendar: paris, eventsToday: 0, firstEventAt: nil)
        #expect(long == .back(agentFinished: false, agentWaiting: false))
    }

    @Test func whatAnAgentDidDuringTheAbsenceIsToldOnReturn() {
        var watch = InitiativeWatch()
        let id = SessionID("s")
        var sessions = SessionReducer.apply(.sessionStarted(id, agent, title: "yumi"), to: [:])
        _ = watch.arrived(now: at(8), calendar: paris, eventsToday: 0, firstEventAt: nil)
        _ = watch.session(.promptSubmitted(id, text: "go"), sessions: sessions, now: at(9))
        watch.left(now: at(9, 5))
        sessions = SessionReducer.apply(.taskCompleted(id), to: sessions)
        let silent = watch.session(.taskCompleted(id), sessions: sessions, now: at(9, 30))
        #expect(silent == nil)
        let back = watch.arrived(now: at(10), calendar: paris, eventsToday: 0, firstEventAt: nil)
        #expect(back == .back(agentFinished: true, agentWaiting: false))
    }

    @Test func aLongTaskEndingIsWorthAWordAndAShortOneIsNot() {
        var watch = InitiativeWatch()
        let id = SessionID("s")
        var sessions = SessionReducer.apply(.sessionStarted(id, agent, title: "yumi"), to: [:])
        _ = watch.session(.promptSubmitted(id, text: "go"), sessions: sessions, now: at(9))
        sessions = SessionReducer.apply(.taskCompleted(id), to: sessions)
        let long = watch.session(.taskCompleted(id), sessions: sessions, now: at(9, 18))
        #expect(long == .agentDone(project: "yumi", minutes: 18))

        _ = watch.session(.promptSubmitted(id, text: "again"), sessions: sessions, now: at(10))
        let short = watch.session(.taskCompleted(id), sessions: sessions, now: at(10, 3))
        let unknown = watch.session(.taskCompleted(SessionID("other")), sessions: sessions, now: at(11))
        #expect(short == nil && unknown == nil)
    }

    @Test func anAppointmentCloseWhileAnAgentWaitsIsSaidOnce() {
        var watch = InitiativeWatch()
        let id = SessionID("s")
        var sessions = SessionReducer.apply(.sessionStarted(id, agent, title: "yumi"), to: [:])
        let nobody = watch.meeting(title: "Point produit", start: at(14, 30), now: at(14, 22))
        #expect(nobody == nil)
        sessions = SessionReducer.apply(.permissionRequested(id, PermissionRequest(tool: "Bash")), to: sessions)
        _ = watch.session(.permissionRequested(id, PermissionRequest(tool: "Bash")), sessions: sessions, now: at(14))
        #expect(watch.agentWaiting)
        let early = watch.meeting(title: "Point produit", start: at(14, 30), now: at(14, 5))
        let close = watch.meeting(title: "Point produit", start: at(14, 30), now: at(14, 22))
        let twice = watch.meeting(title: "Point produit", start: at(14, 30), now: at(14, 25))
        let started = watch.meeting(title: "Autre", start: at(14), now: at(14, 22))
        #expect(early == nil && twice == nil && started == nil)
        #expect(close == .meetingWhileAgentWaits(title: "Point produit", minutes: 8))
    }

    @Test func theBatteryIsMentionedOnceUntilItIsCharged() {
        var watch = InitiativeWatch()
        let fine = watch.battery(percent: 40, charging: false)
        let low = watch.battery(percent: 11, charging: false)
        let lower = watch.battery(percent: 9, charging: false)
        let plugged = watch.battery(percent: 9, charging: true)
        let unplugged = watch.battery(percent: 10, charging: false)
        #expect(fine == nil && lower == nil && plugged == nil)
        #expect(low == .lowBattery(percent: 11))
        #expect(unplugged == .lowBattery(percent: 10))
    }

    @Test func twoHoursOfWorkThenEveryTwoHoursAndABreakStartsAgain() {
        var watch = InitiativeWatch()
        _ = watch.arrived(now: at(9), calendar: paris, eventsToday: 0, firstEventAt: nil)
        #expect(watch.clock(now: at(10, 59), calendar: paris).isEmpty)
        #expect(watch.clock(now: at(11), calendar: paris) == [.longStretch(hours: 2)])
        #expect(watch.clock(now: at(11, 30), calendar: paris).isEmpty)
        #expect(watch.clock(now: at(13), calendar: paris) == [.longStretch(hours: 4)])
        watch.tookBreak(now: at(13, 5))
        #expect(watch.clock(now: at(14), calendar: paris).isEmpty)
        #expect(watch.clock(now: at(15, 5), calendar: paris) == [.longStretch(hours: 2)])
        // Away for a while: the stretch starts again on return.
        watch.left(now: at(15, 10))
        #expect(watch.clock(now: at(19), calendar: paris).isEmpty)
        _ = watch.arrived(now: at(16), calendar: paris, eventsToday: 0, firstEventAt: nil)
        #expect(watch.clock(now: at(17), calendar: paris).isEmpty)
    }

    @Test func lateIsSaidOncePerNight() {
        var watch = InitiativeWatch()
        _ = watch.arrived(now: at(22), calendar: paris, eventsToday: 0, firstEventAt: nil)
        #expect(watch.clock(now: at(23, 29), calendar: paris).isEmpty)
        #expect(watch.clock(now: at(23, 30), calendar: paris).contains(.late))
        #expect(!watch.clock(now: at(1, 0, day: 2), calendar: paris).contains(.late))
        #expect(watch.clock(now: at(23, 40, day: 2), calendar: paris).contains(.late))
    }

    @Test func theWeekEndsOnFridayEveningOnce() {
        var watch = InitiativeWatch()
        _ = watch.arrived(now: at(17, 0, day: 2), calendar: paris, eventsToday: 0, firstEventAt: nil)
        #expect(!watch.clock(now: at(18, 0, day: 1), calendar: paris).contains(.weekEnd))
        #expect(!watch.clock(now: at(17, 59, day: 2), calendar: paris).contains(.weekEnd))
        #expect(watch.clock(now: at(18, 0, day: 2), calendar: paris).contains(.weekEnd))
        #expect(!watch.clock(now: at(19, 0, day: 2), calendar: paris).contains(.weekEnd))
    }

    @Test func theNextMomentToLookAtTheClockIsExact() {
        var watch = InitiativeWatch()
        _ = watch.arrived(now: at(9), calendar: paris, eventsToday: 0, firstEventAt: nil)
        // Thursday 9:00: the two-hour mark comes first.
        #expect(watch.nextDeadline(now: at(9, 1), calendar: paris, nextEventStart: nil) == at(11))
        _ = watch.clock(now: at(11), calendar: paris)
        #expect(watch.nextDeadline(now: at(11, 1), calendar: paris, nextEventStart: at(12)) == at(13))
        // Friday afternoon: the end of the week comes before the next two hours.
        var friday = InitiativeWatch()
        _ = friday.arrived(now: at(17, 0, day: 2), calendar: paris, eventsToday: 0, firstEventAt: nil)
        #expect(friday.nextDeadline(now: at(17, 1, day: 2), calendar: paris, nextEventStart: nil) == at(18, 0, day: 2))
        // Away: nothing to wait for.
        friday.left(now: at(17, 30, day: 2))
        #expect(friday.nextDeadline(now: at(17, 31, day: 2), calendar: paris, nextEventStart: nil) == nil)
    }

    @Test func withAnAgentWaitingTheAppointmentSetsTheDeadline() {
        var watch = InitiativeWatch()
        let id = SessionID("s")
        var sessions = SessionReducer.apply(.sessionStarted(id, agent, title: "yumi"), to: [:])
        _ = watch.arrived(now: at(14), calendar: paris, eventsToday: 1, firstEventAt: at(14, 30))
        sessions = SessionReducer.apply(.questionRequested(id, Question(text: "?")), to: sessions)
        _ = watch.session(.questionRequested(id, Question(text: "?")), sessions: sessions, now: at(14, 1))
        #expect(watch.nextDeadline(now: at(14, 2), calendar: paris, nextEventStart: at(14, 30)) == at(14, 20))
    }
}

/// The driver: a remark is shown, answered, or goes away by itself.
@MainActor
@Suite struct InitiativeDriverTests {
    private final class Box {
        var remarks: [YumiRemark?] = []
        var actions: [RemarkAction] = []
        var focusing = false
        var shared = false
    }

    private func make(talk: YumiTalk = .chatty) -> (InitiativeDriver, Box, UserDefaults) {
        let name = "yumi.tests.initiative.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        defaults.set(talk.rawValue, forKey: YumiTalk.defaultsKey)
        let box = Box()
        var book = MemoryBook()
        book.setName("Esteban")
        let links = InitiativeLinks(show: { box.remarks.append($0) }, memory: { book }, focusRunning: { box.focusing },
                                    agenda: { (nil, nil) }, perform: { box.actions.append($0) },
                                    mac: { (false, false, box.shared) })
        return (InitiativeDriver(links: links, defaults: defaults), box, defaults)
    }

    /// A task of twenty minutes that ends now.
    private func finishLongTask(_ driver: InitiativeDriver) {
        // The watch takes the time of the events as they arrive: the prompt is back-dated through a restored state.
        let id = SessionID("s")
        var sessions = SessionReducer.apply(.sessionStarted(id, ClaudeHookTranslator.agent, title: "yumi"), to: [:])
        driver.backdatePrompt(id: "s", by: 20 * 60)
        sessions = SessionReducer.apply(.taskCompleted(id), to: sessions)
        driver.session(.taskCompleted(id), sessions: sessions)
    }

    @Test func aRemarkIsShownAndItsActionReallyHappens() {
        let (driver, box, _) = make()
        finishLongTask(driver)
        let remark = box.remarks.last ?? nil
        #expect(remark?.text.contains("vingt minutes") == true)
        #expect(remark?.action == "Voir")

        NotificationCenter.default.post(name: .remarkAccepted, object: nil, userInfo: ["id": "not-this-one"])
        #expect(box.actions.isEmpty)
        driver.answer(accepted: remark!.id)
        #expect(box.actions == [.openSession])
        #expect(box.remarks.last! == nil)
        driver.answer(accepted: remark!.id)
        #expect(box.actions.count == 1)
    }

    @Test func aDismissedRemarkGoesAway() {
        let (driver, box, _) = make()
        finishLongTask(driver)
        let remark = (box.remarks.last ?? nil)!
        driver.answer(dismissed: remark.id, ignored: false)
        #expect(box.remarks.count == 2 && box.remarks.last! == nil)
        driver.answer(dismissed: remark.id, ignored: true)
        #expect(box.remarks.count == 2)
    }

    @Test func nothingIsShownWhenHeMustStayQuiet() {
        let (silent, silentBox, _) = make(talk: .silent)
        finishLongTask(silent)
        #expect(silentBox.remarks.isEmpty)

        let (focused, focusBox, _) = make()
        focusBox.focusing = true
        finishLongTask(focused)
        #expect(focusBox.remarks.isEmpty)

        let (shared, sharedBox, _) = make()
        sharedBox.shared = true
        finishLongTask(shared)
        #expect(sharedBox.remarks.isEmpty)
    }

    @Test func theSettingIsReadEachTime() {
        let (driver, box, defaults) = make(talk: .silent)
        finishLongTask(driver)
        #expect(box.remarks.isEmpty)
        defaults.set(YumiTalk.discreet.rawValue, forKey: YumiTalk.defaultsKey)
        finishLongTask(driver)
        #expect(box.remarks.count == 1)
    }

    @Test func whatWasSaidIsKeptAcrossLaunches() {
        let (driver, box, defaults) = make()
        finishLongTask(driver)
        #expect(box.remarks.count == 1)
        // A new driver on the same defaults: twenty minutes have not passed.
        let secondBox = Box()
        let second = InitiativeDriver(links: InitiativeLinks(show: { secondBox.remarks.append($0) }, memory: { MemoryBook() },
                                                             focusRunning: { false }, agenda: { (nil, nil) }, perform: { _ in },
                                                             mac: { (false, false, false) }), defaults: defaults)
        finishLongTask(second)
        #expect(secondBox.remarks.isEmpty)
    }

    @Test func atRestTheDriverIsNeverWoken() async {
        let (driver, _, _) = make()
        // Not started: no observer. Even started, only the system and session events wake it.
        try? await Task.sleep(for: .milliseconds(300))
        #expect(driver.wakeUps == 0)
    }
}
