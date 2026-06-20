import Carbon
import AppKit

@MainActor
final class HotkeyManager {
    var onKeyDown: (() -> Void)?
    var onKeyUp: (() -> Void)?

    nonisolated(unsafe) private var hotKeyRef: EventHotKeyRef?
    nonisolated(unsafe) private var eventHandlerRef: EventHandlerRef?
    private var currentKeyCode: UInt32
    private var currentModifiers: UInt32

    init(keyCode: Int = 0x3F, modifiers: Int = 0) {
        self.currentKeyCode = UInt32(keyCode)
        self.currentModifiers = UInt32(modifiers)
        register()
    }

    deinit {
        if let ref = hotKeyRef { UnregisterEventHotKey(ref) }
        if let ref = eventHandlerRef { RemoveEventHandler(ref) }
    }

    func reregister(keyCode: Int, modifiers: Int) {
        unregister()
        currentKeyCode = UInt32(keyCode)
        currentModifiers = UInt32(modifiers)
        register()
    }

    private func register() {
        let hotKeyID = EventHotKeyID(signature: OSType("TTKY".fourCharCode), id: 1)

        var eventSpec = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]

        InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, event, userData) -> OSStatus in
                guard let userData else { return OSStatus(eventNotHandledErr) }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                var hotKeyID = EventHotKeyID()
                GetEventParameter(event, UInt32(kEventParamDirectObject), UInt32(typeEventHotKeyID), nil,
                                  MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
                let kind = GetEventKind(event)
                Task { @MainActor in
                    if kind == kEventHotKeyPressed {
                        manager.onKeyDown?()
                    } else if kind == kEventHotKeyReleased {
                        manager.onKeyUp?()
                    }
                }
                return noErr
            },
            eventSpec.count,
            &eventSpec,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )

        RegisterEventHotKey(currentKeyCode, currentModifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    private func unregister() {
        if let ref = hotKeyRef { UnregisterEventHotKey(ref); hotKeyRef = nil }
        if let ref = eventHandlerRef { RemoveEventHandler(ref); eventHandlerRef = nil }
    }
}

private extension String {
    var fourCharCode: FourCharCode {
        var result: FourCharCode = 0
        for char in utf16.prefix(4) {
            result = (result << 8) + FourCharCode(char)
        }
        return result
    }
}
