import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var hotkeyManager: HotkeyManager?
    private var dictationController: DictationController?
    private var onboardingWindow: NSWindow?
    private var preferencesWindow: NSWindow?
    private var hotkeyObserver: NSObjectProtocol?
    private var cachedHotkeyKeyCode: Int = 0
    private var cachedHotkeyModifiers: Int = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory) // No Dock icon

        setupStatusItem()
        setupHotkey()

        dictationController = DictationController()

        if !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") {
            showOnboarding()
        }
    }

    private func showOnboarding() {
        var isComplete = false
        let binding = Binding<Bool>(
            get: { isComplete },
            set: { [weak self] val in
                isComplete = val
                if val {
                    UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
                    self?.onboardingWindow?.close()
                    self?.onboardingWindow = nil
                }
            }
        )

        let view = NSHostingView(rootView: OnboardingView(isComplete: binding))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 420),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "欢迎使用 TalkType"
        window.contentView = view
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        onboardingWindow = window
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = statusItem?.button else { return }
        button.image = NSImage(systemSymbolName: "mic", accessibilityDescription: "TalkType")

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "偏好设置...", action: #selector(openPreferences), keyEquivalent: ","))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出 TalkType", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem?.menu = menu
    }

    private func setupHotkey() {
        let s = AppSettings.shared
        hotkeyManager = HotkeyManager(keyCode: s.hotkeyKeyCode, modifiers: s.hotkeyModifiers)
        wireHotkeyCallbacks()

        // Only re-register the Carbon hotkey when its keyCode or modifiers actually change.
        // Listening to all UserDefaults changes (download progress, preferences) would cause
        // unnecessary re-registrations on every minor setting update.
        cachedHotkeyKeyCode = s.hotkeyKeyCode
        cachedHotkeyModifiers = s.hotkeyModifiers
        let center = NotificationCenter.default
        let ud = UserDefaults.standard
        hotkeyObserver = center.addObserver(forName: UserDefaults.didChangeNotification, object: ud, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let newCode = s.hotkeyKeyCode
                let newMods = s.hotkeyModifiers
                if newCode != cachedHotkeyKeyCode || newMods != cachedHotkeyModifiers {
                    cachedHotkeyKeyCode = newCode
                    cachedHotkeyModifiers = newMods
                    self.hotkeyManager?.reregister(keyCode: newCode, modifiers: newMods)
                }
            }
        }
    }

    private func wireHotkeyCallbacks() {
        hotkeyManager?.onKeyDown = { [weak self] in
            Task { @MainActor [weak self] in
                self?.dictationController?.startRecording()
                self?.updateStatusIcon(.recording)
            }
        }
        hotkeyManager?.onKeyUp = { [weak self] in
            Task { @MainActor [weak self] in
                await self?.dictationController?.stopRecording()
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

    func applicationWillTerminate(_ notification: Notification) {
        if let observer = hotkeyObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    @objc private func openPreferences() {
        if preferencesWindow == nil {
            let view = NSHostingView(rootView: PreferencesView())
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 520, height: 480),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "TalkType 偏好设置"
            window.contentView = view
            window.center()
            window.isReleasedWhenClosed = false
            preferencesWindow = window
        }
        preferencesWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

enum StatusIconState {
    case idle, recording, transcribing, showingPopup, error
}
