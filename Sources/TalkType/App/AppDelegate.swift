import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var hotkeyManager: HotkeyManager?
    private var dictationController: DictationController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory) // No Dock icon

        setupStatusItem()
        setupHotkey()
        dictationController = DictationController()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = statusItem?.button else { return }
        button.image = NSImage(systemSymbolName: "mic", accessibilityDescription: "TalkType")
        button.action = #selector(statusItemClicked)
        button.target = self

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "偏好设置...", action: #selector(openPreferences), keyEquivalent: ","))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出 TalkType", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem?.menu = menu
    }

    private func setupHotkey() {
        hotkeyManager = HotkeyManager()
        hotkeyManager?.onKeyDown = { [weak self] in
            Task { @MainActor [weak self] in
                self?.dictationController?.startRecording()
                self?.updateStatusIcon(.recording)
            }
        }
        hotkeyManager?.onKeyUp = { [weak self] in
            Task { @MainActor [weak self] in
                self?.dictationController?.stopRecording()
                self?.updateStatusIcon(.transcribing)
            }
        }
    }

    func updateStatusIcon(_ state: StatusIconState) {
        let symbolName: String
        switch state {
        case .idle:         symbolName = "mic"
        case .recording:    symbolName = "mic.fill"
        case .transcribing: symbolName = "waveform"
        case .showingPopup: symbolName = "checkmark.circle"
        case .error:        symbolName = "exclamationmark.triangle"
        }
        statusItem?.button?.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
    }

    @objc private func statusItemClicked() {}

    @objc private func openPreferences() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

enum StatusIconState {
    case idle, recording, transcribing, showingPopup, error
}
