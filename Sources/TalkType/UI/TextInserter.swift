import Foundation
import AppKit

@MainActor
struct TextInserter {

    func insert(_ text: String) {
        let trusted = AXIsProcessTrusted()
        print("[Inserter] AXIsProcessTrusted=\(trusted), inserting text (\(text.count) chars)")

        if !trusted {
            print("[Inserter] WARNING: No Accessibility permission — CGEvent paste may be silently dropped")
        }

        let pasteboard = NSPasteboard.general
        let previous = pasteboard.string(forType: .string)
        let previousChangeCount = pasteboard.changeCount

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        simulatePaste()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if pasteboard.changeCount == previousChangeCount + 1 {
                pasteboard.clearContents()
                if let previous {
                    pasteboard.setString(previous, forType: .string)
                }
            }
        }
    }

    private func simulatePaste() {
        let src = CGEventSource(stateID: .hidSystemState)

        let keyDown = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: true)
        keyDown?.flags = .maskCommand
        let keyUp = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: false)
        keyUp?.flags = .maskCommand

        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}
