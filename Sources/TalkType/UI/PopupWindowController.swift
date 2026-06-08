import AppKit
import SwiftUI

// Manages the floating result popup window.
// Positions near the bottom-center of the screen (safe fallback for all apps).
@MainActor
final class PopupWindowController {
    private var window: NSPanel?

    func show(basicText: String,
              styledTextBinding: Binding<String?>,
              onSelect: @escaping (String) -> Void,
              onDismiss: @escaping () -> Void) {

        close()

        let view = ResultPopupView(
            basicText: basicText,
            styledText: styledTextBinding,
            onSelect: { [weak self] text in
                self?.close()
                onSelect(text)
            },
            onDismiss: { [weak self] in
                self?.close()
                onDismiss()
            }
        )

        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.contentView = NSHostingView(rootView: view)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.isMovable = true
        panel.hasShadow = false // SwiftUI shadow handles it

        // Position: bottom-center of the main screen
        if let screen = NSScreen.main {
            let sw = screen.visibleFrame.width
            let sx = screen.visibleFrame.origin.x
            let sy = screen.visibleFrame.origin.y
            let pw: CGFloat = 440
            let ph: CGFloat = 160
            panel.setFrame(
                NSRect(x: sx + (sw - pw) / 2, y: sy + 80, width: pw, height: ph),
                display: false
            )
        }

        panel.orderFront(nil)
        window = panel
    }

    func close() {
        window?.close()
        window = nil
    }
}
