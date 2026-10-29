import SwiftUI

@main
struct Island4macApp: App {
    // The AppDelegate creates the island, the menu bar item and the plugins; nothing here opens a window
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = IslandController.shared.getAppState()

    var body: some Scene {
        // The island's windows are made in code. An empty Settings scene keeps the system from making a main window
        Settings {
            MainSettingsView()
                .environmentObject(appState)
        }
    }
}
