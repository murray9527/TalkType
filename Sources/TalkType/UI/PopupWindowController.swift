import AppKit
import SwiftUI

/// NSPanel subclass that explicitly accepts key/main status.
/// Required because .borderless NSPanel has canBecomeKey returning NO by default.
final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Interaction states for the dictation popup.
enum DictationState {
    case listening
    case processing
    case ready
    case busy
}

extension DictationState {
    var label: String {
        switch self {
        case .listening:  return "听写中…"
        case .processing: return "识别中…"
        case .ready:      return "就绪"
        case .busy:       return "正在处理上一次输入…"
        }
    }
    var showSpinner: Bool {
        switch self {
        case .listening, .processing: return true
        case .ready, .busy:           return false
        }
    }
    var canConfirm: Bool {
        self == .ready
    }
}

final class PopupState: ObservableObject {
    @Published var text: String = ""
    @Published var styledText: String? = nil
    @Published var modelLabel: String = ""
    @Published var dictationState: DictationState = .listening
    @Published var elapsedSeconds: Int = 0
    @Published var processingSeconds: Int = 0

    // Text optimization state
    @Published var currentTone: ToneStyle = .none
    @Published var isOptimizing: Bool = false
    @Published var detectedEmotion: ASREmotion? = nil

    // Roast mode
    @Published var roastText: String? = nil
    @Published var isRoasting: Bool = false

    // Transient error banner
    @Published var errorMessage: String? = nil

    var onConfirm: (String) -> Void
    var onCancel: () -> Void
    var onReoptimize: ((String) -> Void)? = nil
    var onRoast: ((String) -> Void)? = nil

    init(state: DictationState, onConfirm: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        self.dictationState = state
        self.onConfirm = onConfirm
        self.onCancel = onCancel
    }
}

@MainActor
final class PopupWindowController {
    private var panel: KeyablePanel?
    private var keyMonitor: Any?
    private var globalKeyMonitor: Any?
    private(set) var popupState: PopupState?

    var isVisible: Bool { panel != nil }

    func show() {
        close()
        popupState = PopupState(
            state: .listening,
            onConfirm: { [weak self] text in self?.close() },
            onCancel: { [weak self] in self?.close() }
        )
        setupKeyMonitors()
        panel = makePanel(
            nonActivating: true,
            state: popupState!,
            frame: initialFrame()
        )
        panel!.orderFront(nil)
    }

    func update(text: String, state: DictationState) {
        popupState?.text = text
        if state == .ready {
            popupState?.dictationState = .ready
            upgradeToReadyPanel()
            resizeForCurrentState()
            return
        }
        popupState?.dictationState = state
        resizeForCurrentState()
    }

    /// Replace the non-activating recording panel with a standard
    /// KeyablePanel that supports keyboard input for editing.
    private func upgradeToReadyPanel() {
        guard let ps = popupState, let old = panel else { return }
        let frame = old.frame

        if let g = globalKeyMonitor { NSEvent.removeMonitor(g); globalKeyMonitor = nil }
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }

        let newPanel = makePanel(
            nonActivating: false,
            state: ps,
            frame: frame
        )

        // Show new panel before closing old — no visible gap
        newPanel.orderFront(nil)
        old.close()
        panel = newPanel
        setupKeyMonitors()

