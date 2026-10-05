import SwiftUI

struct CompactIslandRegion: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var agents = AgentSessionStore.shared
    @ObservedObject private var plugins = PluginStore.shared

    let animation: Namespace.ID

    /// An agent session takes the wings over from music while it works, waits for you or has just finished
    private var agentSession: AgentSession? {
        agents.showsCompactLiveActivity ? agents.liveSession : nil
    }

    /// What a plugin shows beside the notch: a popup ahead of now playing, its compact content after it
    private struct PluginLive {
        let name: String
        let symbol: String?
        let text: String?
        let progress: Double?
    }

    private var pluginPopup: PluginLive? {
        guard let active = plugins.popup else { return nil }
        let name = plugins.installed.first { $0.id == active.pluginID }?.manifest.name ?? active.pluginID
        return PluginLive(name: name, symbol: active.popup.symbol, text: active.popup.text, progress: nil)
    }

    private var pluginCompact: PluginLive? {
        guard let live = plugins.compactPlugin else { return nil }
        return PluginLive(name: live.manifest.name, symbol: live.compact.symbol ?? live.manifest.symbol,
                          text: live.compact.text, progress: live.compact.progress)
    }

    /// The plugin content of the live activity IslandWindow picked, if it's a plugin's
    private var pluginLive: PluginLive? {
        switch appState.liveActivity {
        case .pluginPopup: return pluginPopup
        case .pluginCompact: return pluginCompact
        default: return nil
        }
    }

    var body: some View {
        let notch = appState.notchSize
        let activity = appState.liveActivity
        if notch == .zero {
            // No notch on this display: a small pill at the top center
            HStack(spacing: 8) {
                if activity == .agent, let session = agentSession {
                    CompactAgentLiveActivityView(session: session, isWide: appState.isOnLargeDisplay)
                } else if let live = pluginLive {
                    CompactPluginLiveActivityView(name: live.name, symbol: live.symbol, text: live.text, progress: live.progress)
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
        } else if activity == .agent, let session = agentSession {
            AgentNotchLiveActivityView(session: session, notch: notch, wings: appState.liveActivityWings, activeCount: agents.activeSessionCount)
        } else if let live = pluginLive {
            PluginNotchLiveActivityView(symbol: live.symbol, text: live.text, progress: live.progress, notch: notch, wings: appState.liveActivityWings)
        } else if activity == .music {
            MusicNotchLiveActivityView(notch: notch, wings: appState.liveActivityWings, animation: animation)
        } else {
            // Nothing to show: stay hidden inside the notch
            Color.clear
        }
    }
}
