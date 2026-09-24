import SwiftUI
import Combine
import UniformTypeIdentifiers

struct ExpandedMusicView: View {
    @ObservedObject var musicManager: MusicManager
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
                        Text(musicManager.songTitle.isEmpty ? "Not Playing" : musicManager.songTitle)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        
                        Text(musicManager.artistName.isEmpty ? "Select a track" : musicManager.artistName)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white.opacity(0.6))
                            .lineLimit(1)
                    }
                    
                    // 🎤 LYRICS VIEW (New)
                    if !musicManager.currentLyrics.isEmpty {
                        LyricsView(musicManager: musicManager)
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
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .background(Color.clear)
        .onChange(of: musicManager.songTitle) { oldTitle, newTitle in
            // ✅ 歌曲切换时重置拖拽状态
            if newTitle != oldTitle && !oldTitle.isEmpty {
                isSeeking = false
                seekTime = 0
            }
            lastSongTitle = newTitle
        }
    }
    
    private var albumArtView: some View {
        Button(action: { selectCustomAlbumArt() }) {
            Image(nsImage: musicManager.albumArt)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .matchedGeometryEffect(id: "album_art", in: animation)
                .frame(width: 100, height: 100)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }
    
    private var progressStrip: some View {
        VStack(spacing: 4) {
            GeometryReader { geo in
                let duration = max(0, musicManager.songDuration)
                let displayTime = isSeeking ? seekTime : musicManager.currentDisplayTime
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
                            musicManager.seek(to: target)
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
                Text(formatTime(isSeeking ? seekTime : musicManager.currentDisplayTime))
                Spacer()
                Text(musicManager.songDuration > 0 ? formatTime(musicManager.songDuration) : "--:--")
            }
            .font(.system(size: 9, design: .monospaced))
            .foregroundColor(.white.opacity(0.4))
        }
    }
    
    private var mediaControls: some View {
        HStack(spacing: 20) {
            Spacer()
            controlButton(icon: "backward.fill") { musicManager.previousTrack() }
            
            Button(action: { musicManager.togglePlay() }) {
                Circle()
                    .fill(Color.white.opacity(0.2))
                    .frame(width: 38, height: 38)
                    .overlay(
                        Image(systemName: musicManager.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                    )
            }
            .buttonStyle(.plain)
            
            controlButton(icon: "forward.fill") { musicManager.nextTrack() }
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
    
    /// 📸 选择自定义专辑封面
    private func selectCustomAlbumArt() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.image]
        panel.message = "选择一张图片作为专辑封面"
        
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            
            Task { @MainActor in
                if let image = NSImage(contentsOf: url) {
                    musicManager.albumArt = image
                    musicManager.usingAppIconForArtwork = false
                }
            }
        }
    }
}

// MARK: - Lyrics View
struct LyricsView: View {
    @ObservedObject var musicManager: MusicManager
    
    var body: some View {
        GeometryReader { geo in
            VStack {
                if !musicManager.syncedLyrics.isEmpty {
                    // Synced Lyrics
                    let currentLine = musicManager.lyricLine(at: musicManager.currentDisplayTime)
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
                    Text(cleanLyrics(musicManager.currentLyrics))
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
    
    private func cleanLyrics(_ text: String) -> String {
        // Remove time tags if any remain, though fetcher should strip them
        return text.replacingOccurrences(of: "\\[.*?\\]", with: "", options: .regularExpression)
                   .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
