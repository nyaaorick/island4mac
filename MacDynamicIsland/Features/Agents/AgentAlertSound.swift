import AppKit

/// A short system sound when an agent session needs you, finishes or fails
enum AgentAlertSound {
    static func play(for session: AgentSession, previous: AgentSession.Status?) {
        guard SettingsDefaults.shared.get(SettingsDefaults.agentSoundsEnabled),
              let name = soundName(for: session.status) else { return }
        NSSound(named: NSSound.Name(name))?.play()
    }

    static func soundName(for status: AgentSession.Status) -> String? {
        switch status {
        case .needsPermission: return "Ping"
        case .done: return "Glass"
        case .failed: return "Basso"
        case .idle, .working, .compacting: return nil
        }
    }
}
