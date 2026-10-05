import SwiftUI

/// A plugin's tab: what it shows (PluginContentView), or why it shows nothing (turned off, stopped, needs setting
/// up). Taps and what you type go to the plugin
struct PluginTabView: View {
    let pluginID: String
    @ObservedObject private var plugins = PluginStore.shared

    private var plugin: PluginStore.Installed? { plugins.installed.first { $0.id == pluginID } }
    private var content: PluginStore.Content { plugins.contents[pluginID] ?? PluginStore.Content() }

    var body: some View {
        VStack(spacing: 8) {
            if plugin != nil && !plugins.isEnabled(pluginID) {
                turnedOffState
            } else if case .stopped(let reason) = plugins.statuses[pluginID] {
                stoppedState(reason: reason)
            } else if plugins.statuses[pluginID] == .needsSetup {
                setupState
            } else {
                PluginContentView(content: content, emptySymbol: plugin?.manifest.symbol ?? "puzzlepiece.extension",
                                  emptyTitle: plugin?.manifest.name ?? pluginID,
                                  emptyText: plugin == nil ? L("plugins.tab.missing") : L("plugins.tab.empty")) {
                    plugins.send($0, to: pluginID)
                }
            }
        }
        .padding(.top, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // The plugin may update often while its tab shows and rest otherwise (counted across displays)
        .onAppear { plugins.tabAppeared(pluginID) }
        .onDisappear { plugins.tabDisappeared(pluginID) }
    }

    /// Turned off in Settings > Plugins, while its tab is still one of yours (Agents)
    private var turnedOffState: some View {
        VStack(spacing: 10) {
            Image(systemName: plugin?.manifest.symbol ?? "puzzlepiece.extension")
                .font(.system(size: 28))
                .foregroundStyle(.white.opacity(0.3))
            Text(L("plugins.tab.turned_off", plugin?.manifest.name ?? pluginID))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
            PluginButtonView(title: L("plugins.tab.open_settings"), symbol: "gearshape") {
                SettingsWindowController.shared.showSettings(pane: .plugins)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// A required preference is empty: the plugin waits for it, set in Settings
    private var setupState: some View {
        VStack(spacing: 10) {
            Image(systemName: "gearshape")
                .font(.system(size: 28))
                .foregroundStyle(.white.opacity(0.3))
            Text(L("plugins.tab.needs_setup", plugin?.manifest.name ?? pluginID))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
            PluginButtonView(title: L("plugins.tab.open_settings"), symbol: "gearshape") {
                SettingsWindowController.shared.showSettings(pane: .plugins)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The plugin kept exiting or couldn't start: say so, and offer to start it again
    private func stoppedState(reason: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 28))
                .foregroundStyle(.white.opacity(0.3))
            Text(L("plugins.tab.stopped", plugin?.manifest.name ?? pluginID))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
            Text(reason)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.4))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            PluginButtonView(title: L("plugins.tab.restart"), symbol: "arrow.clockwise") {
                plugins.restart(pluginID)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
