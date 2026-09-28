import SwiftUI

struct AppearanceSettingsView: View {
    // Redraws the theme note, the corner radius value and the background color picker as they change
    @ObservedObject private var settings = SettingsDefaults.shared

    var body: some View {
        SettingsForm {
            Section(header: Text(L("settings.appearance.theme"))) {
                Picker(L("settings.appearance.theme"), selection: Binding(
                    get: { settings.resolveTheme() },
                    set: { settings.set(SettingsDefaults.islandTheme, value: $0.rawValue) }
                )) {
                    ForEach(IslandTheme.allCases) { theme in
                        Text(theme.displayName).tag(theme)
                    }
                }
                .pickerStyle(.segmented)
                SettingsNote(settings.resolveTheme().summary)
            }

            Section(header: Text(L("settings.appearance.header"))) {
                SliderSettingsRow(
                    title: L("settings.appearance.corner_radius"),
                    value: Binding(
                        get: { settings.get(SettingsDefaults.cornerRadiusScaling) },
                        set: { settings.set(SettingsDefaults.cornerRadiusScaling, value: $0) }
                    ),
                    range: 0.5...2.0,
                    step: 0.05,
                    valueText: String(format: "%.2f", settings.get(SettingsDefaults.cornerRadiusScaling))
                )

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
                    key: SettingsDefaults.showNotHumanFace,
                    title: "Show face animation when idle",
                    help: "Show a cute face when the island has no activity"
                )
            }

            Section(header: Text("Color and style")) {
                Picker("Island background color", selection: Binding(
                    get: { settings.get(SettingsDefaults.islandBackgroundColor) },
                    set: { settings.set(SettingsDefaults.islandBackgroundColor, value: $0) }
                )) {
                    Text("Classic black").tag("black")
                    Text("Dark gray").tag("darkgray")
                    Text("Deep blue").tag("deepblue")
                    Text("Deep red").tag("deepred")
                }
                .pickerStyle(.menu)
                .disabled(settings.resolveTheme() != .standard)
                .help(L("settings.appearance.background_color_help"))

                Picker("Progress bar color", selection: Binding(
                    get: { settings.get(SettingsDefaults.sliderColor) },
                    set: { settings.set(SettingsDefaults.sliderColor, value: $0) }
                )) {
                    Text("Pure white").tag("white")
                    Text("System accent color").tag("accent")
                }
                .pickerStyle(.menu)
            }
        }
    }
}
