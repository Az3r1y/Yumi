import Testing
import Foundation

@Suite struct FocusTimerTests {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private func at(_ minutes: Double) -> Date { t0.addingTimeInterval(minutes * 60) }

    @Test func idleOffersToStart() {
        let snapshot = FocusTimer().snapshot(now: t0)
        #expect(snapshot.id == "focus")
        #expect(snapshot.status == "prêt")
        #expect(snapshot.subtitle == "Quatre sessions de vingt-cinq minutes, cinq de pause.")
        #expect(snapshot.primaryAction == "Démarrer")
        #expect(snapshot.secondaryAction == nil)
    }

    @Test func countsDownDuringFocus() {
        var timer = FocusTimer()
        timer.perform(.primary, now: t0)
        let snapshot = timer.snapshot(now: t0.addingTimeInterval(6 * 60 + 18))
        #expect(snapshot.status == "18:42")
        #expect(snapshot.title == "Tu es dedans. Je me tais.")
        #expect(snapshot.subtitle == "Session 1 sur 4, encore 18 min 42.")
        #expect(snapshot.primaryAction == "Pause")
        #expect(snapshot.secondaryAction == "Arrêter")
        #expect(!snapshot.needsAttention)
    }

    @Test func pauseFreezesTheCountdownAndResumeContinuesIt() {
        var timer = FocusTimer()
        timer.start(now: t0)
        timer.perform(.primary, now: at(10))
        #expect(timer.snapshot(now: at(60)).status == "pause")
        #expect(timer.snapshot(now: at(60)).primaryAction == "Reprendre")
        let remaining: TimeInterval? = timer.remaining(now: at(60))
        #expect(remaining == 900.0)

        timer.perform(.primary, now: at(60))
        #expect(timer.state == .running(.focus, round: 1, endsAt: at(75)))
    }

    @Test func aBreakFollowsEachFocusAndAsksForAttention() {
        var timer = FocusTimer()
        timer.start(now: t0)
        let early = timer.advance(now: at(24.9))
        let onTime = timer.advance(now: at(25).addingTimeInterval(1))
        #expect(!early && onTime)
        #expect(timer.state == .running(.rest, round: 1, endsAt: at(30)))

        let snapshot = timer.snapshot(now: at(25).addingTimeInterval(1))
        #expect(snapshot.title == "Pause. Souffle un peu.")
        #expect(snapshot.status == "04:59")
        #expect(snapshot.subtitle == "Session 2 sur 4 dans 4 min 59.")
        #expect(snapshot.primaryAction == "Passer")
        #expect(snapshot.needsAttention)
        #expect(!timer.snapshot(now: at(26)).needsAttention)
    }

    @Test func skippingTheBreakStartsTheNextRound() {
        var timer = FocusTimer()
        timer.start(now: t0)
        timer.advance(now: at(25))
        timer.perform(.primary, now: at(26))
        #expect(timer.state == .running(.focus, round: 2, endsAt: at(51)))
    }

    @Test func aLateTickCatchesUpWithoutShiftingTheSchedule() {
        var timer = FocusTimer()
        timer.start(now: t0)
        // The Mac slept through the first break: 25 + 5 + 3 minutes later we are 3 minutes into round 2.
        timer.advance(now: at(33))
        #expect(timer.state == .running(.focus, round: 2, endsAt: at(55)))
    }

    @Test func finishesAfterTheLastRound() {
        var timer = FocusTimer()
        timer.start(now: t0)
        timer.advance(now: at(4 * 25 + 3 * 5))
        #expect(timer.state == .finished(at: at(115)))
        #expect(!timer.isRunning)

        let snapshot = timer.snapshot(now: at(115))
        #expect(snapshot.title == "Quatre sessions. C'est fait.")
        #expect(snapshot.primaryAction == "Recommencer")
        #expect(snapshot.needsAttention)
        #expect(!timer.snapshot(now: at(116)).needsAttention)

        timer.perform(.secondary, now: at(116))
        #expect(timer.state == .idle)
    }

    @Test func stopGoesBackToIdleFromAnywhere() {
        var timer = FocusTimer()
        timer.start(now: t0)
        timer.perform(.secondary, now: at(3))
        #expect(timer.state == .idle)
        timer.perform(.secondary, now: at(4))
        #expect(timer.state == .idle)
    }
}

@Suite struct FrenchTextTests {
    @Test func durations() {
        #expect(FrenchText.countdown(1122) == "18:42")
        #expect(FrenchText.countdown(0.2) == "00:01")
        #expect(FrenchText.duration(42) == "42 s")
        #expect(FrenchText.duration(300) == "5 min")
        #expect(FrenchText.duration(3900) == "1 h 05")
        #expect(FrenchText.minutes(12 * 60) == "12 min")
        #expect(FrenchText.minutes(20) == "1 min")
        #expect(FrenchText.minutes(65 * 60) == "1 h 05")
        #expect(FrenchText.count(1, "session", "sessions") == "1 session")
    }

    @Test func clocks() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        let date = calendar.date(from: DateComponents(year: 2026, month: 10, day: 1, hour: 9, minute: 5))!
        #expect(FrenchText.clock(date, calendar: calendar) == "9:05")
        #expect(FrenchText.spokenHour(date, calendar: calendar) == "9 h 05")
        let sharp = calendar.date(from: DateComponents(year: 2026, month: 10, day: 1, hour: 18))!
        #expect(FrenchText.spokenHour(sharp, calendar: calendar) == "18 h")
    }
}
