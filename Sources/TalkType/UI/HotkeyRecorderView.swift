import SwiftUI
import Carbon

// Moved out of the View struct to avoid Swift 6 dispatch_once assertion
// when the static is lazily initialized from SwiftUI's AttributeGraph
// (which may run on a non-main thread).
private let keyNames: [UInt32: String] = [
    0x00: "A", 0x01: "S", 0x02: "D", 0x03: "F", 0x04: "H", 0x05: "G",
    0x06: "Z", 0x07: "X", 0x08: "C", 0x09: "V", 0x0B: "B", 0x0C: "Q",
    0x0D: "W", 0x0E: "E", 0x0F: "R", 0x10: "Y", 0x11: "T",
    0x12: "1", 0x13: "2", 0x14: "3", 0x15: "4", 0x16: "6", 0x17: "5",
    0x18: "=", 0x19: "9", 0x1A: "7", 0x1B: "-", 0x1C: "8", 0x1D: "0",
    0x1E: "]", 0x1F: "O", 0x20: "U", 0x21: "[", 0x22: "I", 0x23: "P",
    0x25: "L", 0x26: "J", 0x27: "'", 0x28: "K", 0x29: ";",
    0x2A: "\\", 0x2B: ",", 0x2C: "/", 0x2D: "N", 0x2E: "M", 0x2F: ".",
    0x30: "⇥",
    UInt32(kVK_Space): "Space",
    UInt32(kVK_Return): "↵",
    UInt32(kVK_Delete): "⌫",
    UInt32(kVK_Escape): "⎋",
    UInt32(kVK_Function): "Fn",
    UInt32(kVK_F5): "F5", UInt32(kVK_F6): "F6",
    UInt32(kVK_F7): "F7", UInt32(kVK_F8): "F8",
]

struct HotkeyRecorderView: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var isRecording = false
    @State private var monitor: Any?
    @State private var pendingModifiers: NSEvent.ModifierFlags = []
    @State private var modifierDisplay: String = ""

    var body: some View {
        HStack(spacing: 12) {
            if isRecording {
                Text(modifierDisplay.isEmpty ? "请按下新快捷键…" : modifierDisplay + "…")
                    .font(.caption)
                    .foregroundColor(.accentColor)
                    .animation(.easeInOut(duration: 0.15), value: modifierDisplay)
            } else {
                Text(displayString)
                    .font(.system(.body, design: .monospaced))
            }

            Button(isRecording ? "取消" : "录制") {
                if isRecording { cancel() } else { start() }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .onDisappear { cancel() }
    }

    private var displayString: String {
        Self.keyCodeToString(settings.hotkeyKeyCode, modifiers: settings.hotkeyModifiers)
    }

    private func start() {
        isRecording = true
        pendingModifiers = []
        modifierDisplay = ""
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            if event.type == .flagsChanged {
                pendingModifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                modifierDisplay = Self.modifierString(pendingModifiers)
                return nil
            }
            guard event.type == .keyDown else { return event }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let carbonMods = Self.toCarbonModifiers(flags)
            settings.hotkeyKeyCode = Int(event.keyCode)
            settings.hotkeyModifiers = Int(carbonMods)
            cleanup()
            return nil
        }
    }

    private func cancel() { cleanup() }

    private func cleanup() {
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
        isRecording = false
        pendingModifiers = []
        modifierDisplay = ""
    }

    // MARK: - Conversion

    static func toCarbonModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var mods: UInt32 = 0
        if flags.contains(.command)  { mods |= UInt32(cmdKey) }
        if flags.contains(.shift)    { mods |= UInt32(shiftKey) }
        if flags.contains(.option)   { mods |= UInt32(optionKey) }
        if flags.contains(.control)  { mods |= UInt32(controlKey) }
        return mods
    }

    private static func modifierString(_ flags: NSEvent.ModifierFlags) -> String {
        var parts: [String] = []
        if flags.contains(.control) { parts.append("⌃") }
        if flags.contains(.option)  { parts.append("⌥") }
        if flags.contains(.shift)   { parts.append("⇧") }
        if flags.contains(.command) { parts.append("⌘") }
        return parts.joined()
    }

    static func keyCodeToString(_ keyCode: Int, modifiers: Int) -> String {
        var parts: [String] = []
        let mods = UInt32(modifiers)
        if mods & UInt32(cmdKey) != 0     { parts.append("⌘") }
        if mods & UInt32(shiftKey) != 0   { parts.append("⇧") }
        if mods & UInt32(optionKey) != 0  { parts.append("⌥") }
        if mods & UInt32(controlKey) != 0 { parts.append("⌃") }

        let kc = UInt32(keyCode)
        parts.append(keyNames[kc] ?? "Key\(kc)")
        return parts.joined()
    }

}