        // Activate app and make key — full keyboard support
        NSApp.activate(ignoringOtherApps: true)
        newPanel.makeKey()
        if let content = newPanel.contentView {
            forceFirstResponderTextView(in: content)
        }
    }

    private func makePanel(nonActivating: Bool, state: PopupState, frame: NSRect) -> KeyablePanel {
        var style: NSWindow.StyleMask = .borderless
        if nonActivating {
            style.insert(.nonactivatingPanel)
        }
        let p = KeyablePanel(
            contentRect: frame,
            styleMask: style,
            backing: .buffered,
            defer: false
        )
        let hostingView = NSHostingView(rootView: DictationPopupView(state: state))
        hostingView.wantsLayer = true
        hostingView.layer?.cornerRadius = 20
        hostingView.layer?.masksToBounds = true
        p.contentView = hostingView
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.level = .floating
        p.isMovable = true
        p.becomesKeyOnlyIfNeeded = false
        return p
    }

    private func initialFrame() -> NSRect {
        guard let screen = NSScreen.main else {
            return NSRect(x: 0, y: 0, width: 460, height: 55)
        }
        let sw = screen.visibleFrame.width
        let sx = screen.visibleFrame.origin.x
        let sy = screen.visibleFrame.origin.y
        let sh = screen.visibleFrame.height
        let pw: CGFloat = 600
        let ph: CGFloat = 55
        let py = sy + (sh - ph) * 0.85
        return NSRect(x: sx + (sw - pw) / 2, y: py, width: pw, height: ph)
    }

    private func forceFirstResponderTextView(in view: NSView) {
        if let tv = view as? NSTextView, tv.isEditable {
            tv.window?.makeFirstResponder(tv)
            return
        }
        for subview in view.subviews {
            forceFirstResponderTextView(in: subview)
        }
    }

    func resizeForCurrentState() {
        guard let p = panel, let ps = popupState else { return }
        let targetHeight: CGFloat
        switch ps.dictationState {
        case .busy:
            targetHeight = 55
        case .listening, .processing:
            targetHeight = ps.text.isEmpty ? 55 : 140
        case .ready:
            // Layout (600px wide):
            //   topBar(44) + textLayer(160) = base ~205
            //   + optimizeLayer(~200) if optimization is active
            //   + emotion bar(~44) if emotion detected
            let hasOpt = ps.isOptimizing || ps.isRoasting || (ps.styledText?.isEmpty == false) || (ps.roastText?.isEmpty == false)
            var h: CGFloat = 44 + 1 + 160  // topBar + textLayer
            if hasOpt { h += 1 + 200 }     // optimizeLayer
            if let e = ps.detectedEmotion, e != .neutral, !e.friendlyMessage.isEmpty {
                h += 1 + 44               // emotion bar
            }
            targetHeight = h
        }
        guard abs(p.frame.height - targetHeight) > 1 else { return }
        var frame = p.frame
        let delta = targetHeight - frame.height
        frame.origin.y -= delta
        frame.size.height = targetHeight
        p.setFrame(frame, display: true, animate: true)
    }

    private func setupKeyMonitors() {
        guard popupState != nil else { return }

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let ps = self.popupState, self.isVisible else { return event }
            if event.keyCode == 53 {
                ps.onCancel()
                return nil
            }
            if ps.dictationState == .ready, event.modifierFlags.contains(.command) {
                if event.keyCode == 126 {
                    ps.onConfirm(ps.text)                              // ⌘↑ — insert original
                    return nil
                }
                if event.keyCode == 125 {
                    let text = (ps.styledText?.isEmpty == false) ? ps.styledText! : ps.text
                    ps.onConfirm(text)                                 // ⌘↓ — insert optimized
                    return nil
                }
            }
            return event
        }

        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let ps = self.popupState, self.isVisible else { return }
            if event.keyCode == 53 {
                DispatchQueue.main.async { ps.onCancel() }
            } else if ps.dictationState == .ready, event.modifierFlags.contains(.command) {
                DispatchQueue.main.async {
                    if event.keyCode == 126 {
                        ps.onConfirm(ps.text)                              // ⌘↑ — insert original
                    } else if event.keyCode == 125 {
                        let text = (ps.styledText?.isEmpty == false) ? ps.styledText! : ps.text
                        ps.onConfirm(text)                                 // ⌘↓ — insert optimized
                    }
                }
            }
        }
    }

    func close() {
        if let g = globalKeyMonitor { NSEvent.removeMonitor(g); globalKeyMonitor = nil }
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
        // Clear all text before closing
        popupState?.text = ""
        popupState?.styledText = nil
        popupState?.roastText = nil
        panel?.close()
        panel = nil
        popupState = nil
    }
}
