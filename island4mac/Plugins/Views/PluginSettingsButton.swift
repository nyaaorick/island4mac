import SwiftUI

/// A gear for a plugin's tab when the plugin has settings: opens Settings > Plugins, where the island draws them.
/// In the tab bar, or the tab's corner when the tabs sit beside the camera
struct PluginSettingsButton: View {
    let tab: IslandTab
    @ObservedObject private var plugins = PluginStore.shared

    private var plugin: PluginStore.Installed? {
        guard let id = tab.pluginID ?? plugins.replacesBuiltInTab(tab) else { return nil }
        return plugins.installed.first { $0.id == id }
    }

    var body: some View {
        if let plugin, plugin.manifest.preferences?.isEmpty == false {
            Button {
                SettingsWindowController.shared.showSettings(pane: .plugins)
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.45))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(L("plugins.tab.settings", plugin.manifest.name))
        }
    }
}
