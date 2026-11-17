import SwiftUI

/// Single-window app: closing the window quits it, so clicking the Dock icon
/// afterwards starts a fresh instance instead of doing nothing.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@main
struct MyFilesApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 700, minHeight: 450)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1000, height: 650)
    }
}
