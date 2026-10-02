import AppKit

/// The front application, launches and quits, sleep, wake and lock, from `NSWorkspace` and the
/// distributed notifications of the system. Needs no permission and never polls.
@MainActor
final class WorkspaceContextProvider: ContextProvider {
    /// Yumi itself coming to the front (its settings window) is not a change of context.
    private let ignoredBundleID: String?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []

    init(ignoredBundleID: String? = Bundle.main.bundleIdentifier) {
        self.ignoredBundleID = ignoredBundleID
    }

    func start(report: @escaping @MainActor (ContextObservation) -> Void) {
        stop()
        let workspace = NSWorkspace.shared.notificationCenter
        listen(workspace, NSWorkspace.didActivateApplicationNotification) { [weak self] running in
            guard let app = self?.application(running) else { return }
            report(.applicationActivated(app))
        }
        listen(workspace, NSWorkspace.didLaunchApplicationNotification) { [weak self] running in
            guard let app = self?.application(running, regularOnly: true) else { return }
            report(.applicationLaunched(app))
        }
        listen(workspace, NSWorkspace.didTerminateApplicationNotification) { [weak self] running in
            guard let app = self?.application(running, regularOnly: true) else { return }
            report(.applicationTerminated(app))
        }
        let signals: [(Notification.Name, ContextSystemSignal)] = [
            (NSWorkspace.willSleepNotification, .willSleep),
            (NSWorkspace.didWakeNotification, .didWake),
            (NSWorkspace.screensDidSleepNotification, .screensDidSleep),
            (NSWorkspace.screensDidWakeNotification, .screensDidWake),
            (NSWorkspace.sessionDidResignActiveNotification, .sessionResigned),
            (NSWorkspace.sessionDidBecomeActiveNotification, .sessionResumed),
        ]
        for (name, signal) in signals {
            listen(workspace, name) { _ in report(.system(signal)) }
        }
        let distributed = DistributedNotificationCenter.default()
        listen(distributed, Notification.Name("com.apple.screenIsLocked")) { _ in report(.system(.screenLocked)) }
        listen(distributed, Notification.Name("com.apple.screenIsUnlocked")) { _ in report(.system(.screenUnlocked)) }

        // The application already in front when the engine starts.
        if let front = NSWorkspace.shared.frontmostApplication, let app = context(of: front) {
            report(.applicationActivated(app))
        }
    }

    func stop() {
        for (center, observer) in observers { center.removeObserver(observer) }
        observers = []
    }

    private func listen(_ center: NotificationCenter, _ name: Notification.Name,
                        _ handle: @escaping @MainActor (NSRunningApplication?) -> Void) {
        observers.append((center, center.addObserver(forName: name, object: nil, queue: .main) { note in
            let running = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated { handle(running) }
        }))
    }

    private func application(_ running: NSRunningApplication?, regularOnly: Bool = false) -> ApplicationContext? {
        guard let running else { return nil }
        // Helpers and agents without a window are launched and quit all day long: not worth an event.
        if regularOnly, running.activationPolicy != .regular { return nil }
        return context(of: running)
    }

    private func context(of running: NSRunningApplication) -> ApplicationContext? {
        let bundleID = running.bundleIdentifier ?? ""
        if let ignoredBundleID, bundleID == ignoredBundleID { return nil }
        let name = running.localizedName ?? running.bundleURL?.deletingPathExtension().lastPathComponent ?? bundleID
        return ApplicationContext(bundleID: bundleID, name: name, processID: running.processIdentifier,
                                  category: Self.category(of: running))
    }

    /// Read once per application: the Info.plist of a bundle does not change while it runs.
    private static var categories: [String: ApplicationCategory?] = [:]

    private static func category(of running: NSRunningApplication) -> ApplicationCategory? {
        guard let url = running.bundleURL else { return nil }
        if let known = categories[url.path] { return known }
        let value = (Bundle(url: url)?.object(forInfoDictionaryKey: "LSApplicationCategoryType") as? String)
            .flatMap { $0.isEmpty ? nil : ApplicationCategory($0) }
        categories[url.path] = value
        return value
    }
}
