import SwiftUI

struct CompactIslandRegion: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var plugins = PluginStore.shared

    let animation: Namespace.ID

    /// What a plugin shows beside the notch: a popup ahead of now playing, its compact content after it
    private struct PluginLive {
        let name: String
        let compact: PluginCompact
    }

    private var pluginPopup: PluginLive? {
        guard let active = plugins.popup else { return nil }
        let name = plugins.installed.first { $0.id == active.pluginID }?.manifest.name ?? active.pluginID
        return PluginLive(name: name, compact: PluginCompact(symbol: active.popup.symbol, text: active.popup.text))
    }

    private var pluginCompact: PluginLive? {
        guard let live = plugins.compactPlugin else { return nil }
        var compact = live.compact
        compact.symbol = compact.symbol ?? live.manifest.symbol
        return PluginLive(name: live.manifest.name, compact: compact)
    }

    private var priorityPlugin: PluginLive? {
        guard let live = plugins.priorityPlugin else { return nil }
        var compact = live.compact
        compact.symbol = compact.symbol ?? live.manifest.symbol
        return PluginLive(name: live.manifest.name, compact: compact)
    }

    /// The plugin content of the live activity IslandWindow picked, if it's a plugin's
    private var pluginLive: PluginLive? {
        switch appState.liveActivity {
        case .pluginPopup: return pluginPopup
        case .pluginCompact: return pluginCompact
        case .priorityPlugin: return priorityPlugin
        default: return nil
        }
    }

    var body: some View {
        let notch = appState.notchSize
        let activity = appState.liveActivity
        if notch == .zero {
            // No notch on this display: a small pill at the top center
            HStack(spacing: 8) {
                if let live = pluginLive {
                    CompactPluginLiveActivityView(name: live.name, compact: live.compact)
                } else if activity == .music {
                    CompactMusicLiveActivityView(animation: animation)
                } else {
                    AnimatedFaceView()
                        .frame(width: 28, height: 14)
                    Spacer()
                    Image(systemName: appState.currentSection.iconName)
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.3))
                }
            }
            .padding(.horizontal, 14)
        } else if let live = pluginLive {
            PluginNotchLiveActivityView(compact: live.compact, notch: notch, wings: appState.liveActivityWings)
        } else if activity == .music {
            MusicNotchLiveActivityView(notch: notch, wings: appState.liveActivityWings, animation: animation)
        } else {
            // Nothing to show: stay hidden inside the notch
            Color.clear
        }
    }
}
