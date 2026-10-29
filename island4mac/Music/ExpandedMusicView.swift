import SwiftUI

/// The Music tab: the island's own player for whatever plays (NowPlayingStore), from the built-in Music or a
/// plugin's `media`. Taps on the controls and the progress bar go back to where the track comes from
struct ExpandedMusicView: View {
    @ObservedObject var musicStore: NowPlayingStore
    var animation: Namespace.ID

    @State private var isSeeking = false
    @State private var seekTime: Double = 0
    @State private var lastSongTitle: String = ""

    var body: some View {
        ZStack {
            HStack(alignment: .center, spacing: 18) {
                // 💿 ALBUM ART
                albumArtView
                
                // 📝 TRACK INFO & LYRICS & CONTROLS
                VStack(alignment: .leading, spacing: 8) {
                    // Title & Artist
                    VStack(alignment: .leading, spacing: 2) {
                        Text(musicStore.songTitle.isEmpty ? "Not Playing" : musicStore.songTitle)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        
                        Text(musicStore.artistName.isEmpty ? "Select a track" : musicStore.artistName)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white.opacity(0.6))
                            .lineLimit(1)
                    }
                    
                    // 🎤 LYRICS VIEW (New)
                    if !(musicStore.current?.lyrics.isEmpty ?? true) {
                        LyricsView(musicStore: musicStore)
                            .frame(height: 36)
                    } else {
                        Spacer().frame(height: 8)
                    }
                    
                    // ⏱ PROGRESS STRIP
                    progressStrip
                    
                    // 🎮 MEDIA CONTROLS
                    mediaControls
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .islandTile(cornerRadius: 22)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .onChange(of: musicStore.songTitle) { oldTitle, newTitle in
            // Reset drag state when the track changes
            if newTitle != oldTitle && !oldTitle.isEmpty {
                isSeeking = false
                seekTime = 0
            }
            lastSongTitle = newTitle
        }
    }
    
    private var albumArtView: some View {
        Image(nsImage: musicStore.albumArt)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .matchedGeometryEffect(id: "album_art", in: animation)
            .frame(width: 100, height: 100)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
    
    private var progressStrip: some View {
        // The island runs the progress itself, from where the track was at a given time
        TimelineView(.periodic(from: .now, by: 0.5)) { timeline in
            progressStrip(at: musicStore.estimatedPlaybackPosition(at: timeline.date))
        }
    }

    private func progressStrip(at currentTime: Double) -> some View {
        VStack(spacing: 4) {
            GeometryReader { geo in
                let duration = max(0, musicStore.songDuration)
                let displayTime = isSeeking ? seekTime : currentTime
                let progress = duration > 0 ? min(1.0, max(0.0, displayTime / duration)) : 0
                let barHeight: CGFloat = 4

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.1))
                        .frame(height: barHeight)

                    if duration > 0 {
                        Capsule()
                            .fill(Color.white)
                            .frame(width: max(0, geo.size.width * progress), height: barHeight)
                    }
                }
                .contentShape(Rectangle())
                .gesture(
                    duration > 0
                    ? DragGesture(minimumDistance: 0)
                        .onChanged { gesture in
                            let width = max(CGFloat(1), geo.size.width)
                            let pct = min(1.0, max(0.0, Double(gesture.location.x / width)))
                            seekTime = pct * duration
                            if !isSeeking { 
                                isSeeking = true 
                            }
                        }
                        .onEnded { _ in
                            let target = min(max(0, seekTime), duration)
                            musicStore.seek(to: target)
                            Task { @MainActor in
                                try? await Task.sleep(for: .milliseconds(50))
                                isSeeking = false
                            }
                        }
                    : nil
                )
            }
            .frame(height: 12)

            HStack {
                Text(formatTime(isSeeking ? seekTime : currentTime))
                Spacer()
                Text(musicStore.songDuration > 0 ? formatTime(musicStore.songDuration) : "--:--")
            }
            .font(.system(size: 9, design: .monospaced))
            .foregroundColor(.white.opacity(0.4))
        }
    }
    
    private var mediaControls: some View {
        HStack(spacing: 20) {
            Spacer()
            controlButton(icon: "backward.fill") { musicStore.previousTrack() }
            
            Button(action: { musicStore.togglePlay() }) {
                Circle()
                    .fill(Color.white.opacity(0.2))
                    .frame(width: 38, height: 38)
                    .overlay(
                        Image(systemName: musicStore.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                    )
            }
            .buttonStyle(.plain)
            
            controlButton(icon: "forward.fill") { musicStore.nextTrack() }
            Spacer()
        }
    }
    
    private func controlButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.white.opacity(0.8))
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
    }
    
    private func formatTime(_ seconds: Double) -> String {
        guard !seconds.isNaN && !seconds.isInfinite && seconds >= 0 else { return "0:00" }
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - Lyrics View
struct LyricsView: View {
    @ObservedObject var musicStore: NowPlayingStore
    
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { timeline in
            lyrics(at: musicStore.estimatedPlaybackPosition(at: timeline.date))
        }
    }

    private func lyrics(at time: Double) -> some View {
        GeometryReader { geo in
            VStack {
                if musicStore.hasSyncedLyrics {
                    // Synced Lyrics
                    let currentLine = musicStore.lyricLine(at: time)
                    Text(currentLine.isEmpty ? "..." : currentLine)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(width: geo.size.width, alignment: .leading)
                        .transition(.opacity)
                        .id("synced_\(currentLine)")
                } else {
                    // Static Lyrics (Scrollable automatically via Marquee logic or just partial text)
                    Text(musicStore.plainLyrics)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(.white.opacity(0.8))
                        .lineLimit(2)
                        .lineSpacing(4)
                        .multilineTextAlignment(.leading)
                        .frame(width: geo.size.width, alignment: .topLeading)
                }
            }
        }
    }
}
