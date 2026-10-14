import SwiftUI
import AppKit

@main
struct YumiApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        Settings {
            SettingsView()
        }
    }
}
