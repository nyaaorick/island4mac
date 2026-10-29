import SwiftUI

/// How the island draws what plays. Where lyrics come from is the Music plugin's preference, under Plugins
struct MediaSettingsView: View {
    var body: some View {
        SettingsForm {
            Section(header: Text("Now playing")) {
                ToggleSettingsRow(
                    key: SettingsDefaults.showMusicLiveActivity,
                    title: "Show beside the notch",
                    help: "Show the track beside the notch while the island is collapsed"
                )

                ToggleSettingsRow(
                    key: SettingsDefaults.playerColorTinting,
                    title: "Tint with the artwork",
                    help: "Tint the controls and the spectrum with the album cover's colors"
                )

                ToggleSettingsRow(
                    key: SettingsDefaults.useMusicVisualizer,
                    title: "Spectrum animation",
                    help: "Show a playback animation while the island is open"
                )
            }

            Section(header: Text("Lyrics")) {
                ToggleSettingsRow(
                    key: SettingsDefaults.enableLyrics,
                    title: "Show lyrics",
                    help: "Show synced lyrics below the track when available. Where they come from is the Music plugin's setting, under Plugins"
                )
            }
        }
    }
}
