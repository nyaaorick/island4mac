import SwiftUI

struct AppearanceSettingsView: View {
    var body: some View {
        Form {
            Section(header: Text(L("settings.appearance.header"))) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(L("settings.appearance.corner_radius"))
                        Spacer()
                        Text(String(format: "%.2f", SettingsDefaults.shared.get(SettingsDefaults.cornerRadiusScaling)))
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: Binding(
                        get: { SettingsDefaults.shared.get(SettingsDefaults.cornerRadiusScaling) },
                        set: { SettingsDefaults.shared.set(SettingsDefaults.cornerRadiusScaling, value: $0) }
                    ), in: 0.5...2.0, step: 0.05)
                }
                .padding(.vertical, 4)

                
                ToggleSettingsRow(
                    key: SettingsDefaults.enableShadow,
                    title: "Window shadow",
                    help: "Add a deep shadow to the island when expanded"
                )
                
                ToggleSettingsRow(
                    key: SettingsDefaults.enableGradient,
                    title: "Gradient background",
                    help: "Add a subtle color gradient to the background"
                )
            }
            
            Section(header: Text("Content")) {
                ToggleSettingsRow(
                    key: SettingsDefaults.lightingEffect,
                    title: L("settings.appearance.lighting_effect"),
                    help: L("settings.appearance.lighting_effect_help")
                )
                
                ToggleSettingsRow(
                    key: SettingsDefaults.launchAtLogin,
                    title: L("settings.startup.launch_at_login"),
                    help: "Launch the island automatically after your Mac restarts"
                )
                
                ToggleSettingsRow(
                    key: SettingsDefaults.showNotHumanFace,
                    title: "Show face animation when idle",
                    help: "Show a cute face when the island has no activity"
                )
            }
            
            Section(header: Text("Color & Style")) {
                Picker("Island background color", selection: Binding(
                    get: { SettingsDefaults.shared.get(SettingsDefaults.islandBackgroundColor) },
                    set: { SettingsDefaults.shared.set(SettingsDefaults.islandBackgroundColor, value: $0) }
                )) {
                    Text("Classic black").tag("black")
                    Text("Dark gray").tag("darkgray")
                    Text("Deep blue").tag("deepblue")
                    Text("Deep red").tag("deepred")
                }
                .pickerStyle(.menu)
                
                Picker("Progress bar color", selection: Binding(
                    get: { SettingsDefaults.shared.get(SettingsDefaults.sliderColor) },
                    set: { SettingsDefaults.shared.set(SettingsDefaults.sliderColor, value: $0) }
                )) {
                    Text("Pure white").tag("white")
                    Text("System accent color").tag("accent")
                }
                .pickerStyle(.menu)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
