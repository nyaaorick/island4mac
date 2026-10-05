import SwiftUI

struct MediaSettingsView: View {
    @State private var slotLimit: Double = Double(SettingsDefaults.shared.get(SettingsDefaults.musicControlSlotLimit))

    var body: some View {
        SettingsForm {
            Section(header: Text("Now playing")) {
                ToggleSettingsRow(
                    key: SettingsDefaults.showMusicLiveActivity,
                    title: "Enable live activity",
                    help: "Show track info in the island when collapsed"
                )

                ToggleSettingsRow(
                    key: SettingsDefaults.coloredSpectrogram,
                    title: "Colorful spectrum",
                    help: "Extract colors from the album cover for the audio spectrum animation"
                )

                ToggleSettingsRow(
                    key: SettingsDefaults.playerColorTinting,
                    title: "Tint controls",
                    help: "Tint the control buttons and background with the album cover colors"
                )

                ToggleSettingsRow(
                    key: SettingsDefaults.useMusicVisualizer,
                    title: "Enable music animation",
                    help: "Show a playback animation when the island is expanded"
                )
            }

            Section(header: Text("Lyrics")) {
                ToggleSettingsRow(
                    key: SettingsDefaults.enableLyrics,
                    title: "Show lyrics",
                    help: "Show synced lyrics below the track when available. Where they come from is the Music plugin's setting, under Plugins"
                )
            }

            Section {
                // Saved when the slider is let go, so the island doesn't relayout on every step
                SliderSettingsRow(
                    title: "Control slots shown",
                    value: $slotLimit,
                    range: 3...7,
                    step: 1,
                    valueText: "\(Int(slotLimit))"
                ) { editing in
                    if !editing {
                        SettingsDefaults.shared.set(SettingsDefaults.musicControlSlotLimit, value: Int(slotLimit))
                    }
                }
            } header: {
                Text("Control buttons")
            } footer: {
                SettingsNote("How many media control buttons the expanded island shows.")
            }
        }
    }
}
