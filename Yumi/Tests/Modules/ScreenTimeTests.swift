import Testing
import Foundation

private var paris: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
    return calendar
}
/// October 2026, Paris.
private func at(_ hour: Int, _ minute: Int = 0, day: Int = 14) -> Date {
    paris.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
}
private func sample(idle: TimeInterval, locked: Bool = false, displayOn: Bool = true, watching: Bool = false) -> ScreenSample {
    ScreenSample(idle: idle, locked: locked, displayOn: displayOn, watching: watching)
}

/// When a minute in front of the Mac counts (the rule of temps-ecran).
@Suite struct ScreenActivityTests {
    @Test func aLockedSessionNeverCounts() {
        #expect(!ScreenActivity.counts(sample(idle: 0, locked: true)))
        #expect(!ScreenActivity.counts(sample(idle: 0, locked: true, watching: true)))
    }

    @Test func displayOnCountsUpToFiveMinutesWithoutInput() {
        #expect(ScreenActivity.counts(sample(idle: 0)))
        #expect(ScreenActivity.counts(sample(idle: 300)))
        #expect(!ScreenActivity.counts(sample(idle: 301)))
    }

    @Test func aCallOrAFilmCountsWithoutInputUpToTwoHours() {
        #expect(ScreenActivity.counts(sample(idle: 3600, watching: true)))
        #expect(ScreenActivity.counts(sample(idle: 7200, watching: true)))
        #expect(!ScreenActivity.counts(sample(idle: 7201, watching: true)))
    }

    @Test func displayOffCountsOnlyWithRecentInput() {
        #expect(ScreenActivity.counts(sample(idle: 120, displayOn: false)))
        #expect(!ScreenActivity.counts(sample(idle: 400, displayOn: false)))
        // The assertion does not help with the display off: nobody watches
        #expect(!ScreenActivity.counts(sample(idle: 400, displayOn: false, watching: true)))
    }

    @Test func aBreakEndsWhenTheMinutesCountAgain() {
        var streak = ActivityStreak()
        // The first look says nothing; a minute that counts after one that did not ends a break
        let ends = [true, true, false, false, true, true].map { streak.observe(active: $0) }
        #expect(ends == [false, false, false, false, true, false])
        var fresh = ActivityStreak()
        let afterAway = [false, true].map { fresh.observe(active: $0) }
        #expect(afterAway == [false, true])
    }
}

@Suite struct ScreenTimeLogTests {
    @Test func minutesGoToTheirDayAndHourAcrossMidnight() {
        var log = ScreenTimeLog()
        log.add(at: at(23, 59), calendar: paris)
        log.add(at: at(0, 0, day: 15), calendar: paris)
        log.add(at: at(0, 1, day: 15), calendar: paris)
        #expect(log.minutes(on: at(12), calendar: paris) == 1)
        #expect(log.minutes(on: at(12, day: 15), calendar: paris) == 2)
        #expect(log.hours(on: at(12), calendar: paris)[23] == 1)
        #expect(log.hours(on: at(12, day: 15), calendar: paris)[0] == 2)
        #expect(log.hours(on: at(12, day: 16), calendar: paris) == Array(repeating: 0, count: 24))
    }

    @Test func historyKeepsNinetyDaysAndHoursFourteen() {
        var log = ScreenTimeLog()
        let now = at(12, day: 14)
        for back in [0, 13, 14, 89, 90] {
            log.add(minutes: 10, at: paris.date(byAdding: .day, value: -back, to: now)!, calendar: paris)
        }
        log.prune(now: now, calendar: paris)
        let day = { (back: Int) in paris.date(byAdding: .day, value: -back, to: now)! }
        #expect(log.minutes(on: day(89), calendar: paris) == 10)
        #expect(log.minutes(on: day(90), calendar: paris) == 0)
        #expect(log.hours(on: day(13), calendar: paris).reduce(0, +) == 10)
        #expect(log.hours(on: day(14), calendar: paris).reduce(0, +) == 0)
        #expect(log.minutes(on: day(14), calendar: paris) == 10)
    }

