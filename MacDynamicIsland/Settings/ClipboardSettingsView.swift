//
//  ClipboardSettingsView.swift
//  MacDynamicIsland
//
//  Clipboard pane of the settings window
//

import SwiftUI

/// One form like every other pane: history, storage and the clear actions
struct ClipboardSettingsView: View {
    @ObservedObject var clipboardStore: ClipboardStore

    var body: some View {
        SettingsForm {
            Section(header: Text("History")) {
                Picker("Max items", selection: $clipboardStore.maxItems) {
                    Text("10").tag(10)
                    Text("20").tag(20)
                    Text("50").tag(50)
                    Text("100").tag(100)
                }
                .onChange(of: clipboardStore.maxItems) { _, newValue in
                    clipboardStore.updateSettings(maxItems: newValue)
                }

                Picker("Keep history for", selection: $clipboardStore.ttlHours) {
                    Text("24 hours").tag(24)
                    Text("3 days").tag(72)
                    Text("1 week").tag(168)
                    Text("Forever").tag(0)
                }
                .onChange(of: clipboardStore.ttlHours) { _, newValue in
                    clipboardStore.updateSettings(ttlHours: newValue)
                }
            }

            Section(header: Text("Storage")) {
                LabeledContent("Total items", value: "\(clipboardStore.totalItemCount)")
                LabeledContent("Images", value: "\(clipboardStore.imageItemCount)")
                LabeledContent("Files", value: "\(clipboardStore.fileItemCount)")

                Button("Prune expired items now") {
                    clipboardStore.pruneExpiredItems()
                }
            }

            Section(header: Text("Clear")) {
                Button("Clear unpinned only") {
                    clipboardStore.clearUnpinned()
                }

                Button("Clear all history") {
                    clipboardStore.clearAll()
                }
                .foregroundStyle(.red)
            }
        }
    }
}

#Preview {
    ClipboardSettingsView(clipboardStore: ClipboardStore())
}
