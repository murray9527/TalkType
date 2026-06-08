import Carbon
import AppKit

// Listens for the global push-to-talk hotkey (default: Option+Space).
// Uses Carbon EventHotKey API which works without Accessibility permission.
final class HotkeyManager {
    var onKeyDown: (() -> Void)?
    var onKeyUp: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    // Default: Option (⌥) + Space
    private let keyCode: UInt32 = UInt32(kVK_Space)
    private let modifiers: UInt32 = UInt32(optionKey)

    init() {
        register()
    }

    deinit {
        unregister()
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
                if kind == kEventHotKeyPressed {
                    manager.onKeyDown?()
                } else if kind == kEventHotKeyReleased {
                    manager.onKeyUp?()
                }
                return noErr
            },
            eventSpec.count,
            &eventSpec,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )

        RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    private func unregister() {
        if let ref = hotKeyRef { UnregisterEventHotKey(ref) }
        if let ref = eventHandlerRef { RemoveEventHandler(ref) }
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
