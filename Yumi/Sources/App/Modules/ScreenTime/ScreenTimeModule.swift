import CoreGraphics
import Foundation
import IOKit.pwr_mgt

/// Screen time: once a minute, whether the person is really in front of the Mac, added to the
/// day (`ScreenTimeLog`). Everything stays in Yumi's folder. It also tells when the daily
/// threshold is reached, then every hour above it, and when a real break ends.
@MainActor
final class ScreenTimeModule: YumiModule {
    let id = ScreenTimeSummary.moduleID
    var category: ModuleCategory { .day }

    /// The daily threshold in hours, and whether Yumi says it when it is reached.
    static let thresholdKey = "screenTime.thresholdHours"
    static let remarksKey = "screenTime.remarks"

    private let fileURL: URL
    private let defaults: UserDefaults
    private let sample: @MainActor () -> ScreenSample
    private let onThreshold: @MainActor (_ minutes: Int, _ threshold: Int) -> Void
    private let onBreak: @MainActor () -> Void
    private let openSettings: @MainActor () -> Void

    private var log = ScreenTimeLog()
    private var streak = ActivityStreak()
    private var onChange: (@MainActor () -> Void)?
    private var sampling: Task<Void, Never>?
    private var settingsObserver: NSObjectProtocol?

    init(fileURL: URL = AppIdentity.supportDirectory.appendingPathComponent("screen-time.json"),
         defaults: UserDefaults = .standard,
         sample: @escaping @MainActor () -> ScreenSample = ScreenProbe.sample,
         onThreshold: @escaping @MainActor (_ minutes: Int, _ threshold: Int) -> Void = { _, _ in },
         onBreak: @escaping @MainActor () -> Void = {},
         openSettings: @escaping @MainActor () -> Void = {}) {
        self.fileURL = fileURL
        self.defaults = defaults
        self.sample = sample
        self.onThreshold = onThreshold
        self.onBreak = onBreak
        self.openSettings = openSettings
    }

    /// The daily threshold, in minutes.
    var threshold: Int {
        let hours = defaults.integer(forKey: Self.thresholdKey)
        return (ScreenTimeSummary.thresholds.contains(hours) ? hours : ScreenTimeSummary.defaultThreshold) * 60
    }

    private var remarksOn: Bool { defaults.object(forKey: Self.remarksKey) as? Bool ?? true }

    var snapshot: ModuleSnapshot { ScreenTimeSummary.snapshot(log, threshold: threshold, now: Date()) }

    func start(onChange: @escaping @MainActor () -> Void) {
        self.onChange = onChange
        log = load()
        log.prune(now: Date())
        streak = ActivityStreak()
        settingsObserver = NotificationCenter.default.addObserver(forName: .screenTimeSettingsChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.onChange?() }
        }
        let interval = Self.interval
        sampling = Task { [weak self] in
            while !Task.isCancelled {
                // The Mac asleep, nothing runs: no minute is counted for the time it slept.
                try? await Task.sleep(for: .seconds(interval), tolerance: .seconds(interval / 6))
                guard !Task.isCancelled, let self else { return }
                self.tick(now: Date())
            }
        }
        onChange()
    }

    func stop() {
        sampling?.cancel()
        sampling = nil
        if let settingsObserver { NotificationCenter.default.removeObserver(settingsObserver) }
        settingsObserver = nil
        onChange = nil
        save()
    }

    func perform(_ action: ModuleAction) {
        if action == .primary { openSettings() }
    }

    /// One look: the minute counts or not, a break may have ended, a threshold may be reached.
    func tick(now: Date) {
        let active = ScreenActivity.counts(sample())
        if active { log.add(at: now) }
        if streak.observe(active: active) { onBreak() }
        log.prune(now: now)
        let threshold = threshold
        if let step = log.newStep(threshold: threshold, now: now), remarksOn {
            onThreshold(step, threshold)
        }
        save()
        onChange?()
    }

    // MARK: Storage

    private func load() -> ScreenTimeLog {
        guard let data = try? Data(contentsOf: fileURL) else { return ScreenTimeLog() }
        return (try? JSONDecoder().decode(ScreenTimeLog.self, from: data)) ?? ScreenTimeLog()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(log) else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }

    /// Seconds between two looks, each worth one minute. Debug builds read `YUMI_SCREEN_TIME_TICK`
    /// to make an hour pass in a minute (1 gives one minute counted per second).
    private static var interval: Double {
        #if DEBUG
        if let seconds = ProcessInfo.processInfo.environment["YUMI_SCREEN_TIME_TICK"].flatMap(Double.init), seconds > 0 {
            return seconds
        }
        #endif
        return 60
    }
}

/// Asks the Mac, without any permission: the time since the last input, the lock, the display,
/// and whether a program keeps the display awake (a call, a film, a presentation).
enum ScreenProbe {
    @MainActor static func sample() -> ScreenSample {
        // kCGAnyInputEventType: any key, click or mouse move
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
        let session = CGSessionCopyCurrentDictionary() as? [String: Any]
        let locked = session?["CGSSessionScreenIsLocked"] as? Bool ?? false
        let displayOn = CGDisplayIsAsleep(CGMainDisplayID()) == 0
        var status: Unmanaged<CFDictionary>?
        var watching = false
        if IOPMCopyAssertionsStatus(&status) == kIOReturnSuccess, let assertions = status?.takeRetainedValue() as? [String: Int] {
            watching = (assertions["PreventUserIdleDisplaySleep"] ?? 0) > 0
        }
        return ScreenSample(idle: idle, locked: locked, displayOn: displayOn, watching: watching)
    }
}

extension Notification.Name {
    /// The settings changed the threshold or the remarks.
    static let screenTimeSettingsChanged = AppIdentity.notification("screenTimeSettingsChanged")
}
