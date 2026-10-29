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

                Picker("Background color", selection: Binding(
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
            }
        }
    }
}
