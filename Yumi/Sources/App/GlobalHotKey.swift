import Carbon.HIToolbox

/// One system-wide shortcut, through Carbon's hot keys: the key press is taken before the app in
/// front sees it (⌥ Espace does not type a space there), and no Accessibility permission is needed.
@MainActor
final class GlobalHotKey {
    private var reference: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: @MainActor () -> Void
    private static let signature: OSType = 0x59_75_6D_69 // "Yumi"
    /// Each shortcut has its own number: every handler hears every shortcut of the app, and
    /// answers only its own.
    private static var lastID: UInt32 = 0
    private let id: UInt32

    init(action: @escaping @MainActor () -> Void) {
        self.action = action
        Self.lastID += 1
        id = Self.lastID
    }

    /// Registers the shortcut, replacing the previous one; nil unregisters. False when macOS
    /// refuses it (another app already holds it).
    @discardableResult
    func set(_ shortcut: QuickTaskShortcut?) -> Bool {
        if let reference { UnregisterEventHotKey(reference) }
        reference = nil
        guard let shortcut else { return true }
        installHandler()
        var registered: EventHotKeyRef?
        let status = RegisterEventHotKey(UInt32(shortcut.keyCode), Self.carbonModifiers(shortcut.flags),
                                         EventHotKeyID(signature: Self.signature, id: id),
                                         GetApplicationEventTarget(), 0, &registered)
        reference = registered
        return status == noErr
    }

    private func installHandler() {
        guard handler == nil else { return }
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let me = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, user in
            guard let user, let event else { return OSStatus(eventNotHandledErr) }
            var pressed = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &pressed)
            let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(user).takeUnretainedValue()
            // Another shortcut of the app: let its own handler answer
            guard pressed.signature == 0x59_75_6D_69, MainActor.assumeIsolated({ pressed.id == hotKey.id }) else {
                return OSStatus(eventNotHandledErr)
            }
            MainActor.assumeIsolated { hotKey.action() }
            return noErr
        }, 1, &type, me, &handler)
    }

    /// `NSEvent.ModifierFlags` to Carbon's modifier mask.
    static func carbonModifiers(_ flags: UInt) -> UInt32 {
        var mask: UInt32 = 0
        if flags & (1 << 20) != 0 { mask |= UInt32(cmdKey) }
        if flags & (1 << 19) != 0 { mask |= UInt32(optionKey) }
        if flags & (1 << 18) != 0 { mask |= UInt32(controlKey) }
        if flags & (1 << 17) != 0 { mask |= UInt32(shiftKey) }
        return mask
    }
}