    @Test func theThresholdThenEachHourAboveIsToldOnce() {
        var log = ScreenTimeLog()
        log.add(minutes: 479, at: at(16), calendar: paris)
        #expect(log.newStep(threshold: 480, now: at(16), calendar: paris) == nil)
        log.add(at: at(16, 1), calendar: paris)
        #expect(log.newStep(threshold: 480, now: at(16, 1), calendar: paris) == 480)
        #expect(log.newStep(threshold: 480, now: at(16, 2), calendar: paris) == nil)
        log.add(minutes: 59, at: at(17), calendar: paris)
        #expect(log.newStep(threshold: 480, now: at(17), calendar: paris) == nil)
        log.add(at: at(17, 1), calendar: paris)
        #expect(log.newStep(threshold: 480, now: at(17, 1), calendar: paris) == 540)
        // Many minutes at once (a long sleep cannot do it, but a lowered threshold can): one step only
        log.add(minutes: 200, at: at(18), calendar: paris)
        #expect(log.newStep(threshold: 480, now: at(18), calendar: paris) == 720)   // 740 min: four hours above
        #expect(log.newStep(threshold: 480, now: at(18), calendar: paris) == nil)
        // A new day starts from nothing
        log.add(minutes: 480, at: at(9, day: 15), calendar: paris)
        #expect(log.newStep(threshold: 480, now: at(9, day: 15), calendar: paris) == 480)
    }

    @Test func survivesASaveAndALoad() throws {
        var log = ScreenTimeLog()
        log.add(minutes: 42, at: at(10), calendar: paris)
        _ = log.newStep(threshold: 30, now: at(10), calendar: paris)
        let back = try JSONDecoder().decode(ScreenTimeLog.self, from: JSONEncoder().encode(log))
        #expect(back == log)
    }
}

@Suite struct ScreenTimeStatsTests {
    @Test func averageMedianAndThreeQuarters() {
        #expect(ScreenTimeStats.average([]) == nil)
        #expect(ScreenTimeStats.average([300, 400, 500]) == 400)
        #expect(ScreenTimeStats.median([500, 300, 400]) == 400)
        #expect(ScreenTimeStats.median([300, 400, 500, 600]) == 450)
        #expect(ScreenTimeStats.percentile75([100, 200, 300, 400]) == 300)
        #expect(ScreenTimeStats.percentile75([100, 200, 300, 400, 500]) == 400)
        #expect(ScreenTimeStats.percentile75([42]) == 42)
        #expect(ScreenTimeStats.percentile75([]) == nil)
    }

    @Test func aDayWithoutTheMacIsLeftOutOfTheFigures() {
        var log = ScreenTimeLog()
        log.add(minutes: 300, at: at(10, day: 12), calendar: paris)
        log.add(minutes: 500, at: at(10, day: 14), calendar: paris)
        #expect(log.usedDays(7, now: at(12, day: 14), calendar: paris) == [300, 500])
        #expect(log.lastDays(7, now: at(12, day: 14), calendar: paris).map(\.minutes) == [0, 0, 0, 0, 300, 0, 500])
    }
}

@Suite struct ScreenTimeSummaryTests {
    @Test func todayAgainstTheThreshold() {
        var log = ScreenTimeLog()
        log.add(minutes: 312, at: at(14), calendar: paris)
        let snapshot = ScreenTimeSummary.snapshot(log, threshold: 480, now: at(15), calendar: paris)
        #expect(snapshot.id == "screen-time")
        #expect(snapshot.status == "5 h 12")
        #expect(snapshot.title == "5 h 12 devant l'écran aujourd'hui.")
        #expect(snapshot.subtitle == "Encore 2 h 48 avant ton seuil de 8 h.")
        #expect(snapshot.colorHex == ScreenTimeSummary.calm)
        #expect(snapshot.progress?.fraction == 312.0 / 480.0)
        #expect(snapshot.symbol == "hourglass")
        #expect(snapshot.primarySymbol == "gearshape.fill")
        #expect(ModuleCategory.of(moduleID: snapshot.id) == .day)
    }

    @Test func colourTurnsAmberThenRed() {
        #expect(ScreenTimeSummary.color(minutes: 383, threshold: 480) == ScreenTimeSummary.calm)
        #expect(ScreenTimeSummary.color(minutes: 384, threshold: 480) == ScreenTimeSummary.close)
        #expect(ScreenTimeSummary.color(minutes: 480, threshold: 480) == ScreenTimeSummary.over)
        var log = ScreenTimeLog()
        log.add(minutes: 525, at: at(18), calendar: paris)
        let snapshot = ScreenTimeSummary.snapshot(log, threshold: 480, now: at(18, 30), calendar: paris)
        #expect(snapshot.subtitle == "45 min au-delà de ton seuil de 8 h.")
        #expect(snapshot.progress?.fraction == 1)
    }

