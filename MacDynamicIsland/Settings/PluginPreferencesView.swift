import SwiftUI

/// One plugin's preferences, as a section of Settings > Plugins: the plugin declares them, the island draws them
/// with the same controls as every other setting
struct PluginPreferencesView: View {
    let plugin: PluginStore.Installed
    @ObservedObject var store: PluginPreferencesStore

    var body: some View {
        Section {
            ForEach(plugin.manifest.preferences ?? []) { preference in
                row(for: preference)
                if preference.isMissing(store.value(of: preference, for: plugin.id)) {
                    SettingsNote(L("settings.plugins.required"), color: .orange)
                }
            }
        } header: {
            Label(plugin.manifest.name, systemImage: plugin.manifest.symbol)
        }
    }

    @ViewBuilder
    private func row(for preference: PluginPreference) -> some View {
        switch preference.kind {
        case .text:
            TextField(preference.title, text: text(preference), prompt: preference.placeholder.map { Text($0) })
        case .secure:
            SecureField(preference.title, text: text(preference), prompt: preference.placeholder.map { Text($0) })
        case .toggle:
            Toggle(preference.title, isOn: Binding(
                get: { store.value(of: preference, for: plugin.id) == .bool(true) },
                set: { store.set(.bool($0), of: preference, for: plugin.id) }
            ))
        case .number:
            if let minimum = preference.minimum, let maximum = preference.maximum, minimum < maximum {
                SliderSettingsRow(title: preference.title, value: number(preference), range: minimum...maximum,
                                  step: maximum - minimum >= 2 ? 1 : nil,
                                  valueText: number(preference).wrappedValue.formatted(.number.precision(.fractionLength(0...2))))
            } else {
                TextField(preference.title, value: number(preference), format: .number)
            }
        case .choice:
            Picker(preference.title, selection: Binding(
                get: { store.value(of: preference, for: plugin.id) },
                set: { store.set($0, of: preference, for: plugin.id) }
            )) {
                ForEach(preference.options ?? [], id: \.self) { option in
                    Text(option.title).tag(option.value)
                }
            }
        }
    }

    private func text(_ preference: PluginPreference) -> Binding<String> {
        Binding(
            get: {
                if case .string(let text) = store.value(of: preference, for: plugin.id) { return text }
                return ""
            },
            set: { store.set(.string($0), of: preference, for: plugin.id) }
        )
    }

    private func number(_ preference: PluginPreference) -> Binding<Double> {
        Binding(
            get: {
                if case .number(let number) = store.value(of: preference, for: plugin.id) { return number }
                return 0
            },
            set: { store.set(.number($0), of: preference, for: plugin.id) }
        )
    }
}
