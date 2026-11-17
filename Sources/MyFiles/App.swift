import SwiftUI

@main
struct MyFilesApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 700, minHeight: 450)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1000, height: 650)
    }
}