    @Test func nothingYetToday() {
        let snapshot = ScreenTimeSummary.snapshot(ScreenTimeLog(), threshold: 600, now: at(8), calendar: paris)
        #expect(snapshot.status == "0 min")
        #expect(snapshot.title == "Pas encore d'écran aujourd'hui.")
        #expect(snapshot.pages["hours"] == nil)
        #expect(snapshot.pages["days"]?.count == 7)
        #expect(snapshot.pages["figures"] == nil)
    }

    @Test func hoursFromTheFirstUsedToNowThenTheWeekAndTheFigures() {
        var log = ScreenTimeLog()
        log.add(minutes: 40, at: at(9, 10), calendar: paris)
        log.add(minutes: 20, at: at(11, 10), calendar: paris)
        log.add(minutes: 600, at: at(10, day: 13), calendar: paris)
        let snapshot = ScreenTimeSummary.snapshot(log, threshold: 480, now: at(12, 5), calendar: paris)
        #expect(snapshot.pages["hours"]?.map(\.title) == ["9", "10", "11", "12"])
        #expect(snapshot.pages["hours"]?.map(\.detail) == ["40", "0", "20", "0"])
        let days = snapshot.pages["days"] ?? []
        #expect(days.count == 7)
        #expect(days.last?.detail == "60")
        #expect(days[5].state == .failure)
        #expect(snapshot.pages["figures"]?.map(\.id) == ["average", "median", "p75"])
        #expect(snapshot.pages["figures"]?.first?.label == "5 h 30")
    }

    @Test func theFilmingExampleHasAWeek() {
        let snapshot = ScreenTimeSummary.snapshot(.example(now: at(15), calendar: paris), threshold: 480, now: at(15), calendar: paris)
        #expect(snapshot.pages["hours"]?.count == 9)
        #expect(snapshot.pages["days"]?.filter { $0.detail != "0" }.count == 6)
    }
}

/// The module with a made-up Mac: no real look, no real file.
@MainActor @Suite struct ScreenTimeModuleTests {
    private func make(_ samples: [ScreenSample], remarks: Bool = true, hours: Int = 8)
        -> (ScreenTimeModule, URL, () -> [Int], () -> Int) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("screen-time-\(UUID().uuidString).json")
        let defaults = UserDefaults(suiteName: "yumi.screen-time.\(UUID().uuidString)")!
        defaults.set(hours, forKey: ScreenTimeModule.thresholdKey)
        defaults.set(remarks, forKey: ScreenTimeModule.remarksKey)
        var queue = samples
        var steps: [Int] = []
        var breaks = 0
        let module = ScreenTimeModule(fileURL: url, defaults: defaults,
                                      sample: { queue.isEmpty ? sample(idle: 0) : queue.removeFirst() },
                                      onThreshold: { minutes, _ in steps.append(minutes) },
                                      onBreak: { breaks += 1 })
        return (module, url, { steps }, { breaks })
    }

    @Test func countsTheMinutesThatCountAndSeesTheBreakEnd() {
        let (module, url, _, breaks) = make([sample(idle: 0), sample(idle: 10), sample(idle: 400), sample(idle: 900), sample(idle: 2)])
        for minute in 0..<5 { module.tick(now: at(10, minute)) }
        #expect(module.snapshot.status != "")
        let saved = try? JSONDecoder().decode(ScreenTimeLog.self, from: Data(contentsOf: url))
        #expect(saved?.minutes(on: at(10)) == 3)
        #expect(breaks() == 1)
        try? FileManager.default.removeItem(at: url)
    }

    @Test func tellsTheThresholdOnlyWhenAsked() {
        let (on, onURL, steps, _) = make([], hours: 4)
        for minute in 0..<240 { on.tick(now: at(9).addingTimeInterval(Double(minute) * 60)) }
        #expect(steps() == [240])
        let (off, offURL, quiet, _) = make([], remarks: false, hours: 4)
        for minute in 0..<240 { off.tick(now: at(9).addingTimeInterval(Double(minute) * 60)) }
        #expect(quiet().isEmpty)
        try? FileManager.default.removeItem(at: onURL)
        try? FileManager.default.removeItem(at: offURL)
    }

    @Test func anUnknownThresholdFallsBackToEightHours() {
        let (module, url, _, _) = make([], hours: 7)
        #expect(module.threshold == 480)
        try? FileManager.default.removeItem(at: url)
    }
}
