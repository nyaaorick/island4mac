import SwiftUI

struct ShortcutsSettingsView: View {
    var body: some View {
        Form {
            Section(header: Text("Global Shortcuts")) {
                LabeledContent("Toggle island", value: "⌘ ⇧ Space")
                LabeledContent("Force collapse", value: "⌘ ⌥ Space")
                LabeledContent("Clipboard history", value: "⌘ ⌥ V")
            }
            
            Section(footer: Text("Shortcuts are fixed for now and can't be customized.")) {
                EmptyView()
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
