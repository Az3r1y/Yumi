import SwiftUI
import AppKit

@main
struct YumiApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        Settings {
            // Placeholder settings scene — real settings arrive in a later step.
            Text("Yumi — settings coming soon.")
                .frame(width: 320, height: 120)
        }
    }
}
