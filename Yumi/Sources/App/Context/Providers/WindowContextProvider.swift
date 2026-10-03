import AppKit
import ApplicationServices

/// Whether Yumi may read other applications' windows. Checked without ever showing the
/// system prompt: the person grants it in System Settings, or not at all.
enum AccessibilityPermission {
    static func status() -> ContextPermissionStatus {
        #if APPSTORE
        return .unavailable
        #else
        return AXIsProcessTrusted() ? .granted : .notGranted
        #endif
    }

    /// The Accessibility list of System Settings, for a button the person presses themselves.
    static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
}

/// The focused window of the front application: its title and, when the application says so,
/// the file it shows. Works only if the Accessibility permission was already granted, and
/// listens to the application's own notifications (focus moved, title changed) instead of polling.
@MainActor
final class WindowContextProvider: ContextProvider {
    /// Titles can change several times in a row (a page loading): only the last one is read.
    private let readDelay: Duration
    /// An application that does not answer must never hold Yumi.
    private static let messagingTimeout: Float = 0.25

    private var report: (@MainActor (ContextObservation) -> Void)?
    private var status = ContextPermissionStatus.notGranted
    private var processID: pid_t?
    private var observer: AXObserver?
    private var applicationElement: AXUIElement?
    private var windowElement: AXUIElement?
    private var pendingRead: Task<Void, Never>?
    private var permissionObserver: NSObjectProtocol?
    private var permissionCheck: Task<Void, Never>?

    init(readDelay: Duration = .milliseconds(150)) {
        self.readDelay = readDelay
    }

    func start(report: @escaping @MainActor (ContextObservation) -> Void) {
        stop()
        self.report = report
        status = AccessibilityPermission.status()
        report(.accessibility(status))
        guard status != .unavailable else { return }
        // Posted by the system whenever the Accessibility list changes.
        permissionObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.accessibility.api"), object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.permissionMayHaveChanged() }
        }
    }

    func stop() {
        detach()
        processID = nil
        permissionCheck?.cancel()
        permissionCheck = nil
        if let permissionObserver { DistributedNotificationCenter.default().removeObserver(permissionObserver) }
        permissionObserver = nil
        report = nil
    }

    func applicationDidChange(to application: ApplicationContext?) {
        processID = application?.processID
        attach()
    }

    // MARK: - Permission

    private func permissionMayHaveChanged() {
        // The list is written a moment after the notification.
        permissionCheck?.cancel()
        permissionCheck = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled, let self else { return }
            let now = AccessibilityPermission.status()
            guard now != self.status else { return }
            self.status = now
            self.report?(.accessibility(now))
            self.attach()
        }
    }

    // MARK: - Following the front application

    private func attach() {
        detach()
        guard status == .granted, let processID, report != nil else { return }
        let app = AXUIElementCreateApplication(processID)
        AXUIElementSetMessagingTimeout(app, Self.messagingTimeout)
        applicationElement = app

        var created: AXObserver?
        let callback: AXObserverCallback = { _, _, _, refcon in
            guard let refcon else { return }
            let provider = Unmanaged<WindowContextProvider>.fromOpaque(refcon).takeUnretainedValue()
            MainActor.assumeIsolated { provider.somethingChanged() }
        }
        guard AXObserverCreate(processID, callback, &created) == .success, let created else {
            readNow()
            return
        }
        observer = created
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for name in [kAXFocusedWindowChangedNotification, kAXMainWindowChangedNotification] {
            AXObserverAddNotification(created, app, name as CFString, refcon)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .defaultMode)
        readNow()
    }

    private func detach() {
        pendingRead?.cancel()
        pendingRead = nil
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        observer = nil
        applicationElement = nil
        windowElement = nil
    }

    private func somethingChanged() {
        pendingRead?.cancel()
        pendingRead = Task { [weak self, readDelay] in
            try? await Task.sleep(for: readDelay)
            guard !Task.isCancelled else { return }
            self?.readNow()
        }
    }

    private func readNow() {
        guard let app = applicationElement, let processID else { return }
        let window: AXUIElement? = Self.attribute(kAXFocusedWindowAttribute, of: app)
        follow(window)
        guard let window else {
            report?(.windowFocused(nil))
            return
        }
        let title: String = Self.attribute(kAXTitleAttribute, of: window) ?? ""
        let document: String? = Self.attribute(kAXDocumentAttribute, of: window)
        let path = document.flatMap { URL(string: $0) }.flatMap { $0.isFileURL ? $0.path : nil }
        report?(.windowFocused(WindowContext(title: title, processID: processID, documentPath: path)))
    }

    /// Listens to the title of the focused window, and to its closing.
    private func follow(_ window: AXUIElement?) {
        guard let observer else { return }
        if let windowElement, let window, CFEqual(windowElement, window) { return }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        if let windowElement {
            AXObserverRemoveNotification(observer, windowElement, kAXTitleChangedNotification as CFString)
            AXObserverRemoveNotification(observer, windowElement, kAXUIElementDestroyedNotification as CFString)
        }
        windowElement = window
        if let window {
            AXObserverAddNotification(observer, window, kAXTitleChangedNotification as CFString, refcon)
            AXObserverAddNotification(observer, window, kAXUIElementDestroyedNotification as CFString, refcon)
        }
    }

    private static func attribute<T>(_ name: String, of element: AXUIElement) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success, let value else { return nil }
        if T.self == AXUIElement.self {
            guard CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
            return (value as! T)
        }
        return value as? T
    }
}
