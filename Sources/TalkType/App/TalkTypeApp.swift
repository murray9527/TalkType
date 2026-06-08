import SwiftUI
import AppKit

@main
struct TalkTypeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // No main window — this is a menu bar app
        Settings {
            PreferencesView()
        }
    }
}
