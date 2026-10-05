import SwiftUI

/// Collapsed now-playing on a notched display: album art and spectrum beside the notch
struct MusicNotchLiveActivityView: View {
    @ObservedObject private var musicStore = MusicStore.shared
    @ObservedObject private var settings = SettingsDefaults.shared

    let notch: CGSize
    let wings: IslandWings
    let animation: Namespace.ID

    private var accent: Color {
        if settings.get(SettingsDefaults.playerColorTinting) {
            return Color(nsColor: musicStore.avgColor).ensureMinimumBrightness(factor: 0.55)
        }
        return .accentColor
    }

    var body: some View {
        NotchWingsLayout(notch: notch, wings: wings) { width in
            // A narrow wing keeps a little air around the artwork
            let artSize = min(max(16, notch.height - 12), width - 2)
            Image(nsImage: musicStore.albumArt)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .matchedGeometryEffect(id: "album_art", in: animation)
                .frame(width: artSize, height: artSize)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        } secondary: { _ in
            spectrum
        }
    }

    @ViewBuilder
    private var spectrum: some View {
        if settings.get(SettingsDefaults.useMusicVisualizer) {
            Rectangle()
                .fill((settings.get(SettingsDefaults.playerColorTinting) ? accent : .white).opacity(0.85))
                .frame(width: 18, height: 12)
                .matchedGeometryEffect(id: "spectrum", in: animation)
                .mask {
                    AudioSpectrumView(isPlaying: $musicStore.isPlaying)
                        .frame(width: 16, height: 12)
                }
                .accessibilityHidden(true)
        } else {
            Image(systemName: "waveform")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(musicStore.isPlaying ? .green : Color.white.opacity(0.35))
                .symbolEffect(.bounce, options: .repeating, value: musicStore.isPlaying)
        }
    }
}
