import SwiftUI

struct CompactIslandRegion: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var agents = AgentSessionStore.shared

    let animation: Namespace.ID

    /// An agent session takes the wings over from music while it works, waits for you or has just finished
    private var agentSession: AgentSession? {
        agents.showsCompactLiveActivity ? agents.liveSession : nil
    }

    var body: some View {
        let notch = appState.notchSize
        if notch == .zero {
            // No notch on this display: a small pill at the top center
            HStack(spacing: 8) {
                if appState.showsLiveActivity, let session = agentSession {
                    CompactAgentLiveActivityView(session: session, isWide: appState.isOnLargeDisplay)
                } else if appState.showsLiveActivity && MusicManager.shared.showsCompactLiveActivity {
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
        } else if appState.showsLiveActivity, let session = agentSession {
            AgentNotchLiveActivityView(session: session, notch: notch, wings: appState.liveActivityWings, activeCount: agents.activeSessionCount)
        } else if appState.showsLiveActivity && MusicManager.shared.showsCompactLiveActivity {
            MusicNotchLiveActivityView(notch: notch, wings: appState.liveActivityWings, animation: animation)
        } else {
            // Nothing playing: stay hidden inside the notch
            Color.clear
        }
    }
}
