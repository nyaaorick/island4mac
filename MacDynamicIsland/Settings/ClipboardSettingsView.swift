//
//  ClipboardSettingsView.swift
//  MacDynamicIsland
//
//  Clipboard pane of the settings window
//

import SwiftUI

/// One form like every other pane: how much history to keep, and clearing it. The choices are saved in
/// SettingsDefaults and handed to the store (ClipboardStore.Settings)
struct ClipboardSettingsView: View {
    @ObservedObject var clipboardStore: ClipboardStore

    var body: some View {
        SettingsForm {
            Section(header: Text("History")) {
                Picker("Max items", selection: setting(\.maxItems, SettingsDefaults.clipboardMaxItems)) {
                    Text("10").tag(10)
                    Text("20").tag(20)
                    Text("50").tag(50)
                }

                Picker("Keep history for", selection: setting(\.keepHours, SettingsDefaults.clipboardKeepHours)) {
                    Text("24 hours").tag(24)
                    Text("3 days").tag(72)
                    Text("1 week").tag(168)
                    Text("Forever").tag(0)
                }
            }

            Section(header: Text("Storage")) {
                LabeledContent("Total items", value: "\(clipboardStore.items.count)")
                LabeledContent("Images", value: "\(clipboardStore.imageItemCount)")
            }

            Section(header: Text("Clear")) {
                Button("Clear all history") {
                    clipboardStore.clearAll()
                }
                .foregroundStyle(.red)
            }
        }
    }

    private func setting(_ path: WritableKeyPath<ClipboardStore.Settings, Int>, _ key: SettingsKey<Int>) -> Binding<Int> {
        Binding(get: { clipboardStore.settings[keyPath: path] },
                set: { value in
                    SettingsDefaults.shared.set(key, value: value)
                    clipboardStore.settings[keyPath: path] = value
                })
    }
}

#Preview {
    ClipboardSettingsView(clipboardStore: ClipboardStore(folder: FileManager.default.temporaryDirectory, legacyDefaults: nil))
}
