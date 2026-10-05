import SwiftUI

/// Collapsed now-playing without a notch: album art, progress and lyrics
struct CompactMusicLiveActivityView: View {
    @ObservedObject private var musicManager = MusicManager.shared
    @ObservedObject private var settings = SettingsDefaults.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let animation: Namespace.ID

    private var accent: Color {
        if settings.get(SettingsDefaults.playerColorTinting) {
            return Color(nsColor: musicManager.avgColor).ensureMinimumBrightness(factor: 0.55)
        }
        return .accentColor
    }

    var body: some View {
        GeometryReader { geo in
            // The artwork and the spectrum get a slot as wide on either side, so the title and lyric line between them
            // sit in the middle of the pill. They get all the rest, so the wider pill of a large display shows them whole
            let slot: CGFloat = 24
            let textWidth = max(0, geo.size.width - 2 * slot - 2 * 8)

            HStack(spacing: 8) {
                // Album art (tiny)
                Image(nsImage: musicManager.albumArt)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .matchedGeometryEffect(id: "album_art", in: animation)
                    .frame(width: slot, height: slot)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
                    )

                // Title, lyric line and progress one under the other, so the progress never covers the words
                VStack(spacing: 0) {
                    // Song title
                    IslandMarqueeText(
                        text: .constant(musicManager.songTitle.isEmpty ? "Not Playing" : musicManager.songTitle),
                        font: .system(size: 11, weight: .semibold),
                        nsFont: .systemFont(ofSize: 11, weight: .semibold),
                        textColor: .white,
                        frameWidth: textWidth,
                        centersWhenFitting: true
                    )
                    .frame(height: 13)

                    // Lyrics (real-time) or artist line
                    Group {
                        if settings.get(SettingsDefaults.enableLyrics) {
                            TimelineView(.animation(minimumInterval: 0.25)) { timeline in
                                let elapsed = musicManager.estimatedPlaybackPosition(at: timeline.date)
                                let line = compactLyricsLine(elapsed: elapsed)

                                IslandMarqueeText(
                                    text: .constant(line),
                                    font: .system(size: 10, weight: .medium),
                                    nsFont: .systemFont(ofSize: 10, weight: .medium),
                                    textColor: musicManager.isFetchingLyrics ? Color.white.opacity(0.35) : Color.white.opacity(0.65),
                                    frameWidth: textWidth,
                                    centersWhenFitting: true
                                )
                                .id(line)
                            }
                        } else {
                            IslandMarqueeText(
                                text: .constant(musicManager.artistName.isEmpty ? "" : musicManager.artistName),
                                font: .system(size: 10, weight: .medium),
                                nsFont: .systemFont(ofSize: 10, weight: .medium),
                                textColor: Color.white.opacity(0.55),
                                frameWidth: textWidth,
                                centersWhenFitting: true
                            )
                        }
                    }
                    .frame(height: 12)
                    .padding(.top, 1)

                    CompactMusicProgressBar(accent: accent)
                        .frame(width: textWidth)
                }

                Group {
                    if settings.get(SettingsDefaults.useMusicVisualizer) {
                        // ✅ Removed the .gradient effect; use a solid fill only
                        Rectangle()
                            .fill((settings.get(SettingsDefaults.playerColorTinting) ? accent : .white).opacity(0.85))
                            .frame(width: 18, height: 12)
                            .matchedGeometryEffect(id: "spectrum", in: animation)
                            .mask {
                                AudioSpectrumView(isPlaying: $musicManager.isPlaying)
                                    .frame(width: 16, height: 12)
                            }
                            .accessibilityHidden(true)
                    } else {
                        Image(systemName: "waveform")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(musicManager.isPlaying ? .green : Color.white.opacity(0.35))
                            .symbolEffect(.bounce, options: .repeating, value: musicManager.isPlaying)
                    }
                }
                .frame(width: slot)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        // Title 13, lyric 1 + 12, progress 4
        .frame(height: 30)
    }

    private func compactLyricsLine(elapsed: Double) -> String {
        if musicManager.isFetchingLyrics {
            return "Loading lyrics…"
        }

        if !musicManager.syncedLyrics.isEmpty {
            let line = musicManager.lyricLine(at: elapsed)
            return line.isEmpty ? "…" : line
        }

        // Lyrics without timing can't follow the song: the whole song in one scrolling line is no use here
        return musicManager.artistName
    }
}

private struct CompactMusicProgressBar: View {
    @ObservedObject private var musicManager = MusicManager.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isSeeking = false
    @State private var seekTime: Double = 0

    let accent: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: musicManager.playbackRate > 0 ? 0.2 : nil)) { timeline in
            GeometryReader { geo in
                let duration = musicManager.songDuration
                let elapsed = isSeeking ? seekTime : musicManager.estimatedPlaybackPosition(at: timeline.date)
                let progress = duration > 0 ? min(1.0, max(0.0, elapsed / duration)) : 0

                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.12))

                    if duration > 0 {
                        Capsule()
                            .fill(accent.opacity(0.9))
                            .frame(width: geo.size.width * progress)
                            .animation(reduceMotion ? nil : .linear(duration: 0.2), value: progress)
                    } else if musicManager.isPlaying {
                        // Indeterminate shimmer when duration is unknown
                        let barWidth = max(12, geo.size.width * 0.35)
                        let period: TimeInterval = 1.3
                        let phase = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period
                        let x = reduceMotion ? 0 : (CGFloat(phase) * (geo.size.width + barWidth) - barWidth)

                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [accent.opacity(0.25), accent.opacity(0.85), accent.opacity(0.25)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: barWidth)
                            .offset(x: x)
                    }
                }
                // A thin line, in a slightly taller strip that's easier to grab for seeking
                .frame(height: 2)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    duration > 0
                    ? DragGesture(minimumDistance: 0)
                        .onChanged { gesture in
                            let width = max(CGFloat(1), geo.size.width)
                            let pct = min(1.0, max(0.0, Double(gesture.location.x / width)))
                            seekTime = pct * duration
                            if !isSeeking { isSeeking = true }
                        }
                        .onEnded { _ in
                            let target = min(max(0, seekTime), duration)
                            isSeeking = false
                            musicManager.seek(to: target)
                        }
                    : nil
                )
                .animation(.spring(response: 0.25, dampingFraction: 0.85), value: isSeeking)
            }
        }
        .frame(height: 4)
    }
}
