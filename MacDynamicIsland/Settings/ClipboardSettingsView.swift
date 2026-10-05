//
//  ClipboardSettingsView.swift
//  MacDynamicIsland
//
//  Clipboard pane of the settings window
//

import SwiftUI

/// One form like every other pane: history, storage and the clear actions
struct ClipboardSettingsView: View {
    @ObservedObject var hubStore: ClipboardHubStore

    var body: some View {
        SettingsForm {
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
    ClipboardSettingsView(hubStore: ClipboardHubStore())
}
