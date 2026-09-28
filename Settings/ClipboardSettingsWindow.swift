//
//  ClipboardSettingsWindow.swift
//  MacDynamicIsland
//
//  Clipboard pane of the settings window
//

import SwiftUI

/// One form like every other pane: layout, history, privacy, storage and the clear actions
struct ClipboardSettingsWindow: View {
    @ObservedObject var hubStore: ClipboardHubStore

    var body: some View {
        SettingsForm {
            Section(header: Text("Layout")) {
                Picker("Default view", selection: $hubStore.displayMode) {
                    Text("Grid").tag(ClipboardHubStore.DisplayMode.grid)
                    Text("Reel (horizontal)").tag(ClipboardHubStore.DisplayMode.reel)
                }
                .pickerStyle(.segmented)
            }

            Section(header: Text("History")) {
                Picker("Max items", selection: $hubStore.maxItems) {
                    Text("10").tag(10)
                    Text("20").tag(20)
                    Text("50").tag(50)
                    Text("100").tag(100)
                }
                .onChange(of: hubStore.maxItems) { _, newValue in
                    hubStore.updateSettings(maxItems: newValue)
                }

                Picker("Keep history for", selection: $hubStore.ttlHours) {
                    Text("24 hours").tag(24)
                    Text("3 days").tag(72)
                    Text("1 week").tag(168)
                    Text("Forever").tag(0)
                }
                .onChange(of: hubStore.ttlHours) { _, newValue in
                    hubStore.updateSettings(ttlHours: newValue)
                }
            }

            Section {
                Toggle("Enable encryption", isOn: $hubStore.encryptionEnabled)
                    .onChange(of: hubStore.encryptionEnabled) { _, newValue in
                        hubStore.updateSettings(encryptionEnabled: newValue)
                    }

                Toggle("Require Touch ID or password", isOn: $hubStore.touchIDEnabled)
                    .onChange(of: hubStore.touchIDEnabled) { _, newValue in
                        hubStore.updateSettings(touchIDEnabled: newValue)
                    }

                if hubStore.touchIDEnabled {
                    Picker("Auto-lock after", selection: $hubStore.sessionTimeoutMinutes) {
                        Text("Immediately").tag(0)
                        Text("1 minute").tag(1)
                        Text("5 minutes").tag(5)
                        Text("15 minutes").tag(15)
                        Text("1 hour").tag(60)
                    }
                    .onChange(of: hubStore.sessionTimeoutMinutes) { _, newValue in
                        hubStore.updateSettings(sessionTimeout: newValue)
                    }
                }
            } header: {
                Text("Privacy")
            } footer: {
                SettingsNote("Encryption protects clipboard history on disk with AES-256 GCM.")
            }

            Section(header: Text("Storage")) {
                LabeledContent("Total items", value: "\(hubStore.totalItemCount)")
                LabeledContent("Images", value: "\(hubStore.imageItemCount)")
                LabeledContent("Files", value: "\(hubStore.fileItemCount)")

                Button("Prune expired items now") {
                    hubStore.pruneExpiredItems()
                }
            }

            Section(header: Text("Clear")) {
                Button("Clear unpinned only") {
                    hubStore.clearUnpinned()
                }

                Button("Clear all history") {
                    hubStore.clearAll()
                }
                .foregroundStyle(.red)
            }
        }
    }
}

#Preview {
    ClipboardSettingsWindow(hubStore: ClipboardHubStore())
}
