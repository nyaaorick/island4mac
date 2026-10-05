//
//  MacDynamicIslandApp.swift
//  MacDynamicIsland
//
//  Created on 2026/1/20.
//

import SwiftUI

@main
struct Mac_Dynamic_IslandApp: App {
    
    // 🔥 This plugs the AppDelegate into the app
    // Without this line the AppDelegate never runs and no window ever appears
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = OverlayWindowController.shared.getAppState()

    var body: some Scene {
        // Since this is a Dynamic Island app (windows are controlled purely in code), don't put a WindowGroup here
        // An empty Settings scene is enough and stops the system from creating a blank main window
        Settings {
            MainSettingsView()
                .environmentObject(appState)
        }
    }
}
