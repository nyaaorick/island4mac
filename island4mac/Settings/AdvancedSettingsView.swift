import SwiftUI

struct AdvancedSettingsView: View {
    @ObservedObject private var settings = SettingsDefaults.shared
    @State private var catalogURL = SettingsDefaults.shared.get(SettingsDefaults.pluginIndexURL)
    @State private var showingResetConfirmation = false

    var body: some View {
        SettingsForm {
            Section {
                TextField("Catalog address", text: $catalogURL, prompt: Text("https://…/index.json"))
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(saveCatalogURL)
                HStack {
                    Button("Use Default") {
                        catalogURL = SettingsDefaults.pluginIndexURL.defaultValue
                        saveCatalogURL()
                    }
                    .disabled(catalogURL == SettingsDefaults.pluginIndexURL.defaultValue)
                    Button("Save") { saveCatalogURL() }
                        .disabled(catalogURL == settings.get(SettingsDefaults.pluginIndexURL))
                }
            } header: {
                Text("Plugin catalog")
            } footer: {
                SettingsNote("The index.json the Plugins pane lists plugins from: the island4mac-plugins repo's, or your own (https, or a file on this Mac).")
            }

            Section(header: Text("Troubleshooting")) {
                Button("Restart island4mac") { relaunch() }
            }

            Section(header: Text("Danger zone")) {
                Button("Reset All Settings…") { showingResetConfirmation = true }
                    .foregroundStyle(.red)
                    .alert("Reset settings?", isPresented: $showingResetConfirmation) {
                        Button("Cancel", role: .cancel) {}
                        Button("Reset", role: .destructive) { resetSettings() }
                    } message: {
                        Text("Every setting goes back to its default, and the app restarts. Plugins and their data stay.")
                    }
            }
        }
    }

    private func saveCatalogURL() {
        let trimmed = catalogURL.trimmingCharacters(in: .whitespacesAndNewlines)
        catalogURL = trimmed.isEmpty ? SettingsDefaults.pluginIndexURL.defaultValue : trimmed
        settings.set(SettingsDefaults.pluginIndexURL, value: catalogURL)
    }

    private func resetSettings() {
        if let bundleID = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleID)
        }
        relaunch()
    }

    private func relaunch() {
        NSWorkspace.shared.open(Bundle.main.bundleURL)
        NSApp.terminate(nil)
    }
}
