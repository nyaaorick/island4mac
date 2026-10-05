import SwiftUI

/// Sound toggle and settings for the Agents tab: in the tab bar, or its corner when the tabs sit beside the camera
struct AgentTabControls: View {
    @ObservedObject private var settings = SettingsDefaults.shared

    var body: some View {
        let soundsOn = settings.get(SettingsDefaults.agentSoundsEnabled)
        HStack(spacing: 2) {
            controlButton(soundsOn ? "speaker.wave.2.fill" : "speaker.slash.fill",
                          help: soundsOn ? "Mute agent alerts" : "Play a sound when an agent needs you or finishes") {
                settings.set(SettingsDefaults.agentSoundsEnabled, value: !soundsOn)
            }
            controlButton("gearshape.fill", help: "Agent settings") {
                SettingsWindowController.shared.showSettings()
            }
        }
    }

    private func controlButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.45))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
