import SwiftUI

@main
struct SimpleServeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // All window management is handled by AppDelegate.
        // Using Settings (rather than WindowGroup) satisfies the @main App
        // requirement without auto-opening any window at launch.
        Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    appDelegate.openSettingsWindow()
                }
                .keyboardShortcut(",")
            }
        }
    }
}
