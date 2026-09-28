import SwiftUI

struct ShortcutsSettingsView: View {
    var body: some View {
        SettingsForm {
            Section {
                LabeledContent("Toggle island", value: "⌘ ⇧ Space")
                LabeledContent("Force collapse", value: "⌘ ⌥ Space")
                LabeledContent("Clipboard history", value: "⌘ ⌥ V")
            } header: {
                Text("Global shortcuts")
            } footer: {
                SettingsNote("Shortcuts are fixed for now and can't be customized.")
            }
        }
    }
}
