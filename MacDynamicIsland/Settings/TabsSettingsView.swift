import SwiftUI

/// Which tabs the island shows and in what order: the built-in ones and the installed plugins'
struct TabsSettingsView: View {
    @ObservedObject private var tabs = TabStore.shared

    private var hiddenTabs: [IslandTab] {
        tabs.availableTabs.filter { !tabs.isEnabled($0) }
    }

    var body: some View {
        SettingsForm {
            Section {
                ForEach(tabs.enabledTabs, id: \.self) { tab in
                    row(for: tab)
                }
                .onMove { tabs.moveEnabled(fromOffsets: $0, toOffset: $1) }
            } header: {
                Text(L("settings.tabs.shown"))
            } footer: {
                SettingsNote(L("settings.tabs.shown_help"))
            }

            Section {
                if hiddenTabs.isEmpty {
                    SettingsNote(L("settings.tabs.hidden_none"))
                } else {
                    ForEach(hiddenTabs, id: \.self) { tab in
                        row(for: tab)
                    }
                }
            } header: {
                Text(L("settings.tabs.hidden"))
            } footer: {
                if tabs.enabledTabs.count >= TabStore.maxEnabled && !hiddenTabs.isEmpty {
                    SettingsNote(L("settings.tabs.limit"))
                }
            }
        }
    }

    private func row(for tab: IslandTab) -> some View {
        let info = tabs.info(for: tab)
        return Toggle(isOn: Binding(
            get: { tabs.isEnabled(tab) },
            set: { tabs.setEnabled(tab, $0) }
        )) {
            Label(info.name, systemImage: info.symbol)
        }
        .disabled(!tabs.canToggle(tab))
    }
}
