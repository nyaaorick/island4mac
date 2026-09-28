import SwiftUI

struct AdvancedSettingsView: View {
    @State private var showingResetConfirmation = false

    var body: some View {
        SettingsForm {
            Section(header: Text("Troubleshooting")) {
                Button("Restart app") {
                     let url = URL(fileURLWithPath: Bundle.main.bundlePath)
                     NSWorkspace.shared.open(url)
                     NSApp.terminate(nil)
                }

                ToggleSettingsRow(
                    key: SettingsDefaults.settingsIconInNotch,
                    title: "Show settings icon in the island",
                    help: "Show a gear icon inside the island for quick access to Settings"
                )
            }

            Section(header: Text("Danger zone")) {
                Button("Reset all settings") {
                    showingResetConfirmation = true
                }
                .foregroundStyle(.red)
                .alert("Reset settings?", isPresented: $showingResetConfirmation) {
                    Button("Cancel", role: .cancel) { }
                    Button("Reset", role: .destructive) {
                        resetSettings()
                    }
                } message: {
                    Text("This restores every setting to its default. The app will then restart automatically.")
                }
            }
        }
    }

    private func resetSettings() {
        if let bundleID = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleID)

            // Restart
            let url = URL(fileURLWithPath: Bundle.main.bundlePath)
            NSWorkspace.shared.open(url)
            NSApp.terminate(nil)
        }
    }
}
