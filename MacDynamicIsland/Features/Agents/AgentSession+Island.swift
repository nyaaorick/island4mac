import SwiftUI

// What only the app's own Agents views need of the shared Agents code (AgentsCore): colors and Settings

extension AgentKind {
    /// The badge on a session row
    var color: Color {
        switch self {
        case .claude: return .orange
        case .codex: return .cyan
        case .zcode: return .mint
        }
    }
}

extension AgentSession.Status {
    var color: Color {
        switch self {
        case .idle: return .white.opacity(0.45)
        case .working: return .orange
        case .needsPermission: return .yellow
        case .compacting: return .purple
        case .done: return .green
        case .failed: return .red
        }
    }
}

extension AgentSessionStore {
    /// Whether the collapsed island shows an agent session beside the notch
    var showsCompactLiveActivity: Bool {
        // The Agents plugin shows its own, once turned on
        SettingsDefaults.shared.get(SettingsDefaults.showAgentLiveActivity) && liveSession != nil
            && PluginStore.shared.replacesBuiltInTab(.agents) == nil
    }
}
